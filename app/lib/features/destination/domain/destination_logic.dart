/// Pure logic of screen 2 "Chọn điểm đến" (T23 §5, §10): filters, result
/// rows, pin moves, camera bounds. No Flutter, no map SDK.
///
/// PRIVACY: nothing here logs, and no `toString` prints a name, a query or
/// coordinates.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:napstop/core/map/map_point.dart';
import 'package:napstop/core/text/vn_fold.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_search.dart';

// T23.3: MapPoint and circleBounds moved to lib/core/map (the map widget
// lives there); re-exported so screen 2 keeps its imports.
export 'package:napstop/core/map/map_geometry.dart' show circleBounds;
export 'package:napstop/core/map/map_point.dart';

/// Filter chips of screen 2: "Tất cả / Ga tàu / Bến xe" (T23.2 D2).
enum DestinationFilter { all, train, coach }

/// Letters/digits needed before the offline search runs (after [foldVi],
/// spaces removed).
const int kMinOfflineQueryChars = 2;

/// Most station rows shown.
const int kDisplayLimit = 20;

/// Results fetched before the chip filter keeps a kind.
const int kSearchOverfetch = 60;

/// Wait after the last change of the rows before measuring "cách X km".
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

/// Padding (logical px) around the alarm zone when the camera frames it.
const double kCameraPaddingPx = 48;

/// Letters and digits of [raw] after folding, spaces removed.
int queryChars(String raw) => foldVi(raw).replaceAll(' ', '').length;

/// Offline rows for [filter]: `all` without a kind hint, `train` with the
/// train hint keeping trains only, `coach` with the coach hint keeping coach
/// and bus stations. At most [kDisplayLimit]; a query shorter
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
