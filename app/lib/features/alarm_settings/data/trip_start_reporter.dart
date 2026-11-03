import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/telemetry/analytics/analytics_buckets.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

/// [TripStartReporter] on the session's [Telemetry] (T29 §11, T25):
/// `trip_start` / `trip_start_blocked`, the custom keys `trip_active`,
/// `alarm_mode`, `simulated`, `engine_params_id`, and non-fatals.
///
/// [_telemetry] is read at each call (T25 review R2-2): the provider of
/// this reporter watches nothing, so it never rebuilds `TripStarter` (whose
/// `_pendingStart` must survive for the whole session).
final class TelemetryTripStartReporter implements TripStartReporter {
  new(this._telemetry);

  final Telemetry Function() _telemetry;

  @override
  void started(TripStartFacts facts) {
    final t = _telemetry();
    final event = tripStartEventOf(facts);
    t.analytics.log(event);
    t.crash
      ..setKey(CrashKey.tripActive, true)
      ..setKey(CrashKey.alarmMode, crashAlarmModeOf(event.mode))
      ..setKey(CrashKey.simulated, facts.simulated)
      ..setKey(CrashKey.engineParamsId, facts.paramsId);
  }

  @override
  void blocked(TripStartBlockReason reason, {required bool simulated}) =>
      _telemetry().analytics.log(
        TripStartBlockedEvent(
          reason: startBlockedReasonOf(reason),
          simulated: simulated,
        ),
      );

  @override
  void configRejected(String rule) => _telemetry().crash.recordNonFatal(
    TripConfigRejected(rule),
    StackTrace.current,
    NonFatalReason.other,
  );

  /// Error type only (T22 rule): a database error can quote the row.
  @override
  void historyWriteFailed(Object error, StackTrace stack) => _telemetry().crash
      .recordNonFatal(error, stack, NonFatalReason.historyWriteFailed);
}

/// A config the Dart validator refused (a programming error). [rule] is a
/// `validateTripConfig` message: a field name and a rule, never a value.
@immutable
final class TripConfigRejected implements SafeDiagnostic {
  const new(this.rule);

  final String rule;

  @override
  String toString() => 'TripConfigRejected($rule)';
}

AlarmModeTag alarmModeTagOf(AlarmModeMsg m) => switch (m) {
  AlarmModeMsg.distance => AlarmModeTag.distance,
  AlarmModeMsg.time => AlarmModeTag.time,
  AlarmModeMsg.smart => AlarmModeTag.smart,
};

VehicleTag vehicleTagOf(VehicleKindMsg v) => switch (v) {
  VehicleKindMsg.train => VehicleTag.train,
  VehicleKindMsg.coach => VehicleTag.coach,
  VehicleKindMsg.bus => VehicleTag.bus,
  VehicleKindMsg.unknown => VehicleTag.unknown,
};

DestSourceTag destSourceTagOf(DestinationSource s) => switch (s) {
  DestinationSource.station => DestSourceTag.station,
  DestinationSource.places => DestSourceTag.places,
  DestinationSource.mapPin => DestSourceTag.mapPin,
  DestinationSource.savedPlace => DestSourceTag.savedPlace,
  DestinationSource.recentTrip => DestSourceTag.recentTrip,
};

StartBlockedReason startBlockedReasonOf(TripStartBlockReason r) => switch (r) {
  TripStartBlockReason.locationDenied => StartBlockedReason.locationDenied,
  TripStartBlockReason.locationApproximate =>
    StartBlockedReason.locationApproximate,
  TripStartBlockReason.locationServicesOff =>
    StartBlockedReason.locationServicesOff,
  TripStartBlockReason.noAlarmChannel => StartBlockedReason.noAlarmChannel,
  TripStartBlockReason.startFailed => StartBlockedReason.startFailed,
};

/// `trip_start` of [facts]: thresholds and battery only as buckets; an
/// unknown battery level leaves `battery` out.
TripStartEvent tripStartEventOf(TripStartFacts facts) {
  final mode = alarmModeTagOf(facts.mode);
  final pct = facts.batteryPct;
  return TripStartEvent(
    mode: mode,
    threshold: thresholdKey(
      mode,
      distanceM: facts.distanceThresholdM,
      timeMin: facts.timeThresholdMin,
    ),
    vehicleHint: vehicleTagOf(facts.vehicleHint),
    destSource: destSourceTagOf(facts.destSource),
    preAlert: facts.preAlert,
    shortDistanceWarning: facts.shortDistanceWarning,
    battery: pct == null ? null : batteryBucket(pct),
    charging: facts.charging,
    simulated: facts.simulated,
    paramsId: facts.paramsId,
  );
}
