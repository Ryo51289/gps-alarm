// T23 TS20–TS29 on the real assets/stations.json: acceptance queries of
// TASKS T23 / test report T24 O1, must-have entries with a kind prefix,
// filter chips.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

void main() {
  final catalog = buildStationCatalog(
    File('assets/stations.json').readAsStringSync(),
  );
  final index = catalog.index;

  List<StationMatch> search(String q) => index.search(q);
  int indexOfName(List<StationMatch> r, String name) =>
      r.indexWhere((m) => m.station.name == name);

  test('TS20 "dong hoi" → Ga Đồng Hới first', () {
    final first = search('dong hoi').first.station;
    expect(first.name, 'Ga Đồng Hới');
    expect(first.kind, StationKind.train);
  });

  test('TS21 "ben xe nha trang": two coach stations before Ga Nha Trang', () {
    final r = search('ben xe nha trang');
    expect(r.take(2).map((m) => m.station.name).toSet(), {
      'Bến Xe Bắc Nha Trang',
      'Bến xe liên tỉnh phía Nam Nha Trang',
    });
    for (final m in r.take(2)) {
      expect(m.station.kind, StationKind.coach);
      expect(m.station.province, 'Khánh Hòa');
    }
    expect(indexOfName(r, 'Ga Nha Trang'), greaterThan(1));
  });

  test('TS22 "ben xe vinh": Bến xe Bắc Vinh first, Ga Vinh after it', () {
    final r = search('ben xe vinh');
    expect(r.first.station.name, 'Bến xe Bắc Vinh');
    expect(r.first.station.kind, StationKind.coach);
    expect(r.first.station.province, 'Nghệ An');
    final ga = indexOfName(r, 'Ga Vinh');
    expect(ga == -1 || ga > 0, isTrue);
  });

  test('TS23 "ben xe hue": coach stations of Huế before Ga Huế', () {
    final r = index.search('ben xe hue', limit: 100);
    expect(r.take(2).map((m) => m.station.name).toSet(), {
      'Ben Xe Phía Băc',
      'Bến xe phía Nam',
    });
    final ga = indexOfName(r, 'Ga Huế');
    expect(ga, greaterThan(0));
    final lastCoachHue = r.lastIndexWhere(
      (m) => m.station.kind == StationKind.coach && m.station.province == 'Huế',
    );
    expect(ga, greaterThan(lastCoachHue));
  });

  test('TS24 joined words: hanoi, sapa, saigon, nhatrang (990)', () {
    for (final (q, name) in [
      ('hanoi', 'Ga Hà Nội'),
      ('sapa', 'Bến xe khách Sa Pa'),
      ('saigon', 'Ga Sài Gòn'),
      ('nhatrang', 'Ga Nha Trang'),
    ]) {
      final m = search(q).first;
      expect(m.station.name, name, reason: q);
      expect(m.score, 990, reason: q);
    }
  });

  test('TS25 main coach station of each city first', () {
    for (final (q, name) in [
      ('ben xe da nang', 'Bến xe Trung tâm Đà Nẵng'),
      ('ben xe hai phong', 'Bến xe Bắc Hải Phòng'),
      ('ben xe can tho', 'Bến xe Trung tâm tp.Cần Thơ'),
      ('ben xe thai binh', 'Bến xe khách Trung tâm Thái Bình'),
      ('ben xe ninh binh', 'Bến xe khách Ninh Bình'),
    ]) {
      // Compared folded: some OSM names are stored in NFD (TM07).
      expect(search(q).first.station.nameAscii, foldVi(name), reason: q);
    }
  });

  final mustHave = (jsonDecode(
    File('../data/stations/must_have.json').readAsStringSync(),
  ) as List).cast<Map<String, Object?>>().where((e) => e['waived'] == null);

  test('TS26 "ben xe <match>": a coach of the province in the first 10', () {
    var checked = 0;
    for (final e in mustHave.where((e) => e['kind'] == 'coach')) {
      final r = search('ben xe ${e['match']}').take(10);
      expect(
        r.any(
          (m) =>
              m.station.kind == StationKind.coach &&
              m.station.province == e['province'],
        ),
        isTrue,
        reason: '$e',
      );
      checked++;
    }
    expect(checked, greaterThan(10));
  });

  test('TS27 "ga <match>": the train station of the province first', () {
    var checked = 0;
    for (final e in mustHave.where((e) => e['kind'] == 'train')) {
      final first = search('ga ${e['match']}').first.station;
      expect(first.kind, StationKind.train, reason: '$e');
      expect(first.province, e['province'], reason: '$e');
      checked++;
    }
    expect(checked, greaterThan(10));
  });

  test('TS28 offlineResults per filter for "nha trang"', () {
    final all = offlineResults(index, 'nha trang', DestinationFilter.all);
    expect(
      all.map((m) => m.station.id),
      index.search('nha trang').map((m) => m.station.id),
    );
    expect(all.length, lessThanOrEqualTo(kDisplayLimit));

    final train = offlineResults(index, 'nha trang', DestinationFilter.train);
    expect(train, isNotEmpty);
    expect(train.every((m) => m.station.kind == StationKind.train), isTrue);

    final coach = offlineResults(index, 'nha trang', DestinationFilter.coach);
    expect(coach.length, lessThanOrEqualTo(kDisplayLimit));
    expect(coach.every((m) => m.station.kind != StationKind.train), isTrue);
    expect(coach.take(2).map((m) => m.station.name).toSet(), {
      'Bến Xe Bắc Nha Trang',
      'Bến xe liên tỉnh phía Nam Nha Trang',
    });

    expect(
      offlineResults(index, 'nha trang', DestinationFilter.places),
      isEmpty,
    );
  });

  test('TS29 fewer than 2 letters: no rows', () {
    for (final q in ['x', '  ', 'Đ', '-', '']) {
      expect(
        offlineResults(index, q, DestinationFilter.all),
        isEmpty,
        reason: q,
      );
    }
    // "a b" has 2 letters: the search runs.
    expect(
      () => offlineResults(index, 'a b', DestinationFilter.all),
      returnsNormally,
    );
  });
}
