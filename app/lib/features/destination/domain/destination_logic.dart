/// Pure logic of screen 2 "Chọn điểm đến" (T23 §5, §10): filters, result
/// rows, pin moves, camera bounds. No Flutter, no map SDK.
///
/// PRIVACY: nothing here logs, and no `toString` prints a name, a query or
/// coordinates.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

/// Filter chips of screen 2: "Tất cả / Ga tàu / Bến xe / Địa chỉ".
enum DestinationFilter { all, train, coach, places }

/// A WGS84 point. The map widget converts it to and from the SDK type.
@immutable
final class MapPoint {
  const new(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is MapPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  /// PRIVACY: no coordinates.
  @override
  String toString() => 'MapPoint';
}

/// Letters/digits needed before the offline search runs (after [foldVi],
/// spaces removed).
const int kMinOfflineQueryChars = 2;

/// Letters/digits needed before a Places request.
const int kMinPlacesQueryChars = 3;

/// Most station rows shown.
const int kDisplayLimit = 20;

/// Results fetched before the chip filter keeps a kind.
const int kSearchOverfetch = 60;

const Duration kPlacesDebounce = Duration(milliseconds: 350);
const Duration kDistanceDebounce = Duration(milliseconds: 150);

/// Oldest cached position used for "cách X km".
const int kLastKnownMaxAgeMs = 30 * 60 * 1000;

/// No new distance request this long after the native side had none.
const Duration kDistanceRetryAfter = Duration(seconds: 30);

/// Alarm zone previewed on the map: PRD §4 default distance (1 km, also the
/// 1 km mark of the smart mode). Screen 3 sets the real one.
const double kPreviewRadiusM = 1000;

/// A pin moved at most this far keeps the station/address identity.
const double kPinKeepIdentityM = 500;

/// Places input is cut to this many runes.
const int kMaxPlacesInputRunes = 100;

/// Padding (logical px) around the alarm zone when the camera frames it.
const double kCameraPaddingPx = 48;

/// Letters and digits of [raw] after folding, spaces removed.
int queryChars(String raw) => foldVi(raw).replaceAll(' ', '').length;

/// Offline rows for [filter]: `all` without a kind hint, `train` with the
/// train hint keeping trains only, `coach` with the coach hint keeping coach
/// and bus stations, `places` none. At most [kDisplayLimit]; a query shorter
/// than [kMinOfflineQueryChars] gives none.
List<StationMatch> offlineResults(
  StationSearchIndex index,
  String query,
  DestinationFilter filter,
) {
  if (queryChars(query) < kMinOfflineQueryChars) {
    return const [];
  }
  final rows = switch (filter) {
    DestinationFilter.all => index.search(query, limit: kSearchOverfetch),
    DestinationFilter.train =>
      index
          .search(query, limit: kSearchOverfetch, kindHint: StationKind.train)
          .where((m) => m.station.kind == StationKind.train),
    DestinationFilter.coach =>
      index
          .search(query, limit: kSearchOverfetch, kindHint: StationKind.coach)
          .where((m) => m.station.kind != StationKind.train),
    DestinationFilter.places => const <StationMatch>[],
  };
  return List.unmodifiable(rows.take(kDisplayLimit));
}

/// The chosen destination of screen 2.
///
/// [anchor] is where it was chosen (station, address or pin drop); pin moves
/// are measured from it. [anchorName] is the name shown in "Cách {place}".
@immutable
final class Selection {
  const new({
    required this.destination,
    required this.source,
    required this.anchor,
    required this.anchorName,
  });

  final TripDestination destination;
  final DestinationSource source;
  final MapPoint anchor;
  final String anchorName;

  /// Where the pin is now.
  MapPoint get point => MapPoint(destination.lat, destination.lng);

  @override
  bool operator ==(Object other) =>
      other is Selection &&
      other.destination == destination &&
      other.source == source &&
      other.anchor == anchor &&
      other.anchorName == anchorName;

  @override
  int get hashCode => Object.hash(destination, source, anchor, anchorName);

  /// PRIVACY: no name, no coordinates.
  @override
  String toString() => 'Selection(${destination.kind.name}, ${source.name})';
}

/// The destination after the pin was dragged from [anchor] to [to].
///
/// A station or address moved at most [kPinKeepIdentityM] keeps its name,
/// kind, detail and source with the new coordinates. Farther, it becomes a
/// pin named [pinnedName] with `pinnedDetail(current.name, meters)` as
/// detail. A pin stays a pin (detail null).
({TripDestination destination, DestinationSource source}) afterPinMove({
  required TripDestination current,
  required DestinationSource currentSource,
  required MapPoint anchor,
  required MapPoint to,
  required String pinnedName,
  required String Function(String place, double meters) pinnedDetail,
}) {
  if (current.kind == DestinationKind.pin) {
    return (
      destination: TripDestination(
        name: pinnedName,
        lat: to.lat,
        lng: to.lng,
        kind: DestinationKind.pin,
      ),
      source: DestinationSource.mapPin,
    );
  }
  final meters = distanceM(anchor, to);
  if (meters <= kPinKeepIdentityM) {
    return (
      destination: TripDestination(
        name: current.name,
        lat: to.lat,
        lng: to.lng,
        kind: current.kind,
        detail: current.detail,
      ),
      source: currentSource,
    );
  }
  return (
    destination: TripDestination(
      name: pinnedName,
      lat: to.lat,
      lng: to.lng,
      kind: DestinationKind.pin,
      detail: pinnedDetail(current.name, meters),
    ),
    source: DestinationSource.mapPin,
  );
}

const double _metersPerDegreeLat = 111320;

/// Bounding box (south-west, north-east) of a circle of [radiusM] around
/// [c], for `CameraUpdate.newLatLngBounds`.
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

/// Mean Earth radius (IUGG), metres.
const double _earthRadiusM = 6371008.8;

/// Great-circle distance in metres (haversine).
double distanceM(MapPoint a, MapPoint b) {
  double rad(double deg) => deg * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(h)));
}
