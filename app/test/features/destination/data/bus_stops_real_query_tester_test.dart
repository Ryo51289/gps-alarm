// Tester T24.3: Vietnamese queries on the real assets/bus_stops.json (with
// and without diacritics), the must-have list seen through the app search,
// boundaries of the chip "Tất cả" rule (3 letters) and the bucketed index
// against a full scan on tricky queries and on the limits screen 2 uses
// (5, 20, 60: the top-k insertion path of the index).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

import '../../../helpers/test_station_catalog.dart';

/// Folded names of every stop of the real catalog.
Iterable<String> _foldedNames() =>
    kTestBusStopCatalog.dataset.stations.map((s) => s.nameAscii);

List<String> _ids(List<StationMatch> rows) => [
  for (final m in rows) m.station.id,
];

/// Queries that stress the first-letter bucket and the letter mask:
/// diacritics, case, punctuation, digits, words typed together, province
/// names, typos on first letters, kind prefixes, non-Latin input.
const List<String> _tricky = [
  'bach khoa',
  'Bách Khoa',
  'BÁCH KHOA',
  'bách   khoa',
  'Bách-Khoa',
  'bachkhoa',
  'daihocbachkhoa',
  // A space typed at the wrong place: words-typed-together tiers.
  'bac hkhoa',
  'ki mma',
  'kimm a',
  'daihoc bachkhoa',
  'cho benthanh',
  'dai hoc bach khoa',
  'Đại học Bách khoa',
  'đh bách khoa',
  'dh bach khoa',
  'bach khao',
  'abch khoa',
  'bach mhoa',
  'vach khoa',
  'khoa bach',
  'bach khoa ha noi',
  'bach khoa ho chi minh',
  'bach khoa hcm',
  'Bến Thành',
  'ben thanh',
  'benthanh',
  'cho ben thanh',
  'chợ bến thành',
  'ga ben thanh',
  'ga Hà Nội',
  'ga ha noi',
  'hanoi',
  'ha noi',
  'ho chi minh',
  'tp ho chi minh',
  'thanh pho ho chi minh',
  'tphcm',
  'tram buyt kim ma',
  'trạm xe buýt kim mã',
  'diem dung kim ma',
  'điểm dừng xe buýt kim mã',
  'ben xe buyt kim ma',
  'kim ma',
  '211 kim ma',
  '211',
  'b13',
  'b13 ktx bach khoa',
  'so 1 kim ma',
  'q1',
  'ng',
  'nguyen',
  'nguyễn trãi',
  'đường láng',
  'duong lang',
  '498 duong lang',
  'doi dien 498 duong lang',
  'times city',
  'timescity',
  'benh vien cho ray',
  'bv cho ray',
  'cho ray',
  'suoi tien',
  'san bay tan son nhat',
  'tan son nhat',
  'x',
  'xyzq',
  '!!!',
  '-',
  '(',
  '#1',
  '１２',
  '北京',
  'ß',
  '🚌 bach khoa',
  'café',
  'ʼa',
];

