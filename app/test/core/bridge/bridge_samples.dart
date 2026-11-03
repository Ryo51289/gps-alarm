// Sample Pigeon messages for the bridge tests (T14 D01-D08). Not a test file.
import 'package:napstop/core/bridge/core_api.g.dart';

AlarmSettingsMsg sampleAlarm() => AlarmSettingsMsg(
  soundId: 'default',
  volume: 0.8,
  rampUp: true,
  vibration: VibrationMsg.strong,
  flash: true,
  preferHeadphones: false,
  dismissMethod: DismissMethodMsg.math,
);

TripConfigMsg sampleConfig({bool nulls = false, String tripId = 't1'}) =>
    TripConfigMsg(
      tripId: tripId,
      destinationName: 'Ga Đông Hà',
      mode: nulls ? AlarmModeMsg.smart : AlarmModeMsg.distance,
      distanceThresholdM: nulls ? null : 1000,
      timeThresholdMin: nulls ? null : 15,
      preAlertEnabled: true,
      vehicleHint: VehicleKindMsg.train,
      alarm: sampleAlarm(),
      engineParamsJson: nulls ? null : '{"smartTargetS": 300.0}',
    );

SimulationMsg sampleSimulation() =>
    SimulationMsg(traceAsset: 'stub/normal', speedFactor: 60);

TripStateMsg sampleState({bool nulls = false}) => TripStateMsg(
  tripId: 't1',
  atMs: 1700000012345,
  phase: TripPhaseMsg.alarming,
  gps: GpsStatusMsg.lost,
  locationCause: AvailabilityCauseMsg.servicesOff,
  distanceM: nulls ? null : 9000,
  routeDistanceEstM: nulls ? null : 10800,
  distanceErrorM: nulls ? null : 150,
  isEstimated: true,
  etaS: nulls ? null : 600,
  etaMinS: nulls ? null : 540,
  etaMaxS: nulls ? null : 720,
  speedKmh: nulls ? null : 54.5,
  progress: nulls ? null : 0.55,
  alarmMarkerProgress: nulls ? null : 0.95,
  predictedAlarmAtMs: nulls ? null : 1700000099999,
  samplingTier: nulls ? null : SamplingTierMsg.dense,
  fallbackAtMs: nulls ? null : 1700000100499,
  fallbackStatus: FallbackStatusMsg.confirmed,
  batteryPct: nulls ? null : 30,
  batteryRisk: true,
  batteryChoice: nulls ? null : BatteryChoiceMsg.alarmEarlier,
  preAlertFired: true,
  alarmAtMs: nulls ? null : 1700000012000,
  alarmReason: nulls ? null : AlarmReasonMsg.smartTime,
  alarmRinging: true,
  snoozeCount: 1,
  snoozeUntilMs: nulls ? null : 1700000013000,
  overshootPastM: nulls ? null : 1075,
  outcome: nulls ? null : TripOutcomeMsg.snoozed,
  vehicleGuess: VehicleKindMsg.coach,
  travelledM: 11000,
);

FinishedTripMsg sampleFinished({bool nulls = false, String tripId = 't1'}) =>
    FinishedTripMsg(
      tripId: tripId,
      outcome: TripOutcomeMsg.onTime,
      endReason: EndReasonMsg.dismissed,
      endedAtMs: 1700000020000,
      startedAtMs: 1700000000000,
      alarmAtMs: nulls ? null : 1700000012000,
      alarmReason: nulls ? null : AlarmReasonMsg.distance,
      dismissedAtMs: nulls ? null : 1700000020000,
      snoozeCount: 0,
      travelledM: 19950,
      vehicleGuess: VehicleKindMsg.bus,
    );

ActiveTripMsg sampleActive({bool nulls = false}) => ActiveTripMsg(
  config: sampleConfig(nulls: nulls),
  state: sampleState(nulls: nulls),
  simulation: nulls ? null : sampleSimulation(),
);

PermissionStatusMsg samplePermissions() => PermissionStatusMsg(
  location: LocationAccessMsg.whileInUse,
  precise: PermissionStateMsg.granted,
  locationServicesEnabled: true,
  notifications: PermissionStateMsg.granted,
  fullScreenIntent: PermissionStateMsg.granted,
  exactAlarm: PermissionStateMsg.granted,
  batteryOptimizationIgnored: PermissionStateMsg.denied,
  alarmKit: PermissionStateMsg.notApplicable,
);

DeviceInfoMsg sampleDevice({bool nulls = false}) => DeviceInfoMsg(
  platform: PlatformMsg.android,
  manufacturer: 'Google',
  brand: 'google',
  model: 'sdk_gphone64_x86_64',
  osVersion: '14',
  androidSdkInt: nulls ? null : 34,
  iosMajor: nulls ? null : 26,
);

DeviceStatusMsg sampleDeviceStatus({bool nulls = false}) => DeviceStatusMsg(
  batteryPct: nulls ? null : 4,
  charging: nulls ? null : false,
  alarmVolumePct: nulls ? null : 43,
  alarmMuted: nulls ? null : true,
  interruptionFilter: nulls
      ? InterruptionFilterMsg.unknown
      : InterruptionFilterMsg.priority,
  priorityAllowsAlarms: nulls ? null : true,
);

/// T23: Maps/Places configuration (fake key, never a real one).
MapsConfigMsg sampleMapsConfig({bool nulls = false}) => MapsConfigMsg(
  apiKey: nulls ? null : 'test-key',
  androidPackage: nulls ? null : 'app.napstop.dev',
  androidCertSha1: nulls ? null : 'A9993E364706816ABA3E25717850C26C9CD0D89D',
  iosBundleId: nulls ? null : 'app.napstop',
);

/// One instance of every TripUpdateMsg subclass, all fields set or all
/// nullable fields null.
List<TripUpdateMsg> sampleUpdates({required bool nulls}) => [
  TripStateUpdateMsg(state: sampleState(nulls: nulls)),
  PreAlertMsg(
    tripId: 't1',
    atMs: 1,
    distanceM: 15000,
    etaS: nulls ? null : 1000,
  ),
  AlarmMsg(
    tripId: 't1',
    atMs: 2,
    reason: AlarmReasonMsg.snoozeEnd,
    ringNow: true,
    snoozeAllowed: false,
    distanceM: nulls ? null : 900,
    etaS: nulls ? null : 60,
    batteryPct: nulls ? null : 12,
  ),
  SnoozedMsg(tripId: 't1', atMs: 3, untilMs: 1003),
  GpsLostMsg(
    tripId: 't1',
    atMs: 4,
    cause: GpsLostCauseMsg.noFixTimeout,
    lastFixAgeS: nulls ? null : 15,
  ),
  GpsRecoveredMsg(tripId: 't1', atMs: 5, lostForS: 180),
  LowBatteryRiskMsg(
    tripId: 't1',
    atMs: 6,
    levelPct: 30,
    availableMin: 40,
    neededMin: 55,
  ),
  OvershootMsg(tripId: 't1', atMs: 7, pastM: 1075),
  ArrivedMsg(tripId: 't1', atMs: 8, distanceM: 20),
  TripEndedMsg(atMs: 9, trip: sampleFinished(nulls: nulls)),
];
