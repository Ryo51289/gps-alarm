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
const String _busReportName = 'BUS_BUILD_REPORT.md';
const String _busFileName = 'bus_stops.json';

ArgParser _buildParser() => ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.')
  ..addCommand(
    'fetch',
    ArgParser()
      ..addOption('endpoint', defaultsTo: kDefaultEndpoint)
      ..addOption(
        'dataset',
        defaultsTo: FetchDataset.stations.cliName,
        allowed: [for (final d in FetchDataset.values) d.cliName],
      )
      ..addOption('data', defaultsTo: _defaultData),
  )
  ..addCommand(
    'build',
    ArgParser()
      ..addOption('data', defaultsTo: _defaultData)
      ..addOption('out', defaultsTo: _defaultOut)
      ..addOption('bus-out', help: 'Default: $_busFileName next to --out.'),
  )
  ..addCommand(
    'check',
    ArgParser()
      ..addOption('data', defaultsTo: _defaultData)
      ..addOption('out', defaultsTo: _defaultOut)
      ..addOption('bus-out', help: 'Default: $_busFileName next to --out.'),
  );

String _usage(ArgParser parser) =>
    '''
Usage (run from tools/stationgen):
  dart run bin/stationgen.dart fetch [--dataset stations|bus] [--endpoint <url>] [--data <dir>]
                                                                         # network, run by hand
  dart run bin/stationgen.dart build [--data <dir>] [--out <file>] [--bus-out <file>]  # offline
  dart run bin/stationgen.dart check [--data <dir>] [--out <file>] [--bus-out <file>]  # offline (CI)

Defaults: --endpoint $kDefaultEndpoint, --data $_defaultData,
          --out $_defaultOut, --bus-out $_busFileName next to --out

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
        dataset: FetchDataset.tryParse(command.option('dataset'))!,
      );
    case 'build':
    case 'check':
      final outArg = command.option('out')!;
      final busOutArg =
          command.option('bus-out') ?? _sibling(outArg, _busFileName);
      return await _buildOrCheck(
        check: command.name == 'check',
        data: data,
        outArg: outArg,
        outPath: resolve(outArg),
        busOutArg: busOutArg,
        busOutPath: resolve(busOutArg),
        out: out,
        err: err,
      );
  }
  err.writeln(_usage(parser));
  return kExitUsage;
}

/// [name] in the directory of [path] (either separator).
String _sibling(String path, String name) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? name : '${path.substring(0, i + 1)}$name';
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
  required String busOutArg,
  required String busOutPath,
  required IOSink out,
  required IOSink err,
}) async {
  final BuildResult result;
  final BusBuildResult bus;
  try {
    result = buildDataset(BuildInputs.read(data));
    bus = buildBusDataset(BusBuildInputs.read(data), result.stations);
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
  final perProvince = [
    for (final p in bus.provinces)
      '$p ${bus.stops.where((s) => s.province == p).length}',
  ];
  out.writeln(
    'bus stops: ${bus.stops.length} (${perProvince.join(', ')}), '
    'dropped: ${bus.droppedCount}',
  );
  for (final f in [...result.failures, ...bus.failures]) {
    err.writeln('acceptance $f');
  }
  final outputs = [
    (
      label: outArg,
      path: outPath,
      bytes: utf8.encode(result.stationsJson),
      accepted: result.accepted,
      report: _reportName,
      checks: 'A1–A5',
    ),
    (
      label: busOutArg,
      path: busOutPath,
      bytes: utf8.encode(bus.busStopsJson),
      accepted: bus.accepted,
      report: _busReportName,
      checks: 'B1–B4',
    ),
  ];
  final reports = [
    (_reportName, utf8.encode(result.report)),
    (_busReportName, utf8.encode(bus.report)),
  ];
  if (!check) {
    for (final (name, bytes) in reports) {
      await File('${data.path}/$name').writeAsBytes(bytes, flush: true);
      out.writeln('wrote $name');
    }
    var failed = false;
    for (final o in outputs) {
      if (!o.accepted) {
        err.writeln(
          'acceptance failed: ${o.label} not written (see ${o.report})',
        );
        failed = true;
        continue;
      }
      final file = File(o.path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(o.bytes, flush: true);
      out.writeln(
        'wrote ${o.label} (${o.bytes.length} bytes); ${o.checks} pass',
      );
    }
    return failed ? kExitFailed : kExitOk;
  }
  final problems = <String>[];
  for (final (label, path, bytes) in [
    for (final o in outputs) (o.label, o.path, o.bytes),
    for (final (name, bytes) in reports) (name, '${data.path}/$name', bytes),
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
  if (problems.isNotEmpty || !result.accepted || !bus.accepted) {
    return kExitFailed;
  }
  out.writeln(
    'ok: stations.json, $_busFileName, $_reportName and $_busReportName up '
    'to date; A1–A5 and B1–B4 pass',
  );
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
