/// Parsing of the committed Overpass snapshot and its metadata
/// (spec T24 §2.2 output contract, §2.3).
library;

import 'dart:convert';

import 'package:stationgen/src/model.dart';

/// One admin area of part B with the elements it contains.
final class AreaGroup {
  const new({required this.areaId, required this.tags, required this.refs});

  final int areaId;
  final Map<String, String> tags;

  /// Element refs (`n1`, `w2`, ...) inside the area.
  final List<String> refs;

  /// `name:vi` ?? `name` ?? `area <id>`.
  String get displayName => tags['name:vi'] ?? tags['name'] ?? 'area $areaId';
}

/// Parsed Overpass response.
final class OverpassSnapshot {
  const new({
    required this.osmBase,
    required this.areasBase,
    required this.elements,
    required this.groups,
  });

  final String osmBase;
  final String? areasBase;

  /// Part A, in file order.
  final List<OsmElement> elements;

  /// Part B, in file order.
  final List<AreaGroup> groups;
}

Never _invalid(String message) =>
    throw StationgenException(kErrRawInvalid, message);

Object? _decode(String source, String what) {
  try {
    return jsonDecode(source);
  } on FormatException catch (e) {
    _invalid('$what is not valid JSON: ${e.message}');
  }
}

Map<String, String> _tags(Object? raw, String where) {
  if (raw == null) {
    return const {};
  }
  if (raw is! Map<String, Object?>) {
    _invalid('$where: tags is not an object');
  }
  return {
    for (final e in raw.entries)
      e.key: e.value is String ? e.value! as String : _invalid('$where: tag'),
  };
}

double? _num(Object? v) => v is num ? v.toDouble() : null;

/// Validates the response envelope: `osm3s.timestamp_osm_base` present, no
/// `remark`. Returns the decoded object. Used by `fetch` and `build`.
Map<String, Object?> checkOverpassEnvelope(Object? json) {
  if (json is! Map<String, Object?>) {
    _invalid('response is not a JSON object');
  }
  final remark = json['remark'];
  if (remark != null) {
    _invalid('Overpass remark: $remark');
  }
  final osm3s = json['osm3s'];
  if (osm3s is! Map<String, Object?> ||
      osm3s['timestamp_osm_base'] is! String) {
    _invalid('missing osm3s.timestamp_osm_base');
  }
  if (json['elements'] is! List<Object?>) {
    _invalid('missing elements array');
  }
  return json;
}

/// Parses the raw Overpass JSON according to the output contract.
OverpassSnapshot parseOverpass(String source) {
  final json = checkOverpassEnvelope(_decode(source, 'raw/overpass.json'));
  final osm3s = json['osm3s']! as Map<String, Object?>;
  final elements = <OsmElement>[];
  final groups = <AreaGroup>[];
  final known = <String>{};
  int? areaId;
  Map<String, String>? areaTags;
  var refs = <String>[];

  void closeGroup() {
    if (areaId != null) {
      groups.add(AreaGroup(areaId: areaId, tags: areaTags!, refs: refs));
    }
  }

  for (final (i, raw) in (json['elements']! as List<Object?>).indexed) {
    if (raw is! Map<String, Object?>) {
      _invalid('elements[$i] is not an object');
    }
    final typeName = raw['type'];
    final id = raw['id'];
    if (id is! int) {
      _invalid('elements[$i] has no integer id');
    }
    if (typeName == 'area') {
      closeGroup();
      areaId = id;
      areaTags = _tags(raw['tags'], 'area $id');
      refs = <String>[];
      continue;
    }
    final type = OsmType.fromJson(typeName is String ? typeName : null);
    if (type == null) {
      _invalid('elements[$i] has unknown type "$typeName"');
    }
    final ref = '${type.letter}$id';
    if (areaId == null) {
      // Part A.
      if (!known.add(ref)) {
        _invalid('element $ref appears twice in part A');
      }
      final center = raw['center'];
      final (lat, lon) = type == OsmType.node
          ? (_num(raw['lat']), _num(raw['lon']))
          : center is Map<String, Object?>
          ? (_num(center['lat']), _num(center['lon']))
          : (null, null);
      elements.add(
        OsmElement(
          type: type,
          id: id,
          tags: _tags(raw['tags'], ref),
          lat: lat,
          lon: lon,
        ),
      );
    } else {
      // Part B: ids only.
      if (raw.containsKey('tags')) {
        _invalid('element $ref with tags after the first area (part B)');
      }
      if (!known.contains(ref)) {
        _invalid('area $areaId lists $ref which is not in part A');
      }
      refs.add(ref);
    }
  }
  closeGroup();
  return OverpassSnapshot(
    osmBase: osm3s['timestamp_osm_base']! as String,
    areasBase: osm3s['timestamp_areas_base'] as String?,
    elements: elements,
    groups: groups,
  );
}

/// `raw/fetch-meta.json`.
final class FetchMeta {
  const new({
    required this.fetchedAt,
    required this.endpoint,
    required this.osmBase,
    required this.areasBase,
    required this.bytes,
    required this.query,
  });

  final String fetchedAt;
  final String endpoint;
  final String osmBase;
  final String? areasBase;
  final int bytes;
  final String query;

  Map<String, Object?> toJson() => {
    'fetchedAt': fetchedAt,
    'endpoint': endpoint,
    'osmBase': osmBase,
    'areasBase': areasBase,
    'bytes': bytes,
    'query': query,
  };

  /// Pretty JSON, 2 spaces, LF, trailing newline.
  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';
}

FetchMeta parseFetchMeta(String source) {
  final json = _decode(source, 'raw/fetch-meta.json');
  if (json is! Map<String, Object?> ||
      json['fetchedAt'] is! String ||
      json['endpoint'] is! String ||
      json['osmBase'] is! String ||
      json['bytes'] is! int ||
      json['query'] is! String ||
      (json['areasBase'] != null && json['areasBase'] is! String)) {
    _invalid('raw/fetch-meta.json does not match the expected shape');
  }
  return FetchMeta(
    fetchedAt: json['fetchedAt']! as String,
    endpoint: json['endpoint']! as String,
    osmBase: json['osmBase']! as String,
    areasBase: json['areasBase'] as String?,
    bytes: json['bytes']! as int,
    query: json['query']! as String,
  );
}

/// CRLF / CR → LF.
String normalizeLf(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
