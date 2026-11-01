/// Manual corrections (`data/stations/overrides.json`, spec T24 §4.6).
library;

import 'dart:convert';

import 'package:stationgen/src/model.dart';
import 'package:stationgen/src/names.dart';
import 'package:stationgen/src/prefixes.dart';
import 'package:stationgen/src/provinces.dart';

final RegExp _osmRef = RegExp(r'^[nwr][1-9][0-9]*$');
final RegExp _manualId = RegExp(r'^man:[a-z0-9]+(-[a-z0-9]+)*$');
final RegExp _source = RegExp(
  r'^(survey|osm:(node|way|relation)/[1-9][0-9]*@\d{4}-\d{2}-\d{2}'
  r'|odbl:https?://\S+|public-domain:https?://\S+)$',
);
const List<String> _forbiddenSource = ['google', 'goo.gl', 'maps.app'];

/// `drop` entry.
final class OverrideDrop {
  const new({required this.osm, required this.reason, required this.source});

  final String osm;
  final String reason;
  final String source;
}

/// `patch` entry. Null fields are not changed.
final class OverridePatch {
  const new({
    required this.osm,
    required this.reason,
    required this.source,
    this.name,
    this.kind,
    this.province,
    this.lat,
    this.lng,
    this.aliasesAdd = const [],
  });

  final String osm;
  final String reason;
  final String source;
  final String? name;
  final StationKind? kind;
  final String? province;
  final double? lat;
  final double? lng;
  final List<String> aliasesAdd;

  /// Applies the patch to [c] in place.
  void applyTo(Candidate c) {
    if (name != null) {
      c.name = name!;
    }
    if (kind != null) {
      c.kind = kind!;
    }
    if (province != null) {
      c.province = province!;
    }
    if (lat != null) {
      c.lat = lat!;
    }
    if (lng != null) {
      c.lng = lng!;
    }
    // Re-filter the existing aliases too: a patched name may equal one of
    // them (e.g. the OSM `name` kept as alias when `name:vi` was used).
    c.aliases = mergeAliasValues(c.name, const [], [
      ...c.aliases,
      ...aliasesAdd,
    ]);
  }
}

/// `add` entry (manual station, id `man:<slug>`).
final class OverrideAdd {
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.province,
    required this.lat,
    required this.lng,
    required this.aliases,
    required this.reason,
    required this.source,
  });

  final String id;
  final String name;
  final StationKind kind;
  final String province;
  final double lat;
  final double lng;
  final List<String> aliases;
  final String reason;
  final String source;

  Candidate toCandidate() => Candidate(
    id: id,
    name: collapseSpaces(name),
    kind: kind,
    province: province,
    lat: lat,
    lng: lng,
    aliases: mergeAliasValues(collapseSpaces(name), const [], aliases),
    primary: false,
    typeRank: 3,
    osmId: 0,
  );
}

/// Parsed and validated overrides.
final class Overrides {
  const new({this.drop = const [], this.patch = const [], this.add = const []});

  /// Parses `overrides.json`; [provinces] validates province names.
  factory parse(String source, ProvinceTable provinces) {
    Never bad(String m) => throw StationgenException(kErrOverrideInvalid, m);
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      bad('overrides.json is not valid JSON: ${e.message}');
    }
    if (json is! Map<String, Object?> || json['schemaVersion'] != 1) {
      bad('overrides.json must be an object with "schemaVersion": 1');
    }
    final root = json;
    List<Map<String, Object?>> list(String key) {
      final v = root[key] ?? const <Object?>[];
      if (v is! List<Object?> || v.any((e) => e is! Map<String, Object?>)) {
        bad('"$key" must be an array of objects');
      }
      return v.cast<Map<String, Object?>>();
    }

    String text(Map<String, Object?> m, String key, String where) {
      final v = m[key];
      if (v is! String || v.trim().isEmpty) {
        bad('$where: "$key" is required');
      }
      return v;
    }

    String src(Map<String, Object?> m, String where) {
      final s = text(m, 'source', where);
      final lower = s.toLowerCase();
      if (_forbiddenSource.any(lower.contains)) {
        bad(
          '$where: source "$s" is not allowed (Google / proprietary maps '
          'cannot be used, spec §4.6)',
        );
      }
      if (!_source.hasMatch(s)) {
        bad(
          '$where: source "$s" must be survey, osm:<type>/<id>@<date>, '
          'odbl:<url> or public-domain:<url>',
        );
      }
      return s;
    }

    String osm(Map<String, Object?> m, String where) {
      final v = text(m, 'osm', where);
      if (!_osmRef.hasMatch(v)) {
        bad('$where: "osm" must look like n123 / w123 / r123');
      }
      return v;
    }

