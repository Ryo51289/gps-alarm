/// Catalog of the bundled simulation traces (T18 §7, §9), built by
/// `tracegen bundle-sim`. Parsing is pure; loading reads the asset.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

/// Asset of the catalog.
const String kSimCatalogAsset = 'assets/sim/catalog.json';

/// Catalog `schemaVersion` this app reads.
const int kSimCatalogSchemaVersion = 1;

/// Trace ids (fixtures/traces/README.md §1); the native side checks it too.
final RegExp _idPattern = RegExp(r'^[a-z0-9]+(_[a-z0-9]+)*$');

/// The bundled traces, in catalog order.
final class SimTraceCatalog {
  const new(this.traces);

  final List<SimTrace> traces;

  /// The trace with [id], or null.
  SimTrace? byId(String id) {
    for (final t in traces) {
      if (t.id == id) {
        return t;
      }
    }
    return null;
  }
}

/// Parses `catalog.json`. Throws [FormatException] naming the key only
/// (never a value): unsupported `schemaVersion`, missing key, wrong type,
/// unknown vehicle, duplicate id.
SimTraceCatalog parseSimTraceCatalog(String json) {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw const FormatException('sim catalog: invalid JSON');
  }
  if (root is! Map<String, Object?>) {
    throw const FormatException('sim catalog: not an object');
  }
  if (root['schemaVersion'] != kSimCatalogSchemaVersion) {
    throw const FormatException('sim catalog: schemaVersion unsupported');
  }
  final list = root['traces'];
  if (list is! List<Object?>) {
    throw const FormatException('sim catalog: traces');
  }
  final traces = <SimTrace>[];
  final ids = <String>{};
  for (final (i, raw) in list.indexed) {
    final t = _trace(raw, 'traces[$i]');
    if (!ids.add(t.id)) {
      throw FormatException('sim catalog: traces[$i].id duplicate');
    }
    traces.add(t);
  }
  return SimTraceCatalog(traces);
}

/// Loads and parses [kSimCatalogAsset] from [bundle].
Future<SimTraceCatalog> loadSimTraceCatalog(AssetBundle bundle) async =>
    parseSimTraceCatalog(await bundle.loadString(kSimCatalogAsset));

SimTrace _trace(Object? raw, String at) {
  if (raw is! Map<String, Object?>) {
    throw FormatException('sim catalog: $at');
  }
  T req<T>(Map<String, Object?> m, String key, String path) {
    final v = m[key];
    if (v is! T) {
      throw FormatException('sim catalog: $path.$key');
    }
    return v;
  }

  final dest = req<Map<String, Object?>>(raw, 'destination', at);
  final destAt = '$at.destination';
  final name = dest['name'];
  if (name != null && name is! String) {
    throw FormatException('sim catalog: $destAt.name');
  }
  final vehicleName = req<String>(raw, 'vehicle', at);
  final vehicle = VehicleKindMsg.values
      .where((v) => v.name == vehicleName && v != VehicleKindMsg.unknown)
      .firstOrNull;
  if (vehicle == null) {
    throw FormatException('sim catalog: $at.vehicle');
  }
  final id = req<String>(raw, 'id', at);
  if (!_idPattern.hasMatch(id) || id.length > 64) {
    throw FormatException('sim catalog: $at.id');
  }
  if (req<String>(raw, 'gpx', at) != '$id.gpx') {
    throw FormatException('sim catalog: $at.gpx');
  }
  return SimTrace(
    id: id,
    vehicle: vehicle,
    sampleIntervalS: req<int>(raw, 'sampleIntervalS', at),
    durationS: req<int>(raw, 'durationS', at),
    arrivalT: req<int>(raw, 'arrivalT', at),
    destination: SimDestination(
      id: req<String>(dest, 'id', destAt),
      name: name as String?,
      lat: req<num>(dest, 'lat', destAt).toDouble(),
      lng: req<num>(dest, 'lng', destAt).toDouble(),
    ),
  );
}
