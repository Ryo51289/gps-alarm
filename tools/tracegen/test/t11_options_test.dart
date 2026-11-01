// Generator options and resolution added by T11 (TG10, TG12–TG18).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const ExpectFallbackSpec _tol = ExpectFallbackSpec(
  modeAt: WindowEdge(Anchor('arrival', AnchorKind.arrival), 0),
  toleranceLo: -300,
  toleranceHi: 120,
  ref: 'test',
);

ResolvedFallback window(int modeAtT, int killT) => fallbackWindow(
  spec: _tol,
  modeAtT: modeAtT,
  killT: killT,
  sampleIntervalS: 5,
  durationS: 100000,
);

/// West-bound route at lat 20: `p` [eastM] east of `w`, then `q` 3 km west
/// of `w`; destination `w`.
(Profile, Route) westRoute({required int offset, double eastM = 1000}) {
  final kx = kMetresPerDegLat * cosDeg(20);
  Map<String, Object?> wp(String id, double east) => {
    'id': id,
    'lat': 20.0,
    'lng': 105 + east / kx,
    'source': 'approx',
  };
  return synth(
    route: {
      'id': 'synth',
      'title': 'Synthetic west-bound route',
      'attribution': 'none',
      'waypoints': [wp('p', eastM), wp('w', 0), wp('q', -3000)],
    },
    profile: synthProfileJson(
      destination: 'w',
      first: 'p',
      overrides: {'destinationOffsetM': offset, 'endDwellS': 30},
    ),
  );
}

Map<String, Object?> caseOf(GeneratedTrace t, String id) =>
    ((jsonDecode(t.expectText) as Map<String, Object?>)['cases']!
            as List<Object?>)
        .cast<Map<String, Object?>>()
        .firstWhere((c) => c['id'] == id);

/// Removes every `ref` (the golden layout of §2.5 elides them).
Object? withoutRefs(Object? json) => switch (json) {
  final Map<String, Object?> m => {
    for (final e in m.entries)
      if (e.key != 'ref') e.key: withoutRefs(e.value),
  },
  final List<Object?> l => [for (final v in l) withoutRefs(v)],
  _ => json,
};

GeneratedTrace load(String id) {
  final (p, r) = ProfileRepository(dataDir).load(id);
  return buildTrace(p, r);
}

