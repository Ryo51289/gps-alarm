// NapStop core bridge: Pigeon input. Spec: docs/specs/T14.md
// Regenerate from app/ (then commit all three outputs together):
//   dart run pigeon --input pigeons/core_api.dart
//   dart format lib/core/bridge/core_api.g.dart
//
// PRIVACY (T10 §10, T14 D5): Pigeon >= 27 generates toString()/description
// printing every field. No class in this file may hold coordinates.
// Coordinates cross the bridge only as the primitive destLat/destLng
// parameters of TripHostApi.startTrip. Never log Pigeon message objects
// (TripConfigMsg.destinationName is a place name).
//
// Classic constructors on purpose: this file is parsed by Pigeon's own
// analyzer and is excluded from the app lints (T14 §3.2).
import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/bridge/core_api.g.dart',
    dartPackageName: 'napstop',
    kotlinOut:
        'android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'app.napstop.core.bridge'),
    swiftOut: 'ios/Runner/Bridge/CoreApi.g.swift',
  ),
)
// ---------------------------------------------------------------- enums
// Wire value = index. Append new values at the end only.

enum AlarmModeMsg { distance, time, smart }

enum VehicleKindMsg { train, coach, bus, unknown }

enum VibrationMsg { off, light, medium, strong }

enum DismissMethodMsg { swipe, shake, math }

enum TripPhaseMsg { acquiring, tracking, alarming, snoozed, overshot, ended }

enum GpsStatusMsg { noFixYet, ok, lost }

enum AvailabilityCauseMsg { available, permissionRevoked, servicesOff }

/// T10 FallbackStatus; NONE is renamed notSet (avoids Swift Optional.none).
enum FallbackStatusMsg { notSet, requested, confirmed, failed }

enum SamplingTierMsg { sparse, medium, dense }

enum AlarmReasonMsg {
  distance,
  time,
  smartTime,
  smartDistance,
  smartSlowDistance,
  gpsLost,
  lowBattery,
  passedClosest,
  overshoot,
  snoozeEnd,
  timeout,
  fallback,
  fallbackMissed,
}

enum GpsLostCauseMsg { noFixTimeout, neverAcquired, permissionRevoked, servicesOff }

enum TripOutcomeMsg { onTime, snoozed, missed, cancelled }

enum EndReasonMsg { dismissed, userStop, alarmUnanswered }

/// Screen 7 choices (T10 §2.2 BATTERY_*).
enum BatteryChoiceMsg { maxSaving, alarmAt5, alarmEarlier }

/// `always` only occurs on iOS (ADR-001: Android never asks for background).
enum LocationAccessMsg { notDetermined, denied, whileInUse, always }

enum PermissionStateMsg { notDetermined, denied, granted, notApplicable }

enum PermissionKindMsg { location, notifications, alarmKit }

enum SettingsTargetMsg {
  appDetails,
  locationServices,
  notifications,
  fullScreenIntent,
  exactAlarm,
  batteryOptimization,
}

enum PlatformMsg { android, ios }

/// T14.1: NotificationManager.getCurrentInterruptionFilter(). iOS: unknown.
enum InterruptionFilterMsg { unknown, all, priority, alarms, none }

/// T27: why MainActivity was opened by the native alarm screen. Append only.
enum LaunchActionKindMsg { overshootRoute }

// ------------------------------------------------- trip config (Dart -> native)

/// Alarm presentation (PRD §4 "Báo thức"). Not part of the engine config
/// (T10 §2.1); used by AlarmController (T16/T17).
class AlarmSettingsMsg {
  AlarmSettingsMsg({
    required this.soundId,
    required this.volume,
    required this.rampUp,
    required this.vibration,
    required this.flash,
    required this.preferHeadphones,
    required this.dismissMethod,
  });

  String soundId;
  double volume; // 0.0..1.0
  bool rampUp; // 30 s ramp
  VibrationMsg vibration;
  bool flash;
  bool preferHeadphones;
  DismissMethodMsg dismissMethod;
}

