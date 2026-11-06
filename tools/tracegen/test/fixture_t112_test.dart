// T11.2 TG56: the committed fixtures after `generate --all` follow T11.2 §4
// and §7 (T10.3: Q10 = A windows of coach_md_tb, TR38 / TR27 with
// `allowFallbackFirst` on coach_gb_phuly_offroute, TR32 / TR27 on
// coach_gb_phuly_offroute_2k). Resolved numbers come from the fixture truth.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

typedef _J = Map<String, Object?>;

_J _fixture(String id) =>
    jsonDecode(File('${fixturesDir.path}/$id.expect.json').readAsStringSync())
        as _J;

List<_J> _cases(_J fixture) => (fixture['cases']! as List).cast<_J>();

_J _case(_J fixture, String caseId) =>
    _cases(fixture).firstWhere((c) => c['id'] == caseId);

List<_J> _expect(_J c) => (c['expect']! as List).cast<_J>();

_J _entry(_J c, String event, [String? reason]) =>
    _expect(c).singleWhere((e) => e['event'] == event && e['reason'] == reason);

List<Object?> _window(_J e) => [e['notBefore'], e['notAfter']];

void main() {
  const off = 'coach_gb_phuly_offroute';
  const off2k = 'coach_gb_phuly_offroute_2k';
  final ids = ProfileRepository(dataDir).profileIds();
  final fixtures = {for (final id in ids) id: _fixture(id)};
  final all = {
    for (final MapEntry(key: id, value: j) in fixtures.entries)
      for (final c in _cases(j)) '$id/${c['id']}': c,
  };
  _J truthOf(String id) => fixtures[id]!['truth']! as _J;

  group('TG56 fixtures after T11.2', () {
    test('17 traces (T11.3: + TR40) at generator.version 1.3.0, 65 final cases '
        '(T11.5: + TR44)', () {
      expect(ids, hasLength(17));
      expect(ids, contains(off2k));
      for (final MapEntry(key: id, value: j) in fixtures.entries) {
        expect((j['generator']! as _J)['version'], '1.3.0', reason: id);
      }
      expect(all, hasLength(65));
      for (final MapEntry(:key, :value) in all.entries) {
        expect(value['status'], 'final', reason: key);
      }
    });

    test('coach_md_tb/time_15: preAlert [A − 2700, A − 1740], TIME kept', () {
      const md = 'coach_md_tb';
      final a = truthOf(md)['arrivalT']! as int;
      final c = _case(fixtures[md]!, 'time_15');
      final pre = _entry(c, 'preAlert');
      expect(_window(pre), [a - 2700, a - 1740]);
      expect(pre['window'], {
        'notBefore': {'anchor': 'arrival', 'offsetS': -2700},
        'notAfter': {'anchor': 'arrival', 'offsetS': -1740},
      });
      expect(_window(_entry(c, 'alarm', 'TIME')), [a - 960, a - 840]);
    });

    test('coach_md_tb/smart: SMART_TIME [A − 900, A − 540]', () {
      const md = 'coach_md_tb';
      final a = truthOf(md)['arrivalT']! as int;
      final c = _case(fixtures[md]!, 'smart');
      final e = _entry(c, 'alarm', 'SMART_TIME');
      expect(_window(e), [a - 900, a - 540]);
      expect(e['window'], {
        'notBefore': {'anchor': 'arrival', 'offsetS': -900},
        'notAfter': {'anchor': 'arrival', 'offsetS': -540},
      });
    });

    test('$off: TR38 and TR27 expect FALLBACK [closest, closest + 80]', () {
      final closestT = (truthOf(off)['closest']! as _J)['t']! as int;
      for (final caseId in ['distance_1000', 'summary_unknown']) {
        final c = _case(fixtures[off]!, caseId);
        expect(c['allowFallbackFirst'], isTrue, reason: caseId);
        final e = _entry(c, 'alarm', 'FALLBACK');
        expect(e['ringNow'], isFalse, reason: caseId);
        expect(_window(e), [closestT, closestT + 80], reason: caseId);
        expect(e['window'], {
          'notBefore': {'anchor': 'closest', 'offsetS': 0},
          'notAfter': {'anchor': 'closest', 'offsetS': 80},
        }, reason: caseId);
      }
      final tr38 = _case(fixtures[off]!, 'distance_1000');
      expect(tr38['testIds'], ['TR38']);
      expect(_expect(tr38), hasLength(1));
      expect(tr38['forbid'], ['overshoot', 'gpsLost']);
      expect(tr38['forbidMatch'], [
        {'event': 'alarm', 'reason': 'DISTANCE'},
        {'event': 'alarm', 'reason': 'PASSED_CLOSEST'},
        {'event': 'alarm', 'ringNow': true},
      ]);
      final tr27 = _case(fixtures[off]!, 'summary_unknown');
      expect(tr27['testIds'], ['TR27']);
      expect(
        [for (final e in _expect(tr27)) e['event']],
        ['alarm', 'tripEnded'],
      );
      expect(tr27['expectSummary'], {'vehicleGuess': 'UNKNOWN'});
    });

    test('$off2k: offset 2000, TR32 [closest.departT, + 30], TR27', () {
      final j = fixtures[off2k]!;
      expect((j['destination']! as _J)['offsetM'], 2000);
      final departT = (truthOf(off2k)['closest']! as _J)['departT']! as int;
      final tr32 = _case(j, 'distance_1000');
      expect(tr32['testIds'], ['TR32']);
      final e = _entry(tr32, 'alarm', 'PASSED_CLOSEST');
      expect(_window(e), [departT, departT + 30]);
      expect(e['window'], {
        'notBefore': {'anchor': 'closest.departT', 'offsetS': 0},
        'notAfter': {'anchor': 'closest.departT', 'offsetS': 30},
      });
      expect(tr32['forbid'], ['overshoot', 'gpsLost']);
      expect(tr32['forbidMatch'], [
        {'event': 'alarm', 'reason': 'DISTANCE'},
      ]);
      final tr27 = _case(j, 'summary_unknown');
      expect(tr27['testIds'], ['TR27']);
      expect(tr27['expectSummary'], {'vehicleGuess': 'UNKNOWN'});
      for (final c in _cases(j)) {
        expect(
          c.containsKey('allowFallbackFirst'),
          isFalse,
          reason: '${c['id']}',
        );
      }
    });

    test('no other case has allowFallbackFirst', () {
      expect(
        {
          for (final MapEntry(:key, :value) in all.entries)
            if (value.containsKey('allowFallbackFirst'))
              key: value['allowFallbackFirst'],
        },
        {'$off/distance_1000': true, '$off/summary_unknown': true},
      );
    });
  });
}
