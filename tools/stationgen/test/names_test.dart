// TC04 (names), TC05 (core tokens).
import 'package:stationgen/stationgen.dart';
import 'package:test/test.dart';

void main() {
  group('namesOf (TC04)', () {
    test('train without Ga prefix gets one', () {
      final n = namesOf({'name': 'Đồng Hới'}, StationKind.train);
      expect(n.name, 'Ga Đồng Hới');
      expect(n.aliases, isEmpty);
    });

    test('train already named Ga / Nhà ga keeps the name', () {
      expect(namesOf({'name': 'Ga Vinh'}, StationKind.train).name, 'Ga Vinh');
      expect(
        namesOf({'name': 'Nhà ga Hà Nội'}, StationKind.train).name,
        'Nhà ga Hà Nội',
      );
    });

    test('coach is not prefixed; spaces collapsed', () {
      expect(
        namesOf({'name': ' Bến  xe   Mỹ Đình '}, StationKind.coach).name,
        'Bến xe Mỹ Đình',
      );
    });

    test('name:vi wins, differing name becomes an alias', () {
      final n = namesOf({
        'name': 'Hanoi Station',
        'name:vi': 'Ga Hà Nội',
      }, StationKind.train);
      expect(n.name, 'Ga Hà Nội');
      expect(n.aliases, ['Hanoi Station']);
    });

    test('alt_name split on ;, duplicates dropped', () {
      final n = namesOf({
        'name': 'Bến xe X',
        'alt_name': 'A;B;A',
      }, StationKind.coach);
      expect(n.aliases, ['A', 'B']);
    });

    test('alias equal to the name after folding is dropped', () {
      final n = namesOf({
        'name': 'Bến xe Đồng Hới',
        'alt_name': 'Ben xe Dong Hoi;BẾN XE ĐỒNG HỚI',
      }, StationKind.coach);
      expect(n.aliases, isEmpty);
    });

    test('at most 5 aliases, source order kept', () {
      final n = namesOf({
        'name': 'Bến xe X',
        'alt_name': 'A1;A2;A3',
        'old_name': 'O1;O2',
        'official_name': 'F',
        'short_name': 'S',
        'name:en': 'English',
      }, StationKind.coach);
      expect(n.aliases, ['A1', 'A2', 'A3', 'O1', 'O2']);
    });

    test('official_name and short_name are used, name:en is not', () {
      final n = namesOf({
        'name': 'Bến xe X',
        'official_name': 'Bến xe khách X',
        'short_name': 'BX X',
        'name:en': 'X Bus Station',
      }, StationKind.coach);
      expect(n.aliases, ['Bến xe khách X', 'BX X']);
    });
  });

  group('coreTokens (TC05)', () {
    test('examples of the spec', () {
      expect(coreTokens('Bến xe khách Trung tâm Thái Bình'), [
        'trung',
        'tam',
        'thai',
        'binh',
      ]);
      expect(coreTokens('Nhà ga Hà Nội'), ['ha', 'noi']);
      expect(coreTokens('Ga'), ['ga']);
      expect(coreTokens('Bến xe buýt Long Biên'), ['long', 'bien']);
      expect(coreTokens('Ga Đồng Hới'), ['dong', 'hoi']);
    });

    test('keeps at least one token', () {
      expect(coreTokens('Bến xe khách'), ['khach']);
      expect(coreTokens('Bến xe'), ['ben', 'xe']);
    });
  });

  test('containsTokenRun', () {
    expect(
      containsTokenRun(['trung', 'tam', 'thai', 'binh'], ['thai', 'binh']),
      isTrue,
    );
    expect(
      containsTokenRun(['trung', 'tam', 'thai', 'binh'], ['tam', 'binh']),
      isFalse,
    );
  });
}
