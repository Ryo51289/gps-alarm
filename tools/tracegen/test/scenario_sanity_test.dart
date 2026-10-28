import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

GeneratedTrace build(String id) {
  final (profile, route) = ProfileRepository(dataDir).load(id);
  return buildTrace(profile, route);
}

ResolvedExpect expectOf(GeneratedTrace t, String caseId, String event) => t
    .cases
    .firstWhere((c) => c.spec.id == caseId)
    .expect
    .firstWhere((e) => e.spec.event == event);

int tickIndex(GeneratedTrace t, int time) =>
    t.truth.states.indexWhere((s) => s.t == time);

void main() {
  test('train_hn_dh (TC27)', () {
    final t = build('train_hn_dh');
    final truth = t.truth;
    expect(truth.endT, inInclusiveRange(8.5 * 3600, 10.5 * 3600));
    expect(truth.routeLengthM, inInclusiveRange(460000, 495000));
    expect(truth.stops.where((s) => s.name != null), hasLength(7));
    for (final s in truth.stops) {
      expect(s.departT, lessThanOrEqualTo(truth.arrivalT - 3600));
    }
    expect(truth.gaps, isEmpty);
    expect(t.sensor.outliers, isEmpty);
    expect(t.profile.vehicle, Vehicle.train);

    final a = truth.arrivalT;
    final alarm = expectOf(t, 'time_15', 'alarm');
    expect([alarm.notBefore, alarm.notAfter], [a - 960, a - 840]);
    final pre = expectOf(t, 'time_15', 'preAlert');
    expect([pre.notBefore, pre.notAfter], [a - 1860, a - 1740]);
    final d = expectOf(t, 'distance_1000', 'alarm');
    expect(d.notAfter - d.notBefore, inInclusiveRange(20, 120));
  });

  test('coach_md_tb (TC28)', () {
    final t = build('coach_md_tb');
    final truth = t.truth;
    expect(truth.endT, inInclusiveRange(1.5 * 3600, 2.75 * 3600));
    expect(truth.routeLengthM, inInclusiveRange(95000, 115000));
    final namDinh = truth.stops.singleWhere((s) => s.name == 'TP Nam Định');
    expect(namDinh.departT, lessThanOrEqualTo(truth.arrivalT - 1860));
    expect([
      for (final m in truth.timeMilestones()) m.beforeArrivalMin,
    ], kTimeThresholdsMin);
  });

  test('bus_hn_brt01 (TC29)', () {
    final t = build('bus_hn_brt01');
    final truth = t.truth;
    expect(truth.endT, inInclusiveRange(25 * 60, 60 * 60));
    expect(truth.routeLengthM, inInclusiveRange(11000, 16000));
    expect(truth.stops.length, greaterThanOrEqualTo(12));
    final maxSpeed = truth.states
        .map((s) => s.speedMps)
        .reduce((a, b) => a > b ? a : b);
    expect(maxSpeed * 3.6, lessThanOrEqualTo(28 * 1.15));
    expect(truth.routeLengthM / truth.endT * 3.6, lessThan(25));
    for (final s in truth.stops) {
      expect(s.routeM, lessThan(truth.destinationRouteM - 300));
    }
  });

  test('coach_dn_langco_tunnel (TC30)', () {
    final t = build('coach_dn_langco_tunnel');
    final truth = t.truth;
    final gap = truth.gaps.single;
    expect(gap.toT - gap.fromT, 360);
    expect(t.segments, hasLength(2));
    expect(t.sensor.observations.where((o) => gap.contains(o.t)), isEmpty);
    expect(truth.arrivalT - gap.fromT, inInclusiveRange(600, 1080));
    final atRecovery = tickIndex(t, gap.toT);
    expect(truth.remainingAt(atRecovery), greaterThanOrEqualTo(1300));
    final north = t.route.indexOf('hai_van_tunnel_n');
    expect(
      truth.states[atRecovery].s,
      greaterThanOrEqualTo(t.plan.polyline.cumulativeM[north]),
    );
    final lost = expectOf(t, 'distance_1000_gps_lost', 'gpsLost');
    final alarm = expectOf(t, 'distance_1000_gps_lost', 'alarm');
    final recovered = expectOf(t, 'distance_1000_gps_lost', 'gpsRecovered');
    // gpsLost and alarm must fire while GPS is still lost: the window ends at
    // the last tick inside the gap, never at `toT` (first sample after it).
    final lastGapTick = gap.toT - t.profile.sampleIntervalS;
    expect([lost.notBefore, lost.notAfter], [gap.fromT, lastGapTick]);
    expect([alarm.notBefore, alarm.notAfter], [gap.fromT, lastGapTick]);
    for (final e in [lost, alarm]) {
      expect(e.notAfter, lessThan(gap.toT), reason: e.spec.event);
      expect(gap.contains(e.notAfter), isTrue, reason: e.spec.event);
    }
    expect([recovered.notBefore, recovered.notAfter], [gap.toT, gap.toT + 60]);
  });

  test('coach_gb_phuly_overshoot (TC31)', () {
    final t = build('coach_gb_phuly_overshoot');
    final truth = t.truth;
    final stop = truth.stops.single;
    expect(stop.name, 'Bến xe Trung tâm Phủ Lý');
    expect(stop.routeM, truth.destinationRouteM.round());
    expect(stop.departT - stop.arriveT, inInclusiveRange(85, 90));
    final o = truth.overshoot!;
    expect(o.t - truth.destDepartT, inInclusiveRange(60, 240));

    // Straight-line distance grows at every tick from departure until the
    // coach stands at the end of the route.
    final end = truth.states.indexWhere(
      (s) => s.dwelling && s.s == t.plan.gridS.last,
    );
    for (var j = tickIndex(t, truth.destDepartT + 5) + 1; j <= end; j++) {
      expect(
        truth.straightM[j],
        greaterThan(truth.straightM[j - 1]),
        reason: 't = ${truth.states[j].t}',
      );
    }
    expect(truth.states[tickIndex(t, o.t)].speedMps * 3.6, greaterThan(10));
    expect(truth.straightM.last, greaterThanOrEqualTo(5000));
    final window = expectOf(t, 'distance_1000_overshoot', 'overshoot');
    expect([window.notBefore, window.notAfter], [o.t - 15, o.t + 120]);
  });

  test('bus_hn_brt01_noisy (TC32)', () {
    final noisy = build('bus_hn_brt01_noisy');
    final clean = build('bus_hn_brt01');
    final truth = noisy.truth;
    expect(truth.arrivalT, clean.truth.arrivalT);
    expect(truth.endT, clean.truth.endT);
    expect(noisy.sensor.observations.length, clean.sensor.observations.length);
    expect(
      [for (final s in truth.stops) (s.arriveT, s.departT, s.routeM)],
      [for (final s in clean.truth.stops) (s.arriveT, s.departT, s.routeM)],
    );
    expect(
      [for (final m in truth.distanceMilestones()) (m.routeT, m.straightT)],
      [
        for (final m in clean.truth.distanceMilestones())
          (m.routeT, m.straightT),
      ],
    );

    final scripted = [
      for (final r in noisy.sensor.outliers)
        if (r.kind == OutlierKind.scripted) r.t,
    ];
    expect(scripted, hasLength(5));
    final byT = {for (final o in noisy.sensor.observations) o.t: o};
    final dest = noisy.truth.destination;
    for (var i = 0; i < 5; i++) {
      final j = tickIndex(noisy, scripted[i]);
      final remaining = truth.remainingAt(j);
      if (i < 3) {
        expect(distanceM(byT[scripted[i]]!.pos, dest), closeTo(600, 1));
        expect(remaining, inInclusiveRange(3500, 4000));
      } else {
        expect(distanceM(byT[scripted[i]]!.pos, dest), closeTo(1800, 1));
        expect(remaining, lessThanOrEqualTo(400));
      }
    }
    expect(
      noisy.sensor.outliers.where((r) => r.kind == OutlierKind.random),
      isNotEmpty,
    );
    final missing =
        noisy.sensor.observations.where((o) => o.speedMps == null).length /
        noisy.sensor.observations.length;
    expect(missing, inInclusiveRange(0.2, 0.4));
    final alarm = expectOf(noisy, 'distance_1000_noisy', 'alarm');
    expect(alarm.notBefore, greaterThan(scripted.first));
    expect(noisy.cases.single.spec.forbid, contains('overshoot'));
  });
}