    String province(Object? v, String where) {
      if (v is! String || !provinces.isProvince(v)) {
        bad('$where: province "$v" is not one of the 34 provinces');
      }
      return v;
    }

    double coord(Object? v, String where, {required bool lat}) {
      if (v is! num) {
        bad('$where: ${lat ? 'lat' : 'lng'} must be a number');
      }
      final d = v.toDouble();
      final ok = lat
          ? d >= kMinLat && d <= kMaxLat
          : d >= kMinLng && d <= kMaxLng;
      if (!ok) {
        bad('$where: ${lat ? 'lat' : 'lng'} $d is outside Viet Nam');
      }
      return d;
    }

    StationKind kind(Object? v, String where) {
      final k = v is String ? StationKind.tryParse(v) : null;
      if (k == null) {
        bad('$where: kind must be train, coach or bus');
      }
      return k;
    }

    List<String> strings(Object? v, String where) {
      if (v == null) {
        return const [];
      }
      if (v is! List<Object?> || v.any((e) => e is! String)) {
        bad('$where must be an array of strings');
      }
      return v.cast<String>();
    }

    final refs = <String>{};
    final drops = <OverrideDrop>[];
    for (final (i, m) in list('drop').indexed) {
      final where = 'drop[$i]';
      final ref = osm(m, where);
      if (!refs.add(ref)) {
        bad('$where: $ref has more than one drop/patch entry');
      }
      drops.add(
        OverrideDrop(
          osm: ref,
          reason: text(m, 'reason', where),
          source: src(m, where),
        ),
      );
    }
    final patches = <OverridePatch>[];
    for (final (i, m) in list('patch').indexed) {
      final where = 'patch[$i]';
      final ref = osm(m, where);
      if (!refs.add(ref)) {
        bad('$where: $ref has more than one drop/patch entry');
      }
      final set = m['set'] ?? const <String, Object?>{};
      if (set is! Map<String, Object?>) {
        bad('$where: "set" must be an object');
      }
      const allowed = {'name', 'kind', 'province', 'lat', 'lng'};
      final unknown = set.keys.where((k) => !allowed.contains(k)).toList();
      if (unknown.isNotEmpty) {
        bad('$where: unknown "set" keys ${unknown.join(', ')}');
      }
      final name = set['name'];
      if (name != null && (name is! String || name.trim().isEmpty)) {
        bad('$where: set.name must be a non-empty string');
      }
      patches.add(
        OverridePatch(
          osm: ref,
          reason: text(m, 'reason', where),
          source: src(m, where),
          name: name == null ? null : collapseSpaces(name as String),
          kind: set.containsKey('kind') ? kind(set['kind'], where) : null,
          province: set.containsKey('province')
              ? province(set['province'], where)
              : null,
          lat: set.containsKey('lat')
              ? coord(set['lat'], where, lat: true)
              : null,
          lng: set.containsKey('lng')
              ? coord(set['lng'], where, lat: false)
              : null,
          aliasesAdd: strings(m['aliasesAdd'], '$where.aliasesAdd'),
        ),
      );
    }
    final ids = <String>{};
    final adds = <OverrideAdd>[];
    for (final (i, m) in list('add').indexed) {
      final where = 'add[$i]';
      final id = text(m, 'id', where);
      if (!_manualId.hasMatch(id)) {
        bad('$where: id must match man:<slug> (a-z, 0-9, -)');
      }
      if (!ids.add(id)) {
        bad('$where: duplicate id $id');
      }
      final aliases = strings(m['aliases'], '$where.aliases');
      adds.add(
        OverrideAdd(
          id: id,
          name: text(m, 'name', where),
          kind: kind(m['kind'], where),
          province: province(m['province'], where),
          lat: coord(m['lat'], where, lat: true),
          lng: coord(m['lng'], where, lat: false),
          aliases: aliases,
          reason: text(m, 'reason', where),
          source: src(m, where),
        ),
      );
    }
    return Overrides(drop: drops, patch: patches, add: adds);
  }

  final List<OverrideDrop> drop;
  final List<OverridePatch> patch;
  final List<OverrideAdd> add;

  OverrideDrop? dropFor(String ref) {
    for (final d in drop) {
      if (d.osm == ref) {
        return d;
      }
    }
    return null;
  }

  OverridePatch? patchFor(String ref) {
    for (final p in patch) {
      if (p.osm == ref) {
        return p;
      }
    }
    return null;
  }

  /// Every OSM ref of drop + patch.
  Iterable<String> get osmRefs => [
    for (final d in drop) d.osm,
    for (final p in patch) p.osm,
  ];

  bool get isEmpty => drop.isEmpty && patch.isEmpty && add.isEmpty;
}
