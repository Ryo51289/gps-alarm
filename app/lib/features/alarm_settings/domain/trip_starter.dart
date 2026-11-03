/// "Bắt đầu theo dõi" of screen 3 (T25 §2.7): permissions, config check,
/// history row, `startTrip`, telemetry facts. Reusable by T22/T28 for a
/// start without screen 3.
///
/// PRIVACY: nothing here logs; [TripStartFacts] has no coordinates, no
/// destination name and no trip id.
library;

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/alarm_settings/domain/trip_config_builder.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

/// Everything one start needs, read when screen 3 opened.
@immutable
final class StartRequest {
  const new({
    required this.draft,
    required this.settings,
    required this.alarmPrefs,
    required this.engineParams,
    required this.shortDistanceWarning,
    this.simulation,
  });

  final TripDraft draft;
  final TripSettings settings;
  final AlarmPreferences alarmPrefs;

  /// The object read when the screen opened (never read again, T29 §6).
  final EngineParamsOverride engineParams;

  /// Shown on screen (distance mode only), for `trip_start`.
  final bool shortDistanceWarning;
  final SimulationMsg? simulation;
}

enum StartError {
  invalidDestination,
  tripActive,
  notForeground,
  simulationUnavailable,

  /// `startTrip` did not answer within [kStartTripTimeout]; the trip may
  /// still start. Retryable: the retry checks `currentTrip()` first.
  timeout,
  generic,
}

/// Longest wait for `startTrip` (T25 round 2). The stub answers in a few
/// milliseconds and the real service (T15) starts the foreground service
/// synchronously, so 15 s only trips on a hung native side and keeps the
/// screen from staying on "Đang bắt đầu…" forever.
const Duration kStartTripTimeout = Duration(seconds: 15);

@immutable
sealed class StartOutcome {
  const new();
}

final class StartSucceeded extends StartOutcome {
  const new(this.tripId);

  final String tripId;
}

/// Missing permissions; never empty.
final class StartBlocked extends StartOutcome {
  const new(this.missing);

  final List<StartRequirement> missing;
}

final class StartFailed extends StartOutcome {
  const new(this.error);

  final StartError error;
}

/// Wire values of `trip_start_blocked.reason` (T29 §2).
enum TripStartBlockReason {
  locationDenied,
  locationApproximate,
  locationServicesOff,
  noAlarmChannel,
  startFailed,
}

/// Content of `trip_start` (T29 §2). No coordinates, name or trip id.
@immutable
final class TripStartFacts {
  const new({
    required this.mode,
    required this.distanceThresholdM,
    required this.timeThresholdMin,
    required this.vehicleHint,
    required this.destSource,
    required this.preAlert,
    required this.shortDistanceWarning,
    required this.batteryPct,
    required this.charging,
    required this.simulated,
    required this.paramsId,
  });

  final AlarmModeMsg mode;

  /// The threshold sent to the engine: only the one of [mode].
  final int? distanceThresholdM;
  final int? timeThresholdMin;
  final VehicleKindMsg vehicleHint;
  final DestinationSource destSource;
  final bool preAlert;
  final bool shortDistanceWarning;

  /// Null when unknown.
  final int? batteryPct;
  final bool charging;
  final bool simulated;
  final String paramsId;

  @override
  String toString() =>
      'TripStartFacts(${mode.name}, $distanceThresholdM, $timeThresholdMin, '
      '${vehicleHint.name}, ${destSource.name}, $preAlert, '
      '$shortDistanceWarning, $batteryPct, $charging, $simulated, $paramsId)';
}

/// Telemetry of the start flow; the app uses `TelemetryTripStartReporter`
/// (T29). Must never throw outside debug.
abstract interface class TripStartReporter {
  void started(TripStartFacts facts);

  void blocked(TripStartBlockReason reason, {required bool simulated});

  /// [rule] is a [validateTripConfig] message (no values).
  void configRejected(String rule);

  /// The history row could not be written or removed; the trip itself is
  /// not affected.
  void historyWriteFailed(Object error, StackTrace stack);
}

