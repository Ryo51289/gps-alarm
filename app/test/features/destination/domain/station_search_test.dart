// TC22–TC29: ranking of the offline station search.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

Station st(
  String id,
  String name, {
  StationKind kind = StationKind.bus,
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

void main() {
  test('tiers and scores for "dong hoi" (TC22)', () {
    final index = StationSearchIndex([
      st('fuzzy', 'Dũng Hới'),
      st('substring', 'Xdong Hới'),
      st('province', 'Đồng Tâm', province: 'Hội An'),
      st('any', 'Hới Đồng'),
      st('ordered', 'Đồng Xuân Hới'),
      st('prefix', 'Đồng Hới Bắc'),
      st('exact', 'Đồng Hới'),
      st('none', 'Vinh'),
    ]);
    final r = index.search('dong hoi');
    expect(ids(r), [
      'exact',
      'prefix',
      'ordered',
      'any',
      'province',
      'substring',
      'fuzzy',
    ]);
    expect([for (final m in r) m.tier], StationMatchTier.values);
    expect([for (final m in r) m.score], [1000, 900, 700, 600, 500, 300, 150]);
    expect(index.length, 8);
  });

  test('prefix match while typing the last token', () {
    final index = StationSearchIndex([st('a', 'Đồng Hới')]);
    expect(index.search('dong h').single.tier, StationMatchTier.prefix);
  });

  group('kind (TC23)', () {
    final index = StationSearchIndex([
      st('coach', 'Bến xe Đồng Hới', kind: StationKind.coach),
      st('train', 'Ga Đồng Hới', kind: StationKind.train),
    ]);

    test('train first on a tie', () {
      final r = index.search('dong hoi');
      expect(ids(r), ['train', 'coach']);
      expect(r[0].score, r[1].score);
    });

    test('"ben xe" hint puts the coach station first', () {
      final r = index.search('ben xe dong hoi');
      expect(ids(r), ['coach', 'train']);
      expect(r[0].score, 1150);
    });

    test('"ga" hint', () {
      expect(index.search('ga dong hoi').first.score, 1150);
    });
  });

  group('typos (TC24)', () {
    final index = StationSearchIndex([
      st('md', 'Bến xe Mỹ Đình', kind: StationKind.coach),
      st('nt', 'Ga Nha Trang', kind: StationKind.train),
      st('dh', 'Ga Đồng Hới', kind: StationKind.train),
    ]);

    test('transposition, 1 edit', () {
      final r = index.search('my dihn');
      expect(ids(r), ['md']);
      expect(r.single.tier, StationMatchTier.fuzzy);
      expect(r.single.score, 150);
    });

    test('nha trnag', () {
      final r = index.search('nha trnag');
      expect(ids(r), ['nt']);
      expect(r.single.tier, StationMatchTier.fuzzy);
    });

    test('3-letter tokens are not corrected', () {
      expect(index.search('dong hio'), isEmpty);
    });

    test('first letter must match', () {
      expect(index.search('xy dinh'), isEmpty);
      expect(index.search('my xinh'), isEmpty);
    });

    test('8+ letters allow 2 edits', () {
      final long = StationSearchIndex([st('x', 'Bến xe Phương Trang')]);
      expect(ids(long.search('phuongtrnga')), isEmpty);
      final idx = StationSearchIndex([st('x', 'Bến xe Thanhphohue')]);
      expect(idx.search('thanhpohuee').single.score, 100);
    });
  });

  test('case, NFD and spaces do not matter (TC25)', () {
    final index = StationSearchIndex([
      st('a', 'Ga Đồng Hới', kind: StationKind.train),
      st('b', 'Bến xe Đồng Hới', kind: StationKind.coach),
      st('c', 'Đồng Hới Bắc'),
    ]);
    final base = index.search('dong hoi').toString();
    for (final q in [
      'ĐỒNG HỚI',
      'Đồng Hới',
      'Đồng Hới',
      'dong   hoi',
      '  dong-hoi ',
    ]) {
      expect(index.search(q).toString(), base, reason: q);
    }
  });

  test('tie-break: key length, then nameAscii, then id (TC26)', () {
    final index = StationSearchIndex([
      st('z2', 'Bến xe An B'),
      st('z1', 'Bến xe An B'),
      st('y', 'Bến xe An A'),
      st('long', 'Bến xe An Long'),
    ]);
    expect(ids(index.search('an')), ['y', 'z1', 'z2', 'long']);
  });

  group('limits and duplicates (TC27)', () {
    final index = StationSearchIndex([
      for (var i = 1; i <= 30; i++) st('s$i', 'Bến xe A$i'),
      st('km', 'Bến xe Kim Mã', aliases: ['Kim Mã', 'Điểm Kim Mã']),
    ]);

    test('empty query', () {
      expect(index.search(''), isEmpty);
      expect(index.search('  -- '), isEmpty);
    });

    test('limit', () {
      expect(index.search('a', limit: 3), hasLength(3));
      expect(index.search('a'), hasLength(kDefaultSearchLimit));
    });

    test('a station matching by name and alias appears once', () {
      final r = index.search('kim ma');
      expect(ids(r), ['km']);
      expect(r.single.viaAlias, isFalse);
      expect(r.single.score, 1000);
    });
  });

  test('alias match (TC28)', () {
    final index = StationSearchIndex([
      st('hn', 'Ga Hà Nội', kind: StationKind.train, aliases: ['Ga Hàng Cỏ']),
    ]);
    final r = index.search('hang co').single;
    expect(r.viaAlias, isTrue);
    expect(r.tier, StationMatchTier.exact);
    expect(r.score, 1000 - 25);
  });

  test('province helps, but name must match (TC29)', () {
    final index = StationSearchIndex([
      st('md', 'Bến xe Mỹ Đình', kind: StationKind.coach),
      st('hn', 'Ga Hà Nội', kind: StationKind.train),
    ]);
    final a = index.search('my dinh ha noi');
    expect(ids(a), ['md']);
    expect(a.single.tier, StationMatchTier.provinceAssisted);
    final b = index.search('ha noi');
    expect(ids(b), ['hn']);
    expect(b.single.tier, StationMatchTier.exact);
  });

  group('osaDistance', () {
    test('values', () {
      expect(osaDistance('abc', 'abc', max: 2), 0);
      expect(osaDistance('dihn', 'dinh', max: 1), 1);
      expect(osaDistance('ca', 'ac', max: 1), 1);
      expect(osaDistance('trnag', 'trang', max: 1), 1);
      expect(osaDistance('kitten', 'sitting', max: 3), 3);
      expect(osaDistance('', 'ab', max: 2), 2);
    });

    test('returns max + 1 when exceeded', () {
      expect(osaDistance('kitten', 'sitting', max: 2), 3);
      expect(osaDistance('a', 'abcd', max: 1), 2);
      expect(osaDistance('abcd', 'wxyz', max: 1), 2);
    });
  });
}
