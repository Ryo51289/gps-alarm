// TC06: province table (34 new provinces, 63 former provinces).
import 'dart:convert';
import 'dart:io';

import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final table = realProvinces();

  test('34 provinces, 63 former provinces each listed once', () {
    expect(table.provinces.length, 34);
    expect(table.names.toSet().length, 34);
    final former = [for (final p in table.provinces) ...p.formerly];
    expect(former.length, 63);
    expect(former.map(provinceKey).toSet().length, 63);
  });

  test('provinceKey', () {
    expect(provinceKey('Tỉnh Quảng Bình'), 'quangbinh');
    expect(provinceKey('Thành phố Hồ Chí Minh'), 'hochiminh');
    expect(provinceKey('Bà Rịa - Vũng Tàu'), 'bariavungtau');
    expect(provinceKey('TP. Hồ Chí Minh'), 'hochiminh');
  });

  test('resolve old and new names', () {
    expect(table.resolve('Tỉnh Quảng Bình'), 'Quảng Trị');
    expect(table.resolve('Thành phố Hồ Chí Minh'), 'TP. Hồ Chí Minh');
    expect(table.resolve('Thừa Thiên Huế'), 'Huế');
    expect(table.resolve('Thành phố Huế'), 'Huế');
    expect(table.resolve('Bà Rịa - Vũng Tàu'), 'TP. Hồ Chí Minh');
    expect(table.resolve('Hoà Bình'), 'Phú Thọ');
    expect(table.resolve('Tỉnh Khánh Hòa'), 'Khánh Hòa');
    expect(table.resolve('Thành phố Đồng Nai'), 'Đồng Nai');
    expect(table.resolve('Đăk Lăk'), 'Đắk Lắk');
    expect(table.resolve('Kontum'), 'Quảng Ngãi');
    expect(table.resolve('Xiengkhouang'), isNull);
  });

  group('validation', () {
    final rows = (jsonDecode(
      File('${dataDir.path}/provinces.json').readAsStringSync(),
    ) as List<Object?>).cast<Map<String, Object?>>();

    Matcher invalid() => throwsA(
      isA<StationgenException>().having(
        (e) => e.code,
        'code',
        kErrProvincesInvalid,
      ),
    );

    test('33 provinces', () {
      expect(() => ProvinceTable.parse(jsonEncode(rows.sublist(1))), invalid());
    });

    test('former province listed twice', () {
      final copy = [
        for (final r in rows) {...r},
      ];
      copy[0]['formerly'] = ['Hà Nội', 'Hải Dương'];
      expect(() => ProvinceTable.parse(jsonEncode(copy)), invalid());
    });

    test('alias pointing to two provinces', () {
      final copy = [
        for (final r in rows) {...r},
      ];
      copy[0]['aliases'] = ['Quảng Bình'];
      expect(() => ProvinceTable.parse(jsonEncode(copy)), invalid());
    });
  });
}
