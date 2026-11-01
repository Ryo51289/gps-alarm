// TC07: parsing of the Overpass snapshot and fetch-meta.json.
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Matcher rawInvalid() => throwsA(
  isA<StationgenException>().having((e) => e.code, 'code', kErrRawInvalid),
);

void main() {
  final small = File('${packageDir.path}/test/data/overpass_small.json')
      .readAsStringSync();

  test('parses part A and part B', () {
    final s = parseOverpass(small);
    expect(s.osmBase, '2026-11-01T00:00:00Z');
    expect(s.areasBase, '2026-10-31T23:00:00Z');
    expect(s.elements.map((e) => e.ref), ['n1', 'w2', 'r3']);
    expect(s.elements[0].lat, 17.46892);
    expect(s.elements[1].lon, 105.77752, reason: 'way uses center');
    expect(s.elements[2].lat, 16.8167, reason: 'relation uses center');
    expect(s.elements[0].tags['name'], 'Đồng Hới');
    expect(s.elements[0].stationId, 'osm:n1');
    expect(s.groups.map((g) => g.displayName), [
      'Tỉnh Quảng Bình',
      'Hà Nội',
      'Tỉnh Quảng Trị',
    ]);
    expect(s.groups.map((g) => g.refs), [
      ['n1'],
      ['w2'],
      ['r3'],
    ]);
  });

  Map<String, Object?> decoded() => jsonDecode(small) as Map<String, Object?>;

  test('id in part B missing from part A', () {
    final j = decoded();
    (j['elements']! as List<Object?>).add({'type': 'node', 'id': 99});
    expect(() => parseOverpass(jsonEncode(j)), rawInvalid());
  });

  test('remark (Overpass runtime error)', () {
    final j = decoded()..['remark'] = 'runtime error: Query timed out';
    expect(() => parseOverpass(jsonEncode(j)), rawInvalid());
  });

  test('missing osm3s', () {
    final j = decoded()..remove('osm3s');
    expect(() => parseOverpass(jsonEncode(j)), rawInvalid());
  });

  test('not JSON', () {
    expect(() => parseOverpass('<html>busy</html>'), rawInvalid());
  });

  test('element with tags in part B', () {
    final j = decoded();
    (j['elements']! as List<Object?>).add({
      'type': 'node',
      'id': 1,
      'tags': {'name': 'x'},
    });
    expect(() => parseOverpass(jsonEncode(j)), rawInvalid());
  });

  test('fetch-meta round trip', () {
    final meta = parseFetchMeta(fetchMetaJson());
    expect(meta.query, kTestQuery);
    expect(meta.osmBase, kTestOsmBase);
    expect(meta.encode(), fetchMetaJson());
    expect(() => parseFetchMeta('{}'), rawInvalid());
  });

  test('normalizeLf', () {
    expect(normalizeLf('a\r\nb\rc\n'), 'a\nb\nc\n');
  });
}
