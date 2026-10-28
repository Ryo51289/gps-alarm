import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

MotionPlan planOf(Map<String, Object?> profile) {
  final (p, r) = synth(profile: profile);
  return MotionPlan.build(p, r);
}

void main() {
  group('MotionPlan (TC07)', () {
    final plan = planOf(synthProfileJson());

    test('respects the limit and stops at both ends', () {
      for (final v in plan.speeds) {
        expect(v, lessThanOrEqualTo(20 + 1e-9));
      }
      expect(plan.speeds.first, 0);
      expect(plan.speeds.last, 0);
    });

    test('respects accel and decel limits', () {
      for (var k = 0; k + 1 < plan.speeds.length; k++) {
        final dk = plan.gridS[k + 1] - plan.gridS[k];
        final a = plan.speeds[k];
        final b = plan.speeds[k + 1];
        expect((b * b - a * a).abs(), lessThanOrEqualTo(2 * 0.5 * dk + 1e-6));
      }
    });

    test('takes 500 + 20 + 20 s', () {
      expect(plan.endT, closeTo(540, 1));
    });

    test('grid covers the route', () {
      expect(plan.gridS.first, 0);
      expect(plan.gridS.last, plan.polyline.lengthM);
      expect(plan.lastIndex, (plan.polyline.lengthM / 10).ceil());
    });
  });

  group('MotionPlan with a stop (TC08)', () {
    final plan = planOf(
      synthProfileJson(
        overrides: {
          'stops': [
            {'at': 'mid', 'dwellS': 60},
          ],
        },
      ),
    );

    test('adds braking, dwell and restart time', () {
      expect(plan.endT, closeTo(640, 1));
    });

    test('dwells at 5 km with zero speed', () {
      final ticks = plan.ticks();
      final dwelling = ticks.where((s) => s.dwelling).toList();
      expect(dwelling.length, inInclusiveRange(11, 13));
      for (final s in dwelling) {
        expect(s.s, closeTo(5000, 5));
        expect(s.speedMps, 0);
      }
      for (var j = 1; j < ticks.length; j++) {
        expect(ticks[j].s, greaterThanOrEqualTo(ticks[j - 1].s));
      }
      expect(plan.stopPoints.single.waypointId, 'mid');
    });
  });

  group('cruise jitter (TC09)', () {
    Map<String, Object?> jittered(int seed) => synthProfileJson(
      overrides: {
        'seed': seed,
        'motion': {
          'accelMps2': 0.5,
          'decelMps2': 0.5,
          'cruiseJitter': 0.1,
          'jitterChunkM': 1000,
        },
      },
    );

    test('factors stay within 1 +- jitter', () {
      final plan = planOf(jittered(1));
      expect(plan.jitterFactors, hasLength(10));
      for (final f in plan.jitterFactors) {
        expect(f, inInclusiveRange(0.9, 1.1));
      }
    });

    test('same seed repeats, another seed differs', () {
      final a = planOf(jittered(1));
      final b = planOf(jittered(1));
      final c = planOf(jittered(2));
      expect(a.arriveT, b.arriveT);
      expect(a.endT, isNot(c.endT));
    });
  });

  group('TruthState', () {
    final plan = planOf(synthProfileJson(overrides: {'startDwellS': 20}));

    test('dwells at the start, then moves along the line', () {
      final s0 = plan.at(0);
      expect(s0.s, 0);
      expect(s0.dwelling, isTrue);
      expect(s0.speedMps, 0);
      final s1 = plan.at(100);
      expect(s1.dwelling, isFalse);
      expect(s1.s, greaterThan(0));
      expect(distanceM(s1.pos, synthPoint(s1.s)), lessThan(0.01));
    });

    test('rejects stops next to each other on the grid', () {
      final (p, r) = synth(
        route: synthRouteJson([
          ('a', 0),
          ('x', 5000),
          ('y', 5012),
          ('b', 10000),
        ]),
        profile: synthProfileJson(
          overrides: {
            'stops': [
              {'at': 'x', 'dwellS': 10},
              {'at': 'y', 'dwellS': 10},
            ],
          },
        ),
      );
      expect(
        () => MotionPlan.build(p, r),
        throwsA(
          isA<ProfileException>().having(
            (e) => e.path,
            'path',
            'profiles/synth.json: stops[1].at',
          ),
        ),
      );
    });
  });
}
