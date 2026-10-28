/// Command line interface (spec T02 §3). The only place with file IO besides
/// [ProfileRepository].
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:tracegen/src/generator.dart';
import 'package:tracegen/src/paths.dart';
import 'package:tracegen/src/profile.dart';
import 'package:tracegen/src/validate.dart';

/// Exit code: success.
const int kExitOk = 0;

/// Exit code: differences or validation errors.
const int kExitFailed = 1;

/// Exit code: command line usage error (sysexits `EX_USAGE`).
const int kExitUsage = 64;

/// Exit code: invalid profile or route data (sysexits `EX_DATAERR`).
const int kExitData = 65;

const String _defaultOut = '../../fixtures/traces';
const String _defaultData = 'data';

ArgParser _buildParser() {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
    ..addCommand(
      'list',
      ArgParser()..addOption('data', defaultsTo: _defaultData),
    )
    ..addCommand(
      'generate',
      ArgParser()
        ..addMultiOption('profile', help: 'Profile id (repeatable).')
        ..addFlag('all', negatable: false, help: 'Every profile.')
        ..addOption('out', defaultsTo: _defaultOut)
        ..addOption('data', defaultsTo: _defaultData),
    )
    ..addCommand(
      'check',
      ArgParser()
        ..addOption('out', defaultsTo: _defaultOut)
        ..addOption('data', defaultsTo: _defaultData),
    )
    ..addCommand('validate', ArgParser()..addOption('dir'));
  return parser;
}

String _usage(ArgParser parser) =>
    '''
Usage (run from tools/tracegen):
  dart run bin/tracegen.dart list [--data <dir>]
  dart run bin/tracegen.dart generate (--profile <id> ... | --all) [--out <dir>] [--data <dir>]
  dart run bin/tracegen.dart check [--out <dir>] [--data <dir>]
  dart run bin/tracegen.dart validate (--dir <dir> | <file> ...)

Defaults: --data $_defaultData, --out $_defaultOut

${parser.usage}''';

/// Runs the CLI; returns the process exit code.
Future<int> runCli(
  List<String> args, {
  required IOSink out,
  required IOSink err,
  Directory? workingDirectory,
}) async {
  final parser = _buildParser();
  final ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    err
      ..writeln(e.message)
      ..writeln(_usage(parser));
    return kExitUsage;
  }
  if (results.flag('help')) {
    out.writeln(_usage(parser));
    return kExitOk;
  }
  final command = results.command;
  if (command == null ||
      command.rest.isNotEmpty && command.name != 'validate') {
    err.writeln(_usage(parser));
    return kExitUsage;
  }

  final wd = workingDirectory ?? Directory.current;
  final pubspec = File('${wd.path}/pubspec.yaml');
  if (!pubspec.existsSync() ||
      !RegExp(
        r'^name:\s*tracegen\s*$',
        multiLine: true,
      ).hasMatch(pubspec.readAsStringSync())) {
    err.writeln(
      'error: run from tools/tracegen (no tracegen pubspec.yaml in '
      '${wd.path})',
    );
    return kExitUsage;
  }
  String resolve(String path) => _isAbsolute(path) ? path : '${wd.path}/$path';

  try {
    switch (command.name) {
      case 'list':
        return _list(command, out, resolve);
      case 'generate':
        return await _generate(command, parser, out, err, resolve);
      case 'check':
        return _check(command, out, err, resolve);
      case 'validate':
        return _validate(command, parser, out, err, resolve);
    }
  } on ProfileException catch (e) {
    err.writeln('error: $e');
    return kExitData;
  }
  err.writeln(_usage(parser));
  return kExitUsage;
}