/// T10 §2.1 TripConfig WITHOUT coordinates (D5) + display name + alarm
/// settings. Echoed back by currentTrip(), so it must stay coordinate-free.
class TripConfigMsg {
  TripConfigMsg({
    required this.tripId,
    required this.destinationName,
    required this.mode,
    this.distanceThresholdM,
    this.timeThresholdMin,
    required this.preAlertEnabled,
    required this.vehicleHint,
    required this.alarm,
    this.engineParamsJson,
  });

  String tripId; // UUID from Flutter, [A-Za-z0-9_-]{1,64}
  String destinationName; // for notifications / alarm screen
  AlarmModeMsg mode;
  int? distanceThresholdM; // required when mode == distance: 200..10000
  int? timeThresholdMin; // required when mode == time: 5..60
  bool preAlertEnabled;
  VehicleKindMsg vehicleHint;
  AlarmSettingsMsg alarm;
  // T14.1 (T29 §6): Remote Config engine overrides, verbatim JSON object or
  // null (= defaults). <= 16384 UTF-16 code units (V11). Never log it.
  String? engineParamsJson;
}

/// Simulation mode (T18): a bundled trace played on the real runtime.
/// `traceAsset`: trace id in `assets/sim/catalog.json`
/// (`^[a-z0-9]+(_[a-z0-9]+)*$`, never a path); `speedFactor` 1..600, UI
/// 1/10/60 (T18).
class SimulationMsg {
  SimulationMsg({required this.traceAsset, required this.speedFactor});

  String traceAsset;
  double speedFactor; // 1..600; PRD UI offers 1, 10, 60
}

// -------------------------------------------------- trip state (native -> Dart)

/// = T10 §2.4 TripView minus native-only fields (wakeAtMs, droppedFixes,
/// full samplingPolicy -> samplingTier) plus batteryChoice (from
/// EngineState.battery.choice). Times: epoch ms of the trip clock.
class TripStateMsg {
  TripStateMsg({
    required this.tripId,
    required this.atMs,
    required this.phase,
    required this.gps,
    required this.locationCause,
    this.distanceM,
    this.routeDistanceEstM,
    this.distanceErrorM,
    required this.isEstimated,
    this.etaS,
    this.etaMinS,
    this.etaMaxS,
    this.speedKmh,
    this.progress,
    this.alarmMarkerProgress,
    this.predictedAlarmAtMs,
    this.samplingTier,
    this.fallbackAtMs,
    required this.fallbackStatus,
    this.batteryPct,
    required this.batteryRisk,
    this.batteryChoice,
    required this.preAlertFired,
    this.alarmAtMs,
    this.alarmReason,
    required this.alarmRinging,
    required this.snoozeCount,
    this.snoozeUntilMs,
    this.overshootPastM,
    this.outcome,
    required this.vehicleGuess,
    required this.travelledM,
  });

  String tripId;
  int atMs;
  TripPhaseMsg phase;
  GpsStatusMsg gps;
  AvailabilityCauseMsg locationCause;
  int? distanceM;
  int? routeDistanceEstM;
  int? distanceErrorM;
  bool isEstimated;
  int? etaS;
  int? etaMinS;
  int? etaMaxS;
  double? speedKmh;
  double? progress; // 0..1
  double? alarmMarkerProgress; // 0..1
  int? predictedAlarmAtMs;
  SamplingTierMsg? samplingTier;
  int? fallbackAtMs;
  FallbackStatusMsg fallbackStatus;
  int? batteryPct;
  bool batteryRisk;
  BatteryChoiceMsg? batteryChoice;
  bool preAlertFired;
  int? alarmAtMs; // first ring of the trip (T10 §3 alarm.atMs)
  AlarmReasonMsg? alarmReason; // reason of the latest Alarm
  bool alarmRinging;
  int snoozeCount;
  int? snoozeUntilMs;
  int? overshootPastM;
  TripOutcomeMsg? outcome; // set when phase == ended
  VehicleKindMsg vehicleGuess;
  int travelledM;
}

/// currentTrip(): the running trip, read from the snapshot (T10 §7).
class ActiveTripMsg {
  ActiveTripMsg({required this.config, required this.state, this.simulation});

