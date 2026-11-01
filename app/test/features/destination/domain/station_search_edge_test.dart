// Tester additions for T24 (outside the spec TC list): typo tolerance at the
// token-length boundaries 3/4/7/8, kind tie-break, kind hint, empty and
// whitespace queries, very long queries (64-rune cut), NFD queries.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/text/vn_fold.dart';
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

void main() {
  group('typo tolerance boundaries (maxEdits: <4 → 0, 4–7 → 1, ≥8 → 2)', () {
    // Single-token keys so that only the fuzzy tier can match.
    final index = StationSearchIndex([
      st('k3', 'Bến xe Hoà'), // hoa (3)
      st('k4', 'Bến xe Dinh'), // dinh (4)
      st('k7', 'Bến xe Abcdefg'), // abcdefg (7)
      st('k8', 'Bến xe Mnopqrst'), // mnopqrst (8)
    ]);

    test('3 letters: no correction', () {
      expect(index.search('hoz'), isEmpty);
      expect(index.search('hao'), isEmpty, reason: 'swap, but 3 letters');
    });

    test('4 letters: 1 edit yes, 2 edits no', () {
      final r = index.search('dihn');
      expect(ids(r), ['k4']);
      expect(r.single.tier, StationMatchTier.fuzzy);
      expect(r.single.score, 150);
      expect(index.search('dixx'), isEmpty);
    });

    test('7 letters: 1 edit yes, 2 edits no', () {
      expect(index.search('abcdefx').single.score, 150);
      expect(index.search('abcdexx'), isEmpty);
    });

    test('8 letters: 2 edits yes, 3 edits no', () {
      expect(index.search('mnopqrsx').single.score, 150);
      final two = index.search('mnopqrxx').single;
      expect(two.station.id, 'k8');
      expect(two.score, 100);
      expect(index.search('mnopqxxx'), isEmpty);
    });

    test('a typo in a half-typed token matches against the key prefix', () {
      final idx = StationSearchIndex([st('pt', 'Bến xe Phương')]);
      // "phyo" vs prefix "phuo": 1 edit at 4 letters.
      expect(idx.search('phyo').single.score, 150);
      // 3 letters: never corrected, even as a prefix.
      expect(idx.search('phy'), isEmpty);
    });

    test('errors add up across tokens', () {
      final idx = StationSearchIndex([st('pt', 'Bến xe Phương Trang')]);
      final r = idx.search('phuogn trnag').single;
      expect(r.tier, StationMatchTier.fuzzy);
      expect(r.score, 200 - 50 * 2);
    });
  });

  group('kind priority', () {
    test('equal score: train < coach < bus whatever the input order', () {
      final stations = [
        st('b', 'Đồng Hới', kind: StationKind.bus),
        st('c', 'Bến xe Đồng Hới'),
        st('t', 'Ga Đồng Hới', kind: StationKind.train),
      ];
      for (final order in [
        stations,
        stations.reversed.toList(),
        [stations[1], stations[2], stations[0]],
      ]) {
        final r = StationSearchIndex(order).search('dong hoi');
        expect(ids(r), ['t', 'c', 'b']);
        expect(r.map((m) => m.score).toSet(), {1000});
      }
    });

    test('kind beats key length, nameAscii and id on equal score', () {
      final r = StationSearchIndex([
        st('a-bus', 'Đồng Ý', kind: StationKind.bus), // key "dong y"
        st('z-train', 'Ga Đồng Hới Bắc Mới', kind: StationKind.train),
      ]).search('dong');
      expect(r.map((m) => m.tier).toSet(), {StationMatchTier.prefix});
      expect(ids(r), ['z-train', 'a-bus']);
    });

    test('a higher score wins over kind', () {
      final r = StationSearchIndex([
        st('t', 'Ga Đồng Hới Bắc', kind: StationKind.train), // prefix 900
        st('b', 'Đồng Hới', kind: StationKind.bus), // exact 1000
      ]).search('dong hoi');
      expect(ids(r), ['b', 't']);
    });

    test('"bến xe buýt" hint puts the bus station first', () {
      final index = StationSearchIndex([
        st('t', 'Ga Long Biên', kind: StationKind.train),
        st('b', 'Bến xe buýt Long Biên', kind: StationKind.bus),
      ]);
      expect(ids(index.search('long bien')), ['t', 'b']);
      final r = index.search('ben xe buyt long bien');
      expect(ids(r), ['b', 't']);
      expect(r.first.score, 1150);
      expect(ids(index.search('Điểm trung chuyển Long Biên')), ['b', 't']);
    });
  });

  group('empty, blank and odd queries', () {
    final index = StationSearchIndex([
      st('a', 'Bến xe Mỹ Đình'),
      st('g', 'Ga', kind: StationKind.train),
    ]);

    test('nothing to search → []', () {
      for (final q in [
        '',
        ' ',
        '   ',
        '\t\n\r',
        ' 　', // no-break and ideographic spaces
        '!!!',
        '— … ·',
        '😀😀',
        '́̀', // combining marks only
      ]) {
        expect(parseStationQuery(q).tokens, isEmpty, reason: q);
        expect(index.search(q), isEmpty, reason: q);
      }
    });

    test('limit 0 or negative → []', () {
      expect(index.search('my dinh', limit: 0), isEmpty);
      expect(index.search('my dinh', limit: -1), isEmpty);
    });

    test('a kind word alone stays a token (no hint)', () {
      final q = parseStationQuery('Bến xe');
      expect(q.tokens, ['ben', 'xe']);
      expect(q.kindHint, isNull);
      expect(ids(index.search('Ga')), ['g']);
    });
  });

  group('long queries (kMaxQueryLength = 64 runes)', () {
    final index = StationSearchIndex([
      st('dh', 'Ga Đồng Hới', kind: StationKind.train),
    ]);

    test('exactly 64 runes are kept', () {
      final q = '${' ' * 56}dong hoi';
      expect(q.runes.length, kMaxQueryLength);
      expect(index.search(q).single.tier, StationMatchTier.exact);
    });

    test('the 65th rune is cut', () {
      final q = '${' ' * 57}dong hoi';
      expect(q.runes.length, kMaxQueryLength + 1);
      // "dong ho" is left: still found, as a prefix.
      expect(index.search(q).single.tier, StationMatchTier.prefix);
    });

    test('garbage after 64 runes is ignored', () {
      final q = 'dong hoi${' ' * 60}zzzz qqqq';
      expect(index.search(q).single.tier, StationMatchTier.exact);
    });

    test('10 000 characters do not throw', () {
      expect(index.search('a' * 10000), isEmpty);
      expect(index.search('dong ' * 2000), isEmpty);
      expect(parseStationQuery('đ' * 10000).tokens.single, 'd' * 64);
    });

    test('the cut does not split a surrogate pair', () {
      final q = '😀' * 100;
      expect(q.runes.length, 100);
      expect(parseStationQuery(q).tokens, isEmpty);
      expect(index.search('${'😀' * 70}dong hoi'), isEmpty);
    });
  });

  group('NFC / NFD', () {
    final index = StationSearchIndex([
      st('dh', 'Ga Đồng Hới', kind: StationKind.train),
      st('md', 'Bến xe Mỹ Đình'),
    ]);

    test('NFD and upper-case NFD queries equal the plain query', () {
      const nfdLower = 'Đồng Hới';
      const nfdUpper = 'ĐỒNG HỚI';
      final base = index.search('dong hoi').toString();
      expect(index.search(nfdLower).toString(), base);
      expect(index.search(nfdUpper).toString(), base);
    });

    test('NFD kind prefix gives the same hint', () {
      const nfd = 'Bến xe khách Mỹ Đình';
      final q = parseStationQuery(nfd);
      expect(q.tokens, ['my', 'dinh']);
      expect(q.kindHint, StationKind.coach);
      expect(index.search(nfd).single.score, 1150);
    });

    test('a station stored in NFD is found by an NFC query', () {
      const nfdName = 'Bến xe khách Ninh Bình';
      final idx = StationSearchIndex([st('nb', nfdName)]);
      final r = idx.search('Bến xe khách Ninh Bình').single;
      expect(r.tier, StationMatchTier.exact);
      expect(r.score, 1150);
    });
  });
}