TripStartBlockReason _reasonOf(StartRequirement r) => switch (r) {
  StartRequirement.location => TripStartBlockReason.locationDenied,
  StartRequirement.precise => TripStartBlockReason.locationApproximate,
  StartRequirement.locationServices => TripStartBlockReason.locationServicesOff,
  StartRequirement.alarmChannel => TripStartBlockReason.noAlarmChannel,
};

StartError _errorOf(BridgeErrorCode code) => switch (code) {
  BridgeErrorCode.tripActive => StartError.tripActive,
  BridgeErrorCode.notForeground => StartError.notForeground,
  BridgeErrorCode.simulationUnavailable => StartError.simulationUnavailable,
  // invalid-config is a programming error (Dart validated first).
  _ => StartError.generic,
};

final class TripStarter {
  new({
    required this._bridge,
    required this._trips,
    required this._reporter,
    required this._newTripId,
    required this._nowMs,
    this._startTimeout = kStartTripTimeout,
  });

  final CoreBridge _bridge;
  final TripsRepository _trips;
  final TripStartReporter _reporter;
  final String Function() _newTripId;
  final int Function() _nowMs;
  final Duration _startTimeout;

  /// A `startTrip` that timed out and has not answered yet. While it runs, a
  /// new start never calls `startTrip` again (no duplicate trip).
  Future<void>? _pendingStart;

  /// Steps, in order:
  /// 1. fresh permissions + device → [StartBlocked] unless `checkStart`
  ///    passes (`startTrip` is never called then);
  /// 2. build + validate the config → [StartFailed];
  /// 3. `currentTrip()`: a running trip → [StartFailed] (tripActive). Screen
  ///    1 treats a still-loading `activeTripProvider` as "no trip" (T22
  ///    review round 2), so this screen checks again. Read errors are
  ///    ignored: native still answers `trip-active`;
  /// 4. `deviceStatus()` for `trip_start` only (errors → unknown);
  /// 5. history row BEFORE `startTrip` (T22 §7.2), removed again if
  ///    `startTrip` fails. A failed write is reported and does not stop the
  ///    trip (the alarm matters more than the history);
  /// 6. `startTrip`; errors map to [StartBlocked] / [StartFailed]. No answer
  ///    within [kStartTripTimeout] → [StartError.timeout]; the history row
  ///    stays until the late answer (success keeps it and reports
  ///    `started`, failure removes it).
  ///
  /// A start while a timed-out `startTrip` is still pending waits for it (up
  /// to the timeout again) before step 3, so a late success is seen by
  /// `currentTrip()` and reported as tripActive instead of starting twice.
  /// Still pending → [StartError.timeout] again, without calling `startTrip`.
  Future<StartOutcome> start(StartRequest r) async {
    final simulated = r.simulation != null;
    final StartCheck check;
    try {
      final status = await _bridge.permissionStatus();
      final device = await _bridge.deviceInfo();
      check = checkStart(status, device);
    } on Object {
      _reporter.blocked(TripStartBlockReason.startFailed, simulated: simulated);
      return const StartFailed(StartError.generic);
    }
    if (!check.canStart) {
      _reporter.blocked(_reasonOf(check.missing.first), simulated: simulated);
      return StartBlocked(check.missing);
    }

    final tripId = _newTripId();
    final config = buildTripConfig(
      tripId: tripId,
      draft: r.draft,
      settings: r.settings,
      prefs: r.alarmPrefs,
      engineParamsJson: r.engineParams.json,
    );
    final destination = r.draft.destination;
    final rule = validateTripConfig(
      config,
      destination.lat,
      destination.lng,
      r.simulation,
    );
    if (rule != null) {
      _reporter
        ..configRejected(rule)
        ..blocked(TripStartBlockReason.startFailed, simulated: simulated);
      final invalidDestination =
          rule.startsWith('destLat') ||
          rule.startsWith('destLng') ||
          rule.startsWith('destinationName');
      return StartFailed(
        invalidDestination ? StartError.invalidDestination : StartError.generic,
      );
    }

    final previous = _pendingStart;
    if (previous != null) {
      final settled = await previous
          .then((_) => true)
          .timeout(_startTimeout, onTimeout: () => false);
      if (!settled) {
        _reporter.blocked(
          TripStartBlockReason.startFailed,
          simulated: simulated,
        );
        return const StartFailed(StartError.timeout);
      }
    }

    if (await _hasRunningTrip()) {
      _reporter.blocked(TripStartBlockReason.startFailed, simulated: simulated);
      return const StartFailed(StartError.tripActive);
    }

    DeviceStatusMsg? device;
    try {
      device = await _bridge.deviceStatus();
    } on Object {
      device = null;
    }

    final facts = TripStartFacts(
      mode: config.mode,
      distanceThresholdM: config.distanceThresholdM,
      timeThresholdMin: config.timeThresholdMin,
      vehicleHint: config.vehicleHint,
      destSource: r.draft.source,
      preAlert: config.preAlertEnabled,
      shortDistanceWarning: r.shortDistanceWarning,
      batteryPct: device?.batteryPct,
      charging: device?.charging ?? false,
      simulated: simulated,
      paramsId: r.engineParams.id,
    );
    final wrote = await _insertHistory(r, config, simulated: simulated);
    final call = _bridge.startTrip(
      config,
      destLat: destination.lat,
      destLng: destination.lng,
      simulation: r.simulation,
    );
    try {
      await call.timeout(_startTimeout);
    } on TimeoutException {
      _trackLate(call, tripId, facts, wrote: wrote);
      _reporter.blocked(TripStartBlockReason.startFailed, simulated: simulated);
      return const StartFailed(StartError.timeout);
    } on Object catch (error) {
      if (wrote) {
        await _deleteHistory(tripId);
      }
      if (error is BridgeException &&
          error.code == BridgeErrorCode.permissionMissing) {
        final missing = requirementsFromDetails(error.details);
        if (missing != null) {
          _reporter.blocked(_reasonOf(missing.first), simulated: simulated);
          return StartBlocked(missing);
        }
      }
      _reporter.blocked(TripStartBlockReason.startFailed, simulated: simulated);
      return StartFailed(
        error is BridgeException ? _errorOf(error.code) : StartError.generic,
      );
    }

    _reporter.started(facts);
    return StartSucceeded(tripId);
  }

