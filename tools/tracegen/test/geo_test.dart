import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:tracegen/tracegen.dart';

double haversineM(LatLng a, LatLng b) {
  const r = 6371008.8;
  final p1 = a.lat * math.pi / 180;
  final p2 = b.lat * math.pi / 180;
  final dp = p2 - p1;
  final dl = (b.lng - a.lng) * math.pi / 180;
  final h =
      math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.sqrt(h));
}

void main() {
  group('cosDeg (TC04)', () {
    test('matches dart:math cos on [-90, 90] to 1e-15', () {
      for (var i = -9000; i <= 9000; i++) {
        final x = i / 100;
        final diff = (cosDeg(x) - math.cos(x * math.pi / 180)).abs();
        expect(diff, lessThanOrEqualTo(1e-15), reason: 'x = $x');
      }
    });

    test('rejects angles outside [-90, 90]', () {
      expect(() => cosDeg(90.0001), throwsArgumentError);
      expect(() => cosDeg(-90.0001), throwsArgumentError);
      expect(() => cosDeg(double.nan), throwsArgumentError);
    });
  });

  group('distanceM (TC05)', () {
    const haNoi = LatLng(21.0242144, 105.8410943);
    const dongHoi = LatLng(17.4689199, 106.5997285);

    test('Ga Ha Noi - Ga Dong Hoi within 0.1 % of haversine', () {
      final d = distanceM(haNoi, dongHoi);
      final h = haversineM(haNoi, dongHoi);
      expect((d - h).abs() / h, lessThanOrEqualTo(0.001));
    });

    test('pairs <= 50 km within 0.01 % of haversine', () {
      final rng = SplitMix64(7);
      var checked = 0;
      while (checked < 20) {
        final a = LatLng(8 + 15 * rng.nextDouble(), 103 + 6 * rng.nextDouble());
        final b = offsetM(
          a,
          70000 * (rng.nextDouble() - 0.5),
          70000 * (rng.nextDouble() - 0.5),
        );
        final h = haversineM(a, b);
        if (h > 50000 || h < 100 || b.lat > 23) {
          continue;
        }
        checked++;
        final d = distanceM(a, b);
        expect((d - h).abs() / h, lessThanOrEqualTo(0.0001), reason: '$a $b');
      }
    });

    test('same point is 0 m and order does not matter', () {
      expect(distanceM(haNoi, haNoi), 0);
      expect(distanceM(haNoi, dongHoi), distanceM(dongHoi, haNoi));
    });
  });

  group('Polyline and offsetM (TC06)', () {
    const p0 = LatLng(20, 105);
    final p1 = offsetM(p0, 0, 1000);
    final p2 = offsetM(p1, 500, 0);
    final line = Polyline([p0, p1, p2]);

    void expectNear(LatLng a, LatLng b) {
      expect((a.lat - b.lat).abs(), lessThanOrEqualTo(1e-9));
      expect((a.lng - b.lng).abs(), lessThanOrEqualTo(1e-9));
    }

    test('length is the sum of the segments', () {
      expect(line.cumulativeM.first, 0);
      expect(line.lengthM, distanceM(p0, p1) + distanceM(p1, p2));
    });

    test('pointAt hits the vertices', () {
      expectNear(line.pointAt(0), p0);
      expectNear(line.pointAt(line.cumulativeM[1]), p1);
      expectNear(line.pointAt(line.lengthM), p2);
    });

    test('pointAt rejects s outside [0, L]', () {
      expect(() => line.pointAt(-1), throwsArgumentError);
      expect(() => line.pointAt(line.lengthM + 1), throwsArgumentError);
    });

    test('rejects degenerate input', () {
      expect(() => Polyline([p0]), throwsArgumentError);
      expect(() => Polyline([p0, offsetM(p0, 0.5, 0)]), throwsArgumentError);
    });

    test('offsetM moves the requested distance', () {
      final q = offsetM(p0, 100, 0);
      expect(distanceM(p0, q), closeTo(100, 0.01));
    });
  });
}
