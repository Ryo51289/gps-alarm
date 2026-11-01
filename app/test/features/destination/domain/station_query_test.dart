// TC21: query parsing.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';

void main() {
  test('kind prefix is removed and becomes a hint', () {
    final q = parseStationQuery('ga dong hoi');
    expect(q.tokens, ['dong', 'hoi']);
    expect(q.kindHint, StationKind.train);

    final c = parseStationQuery('Bến xe Mỹ Đình');
    expect(c.tokens, ['my', 'dinh']);
    expect(c.kindHint, StationKind.coach);

    final b = parseStationQuery('ben xe buyt kim ma');
    expect(b.tokens, ['kim', 'ma']);
    expect(b.kindHint, StationKind.bus);
  });

  test('a prefix alone stays a token, without hint', () {
    final q = parseStationQuery('Ga');
    expect(q.tokens, ['ga']);
    expect(q.kindHint, isNull);
  });

  test('blank query', () {
    final q = parseStationQuery('   ');
    expect(q.tokens, isEmpty);
    expect(q.kindHint, isNull);
  });

  test('input is cut to 64 runes', () {
    final long = 'a' * 100;
    final q = parseStationQuery(long);
    expect(q.tokens.single.length, kMaxQueryLength);
    // Runes, not UTF-16 code units: 70 × "đ" keeps 64 letters.
    expect(parseStationQuery('đ' * 70).tokens.single, 'd' * 64);
  });

  test('stationCoreTokens', () {
    expect(stationCoreTokens('Bến xe khách Trung tâm Thái Bình'), [
      'trung',
      'tam',
      'thai',
      'binh',
    ]);
    expect(stationCoreTokens('Nhà ga Hà Nội'), ['ha', 'noi']);
    expect(stationCoreTokens('Ga'), ['ga']);
    expect(stationCoreTokens('Bến xe buýt Long Biên'), ['long', 'bien']);
  });
}