  /// Keeps the timed-out [call] as [_pendingStart] until it answers (the
  /// tracked future never fails): a late failure removes the history row, a
  /// late success keeps it and reports [facts] as started (T25 review R2-1:
  /// a trip that runs is counted as a start, after the timeout's
  /// `blocked(startFailed)`).
  void _trackLate(
    Future<void> call,
    String tripId,
    TripStartFacts facts, {
    required bool wrote,
  }) {
    final pending = call.then<void>(
      (_) {
        try {
          _reporter.started(facts);
        } on Object {
          // The tracked future must not fail (a retry awaits it).
        }
      },
      onError: (Object _) async {
        if (wrote) {
          await _deleteHistory(tripId);
        }
      },
    );
    _pendingStart = pending;
    unawaited(
      pending.whenComplete(() {
        if (identical(_pendingStart, pending)) {
          _pendingStart = null;
        }
      }),
    );
  }

  Future<bool> _hasRunningTrip() async {
    try {
      final active = await _bridge.currentTrip();
      return active != null && active.state.phase != TripPhaseMsg.ended;
    } on Object {
      return false;
    }
  }

  Future<bool> _insertHistory(
    StartRequest r,
    TripConfigMsg config, {
    required bool simulated,
  }) async {
    final d = r.draft.destination;
    final record = TripRecord.started(
      id: config.tripId,
      // The name the engine gets (trimmed, at most 200 units), so the row
      // is valid whenever the config is.
      draft: r.draft.copyWith(
        destination: TripDestination(
          name: config.destinationName,
          lat: d.lat,
          lng: d.lng,
          kind: d.kind,
          detail: d.detail,
        ),
        vehicleHint: r.draft.vehicleHint,
      ),
      alarm: r.settings.toAlarmChoice(),
      startedAtMs: _nowMs(),
      simulated: simulated,
    );
    try {
      await _trips.insertStarted(record);
      return true;
    } on Object catch (error, stack) {
      _reporter.historyWriteFailed(error, stack);
      return false;
    }
  }

  Future<void> _deleteHistory(String tripId) async {
    try {
      await _trips.delete(tripId);
    } on Object catch (error, stack) {
      _reporter.historyWriteFailed(error, stack);
    }
  }
}