  TripConfigMsg config;
  TripStateMsg state;
  SimulationMsg? simulation;
}

/// T10 TripEnded + TripSummary, one record per ended trip (history, T28).
class FinishedTripMsg {
  FinishedTripMsg({
    required this.tripId,
    required this.outcome,
    required this.endReason,
    required this.endedAtMs,
    required this.startedAtMs,
    this.alarmAtMs,
    this.alarmReason,
    this.dismissedAtMs,
    required this.snoozeCount,
    required this.travelledM,
    required this.vehicleGuess,
  });

  String tripId;
  TripOutcomeMsg outcome;
  EndReasonMsg endReason;
  int endedAtMs;
  int startedAtMs;
  int? alarmAtMs; // first alarm (summary.alarmAtMs)
  AlarmReasonMsg? alarmReason; // first alarm reason (summary.alarmReason)
  int? dismissedAtMs;
  int snoozeCount;
  int travelledM;
  VehicleKindMsg vehicleGuess;
}

// ------------------------------------------------------------ stream items
// Contract: per engine Step one TripStateUpdateMsg, then the Step's events in
// T10 §2.3 order. SamplingPolicyChanged / FallbackAlarmChanged are not sent.

sealed class TripUpdateMsg {}

class TripStateUpdateMsg extends TripUpdateMsg {
  TripStateUpdateMsg({required this.state});
  TripStateMsg state;
}

class PreAlertMsg extends TripUpdateMsg {
  PreAlertMsg({required this.tripId, required this.atMs, required this.distanceM, this.etaS});
  String tripId;
  int atMs;
  int distanceM;
  int? etaS;
}

class AlarmMsg extends TripUpdateMsg {
  AlarmMsg({
    required this.tripId,
    required this.atMs,
    required this.reason,
    required this.ringNow,
    required this.snoozeAllowed,
    this.distanceM,
    this.etaS,
    this.batteryPct,
  });
  String tripId;
  int atMs;
  AlarmReasonMsg reason;
  bool ringNow;
  bool snoozeAllowed;
  int? distanceM;
  int? etaS;
  int? batteryPct;
}

class SnoozedMsg extends TripUpdateMsg {
  SnoozedMsg({required this.tripId, required this.atMs, required this.untilMs});
  String tripId;
  int atMs;
  int untilMs;
}

class GpsLostMsg extends TripUpdateMsg {
  GpsLostMsg({required this.tripId, required this.atMs, required this.cause, this.lastFixAgeS});
  String tripId;
  int atMs;
  GpsLostCauseMsg cause;
  int? lastFixAgeS;
}

class GpsRecoveredMsg extends TripUpdateMsg {
  GpsRecoveredMsg({required this.tripId, required this.atMs, required this.lostForS});
  String tripId;
  int atMs;
  int lostForS;
}

class LowBatteryRiskMsg extends TripUpdateMsg {
  LowBatteryRiskMsg({
    required this.tripId,
    required this.atMs,
    required this.levelPct,
    required this.availableMin,
    required this.neededMin,
  });
  String tripId;
  int atMs;
  int levelPct;
  int availableMin;
  int neededMin;
}

class OvershootMsg extends TripUpdateMsg {
  OvershootMsg({required this.tripId, required this.atMs, required this.pastM});
  String tripId;
  int atMs;
  int pastM;
}

class ArrivedMsg extends TripUpdateMsg {
  ArrivedMsg({required this.tripId, required this.atMs, required this.distanceM});
  String tripId;
  int atMs;
  int distanceM;
}

class TripEndedMsg extends TripUpdateMsg {
  TripEndedMsg({required this.atMs, required this.trip});
  int atMs;
  FinishedTripMsg trip;
}

// -------------------------------------------------------------- permissions

/// ARCHITECTURE §7 items of the running platform. Not applicable -> notApplicable.
class PermissionStatusMsg {
  PermissionStatusMsg({
    required this.location,
    required this.precise,
    required this.locationServicesEnabled,
    required this.notifications,
    required this.fullScreenIntent,
    required this.exactAlarm,
    required this.batteryOptimizationIgnored,
    required this.alarmKit,
  });

