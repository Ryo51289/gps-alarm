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
}
