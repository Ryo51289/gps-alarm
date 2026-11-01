// TC09 (dedupe), TC10 (order independence), geo vectors.
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Latitude offset of [m] metres.
double north(double m) => m / kMetresPerDegLat;

List<Candidate> fixture() => [
  // Same station twice, 120 m apart; the way carries the main tag.
  cand(
    'osm:n100',
    'Bến xe khách Mỹ Đình',
    primary: false,
    lat: 21.02827 + north(120),
    lng: 105.77752,
    aliases: ['BX Mỹ Đình'],
  ),
  cand(
    'osm:w200',
    'Bến xe Mỹ Đình',
    typeRank: 1,
    lat: 21.02827,
    lng: 105.77752,
  ),
  // Same name, 50 km apart.
  cand('osm:n300', 'Bến xe phía Nam', lat: 16.4, lng: 107.6, province: 'Huế'),
  cand(
    'osm:n301',
    'Bến xe phía Nam',
    lat: 16.4 + north(50000),
    lng: 107.6,
    province: 'Quảng Trị',
  ),
  // Train and coach at the same place.
  cand(
    'osm:n400',
    'Ga Đồng Hới',
    kind: StationKind.train,
    lat: 17.46,
    lng: 106.6,
    province: 'Quảng Trị',
  ),
  cand(
    'osm:n401',
    'Bến xe Đồng Hới',
    lat: 17.46,
    lng: 106.6,
    province: 'Quảng Trị',
  ),
  // Different names, 100 m apart.
  cand('osm:n500', 'Bến xe Thủ Dầu Một', lat: 11, lng: 106.65),
  cand('osm:n501', 'Bến xe Bình Dương', lat: 11.0 + north(100), lng: 106.65),
];

String summary(DedupeResult r) {
  final kept = [...r.kept]..sort(compareStations);
  return [
    for (final s in kept)
      '${s.id}|${s.name}|${s.aliases.join(';')}|${s.mergedIds.join(';')}',
    for (final n in r.nearDuplicates)
      'near ${n.a.id} ${n.b.id} ${n.distanceM.round()}',
  ].join('\n');
}

void main() {
  test('merges duplicates, keeps distinct places (TC09)', () {
    final r = dedupe(fixture());
    final ids = r.kept.map((s) => s.id).toSet();
    expect(ids, {
      'osm:w200',
      'osm:n300',
      'osm:n301',
      'osm:n400',
      'osm:n401',
      'osm:n500',
      'osm:n501',
    });
    final md = r.kept.firstWhere((s) => s.id == 'osm:w200');
    expect(md.mergedIds, ['osm:n100']);
    expect(md.aliases, ['Bến xe khách Mỹ Đình', 'BX Mỹ Đình']);
    expect(r.nearDuplicates, hasLength(1));
    expect(r.nearDuplicates.single.a.id, 'osm:n500');
    expect(r.nearDuplicates.single.b.id, 'osm:n501');
    expect(r.nearDuplicates.single.distanceM.round(), 100);
  });

  test('radius: trains merge up to 500 m, coaches up to 300 m', () {
    final trains = dedupe([
      cand('osm:n1', 'Ga A', kind: StationKind.train, lat: 20),
      cand('osm:n2', 'A', kind: StationKind.train, lat: 20 + north(450))
        ..name = 'Ga A',
    ]);
    expect(trains.kept, hasLength(1));
    final coaches = dedupe([
      cand('osm:n1', 'Bến xe A', lat: 20),
      cand('osm:n2', 'Bến xe A', lat: 20 + north(350)),
    ]);
    expect(coaches.kept, hasLength(2));
  });

  test('input order does not matter (TC10)', () {
    final a = summary(dedupe(fixture()));
    final b = summary(dedupe(fixture().reversed.toList()));
    final shuffled = fixture()..shuffle();
    expect(b, a);
    expect(summary(dedupe(shuffled)), a);
  });

  test('distance vectors (copied geo)', () {
    expect(cosDeg(0), 1);
    expect(cosDeg(60), closeTo(0.5, 1e-12));
    // 1 degree of latitude on the mean sphere.
    expect(distanceM(20, 105, 21, 105), closeTo(111195.08, 0.01));
    // Hà Nội (Ga) → Đồng Hới (Ga), equirectangular.
    expect(
      distanceM(21.02436, 105.84118, 17.46892, 106.59973),
      closeTo(403287.7, 0.5),
    );
  });
}