void main() {
  test('TG10 expectFallback formula (T11 §5.3)', () {
    final a = window(33700, 31390);
    expect(
      [a.asOfT, a.estimateT, a.notBefore, a.notAfter],
      [31385, 33559, 33259, 33679],
    );
    const arrival = 20000;
    expect(window(arrival - 900, arrival - 2400).estimateT, arrival - 960);
    expect(window(arrival - 600, arrival - 1800).estimateT, arrival - 630);
    final c = window(2340, 1825);
    expect([c.estimateT, c.notBefore, c.notAfter], [2370, 2070, 2490]);
    final d = window(30000 + 600 + 1000, 1000);
    expect(d.estimateT, d.modeAtT + 30 - 1800);
    expect(window(500, 0).notBefore, 230);
  });

  test('TG12 effective destination is left (+) or right (-) of travel', () {
    final kx = kMetresPerDegLat * cosDeg(20);
    const w = LatLng(20, 105);
    final p = LatLng(20, 105 + 1000 / kx);
    for (final (offset, south) in [(1500, true), (-1500, false)]) {
      final d = effectiveDestination(w, p, offset);
      expect(distanceM(d, w), closeTo(1500, 0.01));
      expect(d.lat < w.lat, south, reason: '$offset');
      expect(d.lng, closeTo(w.lng, 1e-9));
    }
    expect(identical(effectiveDestination(w, p, 0), w), isTrue);

    for (final offset in [1500, -1500]) {
      final (profile, route) = westRoute(offset: offset);
      final json = jsonDecode(
        buildTrace(profile, route).expectText,
      ) as Map<String, Object?>;
      final dest = json['destination']! as Map<String, Object?>;
      expect(dest['id'], 'w');
      expect(dest['offsetM'], offset);
      expect(dest.keys, ['id', 'lat', 'lng', 'offsetM']);
    }
    final (plain, route) = westRoute(offset: 0);
    final json =
        jsonDecode(buildTrace(plain, route).expectText) as Map<String, Object?>;
    expect((json['destination']! as Map).containsKey('offsetM'), isFalse);
    expect((json['truth']! as Map).containsKey('closest'), isFalse);
  });

  test('TG13 closest approach and departT', () {
    final times = [for (var j = 0; j < 9; j++) j * 5];
    final c = closestOf(times, [
      3000,
      2000,
      1000,
      1000,
      1000,
      1200,
      1499,
      1500,
      2000,
    ], file: 'x');
    expect([c.t, c.straightM, c.departT], [10, 1000, 35]);
    final big = closestOf(times, [
      3000,
      1500,
      1600,
      2000,
      2249,
      2250,
      2300,
      2400,
      2500,
    ], file: 'x');
    expect([big.t, big.straightM, big.departT], [5, 1500, 25]);
    expect(
      () => closestOf(times, [
        3000,
        2000,
        1000,
        1100,
        1200,
        1300,
        1400,
        1450,
        1499,
      ], file: 'x'),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.message,
          'message',
          contains('no departT'),
        ),
      ),
    );

    final (profile, route) = westRoute(offset: 1500);
    final t = buildTrace(profile, route);
    final closest = t.truth.closest!;
    expect(closest.straightM, closeTo(1500, 2));
    final j = t.truth.states.indexWhere((s) => s.t == closest.departT);
    expect(
      t.truth.straightM[j],
      greaterThanOrEqualTo(
        t.truth.straightM.reduce((a, b) => a < b ? a : b) + 750,
      ),
    );
    final json = jsonDecode(t.expectText) as Map<String, Object?>;
    expect(((json['truth']! as Map)['closest']! as Map).keys, [
      't',
      'straightM',
      'departT',
    ]);
  });

  test('TG14 straightT is null when the threshold is never reached', () {
    final (profile, route) = westRoute(offset: 1500, eastM: 5000);
    final truth = buildTrace(profile, route).truth;
    final byX = {
      for (final m in truth.distanceMilestones()) m.thresholdM: m.straightT,
    };
    expect(byX.keys, containsAll([200, 500, 1000, 2000, 3000]));
    expect([byX[200], byX[500], byX[1000]], [null, null, null]);
    expect(byX[2000], isNotNull);
    expect(byX[3000], isNotNull);
  });

  group('TG15 gap starting while dwelling', () {
    Map<String, Object?> profileJson(Object gap) => synthProfileJson(
      overrides: {
        'endDwellS': 120,
        'stops': [
          {'at': 'mid', 'dwellS': 60},
        ],
        'gpsGaps': [gap],
      },
    );
    final arrival = {'anchor': 'arrival', 'offsetS': 60};

    test('resolves fromT and toT', () {
      final (p, r) = synth(
        profile: profileJson({'atStop': 'mid', 'offsetS': 5, 'until': arrival}),
      );
      final t = buildTrace(p, r);
      final stop = t.truth.stops.single;
      final gap = t.truth.gaps.single;
      expect(gap.fromT, stop.arriveT + 5);
      expect(gap.toT, t.truth.arrivalT + 60);
      expect(t.sensor.observations.where((o) => gap.contains(o.t)), isEmpty);
      expect(t.segments, hasLength(2));

      final (p2, r2) = synth(
        profile: profileJson({
          'atStop': 'mid',
          'offsetS': 10,
          'durationS': 100,
        }),
      );
      final g2 = buildTrace(p2, r2).truth.gaps.single;
      expect([g2.fromT, g2.toT], [stop.arriveT + 10, stop.arriveT + 110]);
    });

    for (final (name, gap, field, build) in [
      (
        'offset past the dwell',
        {'atStop': 'mid', 'offsetS': 65, 'until': arrival},
        'gpsGaps[0].offsetS',
        true,
      ),
      (
        'not a declared stop',
        {'atStop': 'a', 'offsetS': 5, 'until': arrival},
        'gpsGaps[0].atStop',
        false,
      ),
      (
        'until uses a gap anchor',
        {
          'atStop': 'mid',
          'offsetS': 5,
          'until': {'anchor': 'gpsGap[0].start'},
        },
        'gpsGaps[0].until.anchor',
        false,
      ),
      (
        'ends after the last tick',
        {
          'atStop': 'mid',
          'offsetS': 5,
          'until': {'anchor': 'arrival', 'offsetS': 600},
        },
        'gpsGaps[0].until',
        true,
      ),
      (
        'both durationS and until',
        {'atStop': 'mid', 'offsetS': 5, 'durationS': 60, 'until': arrival},
        'gpsGaps[0].durationS',
        false,
      ),
    ]) {
      test('rejects: $name', () {
        expect(
          () {
            final (p, r) = synth(profile: profileJson(gap));
            if (build) {
              buildTrace(p, r);
            }
          },
          throwsA(
            isA<ProfileException>().having(
              (e) => e.path,
              'path',
              'profiles/synth.json: $field',
            ),
          ),
        );
      });
    }
  });

  test('TG16 scripted outliers beyond the destination', () {
    Map<String, Object?> group([String? side]) => {
      'atRemainingM': 3000,
      'count': 3,
      'distanceToDestinationM': 1800,
      'accM': 30,
      'side': ?side,
    };
    GeneratedTrace run(Map<String, Object?> g) {
      final (p, r) = synth(
        profile: synthProfileJson(
          overrides: {
            'endDwellS': 30,
            'scriptedOutliers': [g],
          },
        ),
      );
      return buildTrace(p, r);
    }

    final beyond = run(group('beyond'));
    final dest = beyond.truth.destination;
    final scripted = [
      for (final o in beyond.sensor.outliers)
        if (o.kind == OutlierKind.scripted) o.t,
    ];
    expect(scripted, hasLength(3));
    for (final t in scripted) {
      final obs = beyond.sensor.observations.firstWhere((o) => o.t == t);
      final truthPos = beyond.truth.states.firstWhere((s) => s.t == t).pos;
      expect(distanceM(obs.pos, dest), closeTo(1800, 1));
      final (pe, pn) = localEnM(dest, obs.pos);
      final (te, tn) = localEnM(dest, truthPos);
      expect(pe * te + pn * tn, lessThan(0));
    }
    expect(run(group()).gpxText, run(group('behind')).gpxText);
    expect(run(group()).gpxText, isNot(beyond.gpxText));
  });

  test('TG17 dropSpeedAtStops only removes speed while dwelling', () {
    GeneratedTrace run({required bool drop}) {
      final (p, r) = synth(
        profile: synthProfileJson(
          overrides: {
            'startDwellS': 30,
            'endDwellS': 30,
            'stops': [
              {'at': 'mid', 'dwellS': 60},
            ],
            'dropSpeedAtStops': drop,
          },
        ),
      );
      return buildTrace(p, r);
    }

    final keep = run(drop: false);
    final drop = run(drop: true);
    final a = keep.sensor.observations;
    final b = drop.sensor.observations;
    expect(b, hasLength(a.length));
    final dwelling = {
      for (final s in keep.truth.states)
        if (s.dwelling) s.t,
    };
    expect(dwelling, isNotEmpty);
    for (var j = 0; j < a.length; j++) {
      expect(b[j].t, a[j].t);
      expect(b[j].pos.lat, a[j].pos.lat);
      expect(b[j].pos.lng, a[j].pos.lng);
      expect(b[j].accM, a[j].accM);
      expect(a[j].speedMps, isNotNull);
      if (dwelling.contains(a[j].t)) {
        expect(b[j].speedMps, isNull, reason: 't = ${a[j].t}');
      } else {
        expect(b[j].speedMps, a[j].speedMps, reason: 't = ${a[j].t}');
      }
    }
  });

  test('TG18 golden case layout of T11 §2.5 (TR35, TR18)', () {
    const anchorOvershoot = {
      'notBefore': {'anchor': 'overshoot', 'offsetS': -15},
      'notAfter': {'anchor': 'overshoot', 'offsetS': 60},
    };
    final tr35 = withoutRefs(
      caseOf(
        load('coach_gb_phuly_overshoot'),
        'distance_1000_fallback_silenced',
      ),
    );
    expect(
      jsonEncode(tr35),
      jsonEncode({
        'id': 'distance_1000_fallback_silenced',
        'status': 'final',
        'testIds': ['TR35'],
        'config': {
          'mode': 'distance',
          'thresholdM': 1000,
          'preAlert': true,
          'kill': {'t': 1825, 'anchor': 'arrival', 'offsetS': -600},
          'relaunch': {
            'at': {'anchor': 'osFallbackFired', 'offsetS': 30},
            'fallbackStatus': 'auto',
          },
          'osRingMaxS': 60,
        },
        'expect': [
          {
            'event': 'alarm',
            'reason': 'OVERSHOOT',
            'ringNow': true,
            'notBefore': 2605,
            'notAfter': 2680,
            'window': anchorOvershoot,
          },
          {
            'event': 'overshoot',
            'notBefore': 2605,
            'notAfter': 2680,
            'window': anchorOvershoot,
          },
        ],
        'expectAfter': [
          {
            'event': 'alarm',
            'reason': 'FALLBACK',
            'ringNow': false,
            'after': {'anchor': 'relaunch', 'offsetS': 0},
            'withinS': [0, 0],
          },
        ],
        'expectFallback': {
          'asOfT': 1820,
          'notBefore': 2070,
          'notAfter': 2490,
          'window': {
            'modeAt': {'anchor': 'straight<=1000', 'offsetS': 0},
            'modeAtT': 2340,
            'killT': 1825,
            'estimateT': 2370,
            'toleranceS': [-300, 120],
          },
        },
        'forbid': <Object?>[],
      }),
    );

    final tr18 = withoutRefs(
      caseOf(load('train_hn_dh'), 'distance_1000_snooze'),
    );
    Map<String, Object?> after(String anchor) => {
      'anchor': anchor,
      'offsetS': 0,
    };
    expect(
      jsonEncode(tr18),
      jsonEncode({
        'id': 'distance_1000_snooze',
        'status': 'final',
        'testIds': ['TR18'],
        'config': {
          'mode': 'distance',
          'thresholdM': 1000,
          'preAlert': true,
          'actions': [
            {
              'at': {'anchor': 'event:alarm', 'offsetS': 20},
              'action': 'snooze',
            },
            {
              'at': {'anchor': 'event:snoozed', 'offsetS': 80},
              'action': 'dismiss',
            },
          ],
        },
        'expect': [
          {
            'event': 'alarm',
            'reason': 'DISTANCE',
            'notBefore': 33680,
            'notAfter': 33715,
            'window': {
              'notBefore': {'anchor': 'route<=1300', 'offsetS': 0},
              'notAfter': {'anchor': 'route<=700', 'offsetS': 0},
            },
          },
        ],
        'expectAfter': [
          {
            'event': 'snoozed',
            'after': after('event:alarm'),
            'withinS': [20, 20],
          },
          {
            'event': 'alarm',
            'reason': 'SNOOZE_END',
            'ringNow': true,
            'after': after('event:alarm'),
            'withinS': [80, 85],
          },
          {
            'event': 'tripEnded',
            'after': after('event:snoozed'),
            'withinS': [80, 80],
          },
        ],
        'expectOutcome': 'SNOOZED',
        'forbid': ['gpsLost', 'overshoot'],
      }),
    );

    // A profile `{t}` is written as `{t}` only.
    final (p, r) = synth(
      profile: synthProfileJson(
        overrides: {
          'endDwellS': 30,
          'cases': [
            {
              'id': 'c',
              'config': {
                'mode': 'distance',
                'thresholdM': 1000,
                'kill': {'t': 100},
              },
              'expect': <Object?>[],
              'forbid': <Object?>[],
            },
          ],
        },
      ),
    );
    final c = caseOf(buildTrace(p, r), 'c');
    expect((c['config']! as Map)['kill'], {'t': 100});
    expect(c.keys, ['id', 'status', 'config', 'expect', 'forbid']);
  });
}
