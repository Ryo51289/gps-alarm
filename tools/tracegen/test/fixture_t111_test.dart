// T11.1 fixture checks: the `expectFallback` windows of the T10.2 formula
// (TG43) and the T11.1 case list (TG47), read from the committed fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';
import 'support/window_oracle.dart';

typedef _J = Map<String, Object?>;

_J _fixture(String id) =>
    jsonDecode(File('${fixturesDir.path}/$id.expect.json').readAsStringSync())
        as _J;

List<_J> _cases(_J fixture) => (fixture['cases']! as List).cast<_J>();

_J _case(_J fixture, String caseId) =>
    _cases(fixture).firstWhere((c) => c['id'] == caseId);

void main() {
  group('TG43 expectFallback windows (T11.1 §4)', () {
    // (profile, case, E, [notBefore, notAfter] or null when the speed floor
    // sets the lower edge, floor wins)
    const rows = [
      ('train_hn_dh', 'distance_1000_kill', 33303, [33003, 33423], false),
      ('train_hn_dh', 'time_15_kill', 32695, [32395, 32815], false),
      ('coach_md_tb', 'smart_kill', 6590, null, true),
      (
        'coach_gb_phuly_overshoot',
        'distance_1000_fallback_silenced',
        2370,
        [2070, 2490],
        false,
      ),
    ];
    for (final (id, caseId, e, window, floorWins) in rows) {
      test('$id/$caseId', () {
        final o = Oracle.load(id, data: dataDir, fix: fixturesDir);
        final c = _case(o.fixture, caseId);
        final config = c['config']! as _J;
        final f = c['expectFallback']! as _J;
        final w = f['window']! as _J;
        final asOfT = f['asOfT']! as int;
        final interval = o.intervalS;
        // Review T11.1 nit 1 (tester): the window uses the fixture's own
        // toleranceS; the T10 tolerance is pinned on its own so that a
        // changed tolerance fails here with a clear message.
        final tol = (w['toleranceS']! as List).cast<int>();
        expect(tol, [-300, 120], reason: 'toleranceS of $id/$caseId changed');

        // asOfStraightM: true position at asOfT, effective destination.
        expect(o.truth.states[asOfT ~/ interval].t, asOfT);
        expect(
          w['asOfStraightM'],
          o.truth.straightM[asOfT ~/ interval].floor(),
        );

        final fb = o.fallbackOf(
          mode: config['mode']! as String,
          threshold: (config['thresholdM'] ?? config['thresholdMin']) as int?,
          hint:
              (config['vehicleHint'] ?? (o.fixture['trace']! as _J)['vehicle'])!
                  as String,
          modeAtT: w['modeAtT']! as int,
          killT: w['killT']! as int,
          tolerance: (tol[0], tol[1]),
        );
        expect(
          [w['estimateT'], w['hintEstimateT'], f['notBefore'], f['notAfter']],
          [fb.estimateT, fb.hintEstimateT, fb.notBefore, fb.notAfter],
        );
        expect(w['estimateT'], e);
        final hint = w['hintEstimateT']! as int;
        if (floorWins) {
          expect(hint, lessThan(e));
          expect(f['notBefore'], hint - 300);
          expect(f['notAfter'], 6710);
        } else {
          expect([f['notBefore'], f['notAfter']], window);
        }
        if (caseId == 'distance_1000_kill' || caseId == 'time_15_kill') {
          expect(hint, greaterThan(e));
        }
        if (id == 'coach_gb_phuly_overshoot') {
          expect(hint, greaterThanOrEqualTo(asOfT + 600));
        }
      });
    }
  });

  group('TG47 fixture case list after T11.1', () {
    final ids = ProfileRepository(dataDir).profileIds();
    final fixtures = {for (final id in ids) id: _fixture(id)};
    final all = {
      for (final MapEntry(key: id, value: j) in fixtures.entries)
        for (final c in _cases(j)) '$id/${c['id']}': c,
    };

    // T11.2 RK4: counts and version follow the current state (17 traces,
    // 65 cases after T11.5; version = pubspec).
    test('generator.version equals the pubspec version everywhere', () {
      final pubspec = File('${packageDir.path}/pubspec.yaml')
          .readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(ids, hasLength(17));
      for (final MapEntry(key: id, value: j) in fixtures.entries) {
        expect((j['generator']! as _J)['version'], version, reason: id);
      }
      expect(kGeneratorVersion, version);
    });

    test('65 final cases (T11.5: + TR44), none with samplingModes', () {
      expect(all, hasLength(65));
      for (final MapEntry(:key, :value) in all.entries) {
        expect(value['status'], 'final', reason: key);
        expect(value.containsKey('samplingModes'), isFalse, reason: key);
      }
    });

    test('policyPhaseSweep: true in exactly six cases (T11.5: + TR44)', () {
      expect(
        {
          for (final MapEntry(:key, :value) in all.entries)
            if (value.containsKey('policyPhaseSweep'))
              key: value['policyPhaseSweep'],
        },
        {
          'train_hn_dh_stopgap/distance_1000': true,
          'train_hn_dh_stopgap/summary_unknown': true,
          'train_hn_dh_stopgap/distance_1000_killsweep': true,
          'coach_gb_phuly_overshoot/distance_1000_killsweep': true,
          'train_longstop/distance_1000_killsweep': true,
          'coach_gb_phuly_overshoot/distance_1000_overshoot_ringing': true,
        },
      );
    });

    test('the seven TR37 cases follow T11.1 §5.8', () {
      // profile/case -> (time mode, policyPhaseSweep, statsOnly)
      const table = {
        'train_hn_dh/distance_1000_killsweep': (false, false, false),
        'train_hn_dh/time_15_killsweep': (true, false, false),
        'train_hn_dh_stopgap/distance_1000_killsweep': (false, true, false),
        'coach_md_tb/distance_1000_killsweep': (false, false, false),
        'bus_hn_slow/distance_1000_killsweep': (false, false, false),
        'coach_gb_phuly_overshoot/distance_1000_killsweep': (false, true, true),
        'train_longstop/distance_1000_killsweep': (false, true, true),
      };
      final tr37 = {
        for (final MapEntry(:key, :value) in all.entries)
          if ((value['testIds']! as List).contains('TR37')) key: value,
      };
      expect(tr37.keys.toSet(), table.keys.toSet());
      expect(all.values.where((c) => c.containsKey('killSweep')), hasLength(7));
      for (final MapEntry(:key, value: c) in tr37.entries) {
        final (time, sweep, statsOnly) = table[key]!;
        final fixture = fixtures[key.split('/').first]!;
        final truth = fixture['truth']! as _J;
        final arrivalT = truth['arrivalT']! as int;
        final straight1000 =
            ((fixture['milestones']! as _J)['distance']! as List)
                .cast<_J>()
                .singleWhere((m) => m['thresholdM'] == 1000)['straightT'];

        expect(c['testIds'], ['TR37'], reason: key);
        expect(
          c['config'],
          time
              ? {'mode': 'time', 'thresholdMin': 15, 'preAlert': true}
              : {'mode': 'distance', 'thresholdM': 1000, 'preAlert': true},
          reason: key,
        );
        expect(c['policyPhaseSweep'], sweep ? isTrue : isNull, reason: key);
        expect(c['expect'], isEmpty, reason: key);
        expect(c['forbid'], isEmpty, reason: key);
        final ks = c['killSweep']! as _J;
        expect(ks['from'], {'t': 60}, reason: key);
        expect(ks['everyS'], 60, reason: key);
        expect(ks['notAfter'], {
          't': arrivalT,
          'anchor': 'arrival',
          'offsetS': 0,
        }, reason: key);
        expect(
          ks['earlyFrom'],
          time
              ? {'t': arrivalT - 900, 'anchor': 'arrival', 'offsetS': -900}
              : {'t': straight1000, 'anchor': 'straight<=1000', 'offsetS': 0},
          reason: key,
        );
        expect(ks['statsOnly'], statsOnly ? isTrue : isNull, reason: key);
      }
    });
  });
}
