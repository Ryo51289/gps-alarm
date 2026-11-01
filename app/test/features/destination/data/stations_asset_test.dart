// TC32 (asset sanity), TC33 (acceptance queries), TC34 (performance) on the
// real assets/stations.json.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationDataset dataset;
  late StationSearchIndex index;

  setUpAll(() async {
    final text = await rootBundle.loadString(kStationsAssetKey, cache: false);
    dataset = decodeStationsJson(text);
    index = StationSearchIndex(dataset.stations);
  });

  group('asset (TC32)', () {
    test('schema, counts and attribution', () {
      final trains = dataset.stations.where((s) => s.kind == StationKind.train);
      expect(trains.length, greaterThanOrEqualTo(150));
      expect(dataset.attribution, contains('OpenStreetMap'));
      expect(dataset.licenseUrl, contains('odbl'));
    });

    test('ids unique, nameAscii == foldVi(name), coordinates in Viet Nam', () {
      final ids = <String>{};
      for (final s in dataset.stations) {
        expect(ids.add(s.id), isTrue, reason: 'duplicate ${s.id}');
        expect(s.nameAscii, foldVi(s.name), reason: s.id);
        expect(s.lat, inInclusiveRange(8.0, 23.5), reason: s.id);
        expect(s.lng, inInclusiveRange(102.0, 110.0), reason: s.id);
        expect(s.province, isNotEmpty);
        expect(s.aliases.length, lessThanOrEqualTo(5));
      }
    });
  });

  group('acceptance queries (TC33)', () {
    test('"dong hoi" → Ga Đồng Hới first', () {
      final top = index.search('dong hoi').first.station;
      expect(top.kind, StationKind.train);
      expect(top.name, 'Ga Đồng Hới');
    });

    test('"my dinh" → coach Mỹ Đình in Hà Nội first', () {
      final top = index.search('my dinh').first.station;
      expect(top.kind, StationKind.coach);
      expect(stationCoreTokens(top.name), ['my', 'dinh']);
      expect(top.province, 'Hà Nội');
    });

    test('"ha noi" → Ga Hà Nội first', () {
      expect(index.search('ha noi').first.station.name, 'Ga Hà Nội');
    });

    // Overrides from review T24 round 1 (findings #1–#3).
    test('"sa pa" → Bến xe khách Sa Pa; no tourist train for "sapa"', () {
      final hits = index.search('sa pa');
      expect(hits.first.station.kind, StationKind.coach);
      expect(hits.first.station.name, 'Bến xe khách Sa Pa');
      for (final q in ['sapa', 'sa pa', 'ga sapa']) {
        expect(
          index.search(q).where((m) => m.station.kind == StationKind.train),
          isEmpty,
          reason: q,
        );
      }
    });

    test('"dong hoi" has one "Ga Đồng Hới" row', () {
      final rows = index
          .search('dong hoi')
          .where((m) => m.station.nameAscii == 'ga dong hoi');
      expect(rows, hasLength(1));
    });

    test('"quy nhon" finds Bến xe khách Quy Nhơn by name', () {
      final coach = index
          .search('quy nhon')
          .firstWhere((m) => m.station.kind == StationKind.coach);
      expect(coach.station.name, 'Bến xe khách Quy Nhơn');
      expect(coach.viaAlias, isFalse);
    });

    test('"sai gon" → Ga Sài Gòn first', () {
      expect(index.search('sai gon').first.station.name, 'Ga Sài Gòn');
    });

    test('"giap bat" → train and coach Giáp Bát in the top 2', () {
      final top2 = index.search('giap bat').take(2).map((m) => m.station);
      expect(top2.map((s) => s.kind).toSet(), {
        StationKind.train,
        StationKind.coach,
      });
      for (final s in top2) {
        expect(s.nameAscii, contains('giap bat'));
      }
    });

    test('"mien dong" → a coach station in TP. Hồ Chí Minh in the top 3', () {
      final top3 = index.search('mien dong').take(3).map((m) => m.station);
      expect(
        top3.any(
          (s) => s.kind == StationKind.coach && s.province == 'TP. Hồ Chí Minh',
        ),
        isTrue,
      );
    });
  });

  test('performance (TC34, loose thresholds)', () async {
    final text = await rootBundle.loadString(kStationsAssetKey, cache: false);
    final build = Stopwatch()..start();
    final catalog = buildStationCatalog(text);
    build.stop();

    final names = dataset.stations.map((s) => s.name).toList();
    final queries = <String>[
      for (var i = 0; i < 500; i++)
        switch (i % 4) {
          0 => names[(i * 7) % names.length], // exact
          1 => _head(names[(i * 11) % names.length]), // prefix
          2 => 'nha trnag', // fuzzy
          _ => 'zzqx wvuy $i', // no match
        },
    ];
    final run = Stopwatch()..start();
    var results = 0;
    for (final q in queries) {
      results += catalog.index.search(q).length;
    }
    run.stop();
    final perQueryMs = run.elapsedMicroseconds / queries.length / 1000;
    // Recorded in the implementation notes of docs/specs/T24.md.
    printOnFailure(
      'index ${build.elapsedMilliseconds} ms, '
      '${perQueryMs.toStringAsFixed(3)} ms/query, $results results',
    );
    expect(build.elapsedMilliseconds, lessThan(300));
    expect(perQueryMs, lessThan(5));
  });
}

String _head(String s) => s.length > 5 ? s.substring(0, 5) : s;
