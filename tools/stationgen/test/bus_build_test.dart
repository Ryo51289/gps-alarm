// BS-G05, BS-G06, BS-G09, BS-G10 (buildBusDataset), bus overrides.
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'bus_helpers.dart';
import 'helpers.dart';

Matcher fails(String code) =>
    throwsA(isA<StationgenException>().having((e) => e.code, 'code', code));

const String _hnArea = 'Thành phố Hà Nội';
const String _sgArea = 'Thành phố Hồ Chí Minh';

/// Raw snapshot with every element in Hà Nội unless listed in [sg].
String raw(
  List<Map<String, Object?>> hn, {
  List<Map<String, Object?>> sg = const [],
  Map<String, Object?> extra = const {},
}) => overpassJson(
  [...hn, ...sg],
  groups: [(_hnArea, hn), if (sg.isNotEmpty) (_sgArea, sg)],
  extra: extra,
);

BusBuildResult build(
  String raw, {
  List<Candidate> stations = const [],
  String overrides = kEmptyOverrides,
}) => buildBusDataset(busSynthInputs(raw: raw, overrides: overrides), stations);

String dropped(BusBuildResult r, String reason) =>
    r.report.split('### $reason')[1].split('\n\n')[1];

void main() {
  group('classification in build', () {
    test('drops and keeps', () {
      final r = build(
        raw([
          node(1, 21, 105.8, stopTags('Kim Mã', {'route_ref': '03;14'})),
          node(2, 21.1, 105.8, {'highway': 'bus_stop'}),
          node(3, 21.2, 105.8, {'public_transport': 'platform', 'name': 'X'}),
          way(4, 21.3, 105.8, {
            'public_transport': 'platform',
            'bus': 'yes',
            'name': 'Bến chờ Long Biên',
          }),
          node(5, 30, 105.8, stopTags('Ngoài khung')),
        ]),
      );
      expect(r.stops.map((s) => '${s.id} ${s.name} ${s.routes}'), [
        'w4 Bến chờ Long Biên []',
        'n1 Kim Mã [03, 14]',
      ]);
      expect(r.droppedCount, 3);
      expect(dropped(r, 'NO_NAME'), contains('`n2`'));
      expect(dropped(r, 'NOT_STOP'), contains('`n3`'));
      expect(dropped(r, 'OUTSIDE_BBOX'), contains('`n5`'));
      expect(r.provinces, ['Hà Nội']);
      final json = jsonDecode(r.busStopsJson) as Map<String, Object?>;
      expect(json['counts'], {'Hà Nội': 2});
    });

    test('route_ref issues are reported (section 7)', () {
      final r = build(
        raw([
          node(1, 21, 105.8, stopTags('A', {'route_ref': '1;2;3;4;5;6;7'})),
          node(2, 21.1, 105.8, stopTags('B', {'route_ref': 'Very long'})),
        ]),
      );
      final s7 = r.report.split('## 7.')[1].split('## 8.')[0];
      expect(s7, contains('| Values cut to 6 routes | 1 |'));
      expect(s7, contains('- `n1` — `1;2;3;4;5;6;7`'));
      expect(s7, contains('- `n2` — `Very long`'));
    });
  });

  group('provinces', () {
    final a = node(1, 21, 105.8, stopTags('A'));

    test('element in no area: E_PROVINCE_UNRESOLVED', () {
      expect(
        () => build(
          overpassJson(
            [a, node(2, 21, 105.8, stopTags('B'))],
            groups: [
              (_hnArea, [a]),
            ],
          ),
        ),
        fails(kErrProvinceUnresolved),
      );
    });

    test('two provinces: smallest key, reported', () {
      final r = build(
        overpassJson(
          [a],
          groups: [
            (_sgArea, [a]),
            (_hnArea, [a]),
          ],
        ),
      );
      expect(r.stops.single.province, 'Hà Nội');
      final s8 = r.report.split('## 8.')[1].split('## 9.')[0];
      expect(s8, contains('`n1` A: Hà Nội, TP. Hồ Chí Minh → Hà Nội'));
      expect(
        r.report,
        contains('- Thành phố Hồ Chí Minh → TP. Hồ Chí Minh (1 elements)'),
      );
    });
  });

  test('DUP_OF_STATION (BS-G05)', () {
    final myDinh = cand(
      'osm:w1',
      'Bến xe Mỹ Đình',
      lat: 21.02827,
      lng: 105.77752,
    );
    final r = build(
      raw([
        node(1, 21.02827 + northM(80), 105.77752, stopTags('Bến xe Mỹ Đình')),
        node(2, 21.02827 + northM(500), 105.77752, stopTags('Bến xe Mỹ Đình')),
      ]),
      stations: [myDinh],
    );
    expect(r.stops.map((s) => s.id), ['n2']);
    expect(dropped(r, 'DUP_OF_STATION'), contains('`n1`'));
    expect(
      r.report.split('## 5.')[1].split('## 6.')[0],
      contains('- `n1` Bến xe Mỹ Đình → `osm:w1` Bến xe Mỹ Đình — 80 m'),
    );
  });

  test('input order does not change the output bytes (BS-G06)', () {
    final elements = [
      node(1, 21, 105.8, stopTags('Đại học Bách khoa', {'route_ref': '03'})),
      node(2, 21 + northM(40), 105.8, stopTags('Đại học Bách khoa')),
      node(3, 21.1, 105.8, stopTags('Kim Mã')),
      way(4, 21.1 + northM(30), 105.8, {
        'public_transport': 'platform',
        'bus': 'yes',
        'name': 'Kim Mã',
        'route_ref': '14',
      }),
      node(5, 10.772, 106.698, stopTags('Chợ Bến Thành')),
    ];
    final sg = [elements.last];
    final hn = elements.sublist(0, 4);
    final a = build(raw(hn, sg: sg));
    final b = build(raw(hn.reversed.toList(), sg: sg));
    expect(b.busStopsJson, a.busStopsJson);
    expect(b.report, a.report);
    expect(a.stops.map((s) => '${s.id} ${s.routes}'), [
      'n1 [03]',
      'n3 [14]',
      'n5 []',
    ]);
  });

  group('snapshot (BS-G09)', () {
    test('parses part A and both areas', () {
      final r = build(
        raw(
          [node(1, 21, 105.8, stopTags('A'))],
          sg: [node(2, 10.8, 106.7, stopTags('B'))],
        ),
      );
      expect(r.provinces, ['Hà Nội', 'TP. Hồ Chí Minh']);
    });

    test('id of an area missing from part A', () {
      final j = jsonDecode(
        raw([node(1, 21, 105.8, stopTags('A'))]),
      ) as Map<String, Object?>;
      (j['elements']! as List<Object?>).add({'type': 'node', 'id': 99});
      expect(() => build(jsonEncode(j)), fails(kErrRawInvalid));
    });

    test('remark', () {
      expect(
        () => build(raw([], extra: {'remark': 'runtime error: timeout'})),
        fails(kErrRawInvalid),
      );
    });
  });

  test('query changed after fetch (BS-G10)', () {
    expect(
      () => buildBusDataset(
        busSynthInputs(raw: raw([]), query: '$kTestQuery// edit\n'),
        const [],
      ),
      fails(kErrQueryChanged),
    );
    expect(
      () => buildBusDataset(
        busSynthInputs(
          raw: raw([]),
          query: kTestQuery.replaceAll('\n', '\r\n'),
        ),
        const [],
      ),
      returnsNormally,
    );
  });

  group('bus_overrides.json', () {
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
    const src = 'odbl:https://www.openstreetmap.org/node/1';
    final elements = [
      node(1, 21, 105.8, stopTags('A')),
      node(2, 21.1, 105.8, {'highway': 'bus_stop'}),
    ];

    test('drop, patch of a nameless stop, add', () {
      final r = build(
        raw(elements),
        overrides: ov(
          drop: [
            {'osm': 'n1', 'reason': 'gone', 'source': src},
          ],
          patch: [
            {
              'osm': 'n2',
              'set': {'name': 'Trạm mới', 'lat': 21.2},
              'reason': 'name from survey',
              'source': 'survey',
            },
          ],
          add: [
            {
              'id': 'man:tram-a',
              'name': 'Trạm A',
              'kind': 'bus',
              'province': 'Hà Nội',
              'lat': 21.3,
              'lng': 105.9,
              'reason': 'missing',
              'source': 'survey',
            },
          ],
        ),
      );
      expect(r.stops.map((s) => '${s.id} ${s.name} ${s.lat}'), [
        'man:tram-a Trạm A 21.3',
        'n2 Trạm mới 21.2',
      ]);
      final s9 = r.report.split('## 9.')[1];
      expect(s9, contains('drop `n1` (A): gone'));
      expect(s9, contains('patch `n2` (null): name from survey'));
      expect(s9, contains('add `man:tram-a` (Trạm A): missing'));
    });

    test('invalid entries', () {
      for (final o in [
        ov(
          patch: [
            {
              'osm': 'n1',
              'set': {'kind': 'coach'},
              'reason': 'x',
              'source': 'survey',
            },
          ],
        ),
        ov(
          patch: [
            {
              'osm': 'n1',
              'aliasesAdd': ['B'],
              'reason': 'x',
              'source': 'survey',
            },
          ],
        ),
        ov(
          add: [
            {
              'id': 'man:a',
              'name': 'A',
              'kind': 'coach',
              'province': 'Hà Nội',
              'lat': 21,
              'lng': 105,
              'reason': 'x',
              'source': 'survey',
            },
          ],
        ),
        ov(
          drop: [
            {'osm': 'n1', 'reason': 'x', 'source': 'https://maps.google.com'},
          ],
        ),
      ]) {
        expect(
          () => build(raw(elements), overrides: o),
          fails(kErrOverrideInvalid),
          reason: o,
        );
      }
    });

    test('stale reference', () {
      expect(
        () => build(
          raw(elements),
          overrides: ov(
            drop: [
              {'osm': 'n99', 'reason': 'x', 'source': src},
            ],
          ),
        ),
        fails(kErrStaleOverride),
      );
    });

    test('patch cannot revive a dropped element', () {
      expect(
        () => build(
          raw([
            node(1, 21, 105.8, {
              'highway': 'bus_stop',
              'name': 'A',
              'access': 'no',
            }),
          ]),
          overrides: ov(
            patch: [
              {
                'osm': 'n1',
                'set': {'name': 'B'},
                'reason': 'x',
                'source': 'survey',
              },
            ],
          ),
        ),
        fails(kErrOverrideInvalid),
      );
    });
  });

  group('CLI (BS-G10)', () {
    test('missing raw/bus_overpass.json: exit 65 E_INPUT_MISSING', () async {
      final tmp = copyDataToTemp();
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/raw/bus_overpass.json').deleteSync();
      final r = await runCliCaptured([
        'build',
        '--data',
        tmp.path,
        '--out',
        '${tmp.path}/stations.json',
      ]);
      expect(r.exitCode, 65);
      expect(r.err, contains(kErrInputMissing));
      expect(File('${tmp.path}/stations.json').existsSync(), isFalse);
    });

    test('bus_query.overpassql edited: exit 65 E_QUERY_CHANGED', () async {
      final tmp = copyDataToTemp();
      addTearDown(() => tmp.deleteSync(recursive: true));
      File('${tmp.path}/bus_query.overpassql')
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

    test(
      'bus acceptance failure: report written, bus_stops.json not',
      () async {
        final tmp = copyDataToTemp();
        addTearDown(() => tmp.deleteSync(recursive: true));
        File('${tmp.path}/bus_must_have.json').writeAsStringSync(
          '[{"match": "khong co tram nay", "province": "Hà Nội"}]',
        );
        final r = await runCliCaptured([
          'build',
          '--data',
          tmp.path,
          '--out',
          '${tmp.path}/stations.json',
        ]);
        expect(r.exitCode, 1);
        expect(r.err, contains('B4'));
        expect(File('${tmp.path}/BUS_BUILD_REPORT.md').existsSync(), isTrue);
        expect(File('${tmp.path}/bus_stops.json').existsSync(), isFalse);
        expect(
          File('${tmp.path}/stations.json').existsSync(),
          isTrue,
          reason: 'stations.json passed A1–A5',
        );
      },
    );

    test('--bus-out overrides the default next to --out', () async {
      final tmp = copyDataToTemp();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final r = await runCliCaptured([
        'build',
        '--data',
        tmp.path,
        '--out',
        '${tmp.path}/stations.json',
        '--bus-out',
        '${tmp.path}/other/bus.json',
      ]);
      expect(r.exitCode, 0, reason: r.err);
      expect(File('${tmp.path}/other/bus.json').existsSync(), isTrue);
      expect(File('${tmp.path}/bus_stops.json').existsSync(), isFalse);
    });
  });
}
