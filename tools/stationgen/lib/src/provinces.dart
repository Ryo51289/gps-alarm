/// The 34 provinces after the 2025 merger and the matching of OSM admin
/// area names to them (spec T24 §4.4).
library;

import 'dart:convert';

import 'package:stationgen/src/fold.dart';
import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/prefixes.dart';

/// Number of provincial units after Resolution 202/2025/QH15.
const int kProvinceCount = 34;

/// Number of provincial units before the merger.
const int kFormerProvinceCount = 63;

const List<List<String>> _provincePrefixes = [
  ['thanh', 'pho'],
  ['tinh'],
  ['tp'],
];

/// Matching key: folded, without a leading `tinh` / `thanh pho` / `tp`,
/// without spaces.
String provinceKey(String s) {
  var t = foldTokens(s);
  for (final p in _provincePrefixes) {
    if (t.length > p.length && startsWithTokens(t, p)) {
      t = t.sublist(p.length);
      break;
    }
  }
  return t.join();
}

/// One row of `provinces.json`.
final class Province {
  const new({
    required this.name,
    required this.formerly,
    required this.aliases,
  });

  final String name;
  final List<String> formerly;
  final List<String> aliases;
}

/// Validated province table.
final class ProvinceTable {
  new _(this.provinces, this._byKey);

  /// Parses and validates `provinces.json`.
  factory parse(String source) {
    Never bad(String m) => throw StationgenException(kErrProvincesInvalid, m);
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      bad('provinces.json is not valid JSON: ${e.message}');
    }
    if (json is! List<Object?>) {
      bad('provinces.json must be an array');
    }
    final provinces = <Province>[];
    List<String> strings(Object? v, String where) {
      if (v is! List<Object?> || v.any((e) => e is! String || e.isEmpty)) {
        bad('$where must be an array of non-empty strings');
      }
      return v.cast<String>();
    }

    for (final (i, row) in json.indexed) {
      if (row is! Map<String, Object?> ||
          row['name'] is! String ||
          (row['name']! as String).isEmpty) {
        bad('provinces.json[$i] needs a non-empty "name"');
      }
      final name = row['name']! as String;
      provinces.add(
        Province(
          name: name,
          formerly: strings(row['formerly'], '$name.formerly'),
          aliases: strings(
            row['aliases'] ?? const <Object?>[],
            '$name.aliases',
          ),
        ),
      );
    }
    final names = provinces.map((p) => p.name).toSet();
    if (provinces.length != kProvinceCount || names.length != kProvinceCount) {
      bad('expected $kProvinceCount distinct provinces, got ${names.length}');
    }
    final formerKeys = <String>{};
    var formerCount = 0;
    for (final p in provinces) {
      for (final f in p.formerly) {
        formerCount++;
        if (!formerKeys.add(provinceKey(f))) {
          bad('former province "$f" is listed more than once');
        }
      }
    }
    if (formerCount != kFormerProvinceCount) {
      bad('expected $kFormerProvinceCount former provinces, got $formerCount');
    }
    final byKey = <String, String>{};
    for (final p in provinces) {
      for (final s in [p.name, ...p.formerly, ...p.aliases]) {
        final key = provinceKey(s);
        final existing = byKey[key];
        if (existing != null && existing != p.name) {
          bad('"$s" (key $key) maps to both $existing and ${p.name}');
        }
        byKey[key] = p.name;
      }
    }
    return ProvinceTable._(List.unmodifiable(provinces), byKey);
  }

  final List<Province> provinces;
  final Map<String, String> _byKey;

  /// Province display names, in file order.
  List<String> get names => [for (final p in provinces) p.name];

  bool isProvince(String name) => provinces.any((p) => p.name == name);

  /// New province for an admin area / province name, or null.
  String? resolve(String areaName) => _byKey[provinceKey(areaName)];
}
