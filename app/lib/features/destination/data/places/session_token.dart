/// Places session tokens (T23 D6). Pure Dart.
library;

import 'dart:math';

/// A random UUID version 4 (RFC 4122), lower case `8-4-4-4-12`. The app
/// passes `Random.secure()`; tests pass a seeded [Random].
String newSessionToken(Random rng) {
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
