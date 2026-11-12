/// Acceptance thresholds B1–B4 of the bus stop dataset (spec T24.3 §4).
library;

import 'dart:convert';

import 'package:stationgen/src/acceptance.dart';
import 'package:stationgen/src/classify_bus.dart';
import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/model_bus.dart';
import 'package:stationgen/src/prefixes.dart';
import 'package:stationgen/src/provinces.dart';

/// B1: minimum stops per province.
const int kMinBusStopsPerProvince = 2000;

/// B3: maximum number of stops.
const int kMaxBusStops = 15000;

/// B3: 900 KB, counted as 900 000 bytes (the stricter reading, as T24 A5).
const int kMaxBusFileBytes = 900000;

/// B4: at most this many must-have entries.
const int kMaxBusMustHave = 10;

/// B2: name length limit, in characters (runes).
const int kMaxBusNameChars = 120;

/// One `bus_must_have.json` entry.
final class BusMustHave {
  const new({required this.match, required this.province});

  /// Folded tokens to find as a contiguous run in a core name (T24 §4.8).
  final String match;
  final String province;

  List<String> get matchTokens => foldTokens(match);

  @override
  String toString() => '"$match" ($province)';
}

/// Parses `bus_must_have.json` (`[{match, province}]`, at most
/// [kMaxBusMustHave] entries).
List<BusMustHave> parseBusMustHave(String source, ProvinceTable provinces) {
  Never bad(String m) => throw StationgenException(kErrMustHaveInvalid, m);
  final Object? json;
  try {
    json = jsonDecode(source);
  } on FormatException catch (e) {
    bad('bus_must_have.json is not valid JSON: ${e.message}');
  }
  if (json is! List<Object?>) {
    bad('bus_must_have.json must be an array');
  }
  if (json.length > kMaxBusMustHave) {
    bad('bus_must_have.json has more than $kMaxBusMustHave entries');
  }
  final out = <BusMustHave>[];
  for (final (i, row) in json.indexed) {
    if (row is! Map<String, Object?>) {
      bad('bus_must_have.json[$i] is not an object');
    }
    final match = row['match'];
    final province = row['province'];
    final unknown = row.keys.where((k) => k != 'match' && k != 'province');
    if (match is! String ||
        foldTokens(match).isEmpty ||
        province is! String ||
        !provinces.isProvince(province) ||
        unknown.isNotEmpty) {
      bad('bus_must_have.json[$i] needs only match and one of the provinces');
    }
    out.add(BusMustHave(match: match, province: province));
  }
  return out;
}

/// First stop (in the given order) satisfying [m], or null.
BusStop? findBusMustHave(BusMustHave m, List<BusStop> stops) {
  final needle = m.matchTokens;
  for (final s in stops) {
    if (s.province == m.province &&
        containsTokenRun(coreTokens(s.name), needle)) {
      return s;
    }
  }
  return null;
}

/// Checks B1–B4 on the final, sorted [stops] and the encoded file size.
/// [requiredProvinces] are the provinces of the queried areas; each needs
/// [kMinBusStopsPerProvince] stops (as does every province with stops).
List<AcceptanceFailure> checkBusAcceptance({
  required List<BusStop> stops,
  required int fileBytes,
  required List<BusMustHave> mustHave,
  required ProvinceTable provinces,
  required Iterable<String> requiredProvinces,
}) {
  final failures = <AcceptanceFailure>[];
  final perProvince = <String, int>{for (final p in requiredProvinces) p: 0};
  for (final s in stops) {
    perProvince[s.province] = (perProvince[s.province] ?? 0) + 1;
  }
  final low = [
    for (final p in provinces.names)
      if (perProvince.containsKey(p) &&
          perProvince[p]! < kMinBusStopsPerProvince)
        '$p: ${perProvince[p]}',
  ];
  if (low.isNotEmpty) {
    failures.add(
      AcceptanceFailure(
        'B1',
        'provinces with fewer than $kMinBusStopsPerProvince stops',
        low,
      ),
    );
  }
  final b2 = <String>[];
  final ids = <String>{};
  for (final s in stops) {
    if (!ids.add(s.id)) {
      b2.add('duplicate id ${s.id}');
    }
    final chars = s.name.runes.length;
    if (chars < 1 || chars > kMaxBusNameChars || foldVi(s.name).isEmpty) {
      b2.add('${s.id}: name has $chars characters');
    }
    if (!insideVnBbox(s.lat, s.lng)) {
      b2.add('${s.id}: coordinates outside Viet Nam');
    }
    if (!validRoutes(s.routes)) {
      b2.add('${s.id}: invalid routes "${s.routes.join(';')}"');
    }
    if (!provinces.isProvince(s.province)) {
      b2.add('${s.id}: unknown province "${s.province}"');
    }
  }
  if (b2.isNotEmpty) {
    failures.add(AcceptanceFailure('B2', 'invalid stops', b2));
  }
  if (stops.length > kMaxBusStops) {
    failures.add(
      AcceptanceFailure('B3', 'stops ${stops.length} > $kMaxBusStops'),
    );
  }
  if (fileBytes > kMaxBusFileBytes) {
    failures.add(
      AcceptanceFailure(
        'B3',
        'bus_stops.json $fileBytes B > $kMaxBusFileBytes B',
      ),
    );
  }
  final missing = [
    for (final m in mustHave)
      if (findBusMustHave(m, stops) == null) m.toString(),
  ];
  if (missing.isNotEmpty) {
    failures.add(AcceptanceFailure('B4', 'must-have entries missing', missing));
  }
  return failures;
}
