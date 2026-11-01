// T11 TG32 (tester): recompute every resolved window, `At.t`, `asOfT` and
// truth anchor of the committed fixtures from the motion truth and the GPX,
// independently of the generator's anchor resolution (see
// `support/window_oracle.dart`), plus hand-computed numbers for the windows
// that depend on milestones or on the §5.3 formula, and out-of-spec checks
// that no expectation lets an alarm come after the passenger should be off.
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
      expect(c['samplingModes'], ['all']);
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

    test('TR22 / TR28 / TR29 / TR35 expectFallback (T11 §5.3)', () {
      // (profile, case, killT, modeAtT, asOfT, E, notBefore, notAfter)
      final rows = [
        // TR22: A 33790, kill A−2400 = 31390, m = s≤1000 = 33700,
        // early = (33700−31390−600)~/10 = 171, E = 33700+30−171 = 33559.
        ('train_hn_dh', 'distance_1000_kill', 31390, 33700, 31385, 33559),
        // TR28: m = A−900 = 32890, early = (32890−31390−600)~/10 = 90,
        // E = 32890+30−90 = 32830 = A−960.
        ('train_hn_dh', 'time_15_kill', 31390, 32890, 31385, 32830),
        // TR29: A 7310, kill A−1800 = 5510, m = A−600 = 6710,
        // early = (6710−5510−600)~/10 = 60, E = 6680 = A−630.
        ('coach_md_tb', 'smart_kill', 5510, 6710, 5505, 6680),
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
        final f = caseOf(id, caseId)['expectFallback']! as _Case;
        final w = f['window']! as _Case;
        expect(
          [w['killT'], w['modeAtT'], f['asOfT'], w['estimateT']],
          [kill, modeAt, asOf, e],
          reason: '$id/$caseId',
        );
        expect(
          [f['notBefore'], f['notAfter']],
          [e - 300, e + 120],
          reason: '$id/$caseId',
        );
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

    test('TR32 PASSED_CLOSEST [cl.dep, cl.dep + 30] = [2645, 2675]', () {
      final o = oracle('coach_gb_phuly_offroute');
      // dMin 1500 m at 2425; need = max(500, 750) = 750 → first tick with
      // straight >= 2250 m after 2425 is 2645.
      expect(o.closest, (t: 2425, straightM: 1500, departT: 2645));
      final c = caseOf('coach_gb_phuly_offroute', 'distance_1000');
      expect(window(expectEntry(c, 'alarm', 'PASSED_CLOSEST')), [2645, 2675]);
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
}

String _desc(Map<String, Object?> e) =>
    '${e['event']}${e.containsKey('reason') ? '/${e['reason']}' : ''}';
