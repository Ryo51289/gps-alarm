/// Decoder of `assets/bus_stops.json` schema v1 (spec T24.3 §3, §6.1).
library;

import 'dart:convert';

import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';

/// Schema version of the bus stop file this app understands.
const int kBusStopsSchemaVersion = 1;

/// Columns of a stop row: id, name, province index, lat, lng, routes.
const int _kRowLength = 6;

Never _fail(String message) => throw StationDataException(message);

String _string(Map<String, Object?> m, String key, String where) {
  final v = m[key];
  if (v is! String) {
    _fail('$where: "$key" must be a string');
  }
  return v;
}

/// App id of a stop: `osm:` + the file id (`n123` → `osm:n123`); a manual
/// entry (`man:<slug>`) keeps its id, as in `stations.json`.
String busStopId(String fileId) =>
    fileId.startsWith('man:') ? fileId : 'osm:$fileId';

/// Decodes the bus stop asset. Unknown top-level fields are ignored; a row
/// of the wrong length or type, a province index outside `provinces` or a
/// schema other than 1 throws [StationDataException].
StationDataset decodeBusStopsJson(String source) {
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
  if (version != kBusStopsSchemaVersion) {
    _fail('unsupported schemaVersion $version');
  }
  final sourceBlock = json['source'];
  if (sourceBlock is! Map<String, Object?>) {
    _fail('"source" must be an object');
  }
  final provinces = json['provinces'];
  if (provinces is! List<Object?> || provinces.any((p) => p is! String)) {
    _fail('"provinces" must be an array of strings');
  }
  final rows = json['stops'];
  if (rows is! List<Object?>) {
    _fail('"stops" must be an array');
  }
  final stops = <Station>[];
  for (final (i, row) in rows.indexed) {
    final where = 'stops[$i]';
    if (row is! List<Object?> || row.length != _kRowLength) {
      _fail('$where must be an array of $_kRowLength values');
    }
    final [id, name, province, lat, lng, routes] = row;
    if (id is! String || id.isEmpty || name is! String) {
      _fail('$where: id and name must be strings');
    }
    if (province is! int || province < 0 || province >= provinces.length) {
      _fail('$where: province index out of range');
    }
    if (lat is! num || lng is! num) {
      _fail('$where: lat and lng must be numbers');
    }
    if (routes is! String) {
      _fail('$where: routes must be a string');
    }
    stops.add(
      Station(
        id: busStopId(id),
        name: name,
        nameAscii: foldVi(name),
        kind: StationKind.busStop,
        province: provinces[province]! as String,
        lat: lat.toDouble(),
        lng: lng.toDouble(),
        routeRefs: routes.isEmpty
            ? const []
            : List.unmodifiable(routes.split(';')),
      ),
    );
  }
  return StationDataset(
    osmBase: _string(sourceBlock, 'osmBase', 'source'),
    attribution: _string(sourceBlock, 'attribution', 'source'),
    licenseUrl: _string(sourceBlock, 'licenseUrl', 'source'),
    stations: List.unmodifiable(stops),
  );
}