void main() {
  final bus = kTestBusStopCatalog.index;
  final stations = kTestStationCatalog.index;

  group('real queries, diacritics in or out', () {
    // The same results with or without diacritics / case (foldVi).
    const pairs = [
      ('bach khoa', 'Bách Khoa'),
      ('bach khoa', 'BÁCH KHOA'),
      ('ben thanh', 'Bến Thành'),
      ('cho ben thanh', 'Chợ Bến Thành'),
      ('ga ha noi', 'ga Hà Nội'),
      ('dai hoc bach khoa', 'Đại học Bách khoa'),
      ('kim ma', 'Kim Mã'),
      ('duong lang', 'Đường Láng'),
    ];
    for (final (plain, marked) in pairs) {
      test('"$plain" == "$marked" on every chip', () {
        for (final f in DestinationFilter.values) {
          expect(
            busStopResults(bus, marked, f).toString(),
            busStopResults(bus, plain, f).toString(),
            reason: 'bus stops, chip $f',
          );
          expect(
            offlineResults(stations, marked, f).toString(),
            offlineResults(stations, plain, f).toString(),
            reason: 'stations, chip $f',
          );
        }
      });
    }

    test('"bach khoa" on chip Trạm buýt: both cities; every Bách Khoa '
        'stop before the fuzzy rows', () {
      final rows = busStopResults(bus, 'bach khoa', DestinationFilter.busStop);
      expect(rows, hasLength(kDisplayLimit));
      // Fuzzy rows ("Kho bạc Sơn Tây", T24 §7.3) only fill the tail.
      var seenFuzzy = false;
      for (final m in rows) {
        if (m.tier == StationMatchTier.fuzzy) {
          seenFuzzy = true;
          continue;
        }
        expect(seenFuzzy, isFalse, reason: 'non-fuzzy after fuzzy: $m');
        expect(m.station.nameAscii, contains('bach khoa'), reason: '$m');
      }
      final named = _foldedNames().where((s) => s.contains('bach khoa')).length;
      final strong = rows.where((m) => m.tier != StationMatchTier.fuzzy);
      expect(strong.length, min(named, kDisplayLimit));
      final provinces = {for (final m in rows) m.station.province};
      expect(provinces, containsAll(['Hà Nội', 'TP. Hồ Chí Minh']));
      // "Đại học Bách Khoa" of both cities (HN n8766627164, HCM n3116882984).
      expect(_ids(rows), containsAll(['osm:n8766627164', 'osm:n3116882984']));
    });

    test('"dai hoc bach khoa": the three exact stops come first', () {
      final rows = busStopResults(
        bus,
        'dai hoc bach khoa',
        DestinationFilter.busStop,
      );
      final exact = [
        for (final m in rows)
          if (m.station.nameAscii == 'dai hoc bach khoa') m.station.id,
      ];
      expect(
        exact,
        unorderedEquals([
          'osm:n8766627164',
          'osm:n3116882984',
          'osm:n3118842030',
        ]),
      );
      expect(_ids(rows).take(3), unorderedEquals(exact));
      expect(rows.first.tier, StationMatchTier.exact);
    });

    test('"Bến Thành": Chợ Bến Thành and Ga Bến Thành (HCM)', () {
      final rows = busStopResults(bus, 'Bến Thành', DestinationFilter.busStop);
      expect(_ids(rows), containsAll(['osm:n3166133536', 'osm:n12679325321']));
      final cho = busStopResults(
        bus,
        'cho ben thanh',
        DestinationFilter.busStop,
      );
      expect(cho.first.station.id, 'osm:n3166133536');
      expect(cho.first.station.province, 'TP. Hồ Chí Minh');
    });

    test('"ga Hà Nội" on chip Tất cả: the train station first, the bus '
        'stop "Ga Hà Nội" only in the section under it', () {
      final rows = offlineResults(stations, 'ga Hà Nội', DestinationFilter.all);
      expect(rows.first.station.name, 'Ga Hà Nội');
      expect(rows.first.station.kind, StationKind.train);
      final stops = busStopResults(bus, 'ga Hà Nội', DestinationFilter.all);
      expect(stops.length, lessThanOrEqualTo(kBusStopAllLimit));
      expect(_ids(stops), contains('osm:n4251886989'));
      expect(busStopsFirst('ga Hà Nội', DestinationFilter.all), isFalse);
    });

    test('a typo still finds Bách Khoa (fuzzy)', () {
      final rows = busStopResults(bus, 'bach khao', DestinationFilter.busStop);
      expect(rows, isNotEmpty);
      expect(rows.first.station.nameAscii, contains('bach khoa'));
    });

    test('"trạm buýt kim mã" on chip Tất cả: bus stops first, ≤ 20', () {
      expect(busStopsFirst('trạm buýt kim mã', DestinationFilter.all), isTrue);
      final rows = busStopResults(
        bus,
        'trạm buýt kim mã',
        DestinationFilter.all,
      );
      expect(rows.length, greaterThan(kBusStopAllLimit));
      expect(rows.length, lessThanOrEqualTo(kDisplayLimit));
      for (final m in rows.take(5)) {
        expect(m.station.nameAscii, contains('kim ma'), reason: '$m');
      }
    });

    test('"kim ma" on chip Tất cả: Bến xe Kim Mã stays first', () {
      final rows = offlineResults(stations, 'kim ma', DestinationFilter.all);
      expect(rows.first.station.nameAscii, contains('kim ma'));
      expect(rows.first.station.kind, isNot(StationKind.busStop));
      final stops = busStopResults(bus, 'kim ma', DestinationFilter.all);
      expect(stops, hasLength(kBusStopAllLimit));
    });
  });

  test('every bus_must_have.json entry is found by the app search', () {
    final list = jsonDecode(
      File('../data/stations/bus_must_have.json').readAsStringSync(),
    ) as List;
    expect(list, isNotEmpty);
    for (final e in list.cast<Map<String, Object?>>()) {
      final match = e['match']! as String;
      final province = e['province']! as String;
      final rows = bus.search(match, limit: 60, kindHint: StationKind.busStop);
      final hit = rows.where(
        (m) =>
            m.station.province == province &&
            m.station.nameAscii.contains(foldVi(match)),
      );
      expect(hit, isNotEmpty, reason: '$match / $province');
      // Within what the chip "Trạm buýt" shows (20 rows).
      final shown = busStopResults(bus, match, DestinationFilter.busStop);
      expect(
        shown.any((m) => m.station.province == province),
        isTrue,
        reason: '$match / $province within $kDisplayLimit rows',
      );
    }
  });

  group('chip Tất cả: 3 letters boundary (D9)', () {
    test('2 letters: none; exactly 3: some', () {
      expect(queryChars('ki'), 2);
      expect(busStopResults(bus, 'ki', DestinationFilter.all), isEmpty);
      expect(queryChars('k i'), 2);
      expect(busStopResults(bus, 'k i', DestinationFilter.all), isEmpty);
      expect(queryChars('kim'), 3);
      expect(busStopResults(bus, 'kim', DestinationFilter.all), isNotEmpty);
      expect(queryChars('Kìm'), 3);
      expect(busStopResults(bus, 'Kìm', DestinationFilter.all), isNotEmpty);
      // Chip "Trạm buýt" already lists from 2 letters.
      expect(busStopResults(bus, 'ki', DestinationFilter.busStop), isNotEmpty);
      expect(busStopResults(bus, 'k', DestinationFilter.busStop), isEmpty);
    });
  });

  group('bucketed index ≡ full scan (tester)', () {
    final stops = kTestBusStopCatalog.dataset.stations;
    final bucketed = StationSearchIndex(
      stops,
      bucketByFirstChar: true,
      substringTier: false,
    );
    final full = StationSearchIndex(stops, substringTier: false);

    test('tricky queries, limits 1, 5, 20, 60, 100, with / without hint', () {
      for (final q in _tricky) {
        for (final limit in [1, 5, 20, 60, 100]) {
          for (final hint in [null, StationKind.busStop, StationKind.train]) {
            expect(
              bucketed.search(q, limit: limit, kindHint: hint).toString(),
              full.search(q, limit: limit, kindHint: hint).toString(),
              reason: '"$q" limit $limit hint $hint',
            );
          }
        }
      }
    });

    test('600 seeded queries at the screen limits 5 and 20', () {
      final rng = Random(2431);
      for (var i = 0; i < 600; i++) {
        final s = stops[rng.nextInt(stops.length)];
        final f = foldVi(s.name);
        final q = switch (i % 5) {
          0 => f.substring(0, min(f.length, 2 + rng.nextInt(4))),
          1 => f.split(' ').where((t) => t.isNotEmpty).last,
          2 => '${f.split(' ').first} ${foldVi(s.province)}',
          3 => f.replaceAll(' ', ''),
          _ => f,
        };
        final limit = i.isEven ? 5 : 20;
        final hint = i % 3 == 0 ? StationKind.busStop : null;
        expect(
          bucketed.search(q, limit: limit, kindHint: hint).toString(),
          full.search(q, limit: limit, kindHint: hint).toString(),
          reason: '"$q" limit $limit hint $hint',
        );
      }
    });

    test('the limit only cuts the full ranking (top-k is a prefix)', () {
      for (final q in ['ng', 'cho', 'ha noi', 'bach', 'tram buyt ng']) {
        final all = bucketed.search(q, limit: 100000).toString();
        for (final limit in [1, 5, 20, 60]) {
          final top = bucketed.search(q, limit: limit);
          final head = bucketed.search(q, limit: 100000).take(limit).toList();
          expect(top.toString(), head.toString(), reason: '"$q" $limit');
        }
        expect(all, isNotEmpty);
      }
    });
  });
}
