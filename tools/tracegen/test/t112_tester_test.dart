// T11.2 TG57-TG59 (tester) plus adversarial checks of V14-V16.
//
// The TG59 oracle is independent of the generator code: it reads the raw
// route / profile / fixture JSON and the GPX text with its own regular
// expression, computes the off-route destination D with its own spherical
// geometry (not `effectiveDestination`/`offsetM`), maps the motion truth
// (`TruthState.s` only, shared with the generator as in T11 TG32) onto the
// route with its own polyline walk anchored at the destination waypoint, and
// runs its own closest / departT search (fixtures README §3.1
// `truth.closest`). Hand-computed values are pinned (review T11.2 nit 2):
// 1.5 km closest (2425, 1500, 2645), 2 km closest (2425, 2000, 2690),
// TR38 [2425, 2505], TR32 [2690, 2720], coach_md_tb A = 7310.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

typedef _J = Map<String, Object?>;

const String _off = 'coach_gb_phuly_offroute';
const String _off2k = 'coach_gb_phuly_offroute_2k';
const String _md = 'coach_md_tb';

/// The 15 GPX committed before T11.2 (HEAD 19adfe4 / 2eb76e5).
const List<String> _legacyIds = [
  'bus_hn_brt01',
  'bus_hn_brt01_noisy',
  'bus_hn_brt01_noisy_traps',
  'bus_hn_slow',
  'coach_dn_langco_neardest',
  'coach_dn_langco_shortgap',
  'coach_dn_langco_tunnel',
  'coach_gb_phuly_offroute',
  'coach_gb_phuly_overshoot',
  'coach_md_tb',
  'train_hn_dh',
  'train_hn_dh_midgap',
  'train_hn_dh_stopgap',
  'train_longstop',
  'train_longstop_nospd',
];

String _text(String name) =>
    File('${fixturesDir.path}/$name').readAsStringSync();

_J _readJson(String path) => jsonDecode(File(path).readAsStringSync()) as _J;

_J _fixture(String id) => jsonDecode(_text('$id.expect.json')) as _J;

_J _obj(Object? v) => v! as _J;

List<_J> _cases(_J fixture) => (fixture['cases']! as List).cast<_J>();

_J _caseOf(_J fixture, String id) =>
    _cases(fixture).singleWhere((c) => c['id'] == id);

int _caseIndex(_J fixture, String id) =>
    _cases(fixture).indexWhere((c) => c['id'] == id);

List<_J> _expectList(_J c) => (c['expect']! as List).cast<_J>();

// ---------------------------------------------------------------- geometry

double _rad(double d) => d * pi / 180;
double _deg(double r) => r * 180 / pi;

/// Mean Earth radius (IUGG), metres; deliberately not the generator's.
const double _earthR = 6371008.8;

typedef _P = ({double lat, double lng});

double _dist(_P a, _P b) {
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h =
      pow(sin(dLat / 2), 2) +
      cos(_rad(a.lat)) * cos(_rad(b.lat)) * pow(sin(dLng / 2), 2);
  return 2 * _earthR * asin(sqrt(h));
}

/// Initial bearing a -> b, degrees in [0, 360).
double _bearing(_P a, _P b) {
  final y = sin(_rad(b.lng - a.lng)) * cos(_rad(b.lat));
  final x =
      cos(_rad(a.lat)) * sin(_rad(b.lat)) -
      sin(_rad(a.lat)) * cos(_rad(b.lat)) * cos(_rad(b.lng - a.lng));
  return (_deg(atan2(y, x)) + 360) % 360;
}

/// Point [d] metres from [p] at initial bearing [brg] (great circle).
_P _destPoint(_P p, double brg, double d) {
  final delta = d / _earthR;
  final th = _rad(brg);
  final la1 = _rad(p.lat);
  final lo1 = _rad(p.lng);
  final la2 = asin(sin(la1) * cos(delta) + cos(la1) * sin(delta) * cos(th));
  final lo2 =
      lo1 +
      atan2(sin(th) * sin(delta) * cos(la1), cos(delta) - sin(la1) * sin(la2));
  return (lat: _deg(la2), lng: _deg(lo2));
}

