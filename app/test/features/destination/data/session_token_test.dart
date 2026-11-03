// T23 TP10: session tokens are RFC 4122 UUID v4 and do not repeat.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/data/places/session_token.dart';

void main() {
  test('TP10 1000 tokens: UUID v4 format, all different', () {
    final rng = Random(1);
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final tokens = {for (var i = 0; i < 1000; i++) newSessionToken(rng)};
    expect(tokens, hasLength(1000));
    for (final t in tokens) {
      expect(pattern.hasMatch(t), isTrue, reason: t);
    }
  });

  test('version and variant bits whatever the random bytes', () {
    final zeros = newSessionToken(_Fixed(0));
    final ones = newSessionToken(_Fixed(255));
    expect(zeros, '00000000-0000-4000-8000-000000000000');
    expect(ones, 'ffffffff-ffff-4fff-bfff-ffffffffffff');
  });
}

/// Returns [value] for every byte.
class _Fixed implements Random {
  new(this.value);

  final int value;

  @override
  int nextInt(int max) => value;

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}
