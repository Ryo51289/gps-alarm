/// SplitMix64 pseudo-random generator (spec T02 §5.1).
///
/// Pinned algorithm so output never depends on the SDK version. Relies on
/// the 64-bit wrap-around integers of the Dart VM; not usable on the web.
library;

// 0x9E3779B97F4A7C15, 0xBF58476D1CE4E5B9, 0x94D049BB133111EB built from
// 32-bit halves: a single literal >= 2^63 trips `avoid_js_rounded_ints`.
const int _golden = (0x9E3779B9 << 32) | 0x7F4A7C15;
const int _mix1 = (0xBF58476D << 32) | 0x1CE4E5B9;
const int _mix2 = (0x94D049BB << 32) | 0x133111EB;

/// 2^-53.
const double _unit = 1.0 / 9007199254740992.0;

/// Stream id of the motion jitter draws (seeded with `seed`).
const int kMotionStream = 1;

/// Stream id of the correlated noise draws (seeded with `noiseSeed`).
const int kNoiseStream = 2;

/// Stream id of the random outlier draws (seeded with `noiseSeed`).
const int kOutlierStream = 3;

final class SplitMix64 {
  new(int seed) : _state = seed;

  /// Independent stream [stream] derived from [seed].
  factory stream(int seed, int stream) => SplitMix64(seed ^ (stream * _golden));

  int _state;

  /// Next 64-bit value (two's complement; may be negative).
  int nextInt64() {
    _state = _state + _golden;
    var z = _state;
    z = (z ^ (z >>> 30)) * _mix1;
    z = (z ^ (z >>> 27)) * _mix2;
    return z ^ (z >>> 31);
  }

  /// Uniform double in `[0, 1)` with 53 random bits.
  double nextDouble() => (nextInt64() >>> 11).toDouble() * _unit;

  /// Approximately standard normal (Irwin–Hall with 12 terms), in `[-6, 6]`.
  double nextGaussian() {
    var sum = 0.0;
    for (var i = 0; i < 12; i++) {
      sum = sum + nextDouble();
    }
    return sum - 6.0;
  }
}