/// Point at [m] metres from [a] towards [b] (linear on the short segment
/// fraction; segments here are <= 20 km so the error is centimetres).
_P _along(_P a, _P b, double m) {
  final f = m / _dist(a, b);
  return (lat: a.lat + (b.lat - a.lat) * f, lng: a.lng + (b.lng - a.lng) * f);
}

// ---------------------------------------------------------------- GPX

typedef _Fix = ({int t, _P p, double acc, double? spd});

/// Every GPX fix, parsed with a local regular expression.
List<_Fix> _fixes(String gpx, int startEpochS) => [
  for (final m in RegExp(
    '<trkpt lat="([-0-9.]+)" lon="([-0-9.]+)"><time>([^<]+)</time>'
    '<extensions><napstop:acc>([0-9.]+)</napstop:acc>'
    '(?:<napstop:spd>([0-9.]+)</napstop:spd>)?',
  ).allMatches(gpx))
    (
      t:
          DateTime.parse(m.group(3)!).millisecondsSinceEpoch ~/ 1000 -
          startEpochS,
      p: (lat: double.parse(m.group(1)!), lng: double.parse(m.group(2)!)),
      acc: double.parse(m.group(4)!),
      spd: m.group(5) == null ? null : double.parse(m.group(5)!),
    ),
];

int _startEpoch(_J fixture) =>
    DateTime.parse(_obj(fixture['trace'])['startTime']! as String)
        .millisecondsSinceEpoch ~/
    1000;

// ---------------------------------------------------------------- oracle

/// Independent off-route oracle for one Phủ Lý profile.
typedef _Off = ({
  _P d,
  _P w,
  double offsetM,
  List<(int, double)> straight,
  int closestT,
  double dMin,
  int departT,
  double needM,
  double atDepartT,
  double beforeDepartT,
  List<_Fix> fixes,
  int durationS,
});

_Off _offOracle(String id) {
  final profile = _readJson('${dataDir.path}/profiles/$id.json');
  final route = _readJson(
    '${dataDir.path}/routes/${profile['route']! as String}.json',
  );
  final fixture = _fixture(id);
  final wps = [
    for (final w in (route['waypoints']! as List).cast<_J>())
      (
        id: w['id']! as String,
        p: (
          lat: (w['lat']! as num).toDouble(),
          lng: (w['lng']! as num).toDouble(),
        ),
      ),
  ];
  final wi = wps.indexWhere((w) => w.id == profile['destination']);
  final w = wps[wi].p;
  final prev = wps[wi - 1].p;
  final offset = (profile['destinationOffsetM']! as int).toDouble();
  // Positive offset = left of the travel direction previous -> W.
  final d = _destPoint(w, _bearing(prev, w) - 90, offset);

  // Motion truth (route metres per tick). Positions: own polyline walk
  // anchored at W with s(W) = fixture truth.destinationRouteM.
  final (p, r) = ProfileRepository(dataDir).load(id);
  final states = buildTrace(p, r).truth.states;
  final sW = (_obj(fixture['truth'])['destinationRouteM']! as int).toDouble();
  _P posAt(double s) {
    var rel = s - sW;
    if (rel <= 0) {
      var i = wi;
      var back = -rel;
      while (i > 0) {
        final len = _dist(wps[i - 1].p, wps[i].p);
        if (back <= len) {
          return _along(wps[i].p, wps[i - 1].p, back);
        }
        back -= len;
        i--;
      }
      return wps.first.p;
    }
    var i = wi;
    while (i + 1 < wps.length) {
      final len = _dist(wps[i].p, wps[i + 1].p);
      if (rel <= len) {
        return _along(wps[i].p, wps[i + 1].p, rel);
      }
      rel -= len;
      i++;
    }
    return wps.last.p;
  }

  final straight = [for (final st in states) (st.t, _dist(posAt(st.s), d))];
  final dMin = straight.map((e) => e.$2).reduce(min);
  // First tick at the minimum (dwelling ticks share s, so the tie is exact
  // up to floating noise).
  final closest = straight.firstWhere((e) => e.$2 <= dMin + 1e-6);
  final need = dMin + max(500, 0.5 * dMin);
  final depart = straight.firstWhere((e) => e.$1 > closest.$1 && e.$2 >= need);
  final before = straight.lastWhere((e) => e.$1 < depart.$1);
  return (
    d: d,
    w: w,
    offsetM: offset,
    straight: straight,
    closestT: closest.$1,
    dMin: dMin,
    departT: depart.$1,
    needM: need,
    atDepartT: depart.$2,
    beforeDepartT: before.$2,
    fixes: _fixes(_text('$id.gpx'), _startEpoch(fixture)),
    durationS: _obj(fixture['trace'])['durationS']! as int,
  );
}

