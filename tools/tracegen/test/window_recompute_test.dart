// T11 TG32 (tester): recompute every resolved window, `At.t`, `asOfT` and
// truth anchor of the committed fixtures from the motion truth and the GPX,
// independently of the generator's anchor resolution (see
// `support/window_oracle.dart`), plus hand-computed numbers for the windows
// that depend on milestones or on the §5.3 formula, and out-of-spec checks
// that no expectation lets an alarm come after the passenger should be off.
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';
import 'support/window_oracle.dart';

typedef _Case = Map<String, Object?>;

void main() {
  final ids = ProfileRepository(dataDir).profileIds();
  final oracles = <String, Oracle>{};
  Oracle oracle(String id) =>
      oracles[id] ??= Oracle.load(id, data: dataDir, fix: fixturesDir);

  _Case caseOf(String id, String caseId) =>
      (oracle(id).fixture['cases']! as List).cast<_Case>().firstWhere(
        (c) => c['id'] == caseId,
      );

  List<_Case> expectOf(_Case c) => (c['expect']! as List).cast<_Case>();

  _Case expectEntry(_Case c, String event, [String? reason]) =>
      expectOf(c)
          .firstWhere((e) => e['event'] == event && e['reason'] == reason);

  List<int> window(_Case e) => [e['notBefore']! as int, e['notAfter']! as int];

  group('TG32 every resolved number matches the oracle', () {
    for (final id in ids) {
      test(id, () {
        final rows = oracle(id).rows();
        expect(rows.length, greaterThan(10));
        final bad = rows.where((r) => !r.ok).toList();
        expect(bad, isEmpty, reason: bad.join('\n'));
      });
    }

    test('self-check: the oracle flags a window shifted by one tick', () {
      final o = oracle('train_hn_dh_stopgap');
      final mutated = deepCopy(o.fixture)! as Map<String, Object?>;
      final c = (mutated['cases']! as List).first! as Map<String, Object?>;
      final e = (c['expect']! as List).single! as Map<String, Object?>;
      e['notAfter'] = 35050;
      final m = Oracle(
        id: o.id,
        fixture: mutated,
        truth: o.truth,
        gpxGaps: o.gpxGaps,
      );
      final bad = m.rows().where((r) => !r.ok).toList();
      expect(bad, hasLength(1));
      expect(bad.single.expected, 35045);
      expect(bad.single.actual, 35050);
    });
  });

  group('TG32 hand-computed windows (from truth, T11 §5.3/§5.4)', () {
    test('train_hn_dh_stopgap TR30 [g.start, A − 300] = [28815, 35045]', () {
      final o = oracle('train_hn_dh_stopgap');
      // Truth: Đồng Lê dwell 28810–28985; A = 35345; durationS = 35460.
      final dongLe = o.truth.stops.singleWhere((s) => s.name == 'Ga Đồng Lê');
      expect([dongLe.arriveT, dongLe.departT], [28810, 28985]);
      expect(o.arrivalT, 35345);
      expect(o.durationS, 35460);
      // Gap: atStop ga_dong_le + 5 → until arrival + 60.
      expect(o.gpxGaps, [(28810 + 5, 35345 + 60)]);
      final c = caseOf('train_hn_dh_stopgap', 'distance_1000');
      final e = expectEntry(c, 'alarm', 'GPS_LOST');
      expect(window(e), [28815, 35345 - 300]);
      expect(e['ringNow'], isTrue);
      // T11.1: both sampling modes, the policy run sweeps 36 phases.
      expect(c.containsKey('samplingModes'), isFalse);
      expect(c['policyPhaseSweep'], isTrue);
      // The alarm has to come while GPS is still lost (window ends before
      // GPS returns at toT) and before the train stands at Đồng Hới.
      expect(window(e)[1], lessThan(35405));
      expect(window(e)[1], lessThan(o.arrivalT));
      final s = caseOf('train_hn_dh_stopgap', 'summary_unknown');
      expect(window(expectOf(s).single), [35460, 35460]);
    });

    test('train_hn_dh_stopgap matches train_hn_dh before Đồng Lê', () {
      final a = oracle('train_hn_dh');
      final b = oracle('train_hn_dh_stopgap');
      // Same arrival at and departure from every stop up to Đồng Lê.
      expect(
        [for (final s in b.truth.stops) (s.name, s.arriveT, s.departT)],
        [for (final s in a.truth.stops) (s.name, s.arriveT, s.departT)],
      );
      for (var j = 0; j * 5 < 28815; j++) {
        expect(b.truth.states[j].s, a.truth.states[j].s, reason: 't=${j * 5}');
      }
    });

    test('TR22 / TR28 / TR29 / TR35 expectFallback (T11.1 §4)', () {
      // (profile, case, killT, modeAtT, asOfT, E)
      final rows = [
        // TR22: A 33790, kill A−2400 = 31390, m = s≤1000 = 33700,
        // early = (33700−31390−600)~/4 = 427, E = 33700+30−427 = 33303.
        ('train_hn_dh', 'distance_1000_kill', 31390, 33700, 31385, 33303),
        // TR28: m = A−900 = 32890, early = (32890−31390−600)~/4 = 225,
        // E = 32890+30−225 = 32695.
        ('train_hn_dh', 'time_15_kill', 31390, 32890, 31385, 32695),
        // TR29: A 7310, kill A−1800 = 5510, m = A−600 = 6710,
        // early = (6710−5510−600)~/4 = 150, E = 6590.
        ('coach_md_tb', 'smart_kill', 5510, 6710, 5505, 6590),
        // TR35: A 2425, kill A−600 = 1825, m = s≤1000 = 2340,
        // early = max(0, 2340−1825−600) = 0, E = 2370.
        (
          'coach_gb_phuly_overshoot',
          'distance_1000_fallback_silenced',
          1825,
          2340,
          1820,
          2370,
        ),
      ];
      for (final (id, caseId, kill, modeAt, asOf, e) in rows) {
        final c = caseOf(id, caseId);
        final config = c['config']! as _Case;
        final f = c['expectFallback']! as _Case;
        final w = f['window']! as _Case;
        expect(
          [w['killT'], w['modeAtT'], f['asOfT'], w['estimateT']],
          [kill, modeAt, asOf, e],
          reason: '$id/$caseId',
        );
        // hintEstimateT from the truth (the "≈" numbers of T10 §8.3 are not
        // asserted).
        final fb = oracle(id).fallbackOf(
          mode: config['mode']! as String,
          threshold: (config['thresholdM'] ?? config['thresholdMin']) as int?,
          hint:
              (config['vehicleHint'] ??
                      (oracle(id).fixture['trace']! as _Case)['vehicle'])!
                  as String,
          modeAtT: modeAt,
          killT: kill,
          tolerance: (-300, 120),
        );
        expect(w['hintEstimateT'], fb.hintEstimateT, reason: '$id/$caseId');
        if (caseId == 'smart_kill') {
          // The coach speed floor wins: the lower edge follows the hint.
          expect(fb.hintEstimateT, lessThan(e), reason: '$id/$caseId');
          expect(
            [f['notBefore'], f['notAfter']],
            [fb.hintEstimateT - 300, 6710],
            reason: '$id/$caseId',
          );
        } else {
          expect(fb.hintEstimateT, greaterThan(e), reason: '$id/$caseId');
          expect(
            [f['notBefore'], f['notAfter']],
            [e - 300, e + 120],
            reason: '$id/$caseId',
          );
        }
      }
    });

    test('route<=X windows (milestones only list 200/500/1000…)', () {
      // (profile, case, event, reason, [r≤hi, r≤lo]) recomputed from the
      // per-tick remaining distance.
      final rows = <(String, String, String, String?, int, int, int, int)>[
        (
          'train_hn_dh',
          'distance_1000',
          'preAlert',
          null,
          5300,
          4700,
          33435,
          33470,
        ),
        (
          'train_hn_dh',
          'distance_1000',
          'alarm',
          'DISTANCE',
          1300,
          700,
          33680,
          33715,
        ),
        (
          'coach_md_tb',
          'distance_1000',
          'preAlert',
          null,
          5300,
          4700,
          6675,
          6745,
        ),
        (
          'coach_md_tb',
          'distance_1000',
          'alarm',
          'DISTANCE',
          1300,
          700,
          7145,
          7220,
        ),
        (
          'bus_hn_brt01',
          'distance_500',
          'preAlert',
          null,
          3300,
          2700,
          1740,
          1855,
        ),
        (
          'bus_hn_brt01',
          'distance_500',
          'alarm',
          'DISTANCE',
          800,
          200,
          2210,
          2285,
        ),
        (
          'bus_hn_brt01',
          'distance_1000',
          'alarm',
          'DISTANCE',
          1300,
          700,
          2110,
          2225,
        ),
        (
          'bus_hn_slow',
          'smart',
          'alarm',
          'SMART_SLOW_DISTANCE',
          2800,
          2200,
          2450,
          2695,
        ),
        (
          'bus_hn_slow',
          'smart_floor',
          'alarm',
          'SMART_DISTANCE',
          1300,
          700,
          3065,
          3305,
        ),
        (
          'coach_dn_langco_shortgap',
          'distance_1000_shortgap',
          'alarm',
          'DISTANCE',
          1300,
          700,
          1810,
          1865,
        ),
        (
          'coach_gb_phuly_overshoot',
          'distance_1000_overshoot',
          'preAlert',
          null,
          5300,
          4700,
          2175,
          2200,
        ),
        (
          'coach_gb_phuly_overshoot',
          'distance_1000_overshoot',
          'alarm',
          'DISTANCE',
          1300,
          700,
          2335,
          2360,
        ),
        (
          'train_hn_dh_midgap',
          'distance_1000_midgap',
          'alarm',
          'DISTANCE',
          1300,
          700,
          33680,
          33715,
        ),
      ];
      for (final (id, caseId, event, reason, hi, lo, nb, na) in rows) {
        final o = oracle(id);
        expect(
          [o.routeWithin(hi), o.routeWithin(lo)],
          [nb, na],
          reason: '$id route<=$hi/$lo',
        );
        expect(window(expectEntry(caseOf(id, caseId), event, reason)), [
          nb,
          na,
        ], reason: '$id/$caseId $event');
        // First-tick semantics at the boundary: remaining <= X at nb, > X
        // one tick earlier.
        final j = o.truth.states.indexWhere((s) => s.t == nb);
        expect(o.truth.remainingAt(j), lessThanOrEqualTo(hi));
        expect(o.truth.remainingAt(j - 1), greaterThan(hi));
      }
    });

    test('gap windows TR05 / TR13 / TR14 / TR15', () {
      // (profile, case, event, cause/reason, expected window)
      final rows = <(String, String, String, String?, List<int>)>[
        // TR05: gap 1175–1535: [g.start, g.start + 90], [g.end, g.end + 60].
        (
          'coach_dn_langco_tunnel',
          'distance_1000_gps_lost',
          'gpsLost',
          null,
          [1175, 1265],
        ),
        (
          'coach_dn_langco_tunnel',
          'distance_1000_gps_lost',
          'alarm',
          'GPS_LOST',
          [1175, 1265],
        ),
        (
          'coach_dn_langco_tunnel',
          'distance_1000_gps_lost',
          'gpsRecovered',
          null,
          [1535, 1595],
        ),
        // TR13: gap 405–525: [g.start, g.end − 5], [g.end, g.end + 30].
        (
          'coach_dn_langco_shortgap',
          'distance_1000_shortgap',
          'gpsLost',
          null,
          [405, 520],
        ),
        (
          'coach_dn_langco_shortgap',
          'distance_1000_shortgap',
          'gpsRecovered',
          null,
          [525, 555],
        ),
        // TR14: gap 1175–1535, A 1615.
        (
          'coach_dn_langco_neardest',
          'distance_1000_neardest',
          'gpsLost',
          null,
          [1175, 1265],
        ),
        (
          'coach_dn_langco_neardest',
          'distance_1000_neardest',
          'alarm',
          'GPS_LOST',
          [1175, 1265],
        ),
        (
          'coach_dn_langco_neardest',
          'distance_1000_neardest',
          'gpsRecovered',
          null,
          [1535, 1595],
        ),
        // TR15: gap 16960–17860: [g + 360, g + 720], [g.end, g.end + 30].
        (
          'train_hn_dh_midgap',
          'distance_1000_midgap',
          'gpsLost',
          null,
          [17320, 17680],
        ),
        (
          'train_hn_dh_midgap',
          'distance_1000_midgap',
          'gpsRecovered',
          null,
          [17860, 17890],
        ),
      ];
      for (final (id, caseId, event, reason, w) in rows) {
        final e = expectOf(caseOf(id, caseId)).firstWhere(
          (e) =>
              e['event'] == event &&
              (event != 'alarm' || e['reason'] == reason),
        );
        expect(window(e), w, reason: '$id/$caseId $event');
      }
    });

    test('TR38 FALLBACK [cl.t, cl.t + 80] = [2425, 2505] (T11.2)', () {
      final o = oracle('coach_gb_phuly_offroute');
      // dMin 1500 m at 2425; need = max(500, 750) = 750 → first tick with
      // straight >= 2250 m after 2425 is 2645 (truth only: TR32 moved to
      // coach_gb_phuly_offroute_2k by T11.2).
      expect(o.closest, (t: 2425, straightM: 1500, departT: 2645));
      final c = caseOf('coach_gb_phuly_offroute', 'distance_1000');
      expect(window(expectEntry(c, 'alarm', 'FALLBACK')), [2425, 2505]);
      expect(o.truth.straightM.every((d) => d > 1000), isTrue);
    });

    test('TR32 PASSED_CLOSEST [cl.dep, cl.dep + 30] on the 2 km trace', () {
      final o = oracle('coach_gb_phuly_offroute_2k');
      // Hand-checked by the T11.2 reviewer and tester (TG59): dMin 2000 m
      // at 2425; need = max(500, 1000) = 1000 → first tick with straight
      // >= 3000 m after 2425 is 2690 (2685: 2969.6 m, 2690: 3006.3 m).
      expect(o.closest, (t: 2425, straightM: 2000, departT: 2690));
      final departT = o.closest!.departT;
      final c = caseOf('coach_gb_phuly_offroute_2k', 'distance_1000');
      expect(window(expectEntry(c, 'alarm', 'PASSED_CLOSEST')), [
        departT,
        departT + 30,
      ]);
      // Off-route destination never comes within 1 km (no DISTANCE alarm
      // possible, so a missing PASSED_CLOSEST would mean no alarm at all).
      expect(o.truth.straightM.every((d) => d > 1000), isTrue);
    });

    test('TR33 / TR35 / TR06 overshoot windows [ov − 15, ov + 60]', () {
      expect(oracle('coach_gb_phuly_overshoot').overshoot?.t, 2620);
      for (final caseId in [
        'distance_1000_overshoot',
        'distance_1000_overshoot_silenced',
        'distance_1000_fallback_silenced',
      ]) {
        final e = expectEntry(
          caseOf('coach_gb_phuly_overshoot', caseId),
          'overshoot',
        );
        expect(window(e), [2605, 2680], reason: caseId);
      }
    });

    test('static inputs: kill / relaunch / actions', () {
      // train_hn_dh A = 33790; coach_md_tb A = 7310.
      for (final caseId in [
        'distance_1000_kill',
        'distance_1000_kill_rang',
        'distance_1000_kill_missing',
        'distance_1000_kill_pending',
        'time_15_kill',
        'distance_1000_kill_osdismiss',
      ]) {
        final cfg = caseOf('train_hn_dh', caseId)['config']! as _Case;
        expect((cfg['kill']! as _Case)['t'], 33790 - 2400, reason: caseId);
      }
      final pending =
          caseOf('train_hn_dh', 'distance_1000_kill_pending')['config']!
              as _Case;
      expect(((pending['relaunch']! as _Case)['at']! as _Case)['t'], 31990);
      final perm =
          caseOf('coach_md_tb', 'distance_1000_permission')['config']! as _Case;
      expect(
        (((perm['actions']! as List).single as _Case)['at']! as _Case)['t'],
        7310 - 900,
      );
      final permCase = caseOf('coach_md_tb', 'distance_1000_permission');
      expect(window(expectEntry(permCase, 'alarm', 'GPS_LOST')), [6410, 6410]);
    });
  });

  group('wake-up timing guards on the expectations (out of spec)', () {
    // Reasons whose expected window must close before the vehicle reaches
    // the destination waypoint: if a case allowed one of them after
    // `arrivalT`, a late engine would pass while the passenger missed the
    // stop. OVERSHOOT / PASSED_CLOSEST / SNOOZE_END / FALLBACK* come after
    // arrival by design.
    const beforeArrival = {
      null,
      'DISTANCE',
      'TIME',
      'SMART_TIME',
      'SMART_DISTANCE',
      'SMART_SLOW_DISTANCE',
      'GPS_LOST',
      'LOW_BATTERY',
    };

    for (final id in ids) {
      test('$id: alarm/preAlert windows close by arrival', () {
        final o = oracle(id);
        for (final c in (o.fixture['cases']! as List).cast<_Case>()) {
          for (final e in expectOf(c)) {
            final event = e['event'];
            if (event == 'preAlert' ||
                (event == 'alarm' && beforeArrival.contains(e['reason']))) {
              expect(
                e['notAfter']! as int,
                lessThanOrEqualTo(o.arrivalT),
                reason: '${c['id']} ${_desc(e)} closes after arrival',
              );
            }
          }
        }
      });

      test('$id: preAlert window ends before the alarm window opens', () {
        for (final c in (oracle(id).fixture['cases']! as List).cast<_Case>()) {
          final pre = expectOf(c).where((e) => e['event'] == 'preAlert');
          final alarms = expectOf(c).where((e) => e['event'] == 'alarm');
          for (final p in pre) {
            for (final a in alarms) {
              expect(
                p['notAfter']! as int,
                lessThan(a['notBefore']! as int),
                reason: '${c['id']}',
              );
            }
          }
        }
      });

      test('$id: gpsLost / GPS_LOST windows close while GPS is lost', () {
        final o = oracle(id);
        for (final c in (o.fixture['cases']! as List).cast<_Case>()) {
          final cfg = c['config']! as _Case;
          if (cfg.containsKey('kill') || cfg.containsKey('actions')) {
            continue; // relaunch / permission cases: not gap driven
          }
          for (final e in expectOf(c)) {
            final lost =
                e['event'] == 'gpsLost' ||
                (e['event'] == 'alarm' && e['reason'] == 'GPS_LOST');
            if (!lost) {
              continue;
            }
            final nb = e['notBefore']! as int;
            final na = e['notAfter']! as int;
            final gap = o.gpxGaps.firstWhere(
              (g) => nb >= g.$1 && nb < g.$2,
              orElse: () => fail('${c['id']} ${_desc(e)} opens outside a gap'),
            );
            expect(
              na,
              lessThan(gap.$2),
              reason: '${c['id']} ${_desc(e)} reaches the GPS recovery tick',
            );
          }
        }
      });
    }

    test('run-anchored inputs fall due inside the trace (B <= durationS)', () {
      // Worst case: the anchor event at the latest edge its own expectation
      // allows, plus the declared offsets (README §3.1: B > durationS is a
      // configuration failure of the case).
      // TR18: alarm <= 33715, snooze +20, snoozed then dismiss +80.
      expect(
        33715 + 20 + 80,
        lessThanOrEqualTo(oracle('train_hn_dh').durationS),
      );
      // TR19: alarm <= 2360, dismiss +30.
      expect(
        2360 + 30,
        lessThanOrEqualTo(oracle('coach_gb_phuly_overshoot').durationS),
      );
      // TR23/TR24/TR34: osFallbackFired <= latest fallback of TR22
      // (E + 120 = 33679), relaunch + 40 / + 60.
      expect(33679 + 60, lessThanOrEqualTo(oracle('train_hn_dh').durationS));
      // TR34: osDismiss (osF + 20) strictly before relaunch (osF + 60).
      final osd =
          caseOf('train_hn_dh', 'distance_1000_kill_osdismiss')['config']!
              as _Case;
      expect(
        (osd['osDismiss']! as _Case)['offsetS']! as int,
        lessThan(
          ((osd['relaunch']! as _Case)['at']! as _Case)['offsetS']! as int,
        ),
      );
      // TR35: osFallbackFired <= 2490, relaunch + 30.
      expect(
        2490 + 30,
        lessThanOrEqualTo(oracle('coach_gb_phuly_overshoot').durationS),
      );
    });

    test('kill happens before any expected wake-up of its case', () {
      for (final id in ids) {
        for (final c in (oracle(id).fixture['cases']! as List).cast<_Case>()) {
          final kill = (c['config']! as _Case)['kill'] as _Case?;
          if (kill == null) {
            continue;
          }
          final k = kill['t']! as int;
          final f = c['expectFallback'] as _Case?;
          if (f != null) {
            expect(f['asOfT'], k - 5, reason: '${c['id']}');
            expect(
              f['notBefore']! as int,
              greaterThan(k),
              reason: '${c['id']}',
            );
          }
          for (final e in expectOf(c)) {
            expect(
              e['notBefore']! as int,
              greaterThan(k),
              reason: '${c['id']}',
            );
          }
        }
      }
    });
  });

  // T11.1 TG50 (tester): independent review of the T11.1 numbers from the
  // truth and from the GPX.
  group('TG50 T11.1 windows from truth and GPX', () {
    // (profile, case) of the four expectFallback cases.
    const fallbackCases = [
      ('train_hn_dh', 'distance_1000_kill'),
      ('train_hn_dh', 'time_15_kill'),
      ('coach_md_tb', 'smart_kill'),
      ('coach_gb_phuly_overshoot', 'distance_1000_fallback_silenced'),
    ];

    test('the oracle does not use the generator formula or resolver', () {
      // RK2: the oracle must stay independent of lib/ for every number it
      // recomputes (it may share the motion truth only).
      final src = File('${packageDir.path}/test/support/window_oracle.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final name in [
        'fallbackEstimates',
        'fallbackWindow',
        'kFallback',
        'kExpectedSpeedKmh',
        'kEtaStopPenaltyS',
        'kSmartTargetS',
        'resolveCase',
        'resolveAnchor',
        'writeExpect',
        'validatePair',
        'distanceM(',
        'milestones(',
      ]) {
        expect(src.contains(name), isFalse, reason: 'oracle uses $name');
      }
    });

    for (final (id, caseId) in fallbackCases) {
      test('$id/$caseId asOfStraightM vs GPX fix and milestones', () {
        final o = oracle(id);
        final c = caseOf(id, caseId);
        final f = c['expectFallback']! as _Case;
        final w = f['window']! as _Case;
        final asOfT = f['asOfT']! as int;
        final sM = w['asOfStraightM']! as int;
        final dest = o.fixture['destination']! as _Case;
        final trace = o.fixture['trace']! as _Case;
        final start =
            DateTime.parse(trace['startTime']! as String)
                .millisecondsSinceEpoch ~/
            1000;
        final fixes = fixesFromGpx(
          File('${fixturesDir.path}/$id.gpx').readAsStringSync(),
          start,
        );
        expect(fixes.length, trace['sampleCount'], reason: id);

        // Truth (oracle) at asOfT: exact.
        final j = o.truth.states.indexWhere((s) => s.t == asOfT);
        expect(sM, o.truth.straightM[j].floor(), reason: '$id/$caseId');

        // GPX fix at asOfT (noisy): within 100 m of the true distance.
        final fix = fixes[asOfT];
        expect(fix, isNotNull, reason: '$id/$caseId: no fix at asOfT');
        final gpxM = haversineM(fix!, (
          (dest['lat']! as num).toDouble(),
          (dest['lng']! as num).toDouble(),
        ));
        expect(
          (gpxM - sM).abs(),
          lessThanOrEqualTo(100),
          reason: '$id/$caseId GPX ${gpxM.toStringAsFixed(1)} m vs sM $sM',
        );

        // Milestones: for X > sM the first tick with straight <= X is at or
        // before asOfT (guaranteed); for X < sM it is after asOfT (holds
        // because the four trips approach their destination monotonically
        // before the kill).
        final distance =
            ((o.fixture['milestones']! as _Case)['distance']! as List)
                .cast<_Case>();
        var below = 0;
        var above = 0;
        for (final m in distance) {
          final x = m['thresholdM']! as int;
          final t = m['straightT'] as int?;
          if (t == null) {
            continue;
          }
          if (x > sM) {
            above++;
            expect(t, lessThanOrEqualTo(asOfT), reason: '$id X=$x');
          } else if (x < sM) {
            below++;
            expect(t, greaterThan(asOfT), reason: '$id X=$x');
          }
        }
        expect(below, greaterThan(0), reason: id);
        expect(above, greaterThan(0), reason: id);
      });

      test('$id/$caseId window from the GPX distance (§4 robustness)', () {
        // The window must not hinge on metres: recomputed with the distance
        // of the noisy GPX fix instead of the truth, estimateT and both
        // edges stay the same where estimateT sets the lower edge, and
        // hintEstimateT moves by at most a few seconds where the floor wins.
        final o = oracle(id);
        final c = caseOf(id, caseId);
        final config = c['config']! as _Case;
        final f = c['expectFallback']! as _Case;
        final w = f['window']! as _Case;
        final dest = o.fixture['destination']! as _Case;
        final trace = o.fixture['trace']! as _Case;
        final start =
            DateTime.parse(trace['startTime']! as String)
                .millisecondsSinceEpoch ~/
            1000;
        final fix = fixesFromGpx(
          File('${fixturesDir.path}/$id.gpx').readAsStringSync(),
          start,
        )[f['asOfT']! as int]!;
        final gpxM = haversineM(fix, (
          (dest['lat']! as num).toDouble(),
          (dest['lng']! as num).toDouble(),
        )).floor();
        final tol = (w['toleranceS']! as List).cast<int>();
        final fb = o.fallbackOf(
          mode: config['mode']! as String,
          threshold: (config['thresholdM'] ?? config['thresholdMin']) as int?,
          hint: (config['vehicleHint'] ?? trace['vehicle'])! as String,
          modeAtT: w['modeAtT']! as int,
          killT: w['killT']! as int,
          tolerance: (tol[0], tol[1]),
          straightM: gpxM,
        );
        expect(fb.estimateT, w['estimateT'], reason: '$id/$caseId');
        expect(fb.notAfter, f['notAfter'], reason: '$id/$caseId');
        final h = w['hintEstimateT']! as int;
        expect((fb.hintEstimateT - h).abs(), lessThanOrEqualTo(10));
        if (h > (w['estimateT']! as int)) {
          expect(fb.notBefore, f['notBefore'], reason: '$id/$caseId');
        } else {
          expect(
            ((f['notBefore']! as int) - fb.notBefore).abs(),
            lessThanOrEqualTo(10),
            reason: '$id/$caseId',
          );
        }
      });
    }

    test(
      'the four fallback windows: kill < notBefore <= notAfter <= '
      'modeAtT + lag + 120 (no wake-up later than the live alarm allows)',
      () {
        for (final (id, caseId) in fallbackCases) {
          final f = caseOf(id, caseId)['expectFallback']! as _Case;
          final w = f['window']! as _Case;
          final nb = f['notBefore']! as int;
          final na = f['notAfter']! as int;
          expect(nb, greaterThan(w['killT']! as int), reason: '$id/$caseId');
          expect(nb, lessThanOrEqualTo(na), reason: '$id/$caseId');
          expect(
            na,
            lessThanOrEqualTo((w['modeAtT']! as int) + 30 + 120),
            reason: '$id/$caseId',
          );
        }
      },
    );

    test('killSweep blocks of the seven TR37 cases', () {
      var count = 0;
      for (final id in ids) {
        final o = oracle(id);
        for (final c in (o.fixture['cases']! as List).cast<_Case>()) {
          final ks = c['killSweep'] as _Case?;
          if (ks == null) {
            continue;
          }
          count++;
          final where = '$id/${c['id']}';
          final config = c['config']! as _Case;
          final from = (ks['from']! as _Case)['t']! as int;
          final everyS = ks['everyS']! as int;
          final notAfter = ks['notAfter']! as _Case;
          final earlyFrom = ks['earlyFrom']! as _Case;
          final i = o.intervalS;
          // V6 / V7 on the committed values.
          expect(from, greaterThanOrEqualTo(i), reason: where);
          expect(from % i, 0, reason: where);
          expect(everyS > 0 && everyS % i == 0, isTrue, reason: where);
          // notAfter = arrival, earlyFrom = D1000 straight milestone or
          // A − 900 (T15), recomputed by the oracle (not read from the
          // fixture's own milestones).
          expect(notAfter['t'], o.arrivalT, reason: where);
          final earlyWant = config['mode'] == 'time'
              ? o.arrivalT - 60 * (config['thresholdMin']! as int)
              : o.straightWithin(config['thresholdM']! as int);
          expect(earlyFrom['t'], earlyWant, reason: where);
          // Order: the sweep starts well before the alarm moment, and the
          // early reference is not after the deadline.
          final early = earlyFrom['t']! as int;
          final late = notAfter['t']! as int;
          expect(from, lessThan(early), reason: where);
          expect(early, lessThanOrEqualTo(late), reason: where);
          expect(late, lessThanOrEqualTo(o.durationS), reason: where);
          // At least one kill time per minute of trip before the deadline.
          expect((late - from) ~/ everyS, greaterThan(10), reason: where);
          // No case input that the sweep replaces (V10).
          for (final key in ['kill', 'relaunch', 'osDismiss']) {
            expect(config.containsKey(key), isFalse, reason: where);
          }
          expect(config['osSim'], isNot(false), reason: where);
        }
      }
      expect(count, 7);
    });

    test(
      'self-check: the oracle flags hand edits that validate cannot see',
      () {
        // Review T11.1 "Giới hạn đã biết của validate": a killSweep t that is
        // not anchor + offsetS, and an asOfStraightM edited together with the
        // numbers that depend on it. The oracle catches both.
        final o = oracle('train_hn_dh');
        final mutated = deepCopy(o.fixture)! as Map<String, Object?>;
        final cases = (mutated['cases']! as List).cast<_Case>();
        final ks =
            cases.firstWhere(
                  (c) => c['id'] == 'distance_1000_killsweep',
                )['killSweep']!
                as _Case;
        (ks['earlyFrom']! as _Case)['t'] = 33705;
        final f =
            cases.firstWhere(
                  (c) => c['id'] == 'distance_1000_kill',
                )['expectFallback']!
                as _Case;
        // sM 20000 with the hand-computed H 32684 and NB 32384 (T11.1 §4):
        // self-consistent for validate, wrong for the truth (estimateT
        // 33303 > H, so the floor now sets the lower edge).
        (f['window']! as _Case)
          ..['asOfStraightM'] = 20000
          ..['hintEstimateT'] = 32684;
        f['notBefore'] = 32384;
        final m = Oracle(
          id: o.id,
          fixture: mutated,
          truth: o.truth,
          gpxGaps: o.gpxGaps,
        );
        final bad = m.rows().where((r) => !r.ok).map((r) => r.where).toList();
        expect(bad.toSet(), {
          'train_hn_dh/distance_1000_killsweep killSweep.earlyFrom.t',
          'train_hn_dh/distance_1000_kill expectFallback.window.asOfStraightM',
          'train_hn_dh/distance_1000_kill expectFallback.window.hintEstimateT',
          'train_hn_dh/distance_1000_kill expectFallback.notBefore',
        });
      },
    );
  });
}

String _desc(Map<String, Object?> e) =>
    '${e['event']}${e.containsKey('reason') ? '/${e['reason']}' : ''}';
