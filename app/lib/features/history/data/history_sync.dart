// PRIVACY (T28 §8): logs hold counts or error types only, never a tripId,
// a destination name or coordinates. Pigeon messages are never logged.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/telemetry/analytics/analytics_buckets.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/data/trip_start_reporter.dart';

/// The one way into the history (T28 D3): the native queue of ended trips
/// → drift (idempotent) → ack; then orphan rows are marked (D4). Runs on app
/// start, on resume and on each `TripEndedMsg` (only a signal).
final class HistorySync {
  new({
    required this._bridge,
    required this._repo,
    required this._telemetry,
    required this._nowMs,
  });

  final CoreBridge _bridge;
  final TripsRepository _repo;
  final Telemetry Function() _telemetry;
  final int Function() _nowMs;

  static final Logger _log = AppLog.named('history');

  Future<void>? _running;
  bool _again = false;

  /// Serialized: a call while a run is in progress schedules exactly one
  /// more run after it; every caller's future completes after that run.
  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _loop();
    _running = run;
    return run;
  }

  Future<void> _loop() async {
    try {
      do {
        _again = false;
        await _runOnce();
      } while (_again);
    } finally {
      _running = null;
    }
  }

  Future<void> _runOnce() async {
    final List<FinishedTripMsg> finished;
    try {
      finished = await _bridge.pendingFinishedTrips();
    } on BridgeException {
      return; // No native side: nothing to do.
    }
    final acked = <String>[];
    var noRow = 0;
    for (final f in finished) {
      try {
        final (:result, :record) = await _repo.applyFinished(f);
        if (result == ApplyFinishedResult.applied && record != null) {
          _telemetry().analytics.log(tripEndEventOf(f, record));
        }
        if (result == ApplyFinishedResult.noRow) {
          noRow++;
        }
        acked.add(f.tripId);
      } on Object catch (error, stack) {
        // Not acked: delivered again next time.
        reportNonFatal('historySync.apply', error, stack);
      }
    }
    if (noRow > 0) {
      _log.info('finished trip without row: $noRow');
    }
    if (acked.isNotEmpty) {
      try {
        await _bridge.ackFinishedTrips(acked);
      } on BridgeException {
        // Delivered again later; applyFinished is idempotent (D2).
      }
    }
    final ActiveTripMsg? active;
    try {
      active = await _bridge.currentTrip();
    } on BridgeException {
      return; // The running trip is unknown: no orphan marking this time.
    } on Object catch (error) {
      // Same rule for any other failure (found by T26 W22 at the T26/T28
      // merge): never mark orphans without knowing the running trip.
      _log.warning('currentTrip failed: ${error.runtimeType}');
      return;
    }
    final now = _nowMs();
    try {
      await _repo.markUnfinishedAsUnknown(
        exceptTripId: active?.config.tripId,
        startedBeforeMs: now - kOrphanGrace.inMilliseconds,
        endedAtMs: now,
      );
    } on Object catch (error, stack) {
      reportNonFatal('historySync.orphans', error, stack);
    }
    if (active == null) {
      _telemetry().crash.setKey(CrashKey.tripActive, false);
    }
  }
}

/// `trip_end` of T29 from a finished trip and its row. No name, no
/// coordinates. Durations use the trip clock of [f] (virtual for a simulated
/// trip, T18 D14).
TripEndEvent tripEndEventOf(FinishedTripMsg f, TripRecord rec) => TripEndEvent(
  outcome: TripOutcomeTag.values.byName(f.outcome.name),
  endReason: EndReasonTag.values.byName(f.endReason.name),
  alarmReason: switch (f.alarmReason) {
    null => AlarmReasonTag.none,
    final r => AlarmReasonTag.values.byName(r.name),
  },
  snoozeCount: f.snoozeCount,
  mode: alarmModeTagOf(rec.alarm.mode),
  vehicleGuess: vehicleTagOf(f.vehicleGuess),
  duration: durationBucket(f.endedAtMs - f.startedAtMs),
  distance: distanceBucket(f.travelledM),
  simulated: rec.simulated,
);

final historySyncProvider = Provider<HistorySync>(
  (ref) => HistorySync(
    bridge: ref.watch(coreBridgeProvider),
    repo: ref.watch(tripsRepositoryProvider),
    telemetry: () => ref.read(telemetryProvider),
    nowMs: () => ref.read(clockProvider)().millisecondsSinceEpoch,
  ),
);
