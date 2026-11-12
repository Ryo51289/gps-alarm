/// Decoder of `assets/stations.json` schema v1 (spec T24 §3, §7.4).
library;

import 'dart:convert';

import 'package:napstop/features/destination/domain/station.dart';

/// Schema version this app understands.
const int kStationsSchemaVersion = 1;

/// The station asset is missing, malformed or of an unknown schema.
final class StationDataException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'StationDataException: $message';
}

Never _fail(String message) => throw StationDataException(message);

String _string(Map<String, Object?> m, String key, String where) {
  final v = m[key];
  if (v is! String) {
    _fail('$where: "$key" must be a string');
  }
  return v;
}

double _double(Map<String, Object?> m, String key, String where) {
  final v = m[key];
  if (v is! num) {
    _fail('$where: "$key" must be a number');
  }
  return v.toDouble();
}

/// Kinds of `stations.json`; bus stops live in their own file (T24.3 D1).
const List<StationKind> _stationFileKinds = [
  StationKind.train,
  StationKind.coach,
  StationKind.bus,
];

StationKind _kind(Object? v, String where) {
  for (final k in _stationFileKinds) {
    if (k.name == v) {
      return k;
    }
  }
  _fail('$where: unknown kind "$v"');
}

/// Decodes the asset text. Unknown fields are ignored (forward compatible
/// within schema 1); anything else wrong throws [StationDataException].
StationDataset decodeStationsJson(String source) {
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException catch (e) {
    _fail('invalid JSON: ${e.message}');
  }
  if (json is! Map<String, Object?>) {
    _fail('top level is not an object');
  }
  final version = json['schemaVersion'];
  if (version != kStationsSchemaVersion) {
    _fail('unsupported schemaVersion $version');
  }
  final sourceBlock = json['source'];
  if (sourceBlock is! Map<String, Object?>) {
    _fail('"source" must be an object');
  }
  final list = json['stations'];
  if (list is! List<Object?>) {
    _fail('"stations" must be an array');
  }
  final stations = <Station>[];
  for (final (i, raw) in list.indexed) {
    final where = 'stations[$i]';
    if (raw is! Map<String, Object?>) {
      _fail('$where is not an object');
    }
    final aliases = raw['aliases'] ?? const <Object?>[];
    if (aliases is! List<Object?> || aliases.any((a) => a is! String)) {
      _fail('$where: "aliases" must be an array of strings');
    }
    stations.add(
      Station(
        id: _string(raw, 'id', where),
        name: _string(raw, 'name', where),
        nameAscii: _string(raw, 'nameAscii', where),
        kind: _kind(raw['kind'], where),
        province: _string(raw, 'province', where),
        lat: _double(raw, 'lat', where),
        lng: _double(raw, 'lng', where),
        aliases: List.unmodifiable(aliases.cast<String>()),
      ),
    );
  }
  return StationDataset(
    osmBase: _string(sourceBlock, 'osmBase', 'source'),
    attribution: _string(sourceBlock, 'attribution', 'source'),
    licenseUrl: _string(sourceBlock, 'licenseUrl', 'source'),
    stations: List.unmodifiable(stations),
  );
}
