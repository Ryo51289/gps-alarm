// TC13: acceptance thresholds A1–A5 and the must-have rules.
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  final provinces = realProvinces();

  /// 150 trains in Hà Nội + one coach per province + the two must-haves.
  List<Candidate> passing() => [
    for (var i = 0; i < 150; i++)
      cand('osm:n${1000 + i}', 'Ga T$i', kind: StationKind.train),
    for (final (i, p) in provinces.names.indexed)
      cand('osm:n${2000 + i}', 'Bến xe Tỉnh $i', province: p),
    cand(
      'osm:w1',
      'Ga Đồng Hới',
      kind: StationKind.train,
      province: 'Quảng Trị',
    ),
    cand('osm:r1', 'Bến xe khách Mỹ Đình'),
  ];

  const mustHave = [
    MustHave(kind: StationKind.train, match: 'dong hoi', province: 'Quảng Trị'),
    MustHave(kind: StationKind.coach, match: 'my dinh', province: 'Hà Nội'),
  ];

  List<String> codes(List<Candidate> stations, {int bytes = 1000}) => [
    for (final f in checkAcceptance(
      stations: stations,
      fileBytes: bytes,
      mustHave: mustHave,
      provinces: provinces,
    ))
      f.code,
  ];

  test('passing dataset', () {
    expect(codes(passing()), isEmpty);
  });

  test('A1: 149 train stations', () {
    final s = passing()
      ..removeWhere((c) => c.id == 'osm:n1000')
      ..removeWhere((c) => c.id == 'osm:n1001');
    expect(codes(s), ['A1']);
  });

  test('A2: a province without coach, listed', () {
    final s = passing()..removeWhere((c) => c.province == 'Cà Mau');
    final f = checkAcceptance(
      stations: s,
      fileBytes: 1,
      mustHave: const [],
      provinces: provinces,
    );
    expect(f.single.code, 'A2');
    expect(f.single.items, ['Cà Mau']);
  });

  test('A3: missing must-have, listed', () {
    final s = passing()..removeWhere((c) => c.id == 'osm:r1');
    final f = checkAcceptance(
      stations: s,
      fileBytes: 1,
      mustHave: mustHave,
      provinces: provinces,
    );
    expect(f.single.code, 'A3');
    expect(f.single.items.single, contains('my dinh'));
  });

  test('A3: match is a contiguous run in the core of name or alias', () {
    final s = [
      cand('osm:n1', 'Bến xe khách Trung tâm Thái Bình', province: 'Hưng Yên'),
      cand('osm:n2', 'Bến xe X', aliases: ['Bến xe Nước Ngầm']),
    ];
    MustHave m(String match, String province) =>
        MustHave(kind: StationKind.coach, match: match, province: province);
    expect(findMustHave(m('thai binh', 'Hưng Yên'), s)?.id, 'osm:n1');
    expect(findMustHave(m('tam binh', 'Hưng Yên'), s), isNull);
    expect(findMustHave(m('thai binh', 'Hà Nội'), s), isNull);
    expect(findMustHave(m('nuoc ngam', 'Hà Nội'), s)?.id, 'osm:n2');
    expect(
      findMustHave(
        const MustHave(
          kind: StationKind.train,
          match: 'nuoc ngam',
          province: 'Hà Nội',
        ),
        s,
      ),
      isNull,
    );
  });

  test('A3: waived entries are not required; dong hoi cannot be waived', () {
    final s = passing()..removeWhere((c) => c.id == 'osm:r1');
    final f = checkAcceptance(
      stations: s,
      fileBytes: 1,
      mustHave: const [
        MustHave(
          kind: StationKind.coach,
          match: 'my dinh',
          province: 'Hà Nội',
          waived: 'test',
        ),
      ],
      provinces: provinces,
    );
    expect(f, isEmpty);
    expect(
      () => parseMustHave(
        '[{"kind": "train", "match": "Đồng Hới", "province": "Quảng Trị", '
        '"waived": "x"}]',
        provinces,
      ),
      throwsA(isA<StationgenException>()),
    );
    expect(
      parseMustHave(
        '[{"kind": "coach", "match": "lac long", "province": "Hải Phòng", '
        '"waived": "not on OSM"}]',
        provinces,
      ).single.waived,
      'not on OSM',
    );
  });

  test('A4: duplicate id, coordinates outside, unknown province', () {
    expect(codes([...passing(), cand('osm:r1', 'Bến xe Khác')]), ['A4']);
    expect(codes([...passing(), cand('osm:n9', 'Ga Y', lat: 30)]), ['A4']);
    expect(codes([...passing(), cand('osm:n9', 'Bến xe Y', province: 'Lào')]), [
      'A4',
    ]);
  });

  test('A5: file larger than 800 KB, too many stations', () {
    expect(codes(passing(), bytes: kMaxFileBytes + 1), ['A5']);
    final many = [
      ...passing(),
      for (var i = 0; i < kMaxStations; i++) cand('osm:n${9000 + i}', 'B $i'),
    ];
    expect(codes(many), ['A5']);
  });
}
