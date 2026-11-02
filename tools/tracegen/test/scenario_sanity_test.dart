import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
    expect(lastGapTick, greaterThan(gap.fromT + 90));
    // T11 tightens TR05: both fire within 90 s of losing GPS.
    expect([lost.notBefore, lost.notAfter], [gap.fromT, gap.fromT + 90]);
    expect([alarm.notBefore, alarm.notAfter], [gap.fromT, gap.fromT + 90]);
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
    expect([window.notBefore, window.notAfter], [o.t - 15, o.t + 60]);
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
    final noisyCase = noisy.cases.firstWhere(
      (c) => c.spec.id == 'distance_1000_noisy',
    );
    expect(noisyCase.spec.forbid, containsAll(['overshoot', 'gpsLost']));
  });

  // T11 §6.3 prerequisites of the nine new profiles (TG22–TG30).

  test('bus_hn_slow (TG22)', () {
    final t = build('bus_hn_slow');
    final truth = t.truth;
    final a = truth.arrivalT;
    final jamS = waypointS(t, 'brt_van_phuc_2');
    final entryT = truth.states.firstWhere((s) => s.s >= jamS).t;
    expect(a - entryT, greaterThanOrEqualTo(1800));
    final moving = truth.states.where((s) => !s.dwelling).toList();
    for (final s in moving.where((s) => s.t >= a - 1800)) {
      expect(s.speedMps * 3.6, lessThanOrEqualTo(13), reason: 't = ${s.t}');
    }
    for (final s in moving) {
      final j = tickIndex(t, s.t);
      if (truth.remainingAt(j) <= 1500) {
        expect(s.speedMps * 3.6, lessThanOrEqualTo(12), reason: 't = ${s.t}');
      }
    }
    final jam = moving.where((s) => s.t >= entryT && s.t < a).toList();
    final mean =
        jam.fold<double>(0, (sum, s) => sum + s.speedMps) / jam.length * 3.6;
    expect(mean, inInclusiveRange(6, 13));
  });

  test('coach_dn_langco_shortgap (TG23)', () {
    final t = build('coach_dn_langco_shortgap');
    final truth = t.truth;
    final gap = truth.gaps.single;
    expect(gap.toT - gap.fromT, 120);
    final hoaKhanh = waypointS(t, 'hoa_khanh');
    expect(gap.fromT, truth.states.firstWhere((s) => s.s >= hoaKhanh).t);
    expect(
      truth.straightM[tickIndex(t, gap.fromT)],
      greaterThanOrEqualTo(20600),
    );
    for (final s in truth.states.where((s) => s.t < gap.fromT)) {
      expect(s.speedMps * 3.6, lessThanOrEqualTo(40), reason: 't = ${s.t}');
    }
  });

  test('coach_dn_langco_neardest (TG24)', () {
    final t = build('coach_dn_langco_neardest');
    final truth = t.truth;
    final north = waypointS(t, 'hai_van_tunnel_n');
    expect(waypointS(t, 'lang_co_south') - north, inInclusiveRange(1000, 2000));
    final gap = truth.gaps.single;
    final south = waypointS(t, 'hai_van_tunnel_s');
    expect(gap.fromT, truth.states.firstWhere((s) => s.s >= south).t);
    expect(truth.states[tickIndex(t, gap.toT)].s, greaterThanOrEqualTo(north));
    expect(truth.arrivalT - gap.fromT, lessThanOrEqualTo(900));
    expect(truth.arrivalT, greaterThanOrEqualTo(gap.toT));
  });

  test('train_hn_dh_midgap (TG25)', () {
    final t = build('train_hn_dh_midgap');
    final base = build('train_hn_dh');
    final truth = t.truth;
    final gap = truth.gaps.single;
    expect(gap.toT - gap.fromT, 900);
    final cauGiat = waypointS(t, 'ga_cau_giat');
    expect(gap.fromT, truth.states.firstWhere((s) => s.s >= cauGiat).t);
    expect(truth.states.where((s) => gap.contains(s.t) && s.dwelling), isEmpty);
    expect(truth.arrivalT - gap.toT, greaterThanOrEqualTo(9000));
    expect(truth.arrivalT, base.truth.arrivalT);
    expect(truth.endT, base.truth.endT);
    expect(
      [for (final s in truth.states) s.s],
      [for (final s in base.truth.states) s.s],
    );
  });

  test('bus_hn_brt01_noisy_traps (TG26)', () {
    final t = build('bus_hn_brt01_noisy_traps');
    final noisy = build('bus_hn_brt01_noisy');
    final truth = t.truth;
    final dest = truth.destination;
    final scripted = [
      for (final r in t.sensor.outliers)
        if (r.kind == OutlierKind.scripted) r.t,
    ];
    // 3 bait + 3 + 2 (as in bus_hn_brt01_noisy) + 3 beyond, no shared tick.
    expect(scripted, hasLength(11));
    expect(scripted.toSet(), hasLength(11));
    final byT = {for (final o in t.sensor.observations) o.t: o};
    for (final time in scripted.sublist(0, 3)) {
      expect(distanceM(byT[time]!.pos, dest), closeTo(2000, 1));
      final remaining = truth.remainingAt(tickIndex(t, time));
      expect(remaining, greaterThan(5300));
      expect(remaining, lessThanOrEqualTo(6000));
    }
    for (final time in scripted.sublist(8)) {
      final pos = byT[time]!.pos;
      expect(distanceM(pos, dest), closeTo(1800, 1));
      final (pe, pn) = localEnM(dest, pos);
      final (te, tn) = localEnM(dest, truth.states[tickIndex(t, time)].pos);
      expect(pe * te + pn * tn, lessThan(0), reason: 't = $time');
    }
    expect(truth.arrivalT, noisy.truth.arrivalT);
    expect(
      [for (final s in truth.stops) (s.arriveT, s.departT, s.routeM)],
      [for (final s in noisy.truth.stops) (s.arriveT, s.departT, s.routeM)],
    );
    expect(
      [for (final m in truth.distanceMilestones()) (m.routeT, m.straightT)],
      [
        for (final m in noisy.truth.distanceMilestones())
          (m.routeT, m.straightT),
      ],
    );
  });

  test('train_hn_dh_stopgap (TG27)', () {
    final t = build('train_hn_dh_stopgap');
    final truth = t.truth;
    final gap = truth.gaps.single;
    final dongLe = truth.stops.singleWhere((s) => s.name == 'Ga Đồng Lê');
    expect(gap.fromT, dongLe.arriveT + 5);
    expect(truth.states[tickIndex(t, gap.fromT)].dwelling, isTrue);
    expect(gap.toT, truth.arrivalT + 60);
    expect(t.sensor.observations.where((o) => gap.contains(o.t)), isEmpty);

    // Round 2: engine input before the gap equals train_hn_dh sample by
    // sample, and so do the seven stops.
    final base = build('train_hn_dh');
    final baseByT = {for (final o in base.sensor.observations) o.t: o};
    final before = t.sensor.observations.where((o) => o.t < gap.fromT);
    expect(before, isNotEmpty);
    for (final o in before) {
      final b = baseByT[o.t];
      expect(b, isNotNull, reason: 't = ${o.t}');
      expect(
        [o.pos.lat, o.pos.lng, o.accM, o.speedMps],
        [b!.pos.lat, b.pos.lng, b.accM, b.speedMps],
        reason: 't = ${o.t}',
      );
    }
    expect(truth.stops, hasLength(7));
    expect(
      [for (final s in truth.stops) (s.name, s.routeM, s.arriveT, s.departT)],
      [
        for (final s in base.truth.stops)
          (s.name, s.routeM, s.arriveT, s.departT),
      ],
    );
  });

  // T11 §6.3.1: dead-reckoning feasibility of TR30 (TG36, round 2).
  group('train_hn_dh_stopgap feasibility (TG36, T11.1 F1p)', () {
    test('closingVAt: constant speed straight at the destination', () {
      const interval = 5;
      final states = <TruthState>[];
      final straight = <double>[];
      for (var j = 0; j <= 20; j++) {
        // Ticks 8..11 stand still: the EMA must hold across them.
        final dwelling = j >= 8 && j <= 11;
        final moved = 10.0 * interval * (j <= 8 ? j : (j <= 11 ? 8 : j - 3));
        states.add(
          TruthState(
            t: j * interval,
            s: moved,
            pos: synthPoint(moved),
            speedMps: dwelling ? 0 : 10,
            dwelling: dwelling,
          ),
        );
        straight.add(10000 - moved);
      }
      final dr = DeadReckoning(states, straight, interval);
      expect(dr.closingVAt(7 * interval), closeTo(10, 1e-9));
      expect(dr.closingVAt(20 * interval), closeTo(10, 1e-9));

      // A different speed before the stop: the EMA over the dwelling ticks
      // stays where it was at the last moving tick.
      final varied = [
        for (final s in states)
          TruthState(
            t: s.t,
            s: s.s,
            pos: s.pos,
            speedMps: s.dwelling ? 0 : 8 + s.t / 50,
            dwelling: s.dwelling,
          ),
      ];
      final dv = DeadReckoning(varied, straight, interval);
      final atStop = dv.closingVAt(7 * interval);
      for (var j = 8; j <= 11; j++) {
        expect(dv.closingVAt(j * interval), atStop, reason: 'j = $j');
      }
      expect(dv.closingVAt(12 * interval), isNot(atStop));
    });

    test('F1, F2, F3 hold', () {
      final t = build('train_hn_dh_stopgap');
      final f = Feasibility.of(t);
      expect(
        f.f1Holds,
        isTrue,
        reason:
            'F1: alarmT(fromT - I, 0.95) = ${f.alarmLate} must be <= '
            'A - 420 = ${f.a - 420}; closingVAt(fromT - I) = '
            '${f.closingV}, A = ${f.a}',
      );
      expect(
        f.f2Holds,
        isTrue,
        reason:
            'F2: min alarmT(·, 1.10) = ${f.alarmEarliest} must be >= '
            'durationS - 3480 = ${f.durationS - 3480}; closingVAt(fromT - I) '
            '= ${f.closingV}, alarmT(fromT - I, 0.95) = ${f.alarmLate}, '
            'A = ${f.a}',
      );
      expect(
        f.f3Holds,
        isTrue,
        reason:
            'F3: ${f.f3Left} must be >= durationS + 600 = '
            '${f.durationS + 600}',
      );
    });

    // T11.1 §11 (T10.1 item 3): feasibility in the policy mode with the
    // lost-GPS speed guard, s = 0.95.
    test('F1p holds', () {
      final f = Feasibility.of(build('train_hn_dh_stopgap'));
      final w = f.f1pWorst;
      expect(
        f.f1pHolds,
        isTrue,
        reason:
            'F1p: worst tLast = ${w.tLast}: closingVAt(tLast) = '
            '${f.dr.closingVAt(w.tLast)}, closingVAt(tLast - 180) = '
            '${f.dr.closingVAt(w.tLast - 180)}, alarmTp(tLast, 0.95) = '
            '${w.alarmTp} must be <= A - 420 = ${f.a - 420}',
      );
    });

    test('negative check: 60 km/h after Đồng Lê fails F1 and F1p', () {
      final repo = ProfileRepository(dataDir);
      final (_, route) = repo.load('train_hn_dh_stopgap');
      final file = File('${dataDir.path}/profiles/train_hn_dh_stopgap.json');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final limits = json['speedLimits']! as List<Object?>;
      final last = limits.last! as Map<String, Object?>;
      expect(last['from'], 'ga_dong_le');
      last['kmh'] = 60;
      final profile = parseProfile(
        json,
        file: 'profiles/train_hn_dh_stopgap.json',
        route: route,
      );
      final f = Feasibility.of(buildTrace(profile, route));
      expect(
        f.f1Holds,
        isFalse,
        reason:
            'alarmT(fromT - I, 0.95) = ${f.alarmLate}, A = ${f.a}, '
            'closingVAt(fromT - I) = ${f.closingV}',
      );
      final w = f.f1pWorst;
      expect(
        f.f1pHolds,
        isFalse,
        reason:
            'worst alarmTp(${w.tLast}, 0.95) = ${w.alarmTp}, '
            'A - 420 = ${f.a - 420}',
      );
    });
  });

  test('train_longstop (TG28)', () {
    final t = build('train_longstop');
    final truth = t.truth;
    final a = truth.arrivalT;
    final stop = truth.stops.single;
    expect(stop.name, 'Ga Minh Lệ');
    expect(stop.departT - stop.arriveT, inInclusiveRange(300, 600));
    expect(stop.arriveT, greaterThanOrEqualTo(a - 2700));
    expect(stop.departT, lessThanOrEqualTo(a - 1200));
  });

  test('train_longstop_nospd (TG29)', () {
    final t = build('train_longstop_nospd');
    final base = build('train_longstop');
    final a = base.sensor.observations;
    final b = t.sensor.observations;
    expect(b, hasLength(a.length));
    final dwelling = {
      for (final s in t.truth.states)
        if (s.dwelling) s.t,
    };
    // Start, mid-route stop and destination dwell all count.
    expect(dwelling, contains(0));
    expect(dwelling, contains(t.truth.endT));
    expect(dwelling, contains(t.truth.stops.single.arriveT));
    for (var j = 0; j < a.length; j++) {
      expect(
        [b[j].t, b[j].pos.lat, b[j].pos.lng, b[j].accM],
        [a[j].t, a[j].pos.lat, a[j].pos.lng, a[j].accM],
      );
      if (dwelling.contains(b[j].t)) {
        expect(b[j].speedMps, isNull, reason: 't = ${b[j].t}');
      } else {
        expect(b[j].speedMps, isNotNull, reason: 't = ${b[j].t}');
        expect(b[j].speedMps, a[j].speedMps);
      }
    }
  });

  test('coach_gb_phuly_offroute (TG30)', () {
    final t = build('coach_gb_phuly_offroute');
    final truth = t.truth;
    final closest = truth.closest!;
    final stop = truth.stops.single;
    expect(closest.straightM, inInclusiveRange(1450, 1550));
    expect(closest.t, inInclusiveRange(stop.arriveT - 60, stop.departT + 60));
    expect(closest.departT, greaterThanOrEqualTo(stop.departT));
    for (var j = 0; j < truth.states.length; j++) {
      expect(
        truth.straightM[j],
        greaterThan(1000),
        reason: 't = ${truth.states[j].t}',
      );
    }
    expect(t.profile.destinationOffsetM, 1500);
    // T11.2 TG55 (TR38): the fallback alarm window [closest, closest + 80]
    // lies inside the stop at the bus station.
    expect(closest.t, stop.arriveT);
    expect(closest.t + 80, lessThan(stop.departT));
  });

  test('coach_gb_phuly_offroute_2k (T11.2 TG55)', () {
    final t = build('coach_gb_phuly_offroute_2k');
    final truth = t.truth;
    final closest = truth.closest!;
    final stop = truth.stops.single;
    expect(t.profile.destinationOffsetM, 2000);
    expect(closest.straightM, inInclusiveRange(1950, 2050));
    expect(closest.t, inInclusiveRange(stop.arriveT - 60, stop.departT + 60));
    expect(closest.departT, greaterThanOrEqualTo(stop.departT));
    expect(closest.departT + 30, lessThanOrEqualTo(truth.endT));
    for (var j = 0; j < truth.states.length; j++) {
      expect(
        truth.straightM[j],
        greaterThan(1000),
        reason: 't = ${truth.states[j].t}',
      );
    }

    // Same seed, route, motion and noise as the 1.5 km trace: every GPX
    // sample is identical, only the metadata differs.
    final a = build('coach_gb_phuly_offroute').sensor.observations;
    final b = t.sensor.observations;
    expect(b, hasLength(a.length));
    for (var j = 0; j < a.length; j++) {
      expect(
        [b[j].t, b[j].pos.lat, b[j].pos.lng, b[j].accM, b[j].speedMps],
        [a[j].t, a[j].pos.lat, a[j].pos.lng, a[j].accM, a[j].speedMps],
        reason: 'sample $j',
      );
    }
  });
}

