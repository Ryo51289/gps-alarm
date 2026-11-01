import 'dart:io';

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

import 'helpers.dart';

final class CliRun {
  const new(this.exitCode, this.out, this.err);

  final int exitCode;
  final String out;
  final String err;
}

Future<CliRun> run(List<String> args, {Directory? workingDirectory}) async {
  final out = CapturedSink();
  final err = CapturedSink();
  final code = await runCli(
    args,
    out: out.sink,
    err: err.sink,
    workingDirectory: workingDirectory ?? packageDir,
  );
  return CliRun(code, await out.text(), await err.text());
}

Future<Directory> tempDir() async {
  final dir = await Directory.systemTemp.createTemp('tracegen_cli_');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

List<String> fileNames(Directory dir) => [
  for (final e in dir.listSync())
    if (e is File) e.uri.pathSegments.last,
]..sort();

void main() {
  group('CLI (TC21)', () {
    test('list prints one line per profile in id order', () async {
      final r = await run(['list']);
      expect(r.exitCode, 0);
      final lines = r.out.trim().split('\n');
      expect(lines, hasLength(15));
      expect(lines.first, 'bus_hn_brt01\tbus\tbus_hn_brt01');
      expect(lines.last, 'train_longstop_nospd\ttrain\trail_dl_dh');
    });

    test('generate one profile writes 2 files', () async {
      final tmp = await tempDir();
      final r = await run([
        'generate',
        '--profile',
        'train_hn_dh',
        '--out',
        tmp.path,
      ]);
      expect(r.exitCode, 0, reason: r.err);
      expect(fileNames(tmp), ['train_hn_dh.expect.json', 'train_hn_dh.gpx']);
      expect(r.out, contains('wrote '));
      expect(r.out, contains('bytes)'));
    });

    test('generate --all, check and validate', () async {
      final tmp = await tempDir();
      final gen = await run(['generate', '--all', '--out', tmp.path]);
      expect(gen.exitCode, 0, reason: gen.err);
      expect(fileNames(tmp), hasLength(30));

      final ok = await run(['check', '--out', tmp.path]);
      expect(ok.exitCode, 0, reason: ok.err);

      final valid = await run(['validate', '--dir', tmp.path]);
      expect(valid.exitCode, 0, reason: valid.err);
      expect(valid.out, contains('15 fixture pair(s) valid'));

      // Flip one byte on line 20 of a GPX file.
      final gpx = File('${tmp.path}/coach_md_tb.gpx');
      final lines = gpx.readAsStringSync().split('\n');
      lines[19] = lines[19].replaceFirst('<time>', '<tima>');
      gpx.writeAsStringSync(lines.join('\n'));
      final differs = await run(['check', '--out', tmp.path]);
      expect(differs.exitCode, 1);
      expect(differs.err, contains('coach_md_tb.gpx'));
      expect(differs.err, contains('line 20'));
      expect(differs.err, contains('generate --all'));

      final invalid = await run(['validate', '--dir', tmp.path]);
      expect(invalid.exitCode, 1);
      expect(invalid.err, contains('coach_md_tb.gpx'));
    });

    test('check reports missing and unexpected files', () async {
      final tmp = await tempDir();
      await run(['generate', '--all', '--out', tmp.path]);
      File('${tmp.path}/x.gpx').writeAsStringSync('');
      File('${tmp.path}/bus_hn_brt01.gpx').deleteSync();
      final r = await run(['check', '--out', tmp.path]);
      expect(r.exitCode, 1);
      expect(r.err, contains('unexpected: ${tmp.path}/x.gpx'));
      expect(r.err, contains('missing: ${tmp.path}/bus_hn_brt01.gpx'));
    });

    test('unknown profile is a usage error naming it', () async {
      final r = await run(['generate', '--profile', 'nope']);
      expect(r.exitCode, 64);
      expect(r.err, contains('nope'));
    });

    test('usage errors', () async {
      for (final args in [
        <String>[],
        ['generate'],
        ['generate', '--all', '--profile', 'train_hn_dh'],
        ['frobnicate'],
        ['list', '--bogus'],
        ['validate'],
      ]) {
        final r = await run(args);
        expect(r.exitCode, 64, reason: '$args');
        expect(r.err, contains('Usage'), reason: '$args');
      }
      final help = await run(['--help']);
      expect(help.exitCode, 0);
      expect(help.out, contains('Usage'));
    });

    test('must run from tools/tracegen', () async {
      final tmp = await tempDir();
      final r = await run(['list'], workingDirectory: tmp);
      expect(r.exitCode, 64);
      expect(r.err, contains('run from tools/tracegen'));
    });

    test('invalid profile data exits 65', () async {
      final tmp = await tempDir();
      await Directory('${tmp.path}/profiles').create();
      File('${tmp.path}/profiles/bad.json').writeAsStringSync('{"id": 1}');
      final r = await run(['list', '--data', tmp.path]);
      expect(r.exitCode, 65);
      expect(r.err, contains('profiles/bad.json'));
    });

    test('kGeneratorVersion equals the pubspec version', () {
      final pubspec = File('${packageDir.path}/pubspec.yaml')
          .readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)\s*$',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(kGeneratorVersion, version);
    });

    test('firstDifferentLine', () {
      expect(firstDifferentLine([1, 2], [1, 2]), isNull);
      expect(firstDifferentLine('a\nb\nc'.codeUnits, 'a\nb\nd'.codeUnits), 3);
      expect(firstDifferentLine('a\n'.codeUnits, 'a\nb'.codeUnits), 2);
    });
  });
}
