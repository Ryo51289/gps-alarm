/// Command line interface (spec T24 §6). The only place with file IO besides
/// [BuildInputs.read] and [runFetch].
library;

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:stationgen/src/build.dart';
import 'package:stationgen/src/fetch.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/transport.dart';

const String _defaultData = '../../data/stations';
const String _defaultOut = '../../app/assets/stations.json';
const String _reportName = 'BUILD_REPORT.md';

ArgParser _buildParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
  ..addCommand(
    'fetch',
    ArgParser()
      ..addOption('endpoint', defaultsTo: kDefaultEndpoint)
      ..addOption('data', defaultsTo: _defaultData),
  )
  ..addCommand(
    'build',
    ArgParser()
      ..addOption('data', defaultsTo: _defaultData)
      ..addOption('out', defaultsTo: _defaultOut),
  )
  ..addCommand(
    'check',
    ArgParser()
      ..addOption('data', defaultsTo: _defaultData)
      ..addOption('out', defaultsTo: _defaultOut),
  );

String _usage(ArgParser parser) =>
    '''
Usage (run from tools/stationgen):
  dart run bin/stationgen.dart fetch [--endpoint <url>] [--data <dir>]   # network, run by hand
  dart run bin/stationgen.dart build [--data <dir>] [--out <file>]       # offline
  dart run bin/stationgen.dart check [--data <dir>] [--out <file>]       # offline (CI)

Defaults: --endpoint $kDefaultEndpoint, --data $_defaultData,
          --out $_defaultOut

${parser.usage}''';

/// Runs the CLI; returns the process exit code.
Future<int> runCli(
  List<String> args, {
  required IOSink out,
  required IOSink err,
  Directory? workingDirectory,
  Transport? transport,
  DateTime Function()? clock,
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
  if (command == null || command.rest.isNotEmpty) {
    err.writeln(_usage(parser));
    return kExitUsage;
  }

  final wd = workingDirectory ?? Directory.current;
  final pubspec = File('${wd.path}/pubspec.yaml');
  if (!pubspec.existsSync() ||
      !RegExp(
        r'^name:\s*stationgen\s*$',
        multiLine: true,
      ).hasMatch(pubspec.readAsStringSync())) {
    err.writeln(
      'error: run from tools/stationgen (no stationgen pubspec.yaml in '
      '${wd.path})',
    );
    return kExitUsage;
  }
  String resolve(String path) => _isAbsolute(path) ? path : '${wd.path}/$path';
  final data = Directory(resolve(command.option('data')!));

  switch (command.name) {
    case 'fetch':
      final endpoint = Uri.tryParse(command.option('endpoint')!);
      if (endpoint == null || !endpoint.isScheme('https')) {
        err.writeln('error: --endpoint must be an https URL');
        return kExitUsage;
      }
      return await runFetch(
        endpoint: endpoint,
        dataDir: data,
        transport: transport ?? httpTransport,
        out: out,
        err: err,
        clock: clock ?? DateTime.now,
      );
    case 'build':
    case 'check':
      return await _buildOrCheck(
        check: command.name == 'check',
        data: data,
        outArg: command.option('out')!,
        outPath: resolve(command.option('out')!),
        out: out,
        err: err,
      );
  }
  err.writeln(_usage(parser));
  return kExitUsage;
}

bool _isAbsolute(String path) =>
    path.startsWith('/') ||
    path.startsWith(r'\') ||
    RegExp('^[A-Za-z]:').hasMatch(path);

Future<int> _buildOrCheck({
  required bool check,
  required Directory data,
  required String outArg,
  required String outPath,
  required IOSink out,
  required IOSink err,
}) async {
  final BuildResult result;
  try {
    result = buildDataset(BuildInputs.read(data));
  } on StationgenException catch (e) {
    err.writeln('error: $e');
    return kExitData;
  }
  final counts = <String, int>{};
  for (final s in result.stations) {
    counts[s.kind.name] = (counts[s.kind.name] ?? 0) + 1;
  }
  out.writeln(
    'stations: ${result.stations.length} (train ${counts['train'] ?? 0}, '
    'coach ${counts['coach'] ?? 0}, bus ${counts['bus'] ?? 0}), '
    'dropped: ${result.droppedCount}',
  );
  for (final f in result.failures) {
    err.writeln('acceptance $f');
  }
  final reportPath = '${data.path}/$_reportName';
  final jsonBytes = utf8.encode(result.stationsJson);
  final reportBytes = utf8.encode(result.report);
  if (!check) {
    await File(reportPath).writeAsBytes(reportBytes, flush: true);
    out.writeln('wrote $_reportName');
    if (!result.accepted) {
      err.writeln('acceptance failed: $outArg not written (see $_reportName)');
      return kExitFailed;
    }
    final file = File(outPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(jsonBytes, flush: true);
    out.writeln('wrote $outArg (${jsonBytes.length} bytes); A1–A5 pass');
    return kExitOk;
  }
  final problems = <String>[];
  for (final (label, path, bytes) in [
    (outArg, outPath, jsonBytes),
    (_reportName, reportPath, reportBytes),
  ]) {
    final f = File(path);
    if (!f.existsSync()) {
      problems.add('missing: $label');
      continue;
    }
    final line = firstDifferentLine(f.readAsBytesSync(), bytes);
    if (line != null) {
      problems.add('differs: $label (first difference at line $line)');
    }
  }
  problems.forEach(err.writeln);
  if (problems.isNotEmpty) {
    err.writeln(
      'outputs are out of date; run: dart run bin/stationgen.dart build',
    );
  }
  if (problems.isNotEmpty || !result.accepted) {
    return kExitFailed;
  }
  out.writeln('ok: stations.json and $_reportName up to date; A1–A5 pass');
  return kExitOk;
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
