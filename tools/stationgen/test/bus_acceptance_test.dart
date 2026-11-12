// BS-G08: checkBusAcceptance (B1–B4) and bus_must_have.json.
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'bus_helpers.dart';
import 'helpers.dart';

void main() {
  final provinces = realProvinces();
  const hn = 'Hà Nội';
  const sg = 'TP. Hồ Chí Minh';

  List<BusStop> many(String province, int n, {int from = 0}) => [
    for (var i = 0; i < n; i++)
      busStop('n${from + i + 1}', 'Trạm ${from + i}', province: province),
  ];

  final good = [...many(hn, 2000), ...many(sg, 2000, from: 2000)];

  List<String> codes({
    List<BusStop>? stops,
    int fileBytes = 1000,
    List<BusMustHave> mustHave = const [],
    List<String> required = const [hn, sg],
  }) => [
    for (final f in checkBusAcceptance(
      stops: stops ?? good,
      fileBytes: fileBytes,
      mustHave: mustHave,
      provinces: provinces,
      requiredProvinces: required,
    ))
      f.code,
  ];

  test('valid dataset passes', () {
    expect(codes(), isEmpty);
  });

  test('B1: a city with 1 999 stops, or a queried city with none', () {
    expect(codes(stops: [...many(hn, 2000), ...many(sg, 1999, from: 2000)]), [
      'B1',
    ]);
    expect(codes(stops: many(hn, 2000)), ['B1']);
  });

  test('B2: duplicate id', () {
    expect(codes(stops: [...good, busStop('n1', 'Khác')]), ['B2']);
  });

  test('B2: coordinates outside Viet Nam', () {
    expect(codes(stops: [...good, busStop('n0', 'X', lat: 1)]), ['B2']);
  });

  test('B2: name of 121 characters (120 is fine)', () {
    expect(codes(stops: [...good, busStop('n0', 'a' * 120)]), isEmpty);
    expect(codes(stops: [...good, busStop('n0', 'a' * 121)]), ['B2']);
  });

  test('B2: invalid routes and unknown province', () {
    expect(
      codes(
        stops: [
          ...good,
          busStop('n0', 'X', routes: ['123456789']),
        ],
      ),
      ['B2'],
    );
    expect(
      codes(
        stops: [
          ...good,
          busStop('n0', 'X', province: 'Atlantis'),
        ],
      ),
      ['B2'],
    );
  });

  test('B3: more than 900 KB or 15 000 stops', () {
    expect(codes(fileBytes: 900000), isEmpty);
    expect(codes(fileBytes: 900001), ['B3']);
    expect(codes(stops: [...many(hn, 7501), ...many(sg, 7500, from: 7501)]), [
      'B3',
    ]);
  });

  test('B4: must-have entry missing; found by token run of the core name', () {
    final stops = [
      ...good,
      busStop('n9001', 'Trạm xe buýt Đại học Bách Khoa (cổng sau)'),
    ];
    expect(
      codes(
        stops: stops,
        mustHave: const [BusMustHave(match: 'dai hoc bach khoa', province: hn)],
      ),
      isEmpty,
    );
    expect(
      codes(
        stops: stops,
        mustHave: const [BusMustHave(match: 'dai hoc bach khoa', province: sg)],
      ),
      ['B4'],
    );
    expect(
      codes(
        stops: stops,
        mustHave: const [BusMustHave(match: 'hoc bach', province: hn)],
      ),
      isEmpty,
    );
    expect(
      codes(
        stops: stops,
        mustHave: const [BusMustHave(match: 'bach kho', province: hn)],
      ),
      ['B4'],
      reason: 'whole tokens only',
    );
  });

  group('parseBusMustHave', () {
    Matcher invalid() => throwsA(
      isA<StationgenException>().having(
        (e) => e.code,
        'code',
        kErrMustHaveInvalid,
      ),
    );

    test('valid', () {
      final m = parseBusMustHave(
        '[{"match": "cho ben thanh", "province": "TP. Hồ Chí Minh"}]',
        provinces,
      );
      expect(m.single.matchTokens, ['cho', 'ben', 'thanh']);
    });

    test('invalid entries', () {
      const entry = '{"match": "a", "province": "Hà Nội"}';
      for (final s in [
        '{}',
        'nope',
        '[{"match": "", "province": "Hà Nội"}]',
        '[{"match": "a", "province": "Hà Tây"}]',
        '[{"match": "a", "province": "Hà Nội", "kind": "bus"}]',
        '[${List.filled(11, entry).join(',')}]',
      ]) {
        expect(() => parseBusMustHave(s, provinces), invalid(), reason: s);
      }
    });
  });
}
