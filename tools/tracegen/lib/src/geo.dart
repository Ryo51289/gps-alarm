/// Geometry built only from IEEE-754 basic operations (spec T02 §2 D2, §5.2).
library;

import 'dart:math' show sqrt;

final class LatLng {
  const new(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  String toString() => 'LatLng($lat, $lng)';
}

/// Mean Earth radius (IUGG), metres.
const double kEarthRadiusM = 6371008.8;

/// Degrees to radians, using a literal pi (not `math.pi`).
const double kDegToRad = 3.141592653589793 / 180;

/// Metres per degree of latitude on the mean sphere.
const double kMetresPerDegLat = kEarthRadiusM * kDegToRad;

const List<double> _cosDenominators = [
  462,
  380,
  306,
  240,
  182,
  132,
  90,
  56,
  30,
  12,
  2,
];

/// Cosine of an angle in degrees, `|degrees| <= 90`, by a Taylor series in
/// Horner form (no libm, so results are identical on every platform).
double cosDeg(double degrees) {
  if (!(degrees >= -90 && degrees <= 90)) {
    throw ArgumentError.value(degrees, 'degrees', 'must be in [-90, 90]');
  }
  final x = degrees * kDegToRad;
  final y = x * x;
  var r = 1.0;
  for (final den in _cosDenominators) {
    r = 1.0 - y / den * r;
  }
  return r;
}

/// Equirectangular distance in metres (cosine taken at the mid-latitude).
double distanceM(LatLng a, LatLng b) {
  final kx = kMetresPerDegLat * cosDeg((a.lat + b.lat) / 2);
  final dx = (b.lng - a.lng) * kx;
  final dy = (b.lat - a.lat) * kMetresPerDegLat;
  return sqrt(dx * dx + dy * dy);
}

/// Point [eastM] metres east and [northM] metres north of [p].
LatLng offsetM(LatLng p, double eastM, double northM) => LatLng(
  p.lat + northM / kMetresPerDegLat,
  p.lng + eastM / (kMetresPerDegLat * cosDeg(p.lat)),
);

/// Local east/north metres of [p] relative to [origin] (cosine at origin).
(double, double) localEnM(LatLng origin, LatLng p) => (
  (p.lng - origin.lng) * (kMetresPerDegLat * cosDeg(origin.lat)),
  (p.lat - origin.lat) * kMetresPerDegLat,
);

/// Piecewise linear route through [points] (lat/lng interpolation).
final class Polyline {
  /// Requires >= 2 points, consecutive points >= 1 m apart.
  factory(List<LatLng> points) {
    final segments = _segments(points);
    final cum = <double>[0];
    for (final d in segments) {
      cum.add(cum.last + d);
    }
    return Polyline._(
      List.unmodifiable(points),
      List.unmodifiable(segments),
      List.unmodifiable(cum),
    );
  }

  new _(this.points, this._segmentM, this.cumulativeM);

  final List<LatLng> points;

  final List<double> _segmentM;

  /// Distance along the line to each point; `cumulativeM[0] == 0`.
  final List<double> cumulativeM;

  double get lengthM => cumulativeM.last;

  static List<double> _segments(List<LatLng> points) {
    if (points.length < 2) {
      throw ArgumentError.value(points.length, 'points', 'need >= 2 points');
    }
    final seg = <double>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final d = distanceM(points[i], points[i + 1]);
      if (!(d >= 1)) {
        throw ArgumentError.value(
          d,
          'points',
          'points $i and ${i + 1} are less than 1 m apart',
        );
      }
      seg.add(d);
    }
    return seg;
  }

  /// Point at distance [s] along the line, `0 <= s <= lengthM`.
  LatLng pointAt(double s) {
    if (!(s >= 0 && s <= lengthM)) {
      throw ArgumentError.value(s, 's', 'must be in [0, $lengthM]');
    }
    // Largest i in [0, n - 2] with cumulativeM[i] <= s.
    var lo = 0;
    var hi = points.length - 2;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (cumulativeM[mid] <= s) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    final i = lo;
    final a = points[i];
    final b = points[i + 1];
    final f = (s - cumulativeM[i]) / _segmentM[i];
    return LatLng(a.lat + f * (b.lat - a.lat), a.lng + f * (b.lng - a.lng));
  }
}
