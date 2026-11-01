// Tester additions for T24 (outside the spec TC list): override/alias
// re-filter after a patch, real overrides.json consistency, determinism
// under a shuffled snapshot, a socket-level network guard for build/check,
// and NFD input in the tool.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Matcher fails(String code) =>
    throwsA(isA<StationgenException>().having((e) => e.code, 'code', code));

Candidate byId(BuildResult r, String id) =>
    r.stations.firstWhere((s) => s.id == id);

String ov({
  List<Object?> drop = const [],
  List<Object?> patch = const [],
  List<Object?> add = const [],
}) =>
    jsonEncode({'schemaVersion': 1, 'drop': drop, 'patch': patch, 'add': add});

BuildResult buildOne(List<Map<String, Object?>> elements, String overrides) =>
    buildDataset(
      synthInputs(
        raw: overpassJson(elements, groups: [('Thành phố Hà Nội', elements)]),
        overrides: overrides,
      ),
    );

final class _NoNetwork extends HttpOverrides {
  int attempts = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('no HTTP in build/check');
  }
}

void main() {
  group('patch re-filters aliases (review round 1)', () {
    test('patched name equal to an alias only after folding drops it', () {
      final e = node(30, 21.07, 105.84, {
        'amenity': 'bus_station',
        'name:vi': 'Bến xe',
        'name': 'Ben xe khach Quy Nhon',
        'alt_name': 'Bến xe Trung tâm',
      });
      final before = byId(buildOne([e], ov()), 'osm:n30');
      expect(before.name, 'Bến xe');
      expect(before.aliases, ['Bến xe Trung tâm', 'Ben xe khach Quy Nhon']);

      final r = buildOne(
        [e],
        ov(
          patch: [
            {
              'osm': 'n30',
              'set': {'name': 'Bến xe khách Quy Nhơn'},
              'reason': 'generic name:vi',
              'source': 'survey',
            },
          ],
        ),
      );
      final s = byId(r, 'osm:n30');
      expect(s.name, 'Bến xe khách Quy Nhơn');
      expect(s.aliases, ['Bến xe Trung tâm'], reason: 'fold-equal alias gone');
    });

    test('aliasesAdd: existing first, fold duplicates and the new name '
        'are skipped, at most 5', () {
      final e = node(31, 21.07, 105.84, {
        'amenity': 'bus_station',
        'name': 'Bến xe A',
        'alt_name': 'Bến xe B;Bến xe C;Bến xe D',
      });
      final r = buildOne(
        [e],
        ov(
          patch: [
            {
              'osm': 'n31',
              'set': {'name': 'Bến xe Mới'},
              'aliasesAdd': [
                'BEN XE B', // fold duplicate of an existing alias
                'Ben xe Moi', // fold equal to the patched name
                '  ', // empty
                'Bến xe E',
                'Bến xe F',
                'Bến xe G', // over the limit
              ],
              'reason': 'r',
              'source': 'survey',
            },
          ],
        ),
      );
      final s = byId(r, 'osm:n31');
      expect(s.name, 'Bến xe Mới');
      expect(s.aliases, [
        'Bến xe B',
        'Bến xe C',
        'Bến xe D',
        'Bến xe E',
        'Bến xe F',
      ]);
      expect(s.aliases.length, kMaxAliases);
    });

    test('a patch without name leaves the aliases unchanged', () {
      final e = node(32, 21.07, 105.84, {
        'amenity': 'bus_station',
        'name': 'Bến xe A',
        'alt_name': 'Bến xe B;Bến xe C',
      });
      final r = buildOne(
        [e],
        ov(
          patch: [
            {
              'osm': 'n32',
              'set': {'province': 'Hưng Yên'},
              'reason': 'r',
              'source': 'survey',
            },
          ],
        ),
      );
      final s = byId(r, 'osm:n32');
      expect(s.aliases, ['Bến xe B', 'Bến xe C']);
      expect(s.province, 'Hưng Yên');
    });

    test('train patched to coach is not primary: the bus_station wins', () {
      // Without the post-patch `primary`, n50 (railway=station, lower id)
      // would rank first and be kept.
      final rail = node(50, 21.08, 105.85, {
        'railway': 'station',
        'name': 'Bến xe Mẫu',
      });
      final road = node(51, 21.0802, 105.85, {
        'amenity': 'bus_station',
        'name': 'Bến xe Mẫu',
      });
      final r = buildOne(
        [rail, road],
        ov(
          patch: [
            {
              'osm': 'n50',
              'set': {'kind': 'coach', 'name': 'Bến xe Mẫu'},
              'reason': 'r',
              'source': 'survey',
            },
          ],
        ),
      );
      final kept = r.stations.where((s) => s.coreKey == 'mau').toList();
      expect(kept.map((s) => s.id), ['osm:n51']);
      expect(kept.single.kind, StationKind.coach);
    });

    test('drop and patch of the same element is refused', () {
      final e = node(33, 21.07, 105.84, {
        'amenity': 'bus_station',
        'name': 'Bến xe A',
      });
      expect(
        () => buildOne(
          [e],
          ov(
            drop: [
              {'osm': 'n33', 'reason': 'r', 'source': 'survey'},
            ],
            patch: [
              {
                'osm': 'n33',
                'set': {'name': 'Bến xe B'},
                'reason': 'r',
                'source': 'survey',
              },
            ],
          ),
        ),
        fails(kErrOverrideInvalid),
      );
    });
  });

  group('real overrides.json', () {
    final overridesText = File('${dataDir.path}/overrides.json')
        .readAsStringSync();
    final result = buildDataset(BuildInputs.read(dataDir));

    test('every source is the OSM URL of the element it changes', () {
      final json = jsonDecode(overridesText) as Map<String, Object?>;
      const types = {'n': 'node', 'w': 'way', 'r': 'relation'};
      for (final key in ['drop', 'patch']) {
        for (final e in (json[key]! as List).cast<Map<String, Object?>>()) {
          final osm = e['osm']! as String;
          final url =
              'odbl:https://www.openstreetmap.org/'
              '${types[osm[0]]}/${osm.substring(1)}';
          expect(e['source'], url, reason: osm);
        }
      }
      expect(json['add'], isEmpty);
    });

    test('dropped elements are gone; the Quy Nhơn patch is applied', () {
      final ids = {for (final s in result.stations) s.id};
      const dropped = [
        'osm:n7121064062', // Ga Sapa
        'osm:n5592212588', // Ga Mường Hoa
        'osm:n13922085297', // Ga Làng Vàng
        'osm:n5936550803', // Ga Pom Hán
        'osm:n4195713189', // bus "Ga Đồng Hới"
        'osm:n4195730290', // bus "Ga Yên Bái"
        'osm:n13451983943', // bus "Ga Dụ Nghĩa"
      ];
      for (final id in dropped) {
        expect(ids, isNot(contains(id)));
        expect(result.report, contains('drop `$id`'));
      }
      final qn = byId(result, 'osm:n1534833900');
      expect(qn.name, 'Bến xe khách Quy Nhơn');
      expect(qn.kind, StationKind.coach);
      expect(qn.province, 'Gia Lai');
      expect(qn.aliases, isEmpty);
      // The three train stations keep a single row of their name.
      for (final n in ['ga dong hoi', 'ga yen bai', 'ga du nghia']) {
        final rows = result.stations.where((s) => foldVi(s.name) == n);
        expect(rows.map((s) => s.kind), [StationKind.train], reason: n);
      }
      expect(
        result.stations.where(
          (s) => s.kind == StationKind.train && s.coreKey.contains('sapa'),
        ),
        isEmpty,
      );
    });

    test('counts after the review round: 664 = 282 + 229 + 153', () {
      int count(StationKind k) =>
          result.stations.where((s) => s.kind == k).length;
      expect(result.stations, hasLength(664));
      expect(count(StationKind.train), 282);
      expect(count(StationKind.coach), 229);
      expect(count(StationKind.bus), 153);
      expect(result.droppedCount, 230);
      expect(result.accepted, isTrue);
    });
  });

  group('determinism', () {
    test('two in-memory builds are identical', () {
      final a = buildDataset(BuildInputs.read(dataDir));
      final b = buildDataset(BuildInputs.read(dataDir));
      expect(a.stationsJson, b.stationsJson);
      expect(a.report, b.report);
    });

    test('shuffling part A of the real snapshot does not change '
        'stations.json', () {
      final inputs = BuildInputs.read(dataDir);
      final root = jsonDecode(inputs.raw) as Map<String, Object?>;
      final elements = (root['elements']! as List).cast<Object?>();
      final firstArea = elements.indexWhere(
        (e) => (e! as Map<String, Object?>)['type'] == 'area',
      );
      expect(firstArea, greaterThan(0));
      final partA = elements.sublist(0, firstArea)..shuffle(Random(20261101));
      final shuffled = jsonEncode({
        ...root,
        'elements': [...partA, ...elements.sublist(firstArea)],
      });
      final reference = buildDataset(inputs);
      final r = buildDataset(
        BuildInputs(
          query: inputs.query,
          fetchMeta: inputs.fetchMeta,
          raw: shuffled,
          provinces: inputs.provinces,
          overrides: inputs.overrides,
          mustHave: inputs.mustHave,
        ),
      );
      expect(
        firstDifferentLine(
          utf8.encode(r.stationsJson),
          utf8.encode(reference.stationsJson),
        ),
        isNull,
      );
    });
  });

  group('network guard', () {
    test('build and check open no socket and no HttpClient', () async {
      final tmp = copyDataToTemp();
      addTearDown(() => tmp.deleteSync(recursive: true));
      final out = '${tmp.path}/stations.json';
      var sockets = 0;
      final http = _NoNetwork();
      final (build, check) = await IOOverrides.runZoned(
        () => HttpOverrides.runWithHttpOverrides(
          () async => (
            await runCliCaptured(['build', '--data', tmp.path, '--out', out]),
            await runCliCaptured(['check', '--data', tmp.path, '--out', out]),
          ),
          http,
        ),
        socketConnect: (host, port, {sourceAddress, sourcePort = 0, timeout}) {
          sockets++;
          throw StateError('no sockets in build/check');
        },
        socketStartConnect: (host, port, {sourceAddress, sourcePort = 0}) {
          sockets++;
          throw StateError('no sockets in build/check');
        },
      );
      expect(build.exitCode, 0, reason: build.err);
      expect(check.exitCode, 0, reason: check.err);
      expect(http.attempts, 0);
      expect(sockets, 0);
    });

    test('only transport.dart can open a connection', () {
      final offenders = <String>[];
      final pattern = RegExp(
        r'\b(HttpClient|Socket|RawSocket|WebSocket|SecureSocket|'
        r'HttpRequest)\b',
      );
      for (final f in Directory(
        '${packageDir.path}/lib',
      ).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) {
          continue;
        }
        final name = f.uri.pathSegments.last;
        if (name == 'transport.dart') {
          continue;
        }
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (pattern.hasMatch(code)) {
          offenders.add(name);
        }
      }
      expect(offenders, isEmpty);
      final build = File('${packageDir.path}/lib/src/build.dart')
          .readAsStringSync();
      expect(build, isNot(contains('transport.dart')));
      expect(build, isNot(contains('fetch.dart')));
    });
  });

  group('NFD input (tool)', () {
    // "Đồng Hới" and "Bến xe Mỹ Đình" written with combining marks.
    const nfdDongHoi = 'Đồng Hới';
    const nfdMyDinh = 'Bến xe Mỹ Đình';

    test('NFD train name: prefixed, folded, listed as decomposed', () {
      final r = buildOne([
        node(60, 17.4, 106.6, {'railway': 'station', 'name': nfdDongHoi}),
        node(61, 21.03, 105.78, {'amenity': 'bus_station', 'name': nfdMyDinh}),
      ], ov());
      final train = byId(r, 'osm:n60');
      expect(train.name, 'Ga $nfdDongHoi');
      expect(foldVi(train.name), 'ga dong hoi');
      expect(train.coreKey, 'dong hoi');
      final coach = byId(r, 'osm:n61');
      expect(coach.kind, StationKind.coach);
      expect(coach.coreKey, 'my dinh');
      final section = r.report.split('## 10.')[1].split('## 11.')[0];
      expect(section, contains('`osm:n60`'));
      expect(section, contains('`osm:n61`'));
      expect(r.stationsJson, contains('"nameAscii":"ga dong hoi"'));
    });

    test('NFD and NFC duplicates of one station merge', () {
      final r = buildOne([
        node(62, 21.03, 105.78, {'amenity': 'bus_station', 'name': nfdMyDinh}),
        way(63, 21.0301, 105.78, {
          'amenity': 'bus_station',
          'name': 'Bến xe Mỹ Đình',
        }),
      ], ov());
      final rows = r.stations.where((s) => s.coreKey == 'my dinh').toList();
      expect(rows, hasLength(1));
      expect(rows.single.mergedIds, hasLength(1));
    });
  });
}