double waypointS(GeneratedTrace t, String id) =>
    t.plan.polyline.cumulativeM[t.route.indexOf(id)];

/// Approximate dead-reckoning model of T11 §6.3.1 (test only, not the
/// engine): T10 §4.4/§4.5/§4.8 with the T10 §5 defaults, run on noise-free
/// truth.
final class DeadReckoning {
  new(this.states, this.straight, this.interval);

  final List<TruthState> states;
  final List<double> straight;
  final int interval;

  static const double tauS = 300; // speedEmaTauS
  static const double stationaryMps = 1; // stationarySpeedMps
  static const double routeFactorMin = 1;
  static const double routeFactorMax = 2;

  double _blend(double? e, double x) =>
      e == null ? x : e + (x - e) * interval / (tauS + interval);

  /// `closingV = v / k` with the EMA of the `all` sampling mode (one sample
  /// every [interval] s) up to the last fix at [tLast].
  double closingVAt(int tLast) {
    double? g;
    double? c;
    for (var j = 1; j <= tLast ~/ interval; j++) {
      final s = states[j];
      if (s.dwelling || s.speedMps < stationaryMps) {
        continue;
      }
      g = _blend(g, s.speedMps);
      c = _blend(c, (straight[j - 1] - straight[j]) / interval);
    }
    if (g == null) {
      return 0;
    }
    final k = c != null && c > 0
        ? (g / c).clamp(routeFactorMin, routeFactorMax)
        : routeFactorMax;
    return g / k;
  }

