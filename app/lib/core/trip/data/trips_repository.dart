// PRIVACY: never log rows or records here (coordinates, T22 §12).
import 'package:drift/drift.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

/// Rows read by screen 11, newest first.
const int kHistoryLimit = 200;

/// A trip row whose start is older than this and that has no native trip is
/// an orphan (T28 D4): longer than the start timeout (15 s) plus the wait for
/// the foreground service (5 s) of T25.
const Duration kOrphanGrace = Duration(seconds: 120);

/// What [TripsRepository.applyFinished] did.
enum ApplyFinishedResult {
  /// The row had no result: the result columns were written.
  applied,

  /// The row already has a result (a record delivered again): unchanged.
  alreadyApplied,

  /// No row with that id (insert failed at start, or deleted).
  noRow,
}

/// Trip history (T22 §7.2, T28 §3.1).
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

  /// T28 D2: in one transaction, writes the result columns of [f] (ended_at,
  /// result, end_reason, alarm_at, alarm_reason, dismissed_at, snooze_count,
  /// travelled_m, vehicle_guess) to the row `id = f.tripId` only while its
  /// `result IS NULL`. Never touches started_at, the destination or the alarm
  /// choice. `applied` comes with the updated record.
  Future<({ApplyFinishedResult result, TripRecord? record})> applyFinished(
    FinishedTripMsg f,
  );

  /// Newest first (started_at DESC), at most [limit] rows, simulated
  /// included.
  Stream<List<TripRecord>> watchHistory({int limit = kHistoryLimit});

  /// Real (not simulated) trips with started_at >= [sinceMs], newest first
  /// (month stats).
  Stream<List<TripRecord>> watchRealTripsSince(int sinceMs);

  /// T28 D4: sets ended_at = [endedAtMs] on rows without a result and an end
  /// that started before [startedBeforeMs], except [exceptTripId] (the
  /// running trip). Returns the number of rows changed.
  Future<int> markUnfinishedAsUnknown({
    required String? exceptTripId,
    required int startedBeforeMs,
    required int endedAtMs,
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

  @override
  Future<({ApplyFinishedResult result, TripRecord? record})> applyFinished(
    FinishedTripMsg f,
  ) => _db.transaction(() async {
    final updated =
        await (_db.update(
          _db.trips,
        )..where((t) => t.id.equals(f.tripId) & t.result.isNull())).write(
          TripsCompanion(
            endedAt: Value(f.endedAtMs),
            result: Value(f.outcome),
            endReason: Value(f.endReason),
            alarmAt: Value(f.alarmAtMs),
            alarmReason: Value(f.alarmReason),
            dismissedAt: Value(f.dismissedAtMs),
            snoozeCount: Value(f.snoozeCount),
            travelledM: Value(f.travelledM),
            vehicleGuess: Value(f.vehicleGuess),
          ),
        );
    final record = await byId(f.tripId);
    if (updated > 0) {
      return (result: ApplyFinishedResult.applied, record: record);
    }
    return (
      result: record == null
          ? ApplyFinishedResult.noRow
          : ApplyFinishedResult.alreadyApplied,
      record: null,
    );
  });

  @override
  Stream<List<TripRecord>> watchHistory({int limit = kHistoryLimit}) {
    final query = _db.select(_db.trips)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(limit);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  @override
  Stream<List<TripRecord>> watchRealTripsSince(int sinceMs) {
    final query = _db.select(_db.trips)
      ..where(
        (t) =>
            t.simulated.equals(false) &
            t.startedAt.isBiggerOrEqualValue(sinceMs),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    return query.watch().map(
      (rows) => rows.map(_toDomain).toList(growable: false),
    );
  }

  @override
  Future<int> markUnfinishedAsUnknown({
    required String? exceptTripId,
    required int startedBeforeMs,
    required int endedAtMs,
  }) {
    final query = _db.update(_db.trips)
      ..where((t) {
        final orphan =
            t.result.isNull() &
            t.endedAt.isNull() &
            t.startedAt.isSmallerThanValue(startedBeforeMs);
        return exceptTripId == null
            ? orphan
            : orphan & t.id.equals(exceptTripId).not();
      });
    return query.write(TripsCompanion(endedAt: Value(endedAtMs)));
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
