// PRIVACY: never log rows or records here (coordinates, T22 §12).
import 'package:drift/drift.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

/// Trip history (T22 §7.2). T28 adds `applyFinished(FinishedTripMsg)`
/// (idempotent), history queries and deletion.
abstract interface class TripsRepository {
  /// T25: call BEFORE `bridge.startTrip`; [delete] if `startTrip` throws.
  /// Invalid destination or alarm choice: [ArgumentError]. Existing id:
  /// error from the database.
  Future<void> insertStarted(TripRecord record);

  Future<void> delete(String tripId);

  /// T27 (route back to the destination), T28. Null if unknown.
  Future<TripRecord?> byId(String tripId);

  /// Latest trip per destination, newest first, simulated trips excluded
  /// (D11).
  Stream<List<TripRecord>> watchRecentDestinations({
    int limit = kRecentTripsLimit,
  });
}

final class DriftTripsRepository implements TripsRepository {
  new(this._db);

  final AppDatabase _db;

  @override
  Future<void> insertStarted(TripRecord record) async {
    if (!record.destination.isValid) {
      throw ArgumentError('invalid destination', 'record');
    }
    if (!record.alarm.isValid) {
      throw ArgumentError('invalid alarm choice', 'record');
    }
    await _db.into(_db.trips).insert(_toCompanion(record));
  }

  @override
  Future<void> delete(String tripId) =>
      (_db.delete(_db.trips)..where((t) => t.id.equals(tripId))).go();

  @override
  Future<TripRecord?> byId(String tripId) async {
    final row = await (_db.select(
      _db.trips,
    )..where((t) => t.id.equals(tripId))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Stream<List<TripRecord>> watchRecentDestinations({
    int limit = kRecentTripsLimit,
  }) {
    final query = _db.select(_db.trips)
      ..where((t) => t.simulated.equals(false))
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(kRecentScanWindow);
    return query.watch().map(
      (rows) => latestPerDestination(
        rows.map(_toDomain).toList(growable: false),
        limit: limit,
      ),
    );
  }

  static TripsCompanion _toCompanion(TripRecord r) {
    final d = r.destination;
    return TripsCompanion.insert(
      id: r.id,
      destinationName: d.name,
      destinationDetail: Value(d.detail),
      destinationKind: d.kind,
      destLat: d.lat,
      destLng: d.lng,
      destSource: r.source,
      mode: r.alarm.mode,
      distanceThresholdM: Value(r.alarm.distanceThresholdM),
      timeThresholdMin: Value(r.alarm.timeThresholdMin),
      preAlertEnabled: r.alarm.preAlertEnabled,
      vehicleHint: r.vehicleHint,
      simulated: Value(r.simulated),
      startedAt: r.startedAtMs,
      endedAt: Value(r.endedAtMs),
      result: Value(r.result),
      endReason: Value(r.endReason),
      alarmAt: Value(r.alarmAtMs),
      alarmReason: Value(r.alarmReason),
      dismissedAt: Value(r.dismissedAtMs),
      snoozeCount: Value(r.snoozeCount),
      travelledM: Value(r.travelledM),
      vehicleGuess: Value(r.vehicleGuess),
    );
  }

  static TripRecord _toDomain(TripRow r) => TripRecord(
    id: r.id,
    destination: TripDestination(
      name: r.destinationName,
      lat: r.destLat,
      lng: r.destLng,
      kind: r.destinationKind,
      detail: r.destinationDetail,
    ),
    source: r.destSource,
    alarm: TripAlarmChoice(
      mode: r.mode,
      distanceThresholdM: r.distanceThresholdM,
      timeThresholdMin: r.timeThresholdMin,
      preAlertEnabled: r.preAlertEnabled,
    ),
    vehicleHint: r.vehicleHint,
    simulated: r.simulated,
    startedAtMs: r.startedAt,
    endedAtMs: r.endedAt,
    result: r.result,
    endReason: r.endReason,
    alarmAtMs: r.alarmAt,
    alarmReason: r.alarmReason,
    dismissedAtMs: r.dismissedAt,
    snoozeCount: r.snoozeCount,
    travelledM: r.travelledM,
    vehicleGuess: r.vehicleGuess,
  );
}