  /// Time of the `GPS_LOST` alarm with the last fix at [tLast]; [s] scales
  /// the closing speed. `etaS < 1200` ⇔ `dNow < 1180 · closingV`; loss is
  /// detected after `lostAfterS` = 540 s (sparse phase).
  double alarmT(int tLast, double s) => max(
    tLast + straight[tLast ~/ interval] / (s * closingVAt(tLast)) - 1180,
    tLast + 540.0,
  );

  /// [alarmT] with the lost-GPS speed guard of T10.1 (T11.1 §11): the
  /// closing speed is the larger of the EMA at [tLast] and at
  /// `tLast − 180` (previous sparse fix).
  double alarmTp(int tLast, double s) => max(
    tLast +
        straight[tLast ~/ interval] /
            (s * max(closingVAt(tLast), closingVAt(tLast - 180))) -
        1180,
    tLast + 540.0,
  );
}

/// F1–F3 of T11 §6.3.1 on a built `train_hn_dh_stopgap`.
final class Feasibility {
  new _(this.dr, this.fromT, this.a, this.durationS);

  factory of(GeneratedTrace t) {
    final truth = t.truth;
    return Feasibility._(
      DeadReckoning(truth.states, truth.straightM, t.profile.sampleIntervalS),
      truth.gaps.single.fromT,
      truth.arrivalT,
      truth.endT,
    );
  }

