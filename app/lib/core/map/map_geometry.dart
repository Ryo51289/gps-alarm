/// Pure camera geometry of the MapKit map (T23.3 §3.1): Vietnam bounds,
/// camera limits (D11), frame of a choice, layout of screen 2 (D9).
///
/// PRIVACY: nothing here logs.
library;

import 'dart:math' as math;

import 'package:napstop/core/map/map_wire.dart';

/// Mainland Vietnam and its coastal islands (Phú Quốc, Côn Đảo, Lý Sơn,
/// Bạch Long Vĩ). First frame of screen 2.
const MapBounds kVietnamBounds = MapBounds(
  south: 8.3,
  west: 102,
  north: 23.6,
  east: 109.7,
);

/// Where the camera CENTER may go at street level (D11 layer 3,
/// `cameraBoundary` limits the center only). The east edge reaches the
/// easternmost station (109.377°E, Khánh Hòa; MW05) so that every station
/// can be centered. Native lowers the east edge as the view widens (layer 2,
/// [centerEastLimit]).
const MapBounds kCameraCenterBounds = MapBounds(
  south: 8.3,
  west: 102,
  north: 23.6,
  east: 109.4,
);

/// D11 invariant: the east edge of the visible area never passes this
/// longitude (the two archipelagos lie east of ~111.1°E).
const double kVisibleEastLimitLng = 110.9;

/// D11 layer 1: widest visible longitude span; native recomputes the
/// largest camera distance from the measured span after every layout.
/// 2 × (110.9 − 106.5): wide enough for 102.1–109.5.
const double kMaxVisibleLngSpan = 8.8;

/// D11 layer 1: starting largest camera distance of screen 2, before the
/// first measure (native replaces it).
const double kMaxCameraDistanceM = 800000;

/// D11 layer 1: starting largest camera distance of the screen 4 card.
const double kMaxCardCameraDistanceM = 450000;

/// MI05/MM07 criterion: the measured east edge stays below this.
const double kIslandsWestLng = 111;

/// D11 layer 2: east limit of the camera center while the view spans
/// [visibleLngSpan] degrees of longitude:
/// `min(kCameraCenterBounds.east, kVisibleEastLimitLng − span / 2)`.
/// A span ≤ 0 or not finite gives `kCameraCenterBounds.east`. Same table as
/// the Swift `MapCameraGuard.centerEastLimit` (MW06b).
double centerEastLimit(double visibleLngSpan) {
  final cap = kCameraCenterBounds.east;
  if (!visibleLngSpan.isFinite || visibleLngSpan <= 0) {
    return cap;
  }
  return math.min(cap, kVisibleEastLimitLng - visibleLngSpan / 2);
}

/// Padding around a framed choice (= `kCameraPaddingPx` of T23).
const double kCameraPaddingPt = 48;

/// Radius framed when a choice has no alarm zone.
const double kDefaultFrameRadiusM = 1000;

/// Smallest height left between the top and bottom frame paddings.
const double kMinFrameSpanPt = 48;

const double _metersPerDegreeLat = 111320;

/// Bounding box (south-west, north-east) of a circle of [radiusM] around
/// [c] (T23 §5).
(MapPoint, MapPoint) circleBounds(MapPoint c, double radiusM) {
  final dLat = radiusM / _metersPerDegreeLat;
  final cosLat = math.cos(c.lat * math.pi / 180).abs();
  // Near the poles the box spans every longitude.
  final dLng = cosLat < 1e-6 ? 180.0 : radiusM / (_metersPerDegreeLat * cosLat);
  return (
    MapPoint(c.lat - dLat, c.lng - dLng),
    MapPoint(c.lat + dLat, c.lng + dLng),
  );
}

/// Frame of one choice: [circleBounds] of [point]; a null [radiusM] frames
/// [kDefaultFrameRadiusM].
MapBounds frameBounds(MapPoint point, double? radiusM) {
  final (sw, ne) = circleBounds(point, radiusM ?? kDefaultFrameRadiusM);
  return MapBounds(south: sw.lat, west: sw.lng, north: ne.lat, east: ne.lng);
}

/// Screen 2 (D9): height of the map from the top of the screen down to the
/// top of the panel at its lowest resting size [sheetMin], so the Apple
/// logo and the Legal link stay above the resting panel. [sheetAreaHeight]
/// is the area the panel's fractions refer to.
double destinationMapHeight({
  required double topInset,
  required double topBarHeight,
  required double sheetAreaHeight,
  required double sheetMin,
}) => topInset + topBarHeight + math.max(0, sheetAreaHeight) * (1 - sheetMin);

/// Screen 2: padding when framing a choice. Top: status bar, top bar and
/// zone badge, plus [kCameraPaddingPt]. Bottom: the part of the map the
/// panel covers (its top at [sheetTopY]) plus [kCameraPaddingPt], never so
/// much that less than [kMinFrameSpanPt] is left. Sides: [kCameraPaddingPt].
MapPadding destinationFramePadding({
  required double topInset,
  required double topBarHeight,
  required double badgeHeight,
  required double mapHeight,
  required double sheetTopY,
}) {
  final top = topInset + topBarHeight + badgeHeight + kCameraPaddingPt;
  final covered = math.max(0, mapHeight - sheetTopY);
  final room = math.max(0, mapHeight - top - kMinFrameSpanPt);
  final bottom = math.min(covered + kCameraPaddingPt, room).toDouble();
  return (
    top: math.min(top, kMaxWirePaddingPt),
    left: kCameraPaddingPt,
    bottom: math.min(bottom, kMaxWirePaddingPt),
    right: kCameraPaddingPt,
  );
}
