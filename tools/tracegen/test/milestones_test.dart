import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

void main() {
  group('truth, milestones and anchors (TC15)', () {
    final (profile, route) = synth(
      route: synthRouteJson([
        ('a', 0),
        ('s1', 3000),
        ('g', 5000),
        ('dest', 8000),
        ('end', 11000),
      ]),
      profile: synthProfileJson(
        destination: 'dest',
        overrides: {
          'endDwellS': 10,
          'stops': [
            {'at': 's1', 'dwellS': 60},
          ],
          'gpsGaps': [
            {'at': 'g', 'durationS': 120},
          ],
        },
      ),
    );
    final trace = buildTrace(profile, route);
    final truth = trace.truth;
    final states = truth.states;
    final dest = synthPoint(8000);
    const sDest = 8000.0;

    int firstT(bool Function(TruthState s) test) => states.firstWhere(test).t;

    test('truth summary', () {
      expect(truth.destinationRouteM, closeTo(sDest, 5));
      expect(truth.arrivalT, firstT((s) => s.s >= truth.destinationRouteM));
      expect(truth.endT, states.last.t);
      final stop = truth.stops.single;
      expect(stop.routeM, closeTo(3000, 5));
      expect(stop.departT - stop.arriveT, inInclusiveRange(55, 60));
      expect(stop.name, isNull);
      final gap = truth.gaps.single;
      expect(gap.fromT, firstT((s) => s.s >= 5000));
      expect(gap.toT, gap.fromT + 120);
    });

    test('overshoot after passing the destination', () {
      final o = truth.overshoot!;
      var closest = 0;
      for (var j = 1; j < states.length; j++) {
        if (distanceM(states[j].pos, dest) <
            distanceM(states[closest].pos, dest)) {
          closest = j;
        }
      }
      expect(o.closestT, states[closest].t);
      final limit = distanceM(states[closest].pos, dest) + 1000;
      expect(
        o.t,
        firstT(
          (s) =>
              s.t > truth.destDepartT &&
              s.s > truth.destinationRouteM &&
              distanceM(s.pos, dest) >= limit,
        ),
      );
      expect(truth.resolveAnchor(Anchor.parse('overshoot')), o.t);
    });

    test('resolves every anchor kind', () {
      int r(String a) => truth.resolveAnchor(Anchor.parse(a));
      expect(r('start'), 0);
      expect(r('end'), states.last.t);
      expect(r('arrival'), truth.arrivalT);
      expect(
        r('route<=1000'),
        firstT((s) => truth.destinationRouteM - s.s <= 1000),
      );
      expect(
        r('straight<=1000'),
        firstT((s) => distanceM(s.pos, dest) <= 1000),
      );
      expect(r('gpsGap[0].start'), truth.gaps.single.fromT);
      expect(r('gpsGap[0].end'), truth.gaps.single.toT);
      expect(r('route<=100000'), 0);
    });

    test('clamps windows to [0, durationS]', () {
      expect(truth.arrivalT, lessThan(900));
      expect(truth.resolveEdge(Anchor.parse('arrival'), -900), 0);
      expect(
        truth.resolveEdge(Anchor.parse('arrival'), -100),
        truth.arrivalT - 100,
      );
      expect(truth.resolveEdge(Anchor.parse('start'), -100), 0);
      expect(truth.resolveEdge(Anchor.parse('end'), 100), truth.endT);
    });

    test('rejects bad anchors', () {
      for (final bad in ['route<1000', 'route<=-5', 'foo', 'gpsGap[x].start']) {
        expect(
          () => Anchor.parse(bad),
          throwsA(
            isA<AnchorException>().having(
              (e) => e.message,
              'message',
              isNotEmpty,
            ),
          ),
          reason: bad,
        );
      }
      expect(
        () => truth.resolveAnchor(Anchor.parse('gpsGap[3].start')),
        throwsA(isA<AnchorException>()),
      );

      final (p, r) = synth(
        profile: synthProfileJson(overrides: {'endDwellS': 10}),
      );
      final plain = buildTrace(p, r).truth;
      expect(plain.overshoot, isNull);
      expect(
        () => plain.resolveAnchor(Anchor.parse('overshoot')),
        throwsA(isA<AnchorException>()),
      );
    });

    test('milestones skip unreachable thresholds', () {
      final distance = truth.distanceMilestones();
      expect(
        [for (final m in distance) m.thresholdM],
        [200, 500, 1000, 2000, 3000, 5000],
      );
      for (final m in distance) {
        expect(
          m.routeT,
          firstT((s) => truth.destinationRouteM - s.s <= m.thresholdM),
        );
        expect(
          m.straightT,
          firstT((s) => distanceM(s.pos, dest) <= m.thresholdM),
        );
      }
      final time = truth.timeMilestones();
      for (final m in time) {
        expect(m.t, truth.arrivalT - 60 * m.beforeArrivalMin);
        expect(m.t, greaterThanOrEqualTo(0));
      }
      expect(
        time.length,
        kTimeThresholdsMin.where((n) => truth.arrivalT - 60 * n >= 0).length,
      );
      expect(time.length, lessThan(kTimeThresholdsMin.length));
    });

    test('straightT is null when already within the threshold', () {
      final (p, r) = synth(
        route: synthRouteJson([('a', 0), ('far', 3000), ('dest', 400)]),
        profile: synthProfileJson(
          destination: 'dest',
          overrides: {'endDwellS': 10},
        ),
      );
      final t = buildTrace(p, r).truth;
      final m = t.distanceMilestones().firstWhere((m) => m.thresholdM == 500);
      expect(m.straightT, isNull);
    });
  });
}
