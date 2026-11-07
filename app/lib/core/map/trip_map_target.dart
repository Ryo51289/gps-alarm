import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/map/map_point.dart';
import 'package:napstop/core/map/map_wire.dart' show kMaxWireRadiusM;
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';

/// What the screen 4 map card shows for a trip (T23.3 §3.4).
typedef TripMapTarget = ({MapPoint destination, double? radiusM});

/// The destination of [record], and the zone radius in distance mode only
/// (null when outside `(0, kMaxWireRadiusM]`).
/// Null when the row has no valid destination (no map button then).
TripMapTarget? tripMapTargetOf(TripRecord record) {
  final d = record.destination;
  if (!d.isValid) {
    return null;
  }
  final alarm = record.alarm;
  final threshold = alarm.mode == AlarmModeMsg.distance
      ? alarm.distanceThresholdM?.toDouble()
      : null;
  // Outside the wire range native would drop the whole state (no pin):
  // keep the pin, drop the circle.
  final radius =
      threshold != null && threshold > 0 && threshold <= kMaxWireRadiusM
      ? threshold
      : null;
  return (destination: MapPoint(d.lat, d.lng), radiusM: radius);
}

/// Reads the trip row once (the bridge carries no coordinates, T14 D5;
/// same read as screen 8, T27 D7). Null when there is no row or it cannot
/// be read: the map is optional. Read only, never writes history (T26 D15).
///
/// PRIVACY: never logs the row.
Future<TripMapTarget?> readTripMapTarget(
  TripsRepository trips,
  String tripId,
) async {
  try {
    final record = await trips.byId(tripId);
    return record == null ? null : tripMapTargetOf(record);
  } on Object {
    return null;
  }
}

/// [readTripMapTarget] on the app's trips repository; screen 4 calls it once
/// per trip.
final tripMapTargetReaderProvider =
    Provider<Future<TripMapTarget?> Function(String tripId)>((ref) {
      final trips = ref.watch(tripsRepositoryProvider);
      return (tripId) => readTripMapTarget(trips, tripId);
    });
