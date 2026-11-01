// TC08 (provinces in build), TC11 (overrides), TC16 (query changed).
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Matcher fails(String code) =>
    throwsA(isA<StationgenException>().having((e) => e.code, 'code', code));

Candidate byId(BuildResult r, String id) =>
    r.stations.firstWhere((s) => s.id == id);

void main() {
  group('province assignment (TC08)', () {
    final a = node(1, 17.4, 106.6, {'railway': 'station', 'name': 'Đồng Hới'});
    final b = node(2, 21, 105.8, {
      'amenity': 'bus_station',
      'name': 'Bến xe Ranh Giới',
    });

    test('element in no area', () {
      final raw = overpassJson(
        [a, b],
        groups: [
          ('Tỉnh Quảng Bình', [a]),
        ],
      );
      expect(
        () => buildDataset(synthInputs(raw: raw)),
        throwsA(
          isA<StationgenException>()
              .having((e) => e.code, 'code', kErrProvinceUnresolved)
              .having((e) => e.message, 'message', contains('osm:n2')),
        ),
      );
    });

    test('two areas of the same new province, and an ambiguity', () {
      final raw = overpassJson(
        [a, b],
        groups: [
          ('Tỉnh Quảng Bình', [a]),
          ('Tỉnh Quảng Trị', [a]),
          ('Tỉnh Hưng Yên', [b]),
          ('Thành phố Hà Nội', [b]),
          ('Xiengkhouang', [b]),
        ],
      );
      final r = buildDataset(synthInputs(raw: raw));
      expect(byId(r, 'osm:n1').province, 'Quảng Trị');
      expect(byId(r, 'osm:n1').name, 'Ga Đồng Hới');
      expect(byId(r, 'osm:n2').province, 'Hà Nội', reason: 'smallest key');
      final amb = r.report.split('## 8.')[1].split('## 9.')[0];
      expect(amb, contains('`osm:n2`'));
      expect(amb, isNot(contains('`osm:n1`')));
      final unmatched = r.report.split('## 9.')[1].split('## 10.')[0];
      expect(unmatched, contains('Xiengkhouang (1 elements)'));
    });
  });

  group('overrides (TC11)', () {
    final metro = node(10, 21.03, 105.80, {
      'railway': 'station',
      'station': 'subway',
      'name': 'Cát Linh',
    });
    final unnamed = node(11, 21.04, 105.81, {'amenity': 'bus_station'});
    final dropMe = node(12, 21.05, 105.82, {
      'amenity': 'bus_station',
      'name': 'Bến xe Cũ',
    });
    final patchMe = way(13, 21.06, 105.83, {
      'amenity': 'bus_station',
      'name': 'Ben xe Sai Ten',
    });
    final elements = [metro, unnamed, dropMe, patchMe];
    final raw = overpassJson(
      elements,
      groups: [('Thành phố Hà Nội', elements)],
    );

    String ov({
      List<Object?> drop = const [],
      List<Object?> patch = const [],
      List<Object?> add = const [],
    }) => jsonEncode({
      'schemaVersion': 1,
      'drop': drop,
      'patch': patch,
      'add': add,
    });

    test('drop, patch, add and resurrecting a NO_NAME element', () {
      final r = buildDataset(
        synthInputs(
          raw: raw,
          overrides: ov(
            drop: [
              {'osm': 'n12', 'reason': 'closed', 'source': 'survey'},
            ],
            patch: [
              {
                'osm': 'w13',
                'set': {'name': 'Bến xe Sửa Tên', 'province': 'Hưng Yên'},
                'aliasesAdd': ['Bến xe Tên Cũ'],
                'reason': 'typo',
                'source': 'osm:way/13@2026-11-05',
              },
              {
                'osm': 'n11',
                'set': {'name': 'Bến xe Có Tên'},
                'reason': 'name known',
                'source': 'survey',
              },
            ],
            add: [
              {
                'id': 'man:ben-xe-vi-du',
                'name': 'Bến xe Ví Dụ',
                'kind': 'coach',
                'province': 'Ninh Bình',
                'lat': 20.1,
                'lng': 105.9,
                'aliases': <Object?>[],
                'reason': 'missing on OSM',
                'source': 'survey',
              },
            ],
          ),
        ),
      );
      final ids = r.stations.map((s) => s.id).toSet();
      expect(ids, isNot(contains('osm:n12')));
      expect(ids, isNot(contains('osm:n10')), reason: 'metro still dropped');
      final p = byId(r, 'osm:w13');
      expect(p.name, 'Bến xe Sửa Tên');
      expect(p.province, 'Hưng Yên');
      expect(p.aliases, ['Bến xe Tên Cũ']);
      expect(byId(r, 'osm:n11').name, 'Bến xe Có Tên');
      expect(byId(r, 'osm:n11').kind, StationKind.coach);
      final m = byId(r, 'man:ben-xe-vi-du');
      expect(m.province, 'Ninh Bình');
      expect(m.kind, StationKind.coach);
      expect(r.report, contains('drop `osm:n12`'));
      expect(r.report, contains('add `man:ben-xe-vi-du`'));
    });

    test('a patched name drops the alias it now equals', () {
      final generic = node(30, 21.07, 105.84, {
        'amenity': 'bus_station',
        'name': 'Bến xe khách Quy Nhơn',
        'name:vi': 'Bến xe',
        'alt_name': 'Bến xe Trung tâm',
      });
      final r = buildDataset(
        synthInputs(
          raw: overpassJson(
            [generic],
            groups: [
              ('Thành phố Hà Nội', [generic]),
            ],
          ),
          overrides: ov(
            patch: [
              {
                'osm': 'n30',
                'set': {'name': 'Bến xe khách Quy Nhơn'},
                'reason': 'generic name:vi',
                'source': 'odbl:https://www.openstreetmap.org/node/30',
              },
            ],
          ),
        ),
      );
      final s = byId(r, 'osm:n30');
      expect(s.name, 'Bến xe khách Quy Nhơn');
      expect(s.aliases, ['Bến xe Trung tâm']);
    });

    test('primary is computed from the patched kind', () {
      // A road element patched to train has no railway tag, so the real
      // station (way) must win the dedupe rank over it.
      final road = node(40, 21.08, 105.85, {
        'amenity': 'bus_station',
        'name': 'Ga Mẫu',
      });
      final rail = way(41, 21.0801, 105.8501, {
        'railway': 'station',
        'name': 'Mẫu',
      });
      final r = buildDataset(
        synthInputs(
          raw: overpassJson(
            [road, rail],
            groups: [
              ('Thành phố Hà Nội', [road, rail]),
            ],
          ),
          overrides: ov(
            patch: [
              {
                'osm': 'n40',
                'set': {'kind': 'train'},
                'reason': 'r',
                'source': 'survey',
              },
            ],
          ),
        ),
      );
      final ids = r.stations.map((s) => s.id).toList();
      expect(ids, contains('osm:w41'));
      expect(ids, isNot(contains('osm:n40')));
    });

    test('patch of an id not in the snapshot', () {
      expect(
        () => buildDataset(
          synthInputs(
            raw: raw,
            overrides: ov(
              patch: [
                {
                  'osm': 'n999',
                  'set': {'name': 'X'},
                  'reason': 'r',
                  'source': 'survey',
                },
              ],
            ),
          ),
        ),
        fails(kErrStaleOverride),
      );
    });

    test('missing source', () {
      expect(
        () => buildDataset(
          synthInputs(
            raw: raw,
            overrides: ov(
              drop: [
                {'osm': 'n12', 'reason': 'closed'},
              ],
            ),
          ),
        ),
        fails(kErrOverrideInvalid),
      );
    });

    test('Google as a source is refused', () {
      for (final source in [
        'odbl:https://maps.google.com/x',
        'public-domain:https://goo.gl/maps/x',
        'survey maps.app.goo.gl',
      ]) {
        expect(
          () => buildDataset(
            synthInputs(
              raw: raw,
              overrides: ov(
                drop: [
                  {'osm': 'n12', 'reason': 'closed', 'source': source},
                ],
              ),
            ),
          ),
          fails(kErrOverrideInvalid),
          reason: source,
        );
      }
    });

    test('unknown source form is refused', () {
      expect(
        () => buildDataset(
          synthInputs(
            raw: raw,
            overrides: ov(
              drop: [
                {'osm': 'n12', 'reason': 'closed', 'source': 'wikipedia'},
              ],
            ),
          ),
        ),
        fails(kErrOverrideInvalid),
      );
    });

    test('patch of a METRO element', () {
      expect(
        () => buildDataset(
          synthInputs(
            raw: raw,
            overrides: ov(
              patch: [
                {
                  'osm': 'n10',
                  'set': {'name': 'Ga Cát Linh'},
                  'reason': 'r',
                  'source': 'survey',
                },
              ],
            ),
          ),
        ),
        fails(kErrOverrideInvalid),
      );
    });

    test('CLI maps an invalid override to exit 65', () async {
      final tmp = copyDataToTemp();
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/overrides.json').writeAsStringSync(
        ov(
          drop: [
            {'osm': 'n1', 'reason': 'x', 'source': 'google'},
          ],
        ),
      );
      final r = await runCliCaptured([
        'build',
        '--data',
        tmp.path,
        '--out',
        '${tmp.path}/stations.json',
      ]);
      expect(r.exitCode, 65, reason: r.err);
      expect(File('${tmp.path}/stations.json').existsSync(), isFalse);
    });
  });

  test('query changed after fetch (TC16)', () async {
    final raw = overpassJson([]);
    expect(
      () => buildDataset(synthInputs(raw: raw, query: '$kTestQuery// edit\n')),
      fails(kErrQueryChanged),
    );
    // CRLF only is not a change.
    expect(
      () => buildDataset(
        synthInputs(raw: raw, query: kTestQuery.replaceAll('\n', '\r\n')),
      ),
      returnsNormally,
    );
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/query.overpassql')
        .writeAsStringSync('[out:json];\nnode(1);out;\n');
    final r = await runCliCaptured([
      'build',
      '--data',
      tmp.path,
      '--out',
      '${tmp.path}/stations.json',
    ]);
    expect(r.exitCode, 65);
    expect(r.err, contains(kErrQueryChanged));
  });

  test('acceptance failure writes the report but not stations.json', () async {
    final tmp = copyDataToTemp();
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/must_have.json').writeAsStringSync(
      '[{"kind": "train", "match": "khong co ga nay", "province": "Hà Nội"}]',
    );
    final r = await runCliCaptured([
      'build',
      '--data',
      tmp.path,
      '--out',
      '${tmp.path}/stations.json',
    ]);
    expect(r.exitCode, 1);
    expect(r.err, contains('A3'));
    expect(File('${tmp.path}/BUILD_REPORT.md').existsSync(), isTrue);
    expect(File('${tmp.path}/stations.json').existsSync(), isFalse);
  });
}
