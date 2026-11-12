/// Byte-exact writer of `app/assets/bus_stops.json` (spec T24.3 §3).
library;

import 'dart:convert';

import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/model_bus.dart';
import 'package:stationgen/src/writer.dart';

/// Schema version of `bus_stops.json` (independent of `stations.json`).
const int kBusSchemaVersion = 1;

String _s(String v) => jsonEncode(v);

/// Provinces of [stops] in the order of [provinceOrder] (the 34-province
/// table); the index of a province here is column 2 of a stop row.
List<String> busProvinces(List<BusStop> stops, List<String> provinceOrder) {
  final present = {for (final s in stops) s.province};
  return [
    for (final p in provinceOrder)
      if (present.contains(p)) p,
  ];
}

/// Sort order of the output: province index, folded name, id (code units).
List<BusStop> sortBusStops(List<BusStop> stops, List<String> provinces) {
  final index = {for (final (i, p) in provinces.indexed) p: i};
  int rank(BusStop s) => index[s.province] ?? provinces.length;
  return [...stops]..sort((a, b) {
    final p = rank(a).compareTo(rank(b));
    if (p != 0) {
      return p;
    }
    final n = foldVi(a.name).compareTo(foldVi(b.name));
    return n != 0 ? n : a.id.compareTo(b.id);
  });
}

/// One stop row: `[id, name, provinceIndex, lat, lng, "r1;r2"]`.
String encodeBusStopRow(BusStop s, int provinceIndex) =>
    '[${_s(s.id)},${_s(s.name)},$provinceIndex,${formatCoord(s.lat)},'
    '${formatCoord(s.lng)},${_s(s.routes.join(';'))}]';

/// Encodes [stops] (any order; sorted here). [provinceOrder] is the order
/// of the 34-province table.
String encodeBusStopsJson({
  required String osmBase,
  required List<BusStop> stops,
  required List<String> provinceOrder,
}) {
  final provinces = busProvinces(stops, provinceOrder);
  final sorted = sortBusStops(stops, provinces);
  final index = {for (final (i, p) in provinces.indexed) p: i};
  final counts = {for (final p in provinces) p: 0};
  for (final s in sorted) {
    counts[s.province] = counts[s.province]! + 1;
  }
  final b = StringBuffer()
    ..write('{\n')
    ..write('  "schemaVersion": $kBusSchemaVersion,\n')
    ..write(
      '  "generator": {"name": ${_s(kGeneratorName)}, '
      '"version": ${_s(kGeneratorVersion)}},\n',
    )
    ..write(
      '  "source": {"osmBase": ${_s(osmBase)}, '
      '"attribution": ${_s(kAttribution)}, "license": ${_s(kLicense)}, '
      '"licenseUrl": ${_s(kLicenseUrl)}, '
      '"copyrightUrl": ${_s(kCopyrightUrl)}},\n',
    )
    ..write('  "provinces": [${provinces.map(_s).join(', ')}],\n')
    ..write(
      '  "counts": {'
      '${provinces.map((p) => '${_s(p)}: ${counts[p]}').join(', ')}},\n',
    );
  if (sorted.isEmpty) {
    b.write('  "stops": []\n');
  } else {
    b.write('  "stops": [\n');
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      b
        ..write('    ')
        ..write(encodeBusStopRow(s, index[s.province]!))
        ..write(i + 1 < sorted.length ? ',\n' : '\n');
    }
    b.write('  ]\n');
  }
  b.write('}\n');
  return b.toString();
}
