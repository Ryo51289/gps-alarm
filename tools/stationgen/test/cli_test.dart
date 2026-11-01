// TC17 (CLI usage), TC14 (build/check never use the network), TC19
// (determinism on the real data).
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

final class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('network access is not allowed in build/check');
  }
}

void main() {
  group('usage (TC17)', () {
    test('no command', () async {
      expect((await runCliCaptured([])).exitCode, 64);
    });

    test('unknown command', () async {
      expect((await runCliCaptured(['generate'])).exitCode, 64);
    });

    test('--help', () async {
      final r = await runCliCaptured(['--help']);
      expect(r.exitCode, 0);
      expect(r.out, contains('fetch'));
      expect(r.out, contains('check'));
    });

    test('outside tools/stationgen', () async {
      final tmp = Directory.systemTemp.createTempSync('stationgen_wd_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final r = await runCliCaptured(['check'], workingDirectory: tmp);
      expect(r.exitCode, 64);
      expect(r.err, contains('tools/stationgen'));
    });

    test('missing input file: exit 65', () async {
      final tmp = Directory.systemTemp.createTempSync('stationgen_empty_');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final r = await runCliCaptured(['build', '--data', tmp.path]);
      expect(r.exitCode, 65);
    });
  });

  test('build and check run without network (TC14)', () async {
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final guard = _NoNetwork();
    final out = '${tmp.path}/stations.json';
    final (build, check) = await HttpOverrides.runWithHttpOverrides(
      () async => (
        await runCliCaptured(['build', '--data', tmp.path, '--out', out]),
        await runCliCaptured(['check', '--data', tmp.path, '--out', out]),
      ),
      guard,
    );
    expect(build.exitCode, 0, reason: build.err);
    expect(check.exitCode, 0, reason: check.err);
    expect(guard.attempts, 0);
  });

  test('build twice gives identical bytes; A1–A5 pass (TC19)', () async {
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = '${tmp.path}/stations.json';
    final report = '${tmp.path}/BUILD_REPORT.md';
    final first = await runCliCaptured([
      'build',
      '--data',
      tmp.path,
      '--out',
      out,
    ]);
    expect(first.exitCode, 0, reason: first.err);
    final json1 = File(out).readAsBytesSync();
    final report1 = File(report).readAsBytesSync();
    File(out).deleteSync();
    final second = await runCliCaptured([
      'build',
      '--data',
      tmp.path,
      '--out',
      out,
    ]);
    expect(second.exitCode, 0);
    expect(firstDifferentLine(File(out).readAsBytesSync(), json1), isNull);
    expect(firstDifferentLine(File(report).readAsBytesSync(), report1), isNull);
    expect(buildDataset(BuildInputs.read(tmp)).accepted, isTrue);
  });

  test('check reports a stale output (exit 1)', () async {
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    final out = '${tmp.path}/stations.json';
    await runCliCaptured(['build', '--data', tmp.path, '--out', out]);
    File(out).writeAsStringSync('{}\n');
    final r = await runCliCaptured(['check', '--data', tmp.path, '--out', out]);
    expect(r.exitCode, 1);
    expect(r.err, contains('differs'));
  });

  test('firstDifferentLine', () {
    expect(firstDifferentLine([1, 10, 2], [1, 10, 2]), isNull);
    expect(firstDifferentLine([1, 10, 2], [1, 10, 3]), 2);
    expect(firstDifferentLine([1], [1, 10]), 1);
  });
}
