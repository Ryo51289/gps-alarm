/// `stationgen fetch`: the only command that uses the network (spec T24
/// §2.1, §2.3). One request, no retry.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/raw.dart';
import 'package:stationgen/src/transport.dart';
import 'package:stationgen/src/writer.dart';

/// Default Overpass instance.
const String kDefaultEndpoint = 'https://overpass-api.de/api/interpreter';

/// `User-Agent` sent to Overpass.
const String kUserAgent =
    'NapStop-stationgen/$kGeneratorVersion (+https://napstop.app)';

/// Request body: `data=<urlencoded query>`.
String overpassRequestBody(String query) =>
    'data=${Uri.encodeQueryComponent(query)}';

/// Snapshot family selected by `fetch --dataset` (spec T24.3 §5).
enum FetchDataset {
  /// Stations (T24): `query.overpassql` → `raw/overpass.json`.
  stations('stations', 'query.overpassql', 'overpass.json', 'fetch-meta.json'),

  /// Bus stops (T24.3): `bus_query.overpassql` → `raw/bus_overpass.json`.
  bus(
    'bus',
    'bus_query.overpassql',
    'bus_overpass.json',
    'bus_fetch-meta.json',
  );

  new(this.cliName, this.queryFile, this.rawFile, this.metaFile);

  /// Value of `--dataset`.
  final String cliName;

  /// Query file in the data directory.
  final String queryFile;

  /// Snapshot file in `raw/`.
  final String rawFile;

  /// Metadata file in `raw/`.
  final String metaFile;

  /// Parses a `--dataset` value; null for anything else.
  static FetchDataset? tryParse(String? s) {
    for (final d in values) {
      if (d.cliName == s) {
        return d;
      }
    }
    return null;
  }
}

/// Files written by a successful fetch.
final class FetchedSnapshot {
  const new({required this.raw, required this.meta, required this.snapshot});

  /// Response bytes, unchanged.
  final List<int> raw;
  final FetchMeta meta;
  final OverpassSnapshot snapshot;
}

/// Validates [response] (status, size, UTF-8, JSON, envelope, output
/// contract). Throws [FetchException] with a user facing message.
FetchedSnapshot validateFetchResponse({
  required TransportResponse response,
  required Uri endpoint,
  required String query,
  required DateTime fetchedAt,
}) {
  final bytes = response.bytes;
  if (response.status != 200) {
    final hint = switch (response.status) {
      429 => ' (rate limited: wait, or use another instance via --endpoint)',
      504 =>
        ' (server overloaded: wait, or use another instance via '
            '--endpoint)',
      _ => '',
    };
    final preview = utf8.decode(
      bytes.length > 300 ? bytes.sublist(0, 300) : bytes,
      allowMalformed: true,
    );
    throw FetchException('HTTP ${response.status}$hint\n$preview');
  }
  if (bytes.length > kMaxResponseBytes) {
    throw const FetchException(
      'response larger than $kMaxResponseBytes bytes; refusing to store it',
    );
  }
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException catch (e) {
    throw FetchException('response is not valid UTF-8: ${e.message}');
  }
  final OverpassSnapshot snapshot;
  try {
    snapshot = parseOverpass(text);
  } on StationgenException catch (e) {
    throw FetchException('invalid Overpass response: ${e.message}');
  }
  final meta = FetchMeta(
    fetchedAt: _isoSeconds(fetchedAt),
    endpoint: endpoint.toString(),
    osmBase: snapshot.osmBase,
    areasBase: snapshot.areasBase,
    bytes: bytes.length,
    query: query,
  );
  return FetchedSnapshot(raw: bytes, meta: meta, snapshot: snapshot);
}

String _isoSeconds(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

/// A fetch failure (exit 1).
final class FetchException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs `fetch`; returns the exit code.
Future<int> runFetch({
  required Uri endpoint,
  required Directory dataDir,
  required Transport transport,
  required IOSink out,
  required IOSink err,
  required DateTime Function() clock,
  FetchDataset dataset = FetchDataset.stations,
}) async {
  final queryFile = File('${dataDir.path}/${dataset.queryFile}');
  if (!queryFile.existsSync()) {
    err.writeln('error: ${queryFile.path} not found');
    return kExitData;
  }
  final query = normalizeLf(queryFile.readAsStringSync());
  final headers = {
    'User-Agent': kUserAgent,
    'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    'Accept': 'application/json',
  };
  out.writeln('POST $endpoint (one request, no retry; may take minutes)');
  final TransportResponse response;
  try {
    response = await transport(endpoint, headers, overpassRequestBody(query));
  } on Exception catch (e) {
    err.writeln('error: request failed: $e');
    return kExitFailed;
  }
  final FetchedSnapshot fetched;
  try {
    fetched = validateFetchResponse(
      response: response,
      endpoint: endpoint,
      query: query,
      fetchedAt: clock(),
    );
  } on FetchException catch (e) {
    err
      ..writeln('error: $e')
      ..writeln('nothing written; the previous snapshot is unchanged');
    return kExitFailed;
  }
  final rawDir = Directory('${dataDir.path}/raw');
  await rawDir.create(recursive: true);
  await File('${rawDir.path}/${dataset.rawFile}')
      .writeAsBytes(fetched.raw, flush: true);
  await File('${rawDir.path}/${dataset.metaFile}')
      .writeAsBytes(utf8.encode(fetched.meta.encode()), flush: true);
  final s = fetched.snapshot;
  out
    ..writeln('wrote raw/${dataset.rawFile} (${fetched.raw.length} bytes)')
    ..writeln('wrote raw/${dataset.metaFile}')
    ..writeln('osmBase: ${s.osmBase}, areasBase: ${s.areasBase}')
    ..writeln('elements: ${s.elements.length}, admin areas: ${s.groups.length}')
    ..writeln('next: dart run bin/stationgen.dart build');
  return 0;
}
