// Tester additions for T24 on the real assets/stations.json: acceptance
// queries beyond TC33, must-have entries reachable by search, every
// station findable by its own name (NFC, NFD, upper case) and aliases,
// ranking independent of dataset order.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// Precomposed Vietnamese vowels → base letter (+ vowel mark) + tone mark,
/// i.e. NFD. Tones in the order grave, acute, hook, tilde, dot below.
const Map<String, String> _bases = {
  'a': 'a',
  'ă': 'ă',
  'â': 'â',
  'e': 'e',
  'ê': 'ê',
  'i': 'i',
  'o': 'o',
  'ô': 'ô',
  'ơ': 'ơ',
  'u': 'u',
  'ư': 'ư',
  'y': 'y',
};
const Map<String, String> _toned = {
  'a': 'àáảãạ',
  'ă': 'ằắẳẵặ',
  'â': 'ầấẩẫậ',
  'e': 'èéẻẽẹ',
  'ê': 'ềếểễệ',
  'i': 'ìíỉĩị',
  'o': 'òóỏõọ',
  'ô': 'ồốổỗộ',
  'ơ': 'ờớởỡợ',
  'u': 'ùúủũụ',
  'ư': 'ừứửữự',
  'y': 'ỳýỷỹỵ',
};
const List<String> _tones = ['̀', '́', '̉', '̃', '̣'];

final Map<String, String> _nfd = () {
  final m = <String, String>{};
  void put(String composed, String decomposed) {
    m[composed] = decomposed;
    m[composed.toUpperCase()] =
        decomposed[0].toUpperCase() + decomposed.substring(1);
  }

  for (final MapEntry(key: base, value: letters) in _toned.entries) {
    if (base != _bases[base]) {
      put(base, _bases[base]!);
    }
    for (var i = 0; i < 5; i++) {
      put(letters[i], _bases[base]! + _tones[i]);
    }
  }
  return m;
}();

