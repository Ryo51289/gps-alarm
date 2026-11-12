// BS-G03, BS-G04 (mergeSides), near-same-name, coveringStation.
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

import 'bus_helpers.dart';
import 'helpers.dart';

const String _bk = 'Đại học Bách khoa';

void main() {
  test('distanceM vector (geo.dart, no transcendental functions)', () {
    expect(distanceM(21, 105.8, 21 + northM(150), 105.8), closeTo(150, 1e-6));
    // 0.001° of longitude at 21° N ≈ 103.8 m.
    expect(distanceM(21, 105.8, 21, 105.801), closeTo(103.8, 0.1));
  });

  group('mergeSides (BS-G03)', () {
    test('40 m and 120 m merge; 180 m stays apart', () {
      final stops = mergeSides([
        busCand('n1', _bk),
        busCand('n2', _bk, lat: 21 + northM(40)),
        busCand('n3', _bk, lat: 21 + northM(120), routes: ['03']),
        busCand('n4', _bk, lat: 21 - northM(180)),
      ]);
      expect(stops, hasLength(2));
      final merged = stops.firstWhere((s) => s.id == 'n1');
      expect(merged.members.map((m) => m.id), ['n1', 'n2', 'n3']);
      expect(merged.lat, round5((21 + 21 + northM(40) + 21 + northM(120)) / 3));
      expect(merged.lng, 105.8);
      expect(merged.routes, ['03']);
      expect(stops.firstWhere((s) => s.id == 'n4').members, hasLength(1));
    });

    test('A–B–C 100 m apart: A+B merge (seed A), C alone, no chaining', () {
      final stops = mergeSides([
        busCand('n30', _bk, lat: 21 + northM(200)),
        busCand('n20', _bk, lat: 21 + northM(100)),
        busCand('n10', _bk),
      ]);
      expect(
        [for (final s in stops) '${s.id}:${s.members.map((m) => m.id)}'],
        ['n10:(n10, n20)', 'n30:(n30)'],
      );
    });

    test(
      'seed is the smallest (node < way, number); routes union in order',
      () {
        final stops = mergeSides([
          busCand('w5', _bk, routes: ['14', '22']),
          busCand('n9', _bk, lat: 21 + northM(10), routes: ['03', '14']),
        ]);
        expect(stops.single.id, 'n9');
        expect(stops.single.routes, ['03', '14', '22']);
      },
    );
  });

  group('mergeSides (BS-G04)', () {
    test('same name with other case/diacritics merges', () {
      final stops = mergeSides([
        busCand('n1', _bk),
        busCand('n2', 'dai hoc BACH KHOA', lat: 21 + northM(60)),
      ]);
      expect(stops.single.name, _bk, reason: 'name of the seed');
    });

    test('other province does not merge', () {
      final stops = mergeSides([
        busCand('n1', _bk),
        busCand('n2', _bk, province: 'TP. Hồ Chí Minh', lat: 21 + northM(10)),
      ]);
      expect(stops, hasLength(2));
    });

    test('different name does not merge', () {
      final stops = mergeSides([
        busCand('n1', _bk),
        busCand('n2', 'Đối diện $_bk', lat: 21 + northM(10)),
      ]);
      expect(stops, hasLength(2));
    });

    test('input order does not matter', () {
      List<String> run(List<BusCandidate> c) => [
        for (final s in mergeSides(c))
          '${s.id} ${s.lat} ${s.members.map((m) => m.id)}',
      ]..sort();
      List<BusCandidate> input() => [
        busCand('n1', _bk),
        busCand('n2', _bk, lat: 21 + northM(100)),
        busCand('n3', _bk, lat: 21 + northM(200)),
        busCand('w4', 'Kim Mã', lat: 21.1),
        busCand('n5', 'Kim Mã', lat: 21.1 + northM(20)),
      ];
      expect(run(input().reversed.toList()), run(input()));
    });
  });

  test('findNearSameName: 150–300 m pairs only', () {
    final pairs = findNearSameName([
      busStop('n1', _bk),
      busStop('n2', _bk, lat: 21 + northM(200)),
      busStop('n3', _bk, lat: 21 + northM(600)),
      busStop('n4', 'Kim Mã', lat: 21 + northM(160)),
    ]);
    expect(pairs.map((p) => '${p.a.id}-${p.b.id}'), ['n1-n2']);
    expect(pairs.single.distanceM, closeTo(200, 1e-6));
  });

  group('coveringStation (BS-G05)', () {
    final myDinh = cand(
      'osm:w1',
      'Bến xe Mỹ Đình',
      lat: 21.02827,
      lng: 105.77752,
    );
    final train = cand(
      'osm:n2',
      'Ga Hà Nội',
      kind: StationKind.train,
      lat: 21.0245,
      lng: 105.8412,
    );

    test('same core name within 100 m', () {
      expect(
        coveringStation(
          busCand(
            'n1',
            'Bến xe Mỹ Đình',
            lat: 21.02827 + northM(90),
            lng: 105.77752,
          ),
          [myDinh],
        ),
        same(myDinh),
      );
      expect(
        coveringStation(
          busCand('n1', 'Mỹ Đình', lat: 21.02827 + northM(50), lng: 105.77752),
          [myDinh],
        ),
        same(myDinh),
        reason: 'core key drops the kind prefix',
      );
    });

    test('500 m away, other name, or a train station: kept', () {
      expect(
        coveringStation(
          busCand(
            'n1',
            'Bến xe Mỹ Đình',
            lat: 21.02827 + northM(500),
            lng: 105.77752,
          ),
          [myDinh],
        ),
        isNull,
      );
      expect(
        coveringStation(
          busCand('n1', 'Sân vận động Mỹ Đình', lat: 21.02827, lng: 105.77752),
          [myDinh],
        ),
        isNull,
      );
      expect(
        coveringStation(
          busCand('n1', 'Ga Hà Nội', lat: 21.0245, lng: 105.8412),
          [train],
        ),
        isNull,
      );
    });
  });
}