bool _isAbsolute(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\') ||
    RegExp('^[A-Za-z]:').hasMatch(path);

int _list(ArgResults command, IOSink out, String Function(String) resolve) {
  final repo = ProfileRepository(Directory(resolve(command.option('data')!)));
  for (final id in repo.profileIds()) {
    final (profile, _) = repo.load(id);
    out.writeln('$id\t${profile.vehicle.name}\t${profile.route}');
  }
  return kExitOk;
}

Future<int> _generate(
  ArgResults command,
  ArgParser parser,
  IOSink out,
  IOSink err,
  String Function(String) resolve,
) async {
  final all = command.flag('all');
  final requested = command.multiOption('profile');
  if (all == requested.isNotEmpty) {
    err
      ..writeln('error: generate needs either --profile <id> or --all')
      ..writeln(_usage(parser));
    return kExitUsage;
  }
  final repo = ProfileRepository(Directory(resolve(command.option('data')!)));
  final known = repo.profileIds();
  for (final id in requested) {
    if (!known.contains(id)) {
      err.writeln('error: unknown profile "$id" (see: list)');
      return kExitUsage;
    }
  }
  final ids = all ? known : ([...requested.toSet()]..sort());
  // Generate everything first so a bad profile writes nothing.
  final files = [for (final id in ids) _generateOne(repo, id)];
  final outArg = command.option('out')!;
  await Directory(resolve(outArg)).create(recursive: true);
  for (final f in files) {
    for (final (name, bytes) in [
      ('${f.id}.gpx', f.gpx),
      ('${f.id}.expect.json', f.expect),
    ]) {
      await File('${resolve(outArg)}/$name').writeAsBytes(bytes, flush: true);
      out.writeln('wrote $outArg/$name (${bytes.length} bytes)');
    }
  }
  return kExitOk;
}

TraceFiles _generateOne(ProfileRepository repo, String id) {
  final (profile, route) = repo.load(id);
  return generateTrace(profile, route);
}

int _check(
  ArgResults command,
  IOSink out,
  IOSink err,
  String Function(String) resolve,
) {
  final repo = ProfileRepository(Directory(resolve(command.option('data')!)));
  final outArg = command.option('out')!;
  final dir = Directory(resolve(outArg));
  final problems = <String>[];
  final expected = <String>{};
  for (final id in repo.profileIds()) {
    final files = _generateOne(repo, id);
    for (final (name, bytes) in [
      ('$id.gpx', files.gpx),
      ('$id.expect.json', files.expect),
    ]) {
      expected.add(name);
      final f = File('${dir.path}/$name');
      if (!f.existsSync()) {
        problems.add('missing: $outArg/$name');
        continue;
      }
      final line = firstDifferentLine(f.readAsBytesSync(), bytes);
      if (line != null) {
        problems.add('differs: $outArg/$name (first difference at line $line)');
      }
    }
  }
  if (dir.existsSync()) {
    final extra = <String>[
      for (final e in dir.listSync())
        if (e is File) fileNameOf(e.path),
    ]..sort();
    for (final name in extra) {
      if ((name.endsWith('.gpx') || name.endsWith('.expect.json')) &&
          !expected.contains(name)) {
        problems.add('unexpected: $outArg/$name (no matching profile)');
      }
    }
  }
  if (problems.isEmpty) {
    out.writeln('ok: ${expected.length} fixture file(s) up to date');
    return kExitOk;
  }
  problems.forEach(err.writeln);
  err.writeln(
    'fixtures are out of date; run: dart run bin/tracegen.dart generate --all',
  );
  return kExitFailed;
}

int _validate(
  ArgResults command,
  ArgParser parser,
  IOSink out,
  IOSink err,
  String Function(String) resolve,
) {
  final dirArg = command.option('dir');
  final paths = <String>[];
  if (dirArg != null) {
    final dir = Directory(resolve(dirArg));
    if (!dir.existsSync()) {
      err.writeln('error: directory not found: $dirArg');
      return kExitUsage;
    }
    for (final e in dir.listSync()) {
      if (e is File) {
        final name = fileNameOf(e.path);
        if (name.endsWith('.gpx') || name.endsWith('.expect.json')) {
          paths.add('$dirArg/$name');
        }
      }
    }
  }
  paths.addAll(command.rest);
  if (paths.isEmpty) {
    err
      ..writeln('error: validate needs --dir <dir> or fixture files')
      ..writeln(_usage(parser));
    return kExitUsage;
  }

  // Group by id: <dir>/<id>.gpx + <dir>/<id>.expect.json.
  final pairs = <String, ({String? gpx, String? expect})>{};
  final errors = <String>[];
  for (final p in paths.toSet()) {
    final name = fileNameOf(p);
    final prefix = p.substring(0, p.length - name.length);
    if (name.endsWith('.expect.json')) {
      final key = prefix + name.substring(0, name.length - 12);
      pairs[key] = (gpx: pairs[key]?.gpx, expect: p);
    } else if (name.endsWith('.gpx')) {
      final key = prefix + name.substring(0, name.length - 4);
      pairs[key] = (gpx: p, expect: pairs[key]?.expect);
    } else {
      errors.add('$p: not a .gpx or .expect.json file');
    }
  }
  final keys = pairs.keys.toList()..sort();
  for (final key in keys) {
    final pair = pairs[key]!;
    final gpx = pair.gpx ?? '$key.gpx';
    final expect = pair.expect ?? '$key.expect.json';
    final gpxFile = File(resolve(gpx));
    final expectFile = File(resolve(expect));
    var missing = false;
    for (final (label, f) in [(gpx, gpxFile), (expect, expectFile)]) {
      if (!f.existsSync()) {
        errors.add('$label: file not found (fixtures come in pairs)');
        missing = true;
      }
    }
    if (missing) {
      continue;
    }
    errors.addAll(
      validatePair(
        gpxLabel: gpx,
        gpxBytes: gpxFile.readAsBytesSync(),
        expectLabel: expect,
        expectBytes: expectFile.readAsBytesSync(),
      ),
    );
  }
  if (errors.isEmpty) {
    out.writeln('ok: ${keys.length} fixture pair(s) valid');
    return kExitOk;
  }
  errors.forEach(err.writeln);
  err.writeln('${errors.length} error(s)');
  return kExitFailed;
}

/// 1-based number of the first line where [a] and [b] differ, or null when
/// they are byte-identical.
int? firstDifferentLine(List<int> a, List<int> b) {
  var line = 1;
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) {
      return line;
    }
    if (a[i] == 0x0A) {
      line++;
    }
  }
  return a.length == b.length ? null : line;
}
