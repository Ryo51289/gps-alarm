import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

void main() {
  group('SplitMix64 (TC03)', () {
    test('matches the reference vectors for seed 0', () {
      final rng = SplitMix64(0);
      // https://prng.di.unimi.it/splitmix64.c, checked with BigInt.
      final hex = [
        for (var i = 0; i < 3; i++)
          BigInt.from(rng.nextInt64())
              .toUnsigned(64)
              .toRadixString(16)
              .padLeft(16, '0'),
      ];
      expect(hex, ['e220a8397b1dcdaf', '6e789e6aa1b965f4', '06c45d188009454f']);
    });

    test('nextDouble stays in [0, 1)', () {
      final rng = SplitMix64(42);
      for (var i = 0; i < 100000; i++) {
        final d = rng.nextDouble();
        expect(d >= 0 && d < 1, isTrue, reason: 'draw $i = $d');
      }
    });

    test('nextGaussian is approximately standard normal', () {
      final rng = SplitMix64(42);
      const n = 100000;
      var sum = 0.0;
      var sumSq = 0.0;
      for (var i = 0; i < n; i++) {
        final g = rng.nextGaussian();
        expect(g >= -6 && g <= 6, isTrue);
        sum += g;
        sumSq += g * g;
      }
      final mean = sum / n;
      final variance = sumSq / n - mean * mean;
      expect(mean.abs(), lessThan(0.02));
      expect(variance, inInclusiveRange(0.97, 1.03));
    });

    test('streams differ, same seed repeats', () {
      final a = SplitMix64.stream(42, 1);
      final b = SplitMix64.stream(42, 2);
      expect(a.nextInt64(), isNot(b.nextInt64()));

      final x = SplitMix64.stream(42, 1);
      final y = SplitMix64.stream(42, 1);
      for (var i = 0; i < 1000; i++) {
        expect(x.nextInt64(), y.nextInt64());
      }
    });
  });
}
