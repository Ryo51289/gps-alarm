import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const String tunnel = 'coach_dn_langco_tunnel';

String readText(String name) =>
    File('${fixturesDir.path}/$name').readAsStringSync();

List<String> validateTexts(String gpx, String expect, {String id = tunnel}) =>
    validatePair(
      gpxLabel: '$id.gpx',
      gpxBytes: utf8.encode(gpx),
      expectLabel: '$id.expect.json',
      expectBytes: utf8.encode(expect),
    );

String mutateJson(String text, void Function(Map<String, Object?> j) f) {
  final json = jsonDecode(text) as Map<String, Object?>;
  f(json);
  return const JsonEncoder.withIndent('  ').convert(json);
}

Map<String, Object?> firstExpect(Map<String, Object?> j) {
  final cases = j['cases']! as List<Object?>;
  final c = cases.first! as Map<String, Object?>;
  final expect = c['expect']! as List<Object?>;
  return expect.first! as Map<String, Object?>;
}

void main() {
  final ids = ProfileRepository(dataDir).profileIds();

  group('validate committed fixtures (TC20)', () {
    for (final id in ids) {
      test('$id is valid', () {
        expect(
          validateTexts(
            readText('$id.gpx'),
            readText('$id.expect.json'),
            id: id,
          ),
          isEmpty,
        );
      });
    }
  });

  group('validate mutations (TC20)', () {
    final gpx = readText('$tunnel.gpx');
    final expectText = readText('$tunnel.expect.json');
    final expectJson = jsonDecode(expectText) as Map<String, Object?>;
    final trace = expectJson['trace']! as Map<String, Object?>;
    final gap =
        ((expectJson['truth']! as Map<String, Object?>)['gpsGaps']!
                    as List<Object?>)
                .first!
            as Map<String, Object?>;
    final start = parseIsoUtc(trace['startTime']! as String);

    void expectError(List<String> errors, Pattern pattern) {
      expect(
        errors.any((e) => e.contains(pattern)),
        isTrue,
        reason:
            'expected an error matching "$pattern", got:\n'
            '${errors.join('\n')}',
      );
    }

    test('swapped times', () {
      final t2 = isoUtc(start, 5);
      final t3 = isoUtc(start, 10);
      final mutated = gpx
          .replaceFirst('<time>$t2</time>', '<time>TMP</time>')
          .replaceFirst('<time>$t3</time>', '<time>$t2</time>')
          .replaceFirst('<time>TMP</time>', '<time>$t3</time>');
      expectError(validateTexts(mutated, expectText), 'increase strictly');
    });

    test('missing napstop:acc', () {
      final mutated = gpx.replaceFirst(
        RegExp('<napstop:acc>[^<]*</napstop:acc>'),
        '',
      );
      expectError(validateTexts(mutated, expectText), 'napstop:acc');
    });

    test('wrong GPX namespace', () {
      final mutated = gpx.replaceFirst(
        'xmlns="http://www.topografix.com/GPX/1/1"',
        'xmlns="http://www.topografix.com/GPX/1/0"',
      );
      expectError(validateTexts(mutated, expectText), 'root must be gpx');
    });

    test('lat 91', () {
      final mutated = gpx.replaceFirst(
        RegExp('<trkpt lat="[^"]*"'),
        '<trkpt lat="91.0000000"',
      );
      expectError(validateTexts(mutated, expectText), 'lat must be');
    });

    test('carriage return', () {
      final mutated = gpx.replaceFirst('\n', '\r\n');
      expectError(validateTexts(mutated, expectText), 'carriage return');
    });

    test('schemaVersion 2', () {
      final mutated = mutateJson(expectText, (j) => j['schemaVersion'] = 2);
      expectError(validateTexts(gpx, mutated), 'unsupported schema version');
    });

    test('notBefore > notAfter', () {
      final mutated = mutateJson(expectText, (j) {
        final e = firstExpect(j);
        e['notBefore'] = (e['notAfter']! as int) + 5;
      });
      expectError(validateTexts(gpx, mutated), 'notBefore');
    });

    test('wrong sampleCount', () {
      final mutated = mutateJson(expectText, (j) {
        final t = j['trace']! as Map<String, Object?>;
        t['sampleCount'] = (t['sampleCount']! as int) + 1;
      });
      expectError(validateTexts(gpx, mutated), 'trace.sampleCount');
    });

    test('unknown event', () {
      final mutated = mutateJson(
        expectText,
        (j) => firstExpect(j)['event'] = 'boom',
      );
      expectError(validateTexts(gpx, mutated), 'unknown event');
    });

    test('sample inside a gap', () {
      final fromT = gap['fromT']! as int;
      final extra = [
        '      <trkpt lat="16.1000000" lon="108.1000000">',
        '<time>${isoUtc(start, fromT)}</time>',
        '<extensions><napstop:acc>5.0</napstop:acc></extensions>',
        '</trkpt>\n',
      ].join();
      final mutated = gpx.replaceFirst(
        '    </trkseg>\n',
        '$extra    </trkseg>\n',
      );
      expectError(validateTexts(mutated, expectText), 'inside');
    });

    test('merged trkseg', () {
      final mutated = gpx.replaceFirst('    </trkseg>\n    <trkseg>\n', '');
      expectError(validateTexts(mutated, expectText), 'trkseg');
    });

    test('byte order mark and bad XML', () {
      expectError(validateTexts('﻿$gpx', expectText), 'byte order mark');
      expectError(
        validateTexts(gpx.replaceFirst('</gpx>', ''), expectText),
        'well-formed',
      );
    });
  });

  group('validate T11 case keys (TG19)', () {
    const id = 'coach_gb_phuly_overshoot';
    final gpx = readText('$id.gpx');
    final expectText = readText('$id.expect.json');

    List<String> run(void Function(Map<String, Object?> j) f) =>
        validateTexts(gpx, mutateJson(expectText, f), id: id);

    Map<String, Object?> caseNamed(Map<String, Object?> j, String caseId) =>
        (j['cases']! as List<Object?>).cast<Map<String, Object?>>().firstWhere(
          (c) => c['id'] == caseId,
        );

    Map<String, Object?> silenced(Map<String, Object?> j) =>
        caseNamed(j, 'distance_1000_fallback_silenced');

    void expectError(List<String> errors, String where, Pattern message) {
      expect(
        errors.any((e) => e.contains(where) && e.contains(message)),
        isTrue,
        reason: 'expected "$where ... $message", got:\n${errors.join('\n')}',
      );
    }

    test('the committed fixture is valid', () {
      expect(run((_) {}), isEmpty);
    });

    test('schemaVersion 2 is rejected', () {
      expectError(
        run((j) => j['schemaVersion'] = 2),
        'schemaVersion',
        'unsupported schema version',
      );
    });

    test('unknown key inside a case config fails (must-understand)', () {
      expectError(
        run((j) => (silenced(j)['config']! as Map<String, Object?>)['foo'] = 1),
        'config.foo',
        'unknown key',
      );
      expectError(
        run((j) => silenced(j)['bar'] = true),
        'cases[3].bar',
        'unknown key',
      );
    });

    test('unknown key outside cases is ignored', () {
      expect(
        run((j) => (j['truth']! as Map<String, Object?>)['foo'] = 1),
        isEmpty,
      );
    });

    test('new event names are accepted', () {
      expect(
        run((j) => (silenced(j)['forbid']! as List<Object?>).add('snoozed')),
        isEmpty,
      );
    });

    test('final case without testIds', () {
      expectError(
        run((j) => silenced(j).remove('testIds')),
        'cases[3].testIds',
        'non-empty testIds',
      );
    });

    test('relaunch without kill', () {
      expectError(
        run(
          (j) =>
              (silenced(j)['config']! as Map<String, Object?>).remove('kill'),
        ),
        'config.relaunch',
        'needs config.kill',
      );
    });

    test('withinS lo > hi', () {
      expectError(
        run((j) {
          final after = (silenced(j)['expectAfter']! as List<Object?>).first!;
          (after as Map<String, Object?>)['withinS'] = [5, 0];
        }),
        'expectAfter[0].withinS',
        'lo <= hi',
      );
    });

    test('expectFallback must follow T11 §5.3', () {
      expectError(
        run(
          (j) => (silenced(j)['expectFallback']! as Map<String, Object?>)
              .remove('asOfT'),
        ),
        'expectFallback.asOfT',
        'missing required key',
      );
      expectError(
        run((j) {
          final f = silenced(j)['expectFallback']! as Map<String, Object?>;
          (f['window']! as Map<String, Object?>)['estimateT'] = 2375;
        }),
        'window.estimateT',
        'T11 §5.3',
      );
    });

    test('forbidMatch conflicting with an expectation', () {
      expectError(
        run(
          (j) => silenced(j)['forbidMatch'] = [
            {'event': 'alarm', 'reason': 'OVERSHOOT'},
          ],
        ),
        'forbidMatch[0]',
        'forbids an event',
      );
    });

    test('run-time anchor with a t and static anchor without', () {
      expectError(
        run((j) {
          final config = silenced(j)['config']! as Map<String, Object?>;
          ((config['relaunch']! as Map<String, Object?>)['at']!
                  as Map<String, Object?>)['t'] =
              2000;
        }),
        'relaunch.at.t',
        'run-time anchor has no t',
      );
      expectError(
        run((j) {
          final config = silenced(j)['config']! as Map<String, Object?>;
          (config['kill']! as Map<String, Object?>).remove('t');
        }),
        'config.kill.t',
        'missing required key',
      );
    });
  });

  group('validate T11 round 2 (TG37, TG38)', () {
    const id = 'train_hn_dh';
    final gpx = readText('$id.gpx');
    final expectText = readText('$id.expect.json');
    final cases =
        (jsonDecode(expectText) as Map<String, Object?>)['cases']!
            as List<Object?>;

    int indexOf(String caseId) =>
        cases.indexWhere((c) => (c! as Map<String, Object?>)['id'] == caseId);

    List<String> run(void Function(Map<String, Object?> j) f) =>
        validateTexts(gpx, mutateJson(expectText, f), id: id);

    Map<String, Object?> caseNamed(Map<String, Object?> j, String caseId) =>
        (j['cases']! as List<Object?>)[indexOf(caseId)]!
            as Map<String, Object?>;

    Map<String, Object?> configOf(Map<String, Object?> j, String caseId) =>
        caseNamed(j, caseId)['config']! as Map<String, Object?>;

    Map<String, Object?> objAt(Object? o, List<Object> path) {
      var cur = o;
      for (final k in path) {
        cur = k is int ? (cur! as List<Object?>)[k] : (cur! as Map)[k];
      }
      return cur! as Map<String, Object?>;
    }

    void expectOnlyError(List<String> errors, String where, Pattern message) {
      expect(
        errors.length == 1 &&
            errors.single.contains('$where:') &&
            errors.single.contains(message),
        isTrue,
        reason:
            'expected one "$where: ... $message", got:\n'
            '${errors.join('\n')}',
      );
    }

    const offsetMessage =
        'run anchor in an input requires offsetS >= '
        'sampleIntervalS (5)';

    test('TG37 actions[].at with a run anchor', () {
      final snooze = indexOf('distance_1000_snooze');
      final where = 'cases[$snooze].config.actions[0].at.offsetS';
      for (final offset in [0, -5]) {
        expectOnlyError(
          run((j) {
            objAt(configOf(j, 'distance_1000_snooze'), [
              'actions',
              0,
              'at',
            ])['offsetS'] = offset;
          }),
          where,
          offsetMessage,
        );
      }
      expect(
        run((j) {
          objAt(configOf(j, 'distance_1000_snooze'), [
            'actions',
            0,
            'at',
          ])['offsetS'] = 5;
        }),
        isEmpty,
      );
      final rang = indexOf('distance_1000_kill_rang');
      expectOnlyError(
        run((j) {
          configOf(j, 'distance_1000_kill_rang')['actions'] = [
            {
              'at': {'anchor': 'relaunch', 'offsetS': 0},
              'action': 'dismiss',
            },
          ];
        }),
        'cases[$rang].config.actions[0].at.offsetS',
        offsetMessage,
      );
    });

    test('TG37 relaunch.at with a run anchor', () {
      final rang = indexOf('distance_1000_kill_rang');
      final where = 'cases[$rang].config.relaunch.at.offsetS';
      Map<String, Object?> at(Map<String, Object?> j) =>
          objAt(configOf(j, 'distance_1000_kill_rang'), ['relaunch', 'at']);
      expectOnlyError(run((j) => at(j)['offsetS'] = 0), where, offsetMessage);
      expect(run((j) => at(j)['offsetS'] = 5), isEmpty);
      expectOnlyError(
        run(
          (j) => at(j)
            ..['anchor'] = 'event:preAlert'
            ..['offsetS'] = 0,
        ),
        where,
        offsetMessage,
      );
    });

    test('TG37 checks may use offsetS <= 0', () {
      // Committed fixture: expectAfter after event:alarm + 0 and forbidAfter
      // after relaunch − 5.
      final snooze = cases[indexOf('distance_1000_snooze')]!;
      final rang = cases[indexOf('distance_1000_kill_rang')]!;
      expect(objAt(snooze, ['expectAfter', 0, 'after']), {
        'anchor': 'event:alarm',
        'offsetS': 0,
      });
      expect(objAt(rang, ['forbidAfter', 0, 'after']), {
        'anchor': 'relaunch',
        'offsetS': -5,
      });
      expect(run((_) {}), isEmpty);
    });

    // Must-understand at every depth inside cases[i] (T11 §1, round 2).
    final nested = <(String, String, List<Object>)>[
      ('distance_1000', 'expect[0]', ['expect', 0]),
      ('distance_1000', 'expect[0].window', ['expect', 0, 'window']),
      (
        'distance_1000',
        'expect[0].window.notBefore',
        ['expect', 0, 'window', 'notBefore'],
      ),
      (
        'distance_1000_snooze',
        'config.actions[0].at',
        ['config', 'actions', 0, 'at'],
      ),
      ('distance_1000_kill_rang', 'config.relaunch', ['config', 'relaunch']),
      (
        'distance_1000_snooze',
        'expectAfter[0].after',
        ['expectAfter', 0, 'after'],
      ),
      (
        'distance_1000_kill',
        'expectFallback.window.modeAt',
        ['expectFallback', 'window', 'modeAt'],
      ),
      ('summary_unknown', 'expectSummary', ['expectSummary']),
      ('distance_1000_kill_missing', 'forbidMatch[0]', ['forbidMatch', 0]),
      ('distance_1000_kill_rang', 'forbidAfter[0]', ['forbidAfter', 0]),
    ];
    for (final (caseId, path, keys) in nested) {
      test('TG38 unknown key in $caseId $path fails', () {
        expectOnlyError(
          run((j) => objAt(caseNamed(j, caseId), keys)['foo'] = 1),
          'cases[${indexOf(caseId)}].$path.foo',
          'unknown key',
        );
      });
    }

    test('TG38 unknown key in config.battery[0] fails', () {
      const md = 'coach_md_tb';
      final text = readText('$md.expect.json');
      final mdCases =
          (jsonDecode(text) as Map<String, Object?>)['cases']! as List<Object?>;
      final i = mdCases.indexWhere(
        (c) => (c! as Map<String, Object?>)['id'] == 'distance_1000_battery',
      );
      final errors = validateTexts(
        readText('$md.gpx'),
        mutateJson(text, (j) {
          final c = (j['cases']! as List<Object?>)[i];
          objAt(c, ['config', 'battery', 0])['foo'] = 1;
        }),
        id: md,
      );
      expectOnlyError(errors, 'cases[$i].config.battery[0].foo', 'unknown key');
    });

    for (final top in ['truth', 'trace', 'milestones']) {
      test('TG38 unknown key in $top is ignored', () {
        expect(
          run((j) => (j[top]! as Map<String, Object?>)['foo'] = 1),
          isEmpty,
        );
      });
    }
  });
}