String toNfd(String s) => s.split('').map((c) => _nfd[c] ?? c).join();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StationDataset dataset;
  late StationSearchIndex index;

  setUpAll(() async {
    final text = await rootBundle.loadString(kStationsAssetKey, cache: false);
    dataset = decodeStationsJson(text);
    index = StationSearchIndex(dataset.stations);
  });

  Station top(String q) => index.search(q).first.station;

  test('NFD helper decomposes all 132 marked letters (đ has no NFD form)', () {
    expect(_nfd, hasLength(2 * (12 * 5 + 6)));
    for (final MapEntry(:key, :value) in _nfd.entries) {
      expect(foldVi(value), foldVi(key), reason: key);
      expect(value.runes.any((r) => r >= 0x300 && r <= 0x36F), isTrue);
    }
  });

  group('acceptance queries', () {
    void expectTop(
      String q,
      String name,
      StationKind kind,
      String province, {
      int score = 1000,
    }) {
      final m = index.search(q).first;
      expect(m.station.name, name, reason: q);
      expect(m.station.kind, kind, reason: q);
      expect(m.station.province, province, reason: q);
      expect(m.score, score, reason: q);
      expect(m.tier, StationMatchTier.exact, reason: q);
    }

    test('first result', () {
      expectTop('dong hoi', 'Ga Đồng Hới', StationKind.train, 'Quảng Trị');
      expectTop('my dinh', 'Bến xe Mỹ Đình', StationKind.coach, 'Hà Nội');
      expectTop('giap bat', 'Ga Giáp Bát', StationKind.train, 'Hà Nội');
      expectTop(
        'ga ha noi',
        'Ga Hà Nội',
        StationKind.train,
        'Hà Nội',
        score: 1150,
      );
      expectTop('hue', 'Ga Huế', StationKind.train, 'Huế');
      expectTop('da nang', 'Ga Đà Nẵng', StationKind.train, 'Đà Nẵng');
      expectTop('sai gon', 'Ga Sài Gòn', StationKind.train, 'TP. Hồ Chí Minh');
      expectTop('nha trang', 'Ga Nha Trang', StationKind.train, 'Khánh Hòa');
      expectTop('vinh', 'Ga Vinh', StationKind.train, 'Nghệ An');
      expectTop('quy nhon', 'Ga Quy Nhơn', StationKind.train, 'Gia Lai');
      expectTop('sa pa', 'Bến xe khách Sa Pa', StationKind.coach, 'Lào Cai');
    });

    test('kind hint picks the other station of the same name', () {
      expectTop(
        'ben xe giap bat',
        'Bến xe Giáp Bát',
        StationKind.coach,
        'Hà Nội',
        score: 1150,
      );
      expectTop(
        'Bến xe Mỹ Đình',
        'Bến xe Mỹ Đình',
        StationKind.coach,
        'Hà Nội',
        score: 1150,
      );
      expectTop(
        'ben xe quy nhon',
        'Bến xe khách Quy Nhơn',
        StationKind.coach,
        'Gia Lai',
        score: 1150,
      );
      expectTop(
        'ga vinh',
        'Ga Vinh',
        StationKind.train,
        'Nghệ An',
        score: 1150,
      );
    });

    test('second results: the coach station of the city is close by', () {
      List<Station> head(String q, int n) =>
          index.search(q).take(n).map((m) => m.station).toList();
      bool hasCoach(List<Station> s, String province) =>
          s.any((x) => x.kind == StationKind.coach && x.province == province);
      expect(head('giap bat', 2)[1].name, 'Bến xe Giáp Bát');
      expect(head('quy nhon', 2)[1].name, 'Bến xe khách Quy Nhơn');
      expect(hasCoach(head('sai gon', 2), 'TP. Hồ Chí Minh'), isTrue);
      expect(hasCoach(head('da nang', 3), 'Đà Nẵng'), isTrue);
      expect(hasCoach(head('nha trang', 3), 'Khánh Hòa'), isTrue);
    });

    test('typos on real names', () {
      expect(top('my dihn').name, 'Bến xe Mỹ Đình');
      expect(top('nha trnag').name, 'Ga Nha Trang');
      expect(top('MỸ ĐÌNH').name, 'Bến xe Mỹ Đình');
    });
  });

  test('every non-waived must-have entry is reachable by search', () {
    final entries = (jsonDecode(
      File('../data/stations/must_have.json').readAsStringSync(),
    ) as List).cast<Map<String, Object?>>();
    var checked = 0;
    for (final e in entries) {
      if (e['waived'] != null) {
        continue;
      }
      final r = index.search(e['match']! as String);
      final hit = r.indexWhere(
        (m) =>
            m.station.kind.name == e['kind'] &&
            m.station.province == e['province'],
      );
      expect(hit, greaterThanOrEqualTo(0), reason: '$e');
      checked++;
      if (e['kind'] == 'train') {
        expect(hit, 0, reason: 'a must-have train station ranks first: $e');
      }
    }
    expect(checked, 35 + 18);
  });

  test('every station is found by its own name: NFC, NFD, upper case', () {
    for (final s in dataset.stations) {
      for (final q in [s.name, toNfd(s.name), s.name.toUpperCase()]) {
        final hit = index
            .search(q, limit: dataset.stations.length)
            .where((m) => m.station.id == s.id);
        expect(hit, isNotEmpty, reason: '${s.id} "$q"');
        expect(hit.first.score, greaterThanOrEqualTo(1000), reason: s.id);
        expect(hit.first.viaAlias, isFalse, reason: s.id);
      }
      expect(foldVi(toNfd(s.name)), s.nameAscii, reason: s.id);
    }
  });

  test('every alias finds its station', () {
    for (final s in dataset.stations) {
      for (final a in s.aliases) {
        final hit = index
            .search(a, limit: dataset.stations.length)
            .where((m) => m.station.id == s.id);
        expect(hit, isNotEmpty, reason: '${s.id} alias "$a"');
        expect(hit.first.tier, StationMatchTier.exact, reason: s.id);
      }
    }
  });

  test('ranking does not depend on the order of the dataset', () {
    final shuffled = [...dataset.stations]..shuffle(Random(20261101));
    final other = StationSearchIndex(shuffled);
    for (final q in [
      'dong hoi',
      'my dinh',
      'giap bat',
      'ha noi',
      'vinh',
      'phia nam',
      'nha trnag',
      'x',
      'ben xe',
      'sai gon',
      'mien dong',
      'hue',
    ]) {
      expect(
        other.search(q, limit: 100).toString(),
        index.search(q, limit: 100).toString(),
        reason: q,
      );
    }
  });
}