// ---------------------------------------------------------------- validate

List<String> _validate(String id, String expectText, {String? gpx}) =>
    validatePair(
      gpxLabel: '$id.gpx',
      gpxBytes: utf8.encode(gpx ?? _text('$id.gpx')),
      expectLabel: '$id.expect.json',
      expectBytes: utf8.encode(expectText),
    );

List<String> _mutate(String id, void Function(_J fixture) f) {
  final j = _fixture(id);
  f(j);
  return _validate(id, '${const JsonEncoder.withIndent('  ').convert(j)}\n');
}

const String _v15 =
    'allowFallbackFirst cannot be used with config.kill or killSweep';
const String _v16 =
    'allowFallbackFirst needs an expect entry for alarm with ringNow false';

/// V14: the existing bool message of profile and validate.
const String _v14 = 'must be true or false';

/// Errors on `cases[index].allowFallbackFirst` of [id].
List<String> _afErrors(List<String> errors, String id, int index) => [
  for (final e in errors)
    if (e.startsWith('$id.expect.json:cases[$index].allowFallbackFirst: ')) e,
];

/// Loads profile [id] after [f] mutated its JSON; returns the
/// [ProfileException] text or null when it parses.
String? _profileError(String id, void Function(_J profile) f) {
  final json = _readJson('${dataDir.path}/profiles/$id.json');
  f(json);
  final route = parseRoute(
    _readJson('${dataDir.path}/routes/${json['route']! as String}.json'),
    file: 'routes/${json['route']}.json',
  );
  try {
    parseProfile(json, file: 'profiles/$id.json', route: route);
    return null;
  } on ProfileException catch (e) {
    return e.toString();
  }
}