  LocationAccessMsg location;
  PermissionStateMsg precise;
  bool locationServicesEnabled;
  PermissionStateMsg notifications;
  PermissionStateMsg fullScreenIntent; // Android
  PermissionStateMsg exactAlarm; // Android
  PermissionStateMsg batteryOptimizationIgnored; // Android; granted = ignoring
  PermissionStateMsg alarmKit; // iOS 26+
}

class DeviceInfoMsg {
  DeviceInfoMsg({
    required this.platform,
    required this.manufacturer,
    required this.brand,
    required this.model,
    required this.osVersion,
    this.androidSdkInt,
    this.iosMajor,
  });

  PlatformMsg platform;
  String manufacturer; // Android Build.MANUFACTURER; iOS "Apple"
  String brand; // Android Build.BRAND; iOS "Apple"
  String model;
  String osVersion; // Android Build.VERSION.RELEASE; iOS systemVersion
  int? androidSdkInt; // Build.VERSION.SDK_INT (Android only)
  int? iosMajor; // operatingSystemVersion.majorVersion (iOS only)
}

/// T14.1: live readiness inputs for the home card (T22) and screen 3 /
/// trip_start (T25). Read on demand, no permission. null = unknown.
class DeviceStatusMsg {
  DeviceStatusMsg({
    this.batteryPct,
    this.charging,
    this.alarmVolumePct,
    this.alarmMuted,
    required this.interruptionFilter,
    this.priorityAllowsAlarms,
    this.headphonesConnected,
  });

  int? batteryPct; // 0..100
  bool? charging; // charging or full
  int? alarmVolumePct; // Android STREAM_ALARM 0..100; iOS null
  bool? alarmMuted; // Android isStreamMute(STREAM_ALARM); iOS null
  InterruptionFilterMsg interruptionFilter;
  bool? priorityAllowsAlarms; // Android 30+, only when filter == priority
  // T26 §9: a wired/Bluetooth/USB headphone output is connected. iOS null.
  bool? headphonesConnected;
}

/// T23: Maps/Places configuration of this build. apiKey null = no key
/// configured. PRIVACY: never log (toString prints the key). No coordinates.
class MapsConfigMsg {
  MapsConfigMsg({
    this.apiKey,
    this.androidPackage,
    this.androidCertSha1,
    this.iosBundleId,
  });

  String? apiKey;
  String? androidPackage; // Context.packageName, e.g. app.napstop.dev
  String? androidCertSha1; // SHA-1 of the signing cert, 40 upper-case hex, no colons
  String? iosBundleId;
}

/// T21: screen 9 background check (Android). Times are epoch ms
/// (System.currentTimeMillis). No coordinates.
class BackgroundCheckMsg {
  BackgroundCheckMsg({
    required this.scheduledAtMs,
    required this.dueAtMs,
    this.firedAtMs,
    this.screenOnAtFire,
    required this.exact,
  });

  int scheduledAtMs; // when startBackgroundCheck ran
  int dueAtMs; // scheduledAtMs + delayMs
  int? firedAtMs; // when the receiver ran; null = not yet
  bool? screenOnAtFire; // PowerManager.isInteractive() at fire time
  bool exact; // true: setExactAndAllowWhileIdle; false: setAndAllowWhileIdle
}

/// T27: one launch action (T16 LaunchActions), consumed once. No coordinates:
/// Dart reads the destination from drift by [tripId] (T14 D5).
class LaunchActionMsg {
  LaunchActionMsg({required this.kind, required this.tripId, this.pastM});

  LaunchActionKindMsg kind;
  String tripId; // [A-Za-z0-9_-]{1,64}, checked natively
  int? pastM; // Overshoot.pastM at dismissal, 0..1000000 m; null = unknown
}

// --------------------------------------------------------------------- APIs

