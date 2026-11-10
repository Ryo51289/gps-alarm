// T23.5 AS-D01..AS-D05: pure logic of the address search.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

AddressSuggestion _s(String t, [String s = '']) =>
    AddressSuggestion(title: t, subtitle: s);

void main() {
  test('AS-D01 shouldSearchAddresses', () {
    bool go(String q, [DestinationFilter f = DestinationFilter.all]) =>
        shouldSearchAddresses(query: q, filter: f);
    expect(go('ab'), isFalse);
    expect(go('abc'), isTrue);
    expect(go('a b c'), isTrue);
    expect(go('  Hà  '), isFalse);
    expect(go('abc', DestinationFilter.train), isFalse);
    expect(go('abc', DestinationFilter.coach), isFalse);
  });

  test('AS-D02 isBlockedSuggestion', () {
    expect(isBlockedSuggestion(_s('Tam Sa', 'Hải Nam, Trung Quốc')), isTrue);
    expect(isBlockedSuggestion(_s('Xisha Islands')), isTrue);
    expect(isBlockedSuggestion(_s('三沙市')), isTrue);
    expect(isBlockedSuggestion(_s('Đường Hoàng Sa', 'Đà Nẵng')), isFalse);
    expect(isBlockedSuggestion(_s('Trường Sa', 'Phú Nhuận, TP HCM')), isFalse);
    expect(isBlockedSuggestion(_s('Quần đảo Hoàng Sa')), isFalse);
    // "trung" and "quoc" apart are not the token sequence.
    expect(isBlockedSuggestion(_s('Trung tâm', 'Quốc lộ 1')), isFalse);
  });

  test('AS-D03 visibleSuggestions', () {
    final rows = visibleSuggestions([
      _s('A', 'x'),
      _s('  '),
      _s('Nanjing', 'China'),
      _s('Đường B', 'y'),
      _s('duong b', 'Y'),
      _s('C'),
      _s('D'),
      _s('E'),
    ]);
    expect(rows.map((r) => r.nativeIndex), [0, 3, 5, 6, 7]);
    final many = visibleSuggestions([for (var i = 0; i < 9; i++) _s('T$i')]);
    expect(many.length, kAddressDisplayLimit);
  });

  test('AS-D04 isSupportedDestination', () {
    expect(
      isSupportedDestination(const MapPoint(21.03, 105.85), country: 'VN'),
      isTrue,
    );
    expect(isSupportedDestination(const MapPoint(21.03, 105.85)), isTrue);
    expect(isSupportedDestination(const MapPoint(8.68, 106.61)), isTrue);
    expect(isSupportedDestination(const MapPoint(10.22, 103.96)), isTrue);
    expect(isSupportedDestination(const MapPoint(16.5, 111.6)), isFalse);
    expect(
      isSupportedDestination(const MapPoint(22.82, 108.32), country: 'CN'),
      isFalse,
    );
    expect(
      isSupportedDestination(const MapPoint(21, 105), country: 'LA'),
      isFalse,
    );
  });

  test('AS-D05 addressDestination', () {
    const p = MapPoint(21.03, 105.85);
    final long = '${'a' * 198}😀${'b' * 50}';
    final d = addressDestination(_s('  $long  '), p);
    expect(d.name.length, lessThanOrEqualTo(kMaxDestinationNameLength));
    final last = d.name.codeUnitAt(d.name.length - 1);
    expect(last, isNot(inInclusiveRange(0xD800, 0xDBFF)));
    expect(d.detail, isNull);
    expect(d.kind, DestinationKind.address);
    expect(d.isValid, isTrue);
    final t = addressDestination(_s(' Phố X ', ' Hà Nội '), p);
    expect(t.name, 'Phố X');
    expect(t.detail, 'Hà Nội');
  });

  test('AS-D08 toString prints no text', () {
    expect(_s('Bí mật', 'Kín').toString(), isNot(contains('Bí')));
  });
}
