// T23 TS01–TS18: search changes on top of T24 (joined words, "bến xe
// <city>", kind hint parameter, fuzzy cut at 4 edits).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

Station st(
  String id,
  String name, {
  StationKind kind = StationKind.coach,
  String province = 'Hà Nội',
  List<String> aliases = const [],
}) => Station(
  id: id,
  name: name,
  nameAscii: foldVi(name),
  kind: kind,
  province: province,
  lat: 21,
  lng: 105.8,
  aliases: aliases,
);

List<String> ids(List<StationMatch> m) => [for (final x in m) x.station.id];
List<int> scores(List<StationMatch> m) => [for (final x in m) x.score];

List<StationMatch> run(
  StationSearchIndex index,
  String q, {
  StationKind? hint,
}) => index.search(q, kindHint: hint);

/// Stations and queries of TS01–TS15, for TS16 (independent of test order).
final List<Station> _allStations = [
  st('hn', 'Ga Hà Nội', kind: StationKind.train),
  st('sapa', 'Bến xe khách Sa Pa', province: 'Lào Cai'),
  st('joined', 'Hà Nội'),
  st('word', 'Hanoi'),
  st('bac-vinh', 'Bến xe Bắc Vinh', province: 'Nghệ An'),
  st('vinh-bao', 'Bến xe Vĩnh Bảo', province: 'Hải Phòng'),
  st('ga-vinh', 'Ga Vinh', kind: StationKind.train, province: 'Nghệ An'),
  st('ga-dh', 'Ga Đông Hà', kind: StationKind.train, province: 'Quảng Trị'),
  st('bx-dh', 'Bến xe Đông Hà', province: 'Quảng Trị'),
  st('phia-bac', 'Bến xe phía Bắc', province: 'Huế'),
  st('duc-hue', 'Bến xe khách Đức Huệ', province: 'Tây Ninh'),
  st('ga-hue', 'Ga Huế', kind: StationKind.train, province: 'Huế'),
  st('mien-tay', 'Bến xe Miền Tây', province: 'TP. Hồ Chí Minh'),
  st('a', 'Bến xe Xdonghoi'),
  st('x', 'Ga Dong', kind: StationKind.train),
  st('train', 'Ga Đồng Hới', kind: StationKind.train),
  st('coach', 'Bến xe Đồng Hới'),
  st('f', 'Bến xe Thanhphoxa Huexyzabc Longbien'),
  st('my-dinh', 'Bến xe Mỹ Đình'),
  st('kim-ma', 'Bến xe Kim Mã'),
];

const List<String> _allQueries = [
  'hanoi',
  'HANOI',
  'HàNội',
  'Hà Nội',
  'sapa',
  'hano',
  'han',
  'ha noi',
  'ben xe vinh',
  'vinh',
  'ga ha',
  'ben xe ha',
  'ben xe hue',
  'hue',
  'ben xe ho chi minh',
  'ben xe hochiminh',
  'ben xe tp ho chi minh',
  'ben xe ho chi',
  'ben xe dong',
  'dong hoi',
  'ga dong hoi',
  'thanhxxoxa huexxxabc lonxxien',
  'thanhxxoxa huexxxabc',
  'thanhxxoxa huexyxabc',
  'ben xe ha noi',
  'ben xe hanoi',
];

