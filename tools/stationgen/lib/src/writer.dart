/// Byte-exact writer of `app/assets/stations.json` (spec T24 §3).
library;

import 'dart:convert';

import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/prefixes.dart';

const String kGeneratorName = 'stationgen';

/// Bump together with `version` in pubspec.yaml when the output changes.
const String kGeneratorVersion = '1.1.0';

const int kSchemaVersion = 1;
const String kAttribution = '© OpenStreetMap contributors';
const String kLicense = 'ODbL-1.0';
const String kLicenseUrl = 'https://opendatacommons.org/licenses/odbl/1-0/';
const String kCopyrightUrl = 'https://www.openstreetmap.org/copyright';

/// Fixed 5-decimal coordinate text.
String formatCoord(double v) => v.toStringAsFixed(5);

/// Sort key comparison: kind, nameAscii, id (code unit order).
int compareStations(Candidate a, Candidate b) {
  final k = a.kind.index.compareTo(b.kind.index);
  if (k != 0) {
    return k;
  }
  final n = foldVi(a.name).compareTo(foldVi(b.name));
  if (n != 0) {
    return n;
  }
  return a.id.compareTo(b.id);
}

String _s(String v) => jsonEncode(v);

/// One station line (compact object, key order of §3).
String encodeStationLine(Candidate c) {
  final aliases = c.aliases.map(_s).join(',');
  return '{"id":${_s(c.id)},"name":${_s(c.name)},'
      '"nameAscii":${_s(foldVi(c.name))},"kind":${_s(c.kind.name)},'
      '"province":${_s(c.province)},"lat":${formatCoord(c.lat)},'
      '"lng":${formatCoord(c.lng)},"aliases":[$aliases]}';
}

/// Encodes [stations] (any order; sorted here) with [osmBase].
String encodeStationsJson({
  required String osmBase,
  required List<Candidate> stations,
}) {
  final sorted = [...stations]..sort(compareStations);
  final counts = {for (final k in StationKind.values) k: 0};
  for (final s in sorted) {
    counts[s.kind] = counts[s.kind]! + 1;
  }
  final b = StringBuffer()
    ..write('{\n')
    ..write('  "schemaVersion": $kSchemaVersion,\n')
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
    ..write(
      '  "counts": {"train": ${counts[StationKind.train]}, '
      '"coach": ${counts[StationKind.coach]}, '
      '"bus": ${counts[StationKind.bus]}},\n',
    );
  if (sorted.isEmpty) {
    b.write('  "stations": []\n');
  } else {
    b.write('  "stations": [\n');
    for (var i = 0; i < sorted.length; i++) {
      b
        ..write('    ')
        ..write(encodeStationLine(sorted[i]))
        ..write(i + 1 < sorted.length ? ',\n' : '\n');
    }
    b.write('  ]\n');
  }
  b.write('}\n');
  return b.toString();
}