void main() {
  // ------------------------------------------------------------ TG57
  group('TG57 legacy GPX unchanged (T11.2 §7)', () {
    test('15 legacy + T11.2 + T11.3 GPX, 34 fixture files + README', () {
      final names = {
        for (final f in fixturesDir.listSync().whereType<File>())
          f.uri.pathSegments.last,
      };
      expect(names, {
        'README.md',
        for (final id in [
          ..._legacyIds,
          _off2k,
          'coach_gb_caugie_gappass',
        ]) ...['$id.gpx', '$id.expect.json'],
      });
    });

    test('2 km GPX = 1.5 km GPX except <name> x2 and the trk <desc>', () {
      // coach_gb_phuly_offroute.gpx is hash-pinned by
      // legacy_gpx_unchanged_test; this pins the new GPX through it.
      final a = _text('$_off.gpx').split('\n');
      final b = _text('$_off2k.gpx').split('\n');
      expect(b.length, a.length);
      final diff = [
        for (var i = 0; i < a.length; i++)
          if (a[i] != b[i]) (a[i].trim(), b[i].trim()),
      ];
      expect(diff, [
        ('<name>$_off</name>', '<name>$_off2k</name>'),
        ('<name>$_off</name>', '<name>$_off2k</name>'),
        (
          '<desc>Xe khách Giáp Bát → Phủ Lý, đích cách đường 1,5 km</desc>',
          '<desc>Xe khách Giáp Bát → Phủ Lý, đích cách đường 2 km</desc>',
        ),
      ]);
      expect(
        RegExp('<trkpt ').allMatches(b.join('\n')).length,
        _obj(_fixture(_off2k)['trace'])['sampleCount'],
      );
    });

    test('LF only, no BOM, trailing newline in every fixture file', () {
      for (final f in fixturesDir.listSync().whereType<File>()) {
        final bytes = f.readAsBytesSync();
        final name = f.uri.pathSegments.last;
        expect(bytes.contains(0x0D), isFalse, reason: name);
        expect(bytes.take(3).toList(), isNot([0xEF, 0xBB, 0xBF]));
        expect(bytes.last, 0x0A, reason: name);
      }
    });
  });

  // ------------------------------------------------------------ TG59
  group('TG59 independent oracle (T11.2 §4)', () {
    final o15 = _offOracle(_off);
    final o2k = _offOracle(_off2k);
    final f15 = _fixture(_off);
    final f2k = _fixture(_off2k);

    test('effective destination D: own spherical offset matches fixture', () {
      for (final (o, f) in [(o15, f15), (o2k, f2k)]) {
        final dest = _obj(f['destination']);
        final fixD = (
          lat: (dest['lat']! as num).toDouble(),
          lng: (dest['lng']! as num).toDouble(),
        );
        expect(dest['offsetM'], o.offsetM.toInt());
        expect(_dist(fixD, o.d), lessThan(1.0), reason: '${dest['offsetM']}');
        expect((_dist(fixD, o.w) - o.offsetM).abs(), lessThan(0.5));
      }
      expect(_dist(o15.d, o2k.d), closeTo(500, 0.5));
    });

    test('1.5 km closest = (2425, 1500, 2645) by hand and by oracle', () {
      expect(o15.closestT, 2425);
      expect(o15.dMin.round(), 1500);
      expect(o15.departT, 2645);
      expect(_obj(_obj(f15['truth'])['closest']), {
        't': 2425,
        'straightM': 1500,
        'departT': 2645,
      });
    });

    test('2 km closest = (2425, 2000, 2690) by hand and by oracle', () {
      final why =
          'dMin ${o2k.dMin}, need ${o2k.needM}, '
          'at departT ${o2k.atDepartT}, tick before ${o2k.beforeDepartT}';
      expect(o2k.closestT, 2425, reason: why);
      expect(o2k.dMin.round(), 2000, reason: why);
      expect(o2k.departT, 2690, reason: why);
      expect(_obj(_obj(f2k['truth'])['closest']), {
        't': 2425,
        'straightM': 2000,
        'departT': 2690,
      });
      // The tick is not decided by rounding noise of the oracle geometry.
      expect(o2k.atDepartT - o2k.needM, greaterThan(1), reason: why);
      expect(o2k.needM - o2k.beforeDepartT, greaterThan(1), reason: why);
    });

    test('closest.t is the arrival at the stop, read from the GPX', () {
      for (final (o, f) in [(o15, f15), (o2k, f2k)]) {
        final stop = (_obj(f['truth'])['stops']! as List).cast<_J>().single;
        expect(stop['arriveT'], o.closestT);
        expect(stop['departT'], 2510);
        final byT = {for (final x in o.fixes) x.t: x};
        // Moving one tick before, stopped from closest.t until the stop
        // departs (GPX speed noise sigma 0.3 m/s).
        expect(byT[o.closestT - 5]!.spd, greaterThan(1));
        for (var t = o.closestT; t <= 2505; t += 5) {
          expect(byT[t]!.spd, lessThan(1), reason: 't $t');
          expect(
            (_dist(byT[t]!.p, o.d) - o.offsetM).abs(),
            lessThan(25),
            reason: 't $t',
          );
        }
        // TR38: closest + 80 is still inside the stop.
        expect(o.closestT + 80, lessThan(stop['departT']! as int));
      }
    });

    test('never inside 1 km: oracle truth and every GPX fix', () {
      for (final o in [o15, o2k]) {
        expect(o.straight.every((e) => e.$2 > 1000), isTrue);
        expect(o.fixes.every((x) => _dist(x.p, o.d) > 1000), isTrue);
        expect(o.fixes.last.t, o.durationS);
      }
      // GPX minimum stays near the offset (noise <= 25 m).
      final gpxMin = o2k.fixes.map((x) => _dist(x.p, o2k.d)).reduce(min);
      expect(gpxMin, closeTo(2000, 25));
    });

    test('2 km GPX crosses the opening distance around departT', () {
      final byT = {for (final x in o2k.fixes) x.t: x};
      // Not opened one tick earlier by more than the noise, opened by
      // departT within the noise.
      expect(_dist(byT[2685]!.p, o2k.d), lessThan(o2k.needM));
      expect(_dist(byT[2690]!.p, o2k.d), greaterThan(o2k.needM - 25));
      expect(_dist(byT[2695]!.p, o2k.d), greaterThan(o2k.needM));
    });

    test('TR38 + TR27 (1.5 km): FALLBACK ringNow false [2425, 2505]', () {
      final tr38 = _caseOf(f15, 'distance_1000');
      expect(tr38['testIds'], ['TR38']);
      expect(tr38['allowFallbackFirst'], isTrue);
      expect(tr38['forbid'], ['overshoot', 'gpsLost']);
      expect(tr38['forbidMatch'], [
        {'event': 'alarm', 'reason': 'DISTANCE'},
        {'event': 'alarm', 'reason': 'PASSED_CLOSEST'},
        {'event': 'alarm', 'ringNow': true},
      ]);
      final tr27 = _caseOf(f15, 'summary_unknown');
      expect(tr27['allowFallbackFirst'], isTrue);
      expect(_expectList(tr27).map((e) => e['event']), ['alarm', 'tripEnded']);
      for (final c in [tr38, tr27]) {
        final fb = _expectList(c).first;
        expect(fb['event'], 'alarm');
        expect(fb['reason'], 'FALLBACK');
        expect(fb['ringNow'], isFalse);
        expect([fb['notBefore'], fb['notAfter']], [2425, 2505]);
        expect(
          [fb['notBefore'], fb['notAfter']],
          [o15.closestT, o15.closestT + 80],
        );
        expect(fb['window'], {
          'notBefore': {'anchor': 'closest', 'offsetS': 0},
          'notAfter': {'anchor': 'closest', 'offsetS': 80},
        });
      }
      // No case of the 1.5 km trace still expects PASSED_CLOSEST.
      expect(
        _cases(f15)
            .expand(_expectList)
            .any((e) => e['reason'] == 'PASSED_CLOSEST'),
        isFalse,
      );
    });

    test('TR32 + TR27 (2 km): PASSED_CLOSEST [2690, 2720]', () {
      final tr32 = _caseOf(f2k, 'distance_1000');
      expect(tr32['testIds'], ['TR32']);
      expect(tr32.containsKey('allowFallbackFirst'), isFalse);
      final e = _expectList(tr32).single;
      expect(e['reason'], 'PASSED_CLOSEST');
      expect(e.containsKey('ringNow'), isFalse);
      expect([e['notBefore'], e['notAfter']], [2690, 2720]);
      expect([e['notBefore'], e['notAfter']], [o2k.departT, o2k.departT + 30]);
      expect(o2k.departT + 30, lessThanOrEqualTo(o2k.durationS));
      expect(o2k.durationS, 3240);
      expect(tr32['forbidMatch'], [
        {'event': 'alarm', 'reason': 'DISTANCE'},
      ]);
      final tr27 = _caseOf(f2k, 'summary_unknown');
      expect(tr27['testIds'], ['TR27']);
      expect(tr27.containsKey('allowFallbackFirst'), isFalse);
      expect(_expectList(tr27).map((e) => e['event']), ['tripEnded']);
      expect(tr27['expectSummary'], {'vehicleGuess': 'UNKNOWN'});
    });

    test('coach_md_tb: A = 7310 from GPX; TR03 / TR09 windows (Q10 = A)', () {
      final f = _fixture(_md);
      final dest = _obj(f['destination']);
      final d = (
        lat: (dest['lat']! as num).toDouble(),
        lng: (dest['lng']! as num).toDouble(),
      );
      // Arrival: first fix within 30 m of the destination with speed
      // < 0.3 m/s (independent of the generator's arrivalT).
      final a = _fixes(
        _text('$_md.gpx'),
        _startEpoch(f),
      ).firstWhere((x) => _dist(x.p, d) <= 30 && (x.spd ?? 0) < 0.3).t;
      expect(a, 7310);
      expect(_obj(f['truth'])['arrivalT'], a);

      // PRD §4 marks: pre-alert 30 min, smart 10 min, time mode 15 min.
      // Q10 = A: early bound 1.5 x mark, late bound mark - 60 s.
      const preMark = 30 * 60;
      const smartMark = 10 * 60;
      const timeMark = 15 * 60;
      List<Object?> win(_J e) => [e['notBefore'], e['notAfter']];

      final t15 = _caseOf(f, 'time_15');
      final pre = _expectList(t15).singleWhere((e) => e['event'] == 'preAlert');
      expect(win(pre), [a - preMark * 3 ~/ 2, a - (preMark - 60)]);
      expect(win(pre), [4610, 5570]);
      expect(pre['window'], {
        'notBefore': {'anchor': 'arrival', 'offsetS': -2700},
        'notAfter': {'anchor': 'arrival', 'offsetS': -1740},
      });
      final time = _expectList(t15).singleWhere((e) => e['reason'] == 'TIME');
      expect(win(time), [a - timeMark - 60, a - timeMark + 60]);
      expect(win(time), [6350, 6470]);

      final smart = _expectList(_caseOf(f, 'smart'))
          .singleWhere((e) => e['reason'] == 'SMART_TIME');
      expect(win(smart), [a - smartMark * 3 ~/ 2, a - (smartMark - 60)]);
      expect(win(smart), [6410, 6770]);
      expect(smart['window'], {
        'notBefore': {'anchor': 'arrival', 'offsetS': -900},
        'notAfter': {'anchor': 'arrival', 'offsetS': -540},
      });
    });
  });

  // ------------------------------------------------- adversarial V14-V16
  group('T11.2 V14-V16 mutations (tester)', () {
    final f15 = _fixture(_off);
    final i38 = _caseIndex(f15, 'distance_1000');
    final i27 = _caseIndex(f15, 'summary_unknown');

    test('positive controls: both Phủ Lý fixtures valid as committed', () {
      expect(_validate(_off, _text('$_off.expect.json')), isEmpty);
      expect(_validate(_off2k, _text('$_off2k.expect.json')), isEmpty);
      // The round trip of the mutation helper itself is lossless.
      expect(_mutate(_off, (_) {}), isEmpty);
    });

    for (final bad in <Object?>[null, 0, 1, 'true', 'false', <Object?>[], {}]) {
      test('V14 allowFallbackFirst ${jsonEncode(bad)} is rejected', () {
        final errors = _mutate(_off, (j) {
          _cases(j)[i38]['allowFallbackFirst'] = bad;
        });
        expect(_afErrors(errors, _off, i38), [
          '$_off.expect.json:cases[$i38].allowFallbackFirst: $_v14',
        ], reason: errors.join('\n'));
        expect(
          _profileError(_off, (p) {
            (p['cases']! as List).cast<_J>()[i38]['allowFallbackFirst'] = bad;
          }),
          'profiles/$_off.json: cases[$i38].allowFallbackFirst: $_v14',
        );
      });
    }

    final v16Mutations = <String, void Function(_J c)>{
      'FALLBACK ringNow true': (c) => _expectList(c).first['ringNow'] = true,
      'FALLBACK ringNow removed': (c) => _expectList(c).first.remove('ringNow'),
      'FALLBACK moved to forbidMatch only': (c) {
        final fb = _expectList(c).first;
        (c['expect']! as List).removeAt(0);
        ((c['forbidMatch'] ??= <Object?>[]) as List).add({
          'event': 'alarm',
          'ringNow': fb['ringNow'],
        });
      },
    };
    for (final MapEntry(key: name, value: f) in v16Mutations.entries) {
      for (final i in [i38, i27]) {
        test('V16 $name (cases[$i])', () {
          final errors = _mutate(_off, (j) => f(_cases(j)[i]));
          expect(_afErrors(errors, _off, i), [
            '$_off.expect.json:cases[$i].allowFallbackFirst: $_v16',
          ], reason: errors.join('\n'));
        });
      }
    }

    test('V16 ringNow false on a non-alarm event does not satisfy it', () {
      final errors = _mutate(_off, (j) {
        final fb = _expectList(_cases(j)[i27]).first;
        fb['event'] = 'preAlert';
        fb.remove('reason');
      });
      // ringNow is illegal on preAlert, and V16 still reports.
      expect(
        errors.any((e) => e.contains('cases[$i27].expect[0].ringNow')),
        isTrue,
        reason: errors.join('\n'),
      );
      expect(_afErrors(errors, _off, i27), [
        '$_off.expect.json:cases[$i27].allowFallbackFirst: $_v16',
      ]);
    });

    test('V15 beats V16: kill + no FALLBACK gives one V15 error', () {
      final errors = _mutate(_off, (j) {
        final c = _cases(j)[i38];
        _obj(c['config'])['kill'] = {'t': 1200};
        (c['expect']! as List).removeAt(0);
      });
      expect(_afErrors(errors, _off, i38), [
        '$_off.expect.json:cases[$i38].allowFallbackFirst: $_v15',
      ], reason: errors.join('\n'));
    });

    test('V15 on a real kill case of train_hn_dh; false is accepted', () {
      final dh = _fixture('train_hn_dh');
      final iKill = _caseIndex(dh, 'distance_1000_kill');
      expect(iKill, isNonNegative);
      var errors = _mutate('train_hn_dh', (j) {
        _cases(j)[iKill]['allowFallbackFirst'] = true;
      });
      expect(_afErrors(errors, 'train_hn_dh', iKill), [
        'train_hn_dh.expect.json:cases[$iKill].allowFallbackFirst: $_v15',
      ], reason: errors.join('\n'));
      errors = _mutate('train_hn_dh', (j) {
        _cases(j)[iKill]['allowFallbackFirst'] = false;
      });
      expect(errors, isEmpty);
    });

    test('V16 on the 2 km TR32 case (PASSED_CLOSEST is not enough)', () {
      final f2k = _fixture(_off2k);
      final i = _caseIndex(f2k, 'distance_1000');
      // allowFallbackFirst without a ringNow-false alarm on TR32: V16.
      final errors = _mutate(_off2k, (j) {
        _cases(j)[i]['allowFallbackFirst'] = true;
      });
      expect(_afErrors(errors, _off2k, i), [
        '$_off2k.expect.json:cases[$i].allowFallbackFirst: $_v16',
      ], reason: errors.join('\n'));
    });

    test('profile and validate give the same V15 / V16 text', () {
      final p16 = _profileError(_off, (p) {
        final c = (p['cases']! as List).cast<_J>()[i38];
        (c['expect']! as List).removeAt(0);
        // Keep the case non-empty so that only V16 is at stake.
        (c['expect']! as List).add({
          'event': 'alarm',
          'reason': 'FALLBACK',
          'ringNow': true,
          'notBefore': {'anchor': 'closest'},
          'notAfter': {'anchor': 'closest', 'offsetS': 80},
          'ref': 'x',
        });
      });
      expect(p16, 'profiles/$_off.json: cases[$i38].allowFallbackFirst: $_v16');
      final p15 = _profileError(_off, (p) {
        final c = (p['cases']! as List).cast<_J>()[i27];
        _obj(c['config'])['kill'] = {'t': 1200};
      });
      expect(p15, 'profiles/$_off.json: cases[$i27].allowFallbackFirst: $_v15');
      // Same mutation through validate: same message after the path.
      final v15 = _mutate(_off, (j) {
        _obj(_cases(j)[i27]['config'])['kill'] = {'t': 1200};
      });
      expect(
        _afErrors(v15, _off, i27).single.split('allowFallbackFirst: ').last,
        p15!.split('allowFallbackFirst: ').last,
      );
    });

    test('removing allowFallbackFirst keeps the fixture schema-valid', () {
      // P02 exemption is the harness's job; validate must not demand the key
      // just because a ringNow-false alarm is expected.
      final errors = _mutate(_off, (j) {
        _cases(j)[i38].remove('allowFallbackFirst');
      });
      expect(errors, isEmpty);
    });
  });
}
