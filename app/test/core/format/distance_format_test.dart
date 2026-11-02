// U13: formatDistanceShort.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/format/distance_format.dart';

void main() {
  test('U13 meters below 1 km', () {
    expect(formatDistanceShort(200, 'vi'), '200 m');
    expect(formatDistanceShort(999, 'vi'), '999 m');
    expect(formatDistanceShort(0, 'en'), '0 m');
  });

  test('U13 kilometers, one decimal at most, locale separator', () {
    expect(formatDistanceShort(1000, 'vi'), '1 km');
    expect(formatDistanceShort(1250, 'vi'), '1,3 km');
    expect(formatDistanceShort(1500, 'vi'), '1,5 km');
    expect(formatDistanceShort(1500, 'en'), '1.5 km');
    expect(formatDistanceShort(10000, 'vi'), '10 km');
    expect(formatDistanceShort(10000, 'en'), '10 km');
    expect(formatDistanceShort(1949, 'en'), '1.9 km');
    expect(formatDistanceShort(1950, 'en'), '2 km');
  });
}
