/// Simulation traces bundled with the app (spec T18 §7): byte copies of a
/// few fixture GPX files plus `catalog.json`, built from the fixtures and
/// their `expect.json`. Pure: the CLI does the file IO.
library;

import 'dart:convert';

import 'package:tracegen/src/profile.dart';

/// `schemaVersion` of `catalog.json` (independent of the fixture schema).
const int kSimCatalogSchemaVersion = 1;

/// Name of the catalog file in the bundle directory.
const String kSimCatalogFile = 'catalog.json';

/// File listing the bundled trace ids, relative to the data directory.
const String kSimBundleListFile = 'sim_bundle.json';

/// Ids of `sim_bundle.json` (`{"ids": [...]}`), in file order; throws
/// [ProfileException].
List<String> parseSimBundleIds(String text) {
  const file = kSimBundleListFile;
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const ProfileException(file, 'invalid JSON');
  }
  final ids = json is Map<String, Object?> ? json['ids'] : null;
  if (ids is! List<Object?> || ids.isEmpty) {
    throw const ProfileException('$file: ids', 'must be a non-empty list');
  }
  final out = <String>[];
  for (final (i, id) in ids.indexed) {
    if (id is! String || !kIdPattern.hasMatch(id)) {
      throw ProfileException('$file: ids[$i]', 'must be a trace id');
    }
    if (out.contains(id)) {
      throw ProfileException('$file: ids[$i]', 'duplicate "$id"');
    }
    out.add(id);
  }
  return out;
}

/// The bundle: file name → bytes, `<id>.gpx` in [ids] order then
/// `catalog.json`. [readFixture] returns the bytes of a fixture file by name,
/// or null when it does not exist; throws [ProfileException] naming the file.
Map<String, List<int>> buildSimBundle(
  List<String> ids,
  List<int>? Function(String name) readFixture,
) {
  final files = <String, List<int>>{};
  final traces = <Map<String, Object?>>[];
  for (final id in ids) {
    final gpxName = '$id.gpx';
    final expectName = '$id.expect.json';
    final gpx = readFixture(gpxName);
    if (gpx == null) {
      throw ProfileException(gpxName, 'fixture not found');
    }
    final expect = readFixture(expectName);
    if (expect == null) {
      throw ProfileException(expectName, 'fixture not found');
    }
    files[gpxName] = gpx;
    traces.add(_catalogEntry(id, expectName, utf8.decode(expect)));
  }
  final catalog = <String, Object?>{
    'schemaVersion': kSimCatalogSchemaVersion,
    'traces': traces,
  };
  files[kSimCatalogFile] = utf8.encode(
    '${const JsonEncoder.withIndent('  ').convert(catalog)}\n',
  );
  return files;
}

Map<String, Object?> _catalogEntry(String id, String file, String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw ProfileException(file, 'invalid JSON');
  }
  Object? at(Object? node, List<String> keys) {
    var cur = node;
    for (final k in keys) {
      cur = cur is Map<String, Object?> ? cur[k] : null;
    }
    return cur;
  }

  T req<T>(List<String> keys) {
    final v = at(json, keys);
    if (v is! T) {
      throw ProfileException('$file: ${keys.join('.')}', 'missing or invalid');
    }
    return v;
  }

  if (req<String>(['trace', 'id']) != id) {
    throw ProfileException('$file: trace.id', 'must be "$id"');
  }
  final gpx = req<String>(['trace', 'gpx']);
  if (gpx != '$id.gpx') {
    throw ProfileException('$file: trace.gpx', 'must be "$id.gpx"');
  }
  final name = at(json, ['destination', 'name']);
  return {
    'id': id,
    'gpx': gpx,
    'vehicle': req<String>(['trace', 'vehicle']),
    'sampleIntervalS': req<int>(['trace', 'sampleIntervalS']),
    'durationS': req<int>(['trace', 'durationS']),
    'arrivalT': req<int>(['truth', 'arrivalT']),
    'destination': {
      'id': req<String>(['destination', 'id']),
      if (name is String) 'name': name,
      'lat': req<num>(['destination', 'lat']),
      'lng': req<num>(['destination', 'lng']),
    },
  };
}
