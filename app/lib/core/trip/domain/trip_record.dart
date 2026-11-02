/// A trip as stored in the history (T22 §6.3).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

/// Rows shown under "Chuyến gần đây" (Q5).
const int kRecentTripsLimit = 3;

/// Rows read before de-duplicating recent destinations.
const int kRecentScanWindow = 50;

/// One trip of the history. Start fields are written by T25 before
/// `startTrip`; result fields by T28 from `FinishedTripMsg` (null while the
/// trip runs).
///
/// PRIVACY: [toString] never prints the name or the coordinates.
@immutable
final class TripRecord {
  const new({
    required this.id,
    required this.destination,
    required this.source,
    required this.alarm,
    required this.vehicleHint,
    required this.simulated,
    required this.startedAtMs,
    this.endedAtMs,
    this.result,
    this.endReason,
    this.alarmAtMs,
    this.alarmReason,
    this.dismissedAtMs,
    this.snoozeCount = 0,
    this.travelledM,
    this.vehicleGuess,
  });

  /// Row written by T25 before `startTrip`: result fields empty.
  factory started({
    required String id,
    required TripDraft draft,
    required TripAlarmChoice alarm,
    required int startedAtMs,
    bool simulated = false,
  }) => TripRecord(
    id: id,
    destination: draft.destination,
    source: draft.source,
    alarm: alarm,
    vehicleHint: draft.vehicleHint,
    simulated: simulated,
    startedAtMs: startedAtMs,
  );

  final String id;
  final TripDestination destination;
  final DestinationSource source;
  final TripAlarmChoice alarm;
  final VehicleKindMsg vehicleHint;
  final bool simulated;
  final int startedAtMs;
  final int? endedAtMs;
  final TripOutcomeMsg? result;
  final EndReasonMsg? endReason;
  final int? alarmAtMs;
  final AlarmReasonMsg? alarmReason;
  final int? dismissedAtMs;
  final int snoozeCount;
  final int? travelledM;
  final VehicleKindMsg? vehicleGuess;

  /// [vehicleGuess] when known, else [vehicleHint]; null when both unknown.
  VehicleKindMsg? get displayVehicle {
    final guess = vehicleGuess;
    if (guess != null && guess != VehicleKindMsg.unknown) {
      return guess;
    }
    return vehicleHint == VehicleKindMsg.unknown ? null : vehicleHint;
  }

  @override
  bool operator ==(Object other) =>
      other is TripRecord &&
      other.id == id &&
      other.destination == destination &&
      other.source == source &&
      other.alarm == alarm &&
      other.vehicleHint == vehicleHint &&
      other.simulated == simulated &&
      other.startedAtMs == startedAtMs &&
      other.endedAtMs == endedAtMs &&
      other.result == result &&
      other.endReason == endReason &&
      other.alarmAtMs == alarmAtMs &&
      other.alarmReason == alarmReason &&
      other.dismissedAtMs == dismissedAtMs &&
      other.snoozeCount == snoozeCount &&
      other.travelledM == travelledM &&
      other.vehicleGuess == vehicleGuess;

  @override
  int get hashCode => Object.hash(
    id,
    destination,
    source,
    alarm,
    vehicleHint,
    simulated,
    startedAtMs,
    endedAtMs,
    result,
    endReason,
    alarmAtMs,
    alarmReason,
    dismissedAtMs,
    snoozeCount,
    travelledM,
    vehicleGuess,
  );

  @override
  String toString() =>
      'TripRecord($destination, ${source.name}, ${result?.name})';
}

/// Latest record per destination (D11). Destinations are the same when the
/// names are equal and the coordinates match once rounded to 4 decimals
/// (about 11 m). [records] must be newest first; the first record of each
/// destination is kept, at most [limit] in total.
List<TripRecord> latestPerDestination(
  List<TripRecord> records, {
  int limit = kRecentTripsLimit,
}) {
  final seen = <(String, int, int)>{};
  final out = <TripRecord>[];
  for (final r in records) {
    if (out.length >= limit) {
      break;
    }
    final d = r.destination;
    final key = (d.name, (d.lat * 1e4).round(), (d.lng * 1e4).round());
    if (seen.add(key)) {
      out.add(r);
    }
  }
  return out;
}