  final DeadReckoning dr;
  final int fromT;
  final int a;
  final int durationS;

  int get interval => dr.interval;

  /// `closingVAt(fromT − I)`.
  double get closingV => dr.closingVAt(fromT - interval);

  /// `alarmT(fromT − I, 0.95)`.
  double get alarmLate => dr.alarmT(fromT - interval, 0.95);

  /// `alarmT(fromT − I, 1.05)` (reported in the implementation notes).
  double get alarmEarly => dr.alarmT(fromT - interval, 1.05);

  /// `min` of `alarmT(tLast, 1.10)` over `tLast ∈ [fromT − 180, fromT − I]`.
  double get alarmEarliest => [
    for (var tLast = fromT - 180; tLast <= fromT - interval; tLast += interval)
      dr.alarmT(tLast, 1.10),
  ].reduce(min);

  /// Left side of F3: `2 · (straight[0] · 1.2 / (60 / 3.6) + 20)`.
  double get f3Left => 2 * (dr.straight[0] * 1.2 / (60 / 3.6) + 20);

  bool get f1Holds => alarmLate <= a - 300 - 120;

  /// Largest `alarmTp(tLast, 0.95)` over `tLast ∈ [fromT − 180, fromT − I]`
  /// (36 values with I = 5) and its `tLast`.
  ({int tLast, double alarmTp}) get f1pWorst {
    var worst = (tLast: fromT - 180, alarmTp: double.negativeInfinity);
    for (var t = fromT - 180; t <= fromT - interval; t += interval) {
      final v = dr.alarmTp(t, 0.95);
      if (v > worst.alarmTp) {
        worst = (tLast: t, alarmTp: v);
      }
    }
    return worst;
  }

  /// F1p: every `alarmTp(tLast, 0.95) ≤ A − 300 − 120`.
  bool get f1pHolds => f1pWorst.alarmTp <= a - 300 - 120;

  bool get f2Holds => alarmEarliest >= durationS - 3600 + 120;

  bool get f3Holds => f3Left >= durationS + 600;
}
