// Golden test (TC22): the committed fixtures must be byte-identical to what
// the generator produces on this machine. CI runs it on Linux against files
// generated on Windows, which proves the output is platform independent.
import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

const String _fix =
    'cd tools/tracegen && dart run bin/tracegen.dart generate --all';

void main() {
  final repo = ProfileRepository(dataDir);
  final ids = repo.profileIds();

  test('fixtures directory has exactly the generated pairs', () {
    final expected = <String>{
      for (final id in ids) ...['$id.gpx', '$id.expect.json'],
    };
    final actual = <String>{
      for (final e in fixturesDir.listSync())
        if (e is File) e.uri.pathSegments.last,
    };
    final fixtureFiles = actual.where(
      (n) => n.endsWith('.gpx') || n.endsWith('.expect.json'),
    );
    expect(
      fixtureFiles.toSet().difference(expected),
      isEmpty,
      reason: 'unexpected fixture files (no profile); fix: $_fix',
    );
    expect(
      expected.difference(actual),
      isEmpty,
      reason: 'missing fixture files; fix: $_fix',
    );
    expect(
      actual.difference(expected),
      everyElement('README.md'),
      reason: 'fixtures/traces only holds fixture pairs and README.md',
    );
  });

  for (final id in ids) {
    test('$id matches the generator byte for byte', () {
      final (profile, route) = repo.load(id);
      final files = generateTrace(profile, route);
      for (final (name, bytes) in [
        ('$id.gpx', files.gpx),
        ('$id.expect.json', files.expect),
      ]) {
        final f = File('${fixturesDir.path}/$name');
        expect(f.existsSync(), isTrue, reason: '$name is missing; fix: $_fix');
        final line = firstDifferentLine(f.readAsBytesSync(), bytes);
        expect(
          line,
          isNull,
          reason: '$name differs from the generator at line $line; fix: $_fix',
        );
      }
    });
  }
}