void main() {
  final gaHaNoi = st('hn', 'Ga Hà Nội', kind: StationKind.train);
  final sapa = st('sapa', 'Bến xe khách Sa Pa', province: 'Lào Cai');

  test('TS01 words typed together match exactly (990)', () {
    final index = StationSearchIndex([gaHaNoi, sapa]);
    for (final q in ['hanoi', 'HANOI', 'Hà Nội'.replaceAll(' ', '')]) {
      final r = run(index, q);
      expect(ids(r).first, 'hn', reason: q);
      expect(r.first.score, 990, reason: q);
      expect(r.first.tier, StationMatchTier.exact, reason: q);
    }
    expect(run(index, 'Hà Nội').first.score, 1000);
    final s = run(index, 'sapa');
    expect(ids(s), ['sapa']);
    expect(s.single.score, 990);
  });

  test('TS02 compact prefix needs 4 letters', () {
    final index = StationSearchIndex([gaHaNoi]);
    final hano = run(index, 'hano');
    expect(hano.single.tier, StationMatchTier.prefix);
    expect(hano.single.score, 890);
    expect(run(index, 'han'), isEmpty);
    expect(run(index, 'ha noi').single.score, 1000);
  });

  test('TS03 spaced exact beats joined exact', () {
    final index = StationSearchIndex([
      st('joined', 'Hà Nội'),
      st('word', 'Hanoi'),
    ]);
    final r = run(index, 'hanoi');
    expect(ids(r), ['word', 'joined']);
    expect(scores(r), [1000, 990]);
  });

  group('"bến xe <city>"', () {
    final index = StationSearchIndex([
      st('bac-vinh', 'Bến xe Bắc Vinh', province: 'Nghệ An'),
      st('vinh-bao', 'Bến xe Vĩnh Bảo', province: 'Hải Phòng'),
      st('ga-vinh', 'Ga Vinh', kind: StationKind.train, province: 'Nghệ An'),
    ]);

    test('TS04 coach stations of the city before the train station', () {
      final r = run(index, 'ben xe vinh');
      expect(ids(r), ['bac-vinh', 'vinh-bao', 'ga-vinh']);
      expect(scores(r), [1100, 1050, 1000]);
      expect(r.first.tier, StationMatchTier.orderedTokens);
    });

    test('TS05 without a hint the T24 order stays', () {
      final r = run(index, 'vinh');
      expect(ids(r), ['ga-vinh', 'vinh-bao', 'bac-vinh']);
      expect(scores(r), [1000, 900, 700]);
    });
  });

  test('TS06 stripLeadingQualifiers removes every leading qualifier', () {
    List<String>? strip(String name) =>
        stripLeadingQualifiers(stationCoreTokens(name));
    expect(strip('Bến xe liên tỉnh phía Nam Nha Trang'), ['nha', 'trang']);
    expect(strip('Bến xe phía Đông Thành phố Vinh'), ['vinh']);
    expect(strip('Bến xe khách Trung tâm Thái Bình'), ['thai', 'binh']);
    expect(strip('Bến xe Trung tâm tp.Cần Thơ'), ['can', 'tho']);
    expect(strip('Bến xe Bắc Vinh'), ['vinh']);
  });

  test('TS07 never strips down to nothing', () {
    expect(
      stripLeadingQualifiers(stationCoreTokens('Bến xe phía Nam')),
      isNull,
    );
    expect(
      stripLeadingQualifiers(stationCoreTokens('Bến xe Trung tâm')),
      isNull,
    );
    expect(stripLeadingQualifiers(stationCoreTokens('Bến xe Mỹ Đình')), isNull);
  });

  test('TS08 no qualified match for trains or 2-letter queries', () {
    final index = StationSearchIndex([
      st('ga', 'Ga Đông Hà', kind: StationKind.train, province: 'Quảng Trị'),
      st('bx', 'Bến xe Đông Hà', province: 'Quảng Trị'),
    ]);
    for (final m in [...run(index, 'ga ha'), ...run(index, 'ben xe ha')]) {
      expect(m.score, isNot(anyOf(950, 1100)), reason: m.toString());
    }
    // The coach qualified key is [ha]: "ha" has 2 letters only.
    expect(
      run(
        index,
        'ben xe ha',
      ).where((m) => m.station.id == 'bx').map((m) => m.score),
      isNot(contains(1100)),
    );
  });

  group('province name with a hint', () {
    final index = StationSearchIndex([
      st('phia-bac', 'Bến xe phía Bắc', province: 'Huế'),
      st('duc-hue', 'Bến xe khách Đức Huệ', province: 'Tây Ninh'),
      st('ga-hue', 'Ga Huế', kind: StationKind.train, province: 'Huế'),
    ]);

    test('TS09 "ben xe hue": coach stations of Huế first', () {
      final r = run(index, 'ben xe hue');
      expect(ids(r), ['phia-bac', 'duc-hue', 'ga-hue']);
      expect(scores(r), [950, 850, 1000]);
      expect(r.first.tier, StationMatchTier.provinceAssisted);
    });

    test('TS10 "hue" without a hint: as T24', () {
      final r = run(index, 'hue');
      expect(ids(r), ['ga-hue', 'duc-hue']);
      expect(scores(r), [1000, 700]);
    });
  });

  test('TS11 province core, joined and full name; no prefix', () {
    final index = StationSearchIndex([
      st('mien-tay', 'Bến xe Miền Tây', province: 'TP. Hồ Chí Minh'),
    ]);
    for (final q in [
      'ben xe ho chi minh',
      'ben xe hochiminh',
      'ben xe tp ho chi minh',
    ]) {
      final r = run(index, q);
      expect(scores(r), [950], reason: q);
      expect(r.single.tier, StationMatchTier.provinceAssisted, reason: q);
    }
    expect(run(index, 'ben xe ho chi'), isEmpty);
  });

  test('TS12 substring and fuzzy matches do not jump ahead with a hint', () {
    final index = StationSearchIndex([
      st('a', 'Bến xe Xdonghoi'),
      st('x', 'Ga Dong', kind: StationKind.train),
    ]);
    // Coach "xdonghoi" only contains "dong"; the train is an exact match.
    final r = run(index, 'ben xe dong');
    expect(ids(r), ['x', 'a']);
    expect(r.last.tier, StationMatchTier.substring);
  });

  test('TS13 kindHint parameter; a prefix in the query wins', () {
    final index = StationSearchIndex([
      st('train', 'Ga Đồng Hới', kind: StationKind.train),
      st('coach', 'Bến xe Đồng Hới'),
    ]);
    final r = run(index, 'dong hoi', hint: StationKind.coach);
    expect(ids(r), ['coach', 'train']);
    expect(r.first.score, 1150);
    expect(ids(run(index, 'ga dong hoi', hint: StationKind.coach)), [
      'train',
      'coach',
    ]);
    expect(ids(run(index, 'dong hoi')), ['train', 'coach']);
  });

  test('TS14 without kindHint the 12 T24 order queries are unchanged', () {
    final catalog = buildStationCatalog(
      File('assets/stations.json').readAsStringSync(),
    );
    final baseline = jsonDecode(
      File('test/features/destination/fixtures/t24_search_baseline.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(baseline, hasLength(12));
    for (final MapEntry(key: q, value: expected) in baseline.entries) {
      expect(
        catalog.index.search(q, limit: 100).toString(),
        expected,
        reason: q,
      );
    }
  });

  test('TS15 fuzzy: 3 edits score 50, 4 or more do not match', () {
    final index = StationSearchIndex([
      st('f', 'Bến xe Thanhphoxa Huexyzabc Longbien'),
    ]);
    // Three tokens of 8+ letters, 2 substitutions each: E = 6.
    expect(run(index, 'thanhxxoxa huexxxabc lonxxien'), isEmpty);
    // E = 4: two tokens with 2 substitutions.
    expect(run(index, 'thanhxxoxa huexxxabc'), isEmpty);
    // E = 3: 2 + 1.
    final three = run(index, 'thanhxxoxa huexyxabc');
    expect(three.single.tier, StationMatchTier.fuzzy);
    expect(three.single.score, 50);
  });

  test('TS16 every result scores above 0', () {
    final index = StationSearchIndex(_allStations);
    var results = 0;
    for (final hint in [null, ...StationKind.values]) {
      for (final q in _allQueries) {
        for (final m in index.search(q, kindHint: hint, limit: 100)) {
          expect(m.score, greaterThan(0), reason: '$q $hint $m');
          results++;
        }
      }
    }
    expect(results, greaterThan(50));
  });

  test('TS17 provinceCoreTokens', () {
    expect(provinceCoreTokens('TP. Hồ Chí Minh'), ['ho', 'chi', 'minh']);
    expect(provinceCoreTokens('Thành phố Huế'), ['hue']);
    expect(provinceCoreTokens('Tỉnh Quảng Trị'), ['quang', 'tri']);
    expect(provinceCoreTokens('Huế'), ['hue']);
    expect(provinceCoreTokens('Tỉnh'), ['tinh']);
  });

  test('TS18 "ben xe ha noi": stations of Hà Nội before Ga Hà Nội', () {
    final index = StationSearchIndex([
      st('my-dinh', 'Bến xe Mỹ Đình'),
      st('kim-ma', 'Bến xe Kim Mã'),
      gaHaNoi,
    ]);
    for (final q in ['ben xe ha noi', 'ben xe hanoi']) {
      final r = run(index, q);
      expect(ids(r), ['kim-ma', 'my-dinh', 'hn'], reason: q);
      expect(scores(r).take(2), [950, 950], reason: q);
    }
  });
}
