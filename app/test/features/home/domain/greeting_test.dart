// U10: greeting boundaries.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/home/domain/greeting.dart';

void main() {
  test('U10 greetingFor boundaries', () {
    DateTime at(int h, int m) => DateTime(2026, 11, 2, h, m);
    final cases = <(DateTime, Greeting)>[
      (at(4, 59), Greeting.evening),
      (at(5, 0), Greeting.morning),
      (at(10, 59), Greeting.morning),
      (at(11, 0), Greeting.noon),
      (at(12, 59), Greeting.noon),
      (at(13, 0), Greeting.afternoon),
      (at(17, 59), Greeting.afternoon),
      (at(18, 0), Greeting.evening),
      (at(0, 0), Greeting.evening),
      (at(23, 59), Greeting.evening),
    ];
    for (final (time, expected) in cases) {
      expect(greetingFor(time), expected, reason: '$time');
    }
  });
}
