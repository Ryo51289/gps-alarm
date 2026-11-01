/// Distances without `dart:math` transcendental functions, so threshold
/// decisions are identical on every platform (spec T24 §4.5, T02 D2).
///
/// Copied (not imported) from `tools/tracegen/lib/src/geo.dart`.
library;

import 'dart:math' show sqrt;

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
/// Horner form.
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

/// Equirectangular distance in metres (cosine at the mid-latitude).
double distanceM(double lat1, double lng1, double lat2, double lng2) {
  final kx = kMetresPerDegLat * cosDeg((lat1 + lat2) / 2);
  final dx = (lng2 - lng1) * kx;
  final dy = (lat2 - lat1) * kMetresPerDegLat;
  return sqrt(dx * dx + dy * dy);
}
