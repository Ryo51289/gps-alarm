// Generator options and resolution added by T11 (TG12–TG18) and T11.1
// (TG42 replaces TG10; TG40).
import 'dart:convert';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

/// [fallbackEstimates] with I = 5 and tolerance [-300, 120] as a list
/// `[estimateT, hintEstimateT, notBefore, notAfter]`.
List<int> estimates(
  CaseMode mode,
  int? threshold,
  String hint,
  int modeAtT,
  int killT,
  int asOfStraightM, {
  int durationS = 100000,
}) {
  final e = fallbackEstimates(
    mode: mode,
    threshold: threshold,
    hint: hint,
    modeAtT: modeAtT,
    killT: killT,
    asOfStraightM: asOfStraightM,
    sampleIntervalS: 5,
    durationS: durationS,
    toleranceLo: -300,
    toleranceHi: 120,
  );
  return [e.estimateT, e.hintEstimateT, e.notBefore, e.notAfter];
}

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
  group('TG42 expectFallback formula (T11.1 §4)', () {
    const d = CaseMode.distance;
    test('(a) distance 1000, train', () {
      expect(estimates(d, 1000, 'train', 33700, 31390, 39206), [
        33303,
        33815,
        33003,
        33423,
      ]);
    });
    test('(b) time 15, train', () {
      expect(estimates(CaseMode.time, 15, 'train', 32890, 31390, 39206), [
        32695,
        33215,
        32395,
        32815,
      ]);
    });
    test('(c) smart, coach: the speed floor sets the lower edge', () {
      expect(estimates(CaseMode.smart, null, 'coach', 6710, 5510, 17355), [
        6590,
        6187,
        5887,
        6710,
      ]);
    });
    test('(d) near zone: hintEstimateT is at least asOfT + 600', () {
      for (final sM in [6000, 0]) {
        expect(estimates(d, 1000, 'coach', 2340, 1825, sM), [
          2370,
          2420,
          2070,
          2490,
        ], reason: 'sM $sM');
      }
    });
    test('(e) early is capped at 3600', () {
      // modeAtT − killT − 600 = 20000 → 20000 ~/ 4 = 5000 → 3600.
      expect(estimates(d, 1000, 'train', 21600, 1000, 0)[0], 21600 + 30 - 3600);
      // 14396 ~/ 4 = 3599, just under the cap.
      expect(estimates(d, 1000, 'train', 15996, 1000, 0)[0], 15996 + 30 - 3599);
    });
    test('(f) bus 20 km/h', () {
      // hT = 4000·432 ~/ 2000 = 864; 3595 + max(600, 864 + 30 − 66) = 4423.
      expect(estimates(d, 1000, 'bus', 4200, 3600, 5000), [
        4230,
        4423,
        3930,
        4350,
      ]);
    });
    test('(g) hint unknown uses 60 km/h like coach', () {
      for (final (mode, threshold, modeAtT, killT, sM) in [
        (CaseMode.smart, null, 6710, 5510, 17355),
        (d, 1000, 33700, 31390, 39206),
        (CaseMode.time, 15, 32890, 31390, 39206),
      ]) {
        final unknown = estimates(
          mode,
          threshold,
          'unknown',
          modeAtT,
          killT,
          sM,
        );
        expect(
          unknown,
          estimates(mode, threshold, 'coach', modeAtT, killT, sM),
        );
        expect(
          unknown[1],
          isNot(estimates(mode, threshold, 'train', modeAtT, killT, sM)[1]),
        );
      }
      // Through resolveCase: vehicleHint unknown on a train trace.
      Map<String, Object?> fallbackCase(String id, {String? hint}) => {
        'id': id,
        'config': {
          'mode': 'distance',
          'thresholdM': 1000,
          'preAlert': true,
          'vehicleHint': ?hint,
          'kill': {'t': 100},
        },
        'expect': <Object?>[],
        'expectFallback': {
          'modeAt': {'anchor': 'straight<=1000'},
          'toleranceS': [-300, 120],
          'ref': 'test',
        },
        'forbid': <Object?>[],
      };
      final (p, r) = synth(
        profile: synthProfileJson(
          overrides: {
            'vehicle': 'train',
            'endDwellS': 30,
            'cases': [
              fallbackCase('plain'),
              fallbackCase('unknown', hint: 'unknown'),
            ],
          },
        ),
      );
      final t = buildTrace(p, r);
      final plain = t.cases[0].fallback!;
      final unknown = t.cases[1].fallback!;
      expect(plain.asOfStraightM, unknown.asOfStraightM);
      expect(
        unknown.asOfStraightM,
        t.truth.straightM[plain.asOfT ~/ 5].floor(),
      );
      List<int> fromSpec(String hint) => estimates(
        d,
        1000,
        hint,
        plain.modeAtT,
        100,
        plain.asOfStraightM,
        durationS: t.truth.endT,
      );
      expect([
        plain.estimateT,
        plain.hintEstimateT,
        plain.notBefore,
        plain.notAfter,
      ], fromSpec('train'));
      expect([
        unknown.estimateT,
        unknown.hintEstimateT,
        unknown.notBefore,
        unknown.notAfter,
      ], fromSpec('unknown'));
    });
    test('(h) both edges are clamped to durationS', () {
      expect(estimates(d, 1000, 'coach', 2340, 1825, 0, durationS: 2400), [
        2370,
        2420,
        2070,
        2400,
      ]);
      expect(
        estimates(d, 1000, 'coach', 2340, 1825, 0, durationS: 2000)[2],
        2000,
      );
    });
  });

  test('TG40 golden key order of the T11.1 keys (T11.1 §1)', () {
    Map<String, Object?> at(String anchor) => {'anchor': anchor};
    final cases = [
      // (i) samplingModes ["policy"] + policyPhaseSweep + expectFallback.
      {
        'id': 'i',
        'config': {
          'mode': 'distance',
          'thresholdM': 1000,
          'preAlert': true,
          'kill': {'t': 100},
        },
        'samplingModes': ['policy'],
        'policyPhaseSweep': true,
        'expect': <Object?>[],
        'expectFallback': {
          'modeAt': at('straight<=1000'),
          'toleranceS': [-300, 120],
          'ref': 'test',
        },
        'forbid': <Object?>[],
      },
      // (ii) every optional key after config, killSweep with statsOnly.
      {
        'id': 'ii',
        'status': 'final',
        'testIds': ['TR37'],
        'config': {'mode': 'distance', 'thresholdM': 1000, 'preAlert': true},
        'policyPhaseSweep': true,
        'expect': <Object?>[],
        'expectAfter': [
          {
            'event': 'tripEnded',
            'after': {'anchor': 'event:alarm', 'offsetS': 30},
            'withinS': [0, 0],
            'ref': 'test',
          },
        ],
        'killSweep': {
          'from': {'t': 60},
          'everyS': 60,
          'notAfter': at('arrival'),
          'earlyFrom': at('straight<=1000'),
          'statsOnly': true,
        },
        'expectOutcome': 'ON_TIME',
        'expectSummary': {'vehicleGuess': 'COACH'},
        'forbid': <Object?>[],
        'forbidMatch': [
          {'event': 'alarm', 'reason': 'OVERSHOOT'},
        ],
        'forbidAfter': [
          {'event': 'gpsLost', 'after': at('arrival')},
        ],
      },
      // (iii) explicit false is not written.
      {
        'id': 'iii',
        'config': {'mode': 'distance', 'thresholdM': 1000, 'preAlert': true},
        'policyPhaseSweep': false,
        'expect': <Object?>[],
        'killSweep': {
          'from': {'t': 60},
          'everyS': 60,
          'notAfter': at('arrival'),
          'earlyFrom': at('straight<=1000'),
          'statsOnly': false,
        },
        'forbid': <Object?>[],
      },
    ];
    final (p, r) = synth(
      profile: synthProfileJson(overrides: {'endDwellS': 30, 'cases': cases}),
    );
    final t = buildTrace(p, r);

    final i = caseOf(t, 'i');
    expect(i.keys, [
      'id',
      'status',
      'config',
      'samplingModes',
      'policyPhaseSweep',
      'expect',
      'expectFallback',
      'forbid',
    ]);
    expect(i['policyPhaseSweep'], isTrue);
    final f = i['expectFallback']! as Map<String, Object?>;
    expect(f.keys, ['asOfT', 'notBefore', 'notAfter', 'window', 'ref']);
    expect((f['window']! as Map).keys, [
      'modeAt',
      'modeAtT',
      'killT',
      'estimateT',
      'asOfStraightM',
      'hintEstimateT',
      'toleranceS',
    ]);

    final ii = caseOf(t, 'ii');
    expect(ii.keys, [
      'id',
      'status',
      'testIds',
      'config',
      'policyPhaseSweep',
      'expect',
      'expectAfter',
      'killSweep',
      'expectOutcome',
      'expectSummary',
      'forbid',
      'forbidMatch',
      'forbidAfter',
    ]);
    final arrival = t.truth.arrivalT;
    final early = t.truth.resolveAnchor(Anchor.parse('straight<=1000'));
    expect(
      jsonEncode(ii['killSweep']),
      jsonEncode({
        'from': {'t': 60},
        'everyS': 60,
        'notAfter': {'t': arrival, 'anchor': 'arrival', 'offsetS': 0},
        'earlyFrom': {'t': early, 'anchor': 'straight<=1000', 'offsetS': 0},
        'statsOnly': true,
      }),
    );

    final iii = caseOf(t, 'iii');
    expect(iii.keys, [
      'id',
      'status',
      'config',
      'expect',
      'killSweep',
      'forbid',
    ]);
    expect((iii['killSweep']! as Map).keys, [
      'from',
      'everyS',
      'notAfter',
      'earlyFrom',
    ]);
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
    final overshootTrace = load('coach_gb_phuly_overshoot');
    final tr35 = withoutRefs(
      caseOf(overshootTrace, 'distance_1000_fallback_silenced'),
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
            // T11.1: from the truth at asOfT (not asserted as numbers here).
            'asOfStraightM': overshootTrace.truth.straightM[1820 ~/ 5].floor(),
            'hintEstimateT': overshootTrace.cases
                .singleWhere(
                  (c) => c.spec.id == 'distance_1000_fallback_silenced',
                )
                .fallback!
                .hintEstimateT,
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