@HostApi()
abstract class TripHostApi {
  /// Starts tracking. Android: only while the activity is visible (ADR-001 #2).
  /// Errors: invalid-config, trip-active, permission-missing, not-foreground,
  /// start-failed, simulation-unavailable, internal (T14 §4).
  @async
  void startTrip(
    TripConfigMsg config,
    double destLat,
    double destLng,
    SimulationMsg? simulation,
  );

  /// UserAction STOP_TRIP. No-op if tripId is not the active trip.
  @async
  void stopTrip(String tripId);

  /// Active trip read from the snapshot (works after process death), or null.
  @async
  ActiveTripMsg? currentTrip();

  /// Screen 7 -> UserAction BATTERY_*. No-op if tripId is not active.
  @async
  void setBatteryChoice(String tripId, BatteryChoiceMsg choice);

  /// UserAction DISMISS. No-op if tripId is not active or phase not alarming.
  @async
  void dismiss(String tripId);

  /// UserAction SNOOZE. No-op if not allowed (T10 §3).
  @async
  void snooze(String tripId);

  /// Ended trips not yet acknowledged, oldest first (D12).
  @async
  List<FinishedTripMsg> pendingFinishedTrips();

  /// Removes acknowledged records. Unknown ids are ignored.
  @async
  void ackFinishedTrips(List<String> tripIds);
}

@HostApi()
abstract class PermissionHostApi {
  /// T21: @async (native reads stored flags off the main thread; iOS reads
  /// notification settings asynchronously). Dart signature unchanged.
  @async
  PermissionStatusMsg status();

  /// Shows the system prompt. Not applicable kinds return status() unchanged.
  /// Errors: request-in-progress.
  @async
  PermissionStatusMsg request(PermissionKindMsg kind);

  /// Opens the settings page. false = nothing could be opened / not applicable.
  bool openSettings(SettingsTargetMsg target);

  DeviceInfoMsg deviceInfo();

  /// T14.1: battery, alarm stream volume, Do Not Disturb. Cheap, never throws
  /// for an unreadable item (that item is null / unknown).
  DeviceStatusMsg deviceStatus();

  /// T23: Maps/Places configuration of this build. Cheap, main-safe, no
  /// permission.
  MapsConfigMsg mapsConfig();

  /// T23: distances in metres from the device's last known position to each
  /// (lat, lng) pair of [latLngPairs] (flat list, even length <= 100). null
  /// when: no location permission, location off, no cached fix younger than
  /// [maxAgeMs], or invalid input. Never requests a new fix, never prompts.
  /// The user's coordinates never cross the bridge (T14 D5).
  @async
  List<double>? distancesFromLastKnownM(List<double> latLngPairs, int maxAgeMs);

  /// T21: schedules the screen 9 check alarm in [delayMs] (5000..120000),
  /// replacing any previous check. Errors: invalid-config
  /// ("delayMs: out of range"). iOS: internal ("unsupported").
  @async
  BackgroundCheckMsg startBackgroundCheck(int delayMs);

  /// T21: the latest check (survives process death), or null.
  @async
  BackgroundCheckMsg? backgroundCheck();

  /// T21: cancels the alarm and forgets the record. No-op when none.
  @async
  void cancelBackgroundCheck();
}

@HostApi()
abstract class AlarmHostApi {
  /// Settings screen preview, USAGE_ALARM on Android (T16).
  void previewSound(String soundId, double volume);

  void stopPreview();

  /// T27: returns and clears the launch action MainActivity was opened with
  /// (T16 §4.5), or null (none, expired after 10 min, iOS).
  @async
  LaunchActionMsg? consumeLaunchAction();

  /// T27: brings the native alarm screen of [tripId] to the front when its
  /// ring is live. false = not ringing / could not start it / iOS.
  /// Never throws for those cases.
  @async
  bool showAlarmScreen(String tripId);

  /// T28: language of native strings (tracking/alarm notifications, alarm
  /// screen in `:ring`). 'vi' | 'en'; null = follow the device. Any other
  /// value is treated as null. Cheap; never throws.
  void setAppLocale(String? languageTag);
}

@EventChannelApi()
abstract class TripEventChannelApi {
  TripUpdateMsg tripUpdates();
}
