// T26 builders of trip views and configs. Not a test file.
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';

/// Trip clock of the default view.
const int kAtMs = 1762372800000;

const String kTripId = 'trip-1';

AlarmSettingsMsg alarmMsg({
  String soundId = 'default',
  double volume = 0.8,
  bool preferHeadphones = false,
}) => AlarmSettingsMsg(
  soundId: soundId,
  volume: volume,
  rampUp: true,
  vibration: VibrationMsg.strong,
  flash: false,
  preferHeadphones: preferHeadphones,
  dismissMethod: DismissMethodMsg.swipe,
);

TripConfigMsg configMsg({
  String tripId = kTripId,
  String destinationName = 'Ga Đồng Hới',
  AlarmModeMsg mode = AlarmModeMsg.smart,
  int? distanceThresholdM,
  int? timeThresholdMin,
  AlarmSettingsMsg? alarm,
  String? engineParamsJson,
}) => TripConfigMsg(
  tripId: tripId,
  destinationName: destinationName,
  mode: mode,
  distanceThresholdM: distanceThresholdM,
  timeThresholdMin: timeThresholdMin,
  preAlertEnabled: true,
  vehicleHint: VehicleKindMsg.train,
  alarm: alarm ?? alarmMsg(),
  engineParamsJson: engineParamsJson,
);

TripStateMsg stateMsg({
  String tripId = kTripId,
  int atMs = kAtMs,
  TripPhaseMsg phase = TripPhaseMsg.tracking,
  GpsStatusMsg gps = GpsStatusMsg.ok,
  AvailabilityCauseMsg locationCause = AvailabilityCauseMsg.available,
  int? distanceM,
  int? distanceErrorM,
  bool isEstimated = false,
  int? etaS,
  double? speedKmh,
  double? progress,
  double? alarmMarkerProgress,
  int? predictedAlarmAtMs,
  SamplingTierMsg? samplingTier,
  FallbackStatusMsg fallbackStatus = FallbackStatusMsg.notSet,
  int? batteryPct,
  bool batteryRisk = false,
  BatteryChoiceMsg? batteryChoice,
  AlarmReasonMsg? alarmReason,
  bool alarmRinging = false,
  int? snoozeUntilMs,
  int? overshootPastM,
  TripOutcomeMsg? outcome,
}) => TripStateMsg(
  tripId: tripId,
  atMs: atMs,
  phase: phase,
  gps: gps,
  locationCause: locationCause,
  distanceM: distanceM,
  distanceErrorM: distanceErrorM,
  isEstimated: isEstimated,
  etaS: etaS,
  speedKmh: speedKmh,
  progress: progress,
  alarmMarkerProgress: alarmMarkerProgress,
  predictedAlarmAtMs: predictedAlarmAtMs,
  samplingTier: samplingTier,
  fallbackStatus: fallbackStatus,
  batteryPct: batteryPct,
  batteryRisk: batteryRisk,
  batteryChoice: batteryChoice,
  preAlertFired: false,
  alarmReason: alarmReason,
  alarmRinging: alarmRinging,
  snoozeCount: 0,
  snoozeUntilMs: snoozeUntilMs,
  overshootPastM: overshootPastM,
  outcome: outcome,
  vehicleGuess: VehicleKindMsg.train,
  travelledM: 0,
);

TrackedTrip tracked({
  TripStateMsg? state,
  TripConfigMsg? config,
  SimulationMsg? simulation,
  int receivedAtMs = kAtMs,
  int? acquiringSinceMs,
  bool neverAcquired = false,
  LowBatteryRiskMsg? lowBattery,
}) => TrackedTrip(
  config: config ?? configMsg(),
  simulation: simulation,
  state: state ?? stateMsg(),
  receivedAtMs: receivedAtMs,
  acquiringSinceMs: acquiringSinceMs,
  neverAcquired: neverAcquired,
  lowBattery: lowBattery,
);

ActiveTripMsg activeMsg({
  TripStateMsg? state,
  TripConfigMsg? config,
  SimulationMsg? simulation,
}) => ActiveTripMsg(
  config: config ?? configMsg(),
  state: state ?? stateMsg(),
  simulation: simulation,
);

/// W01 view: real train trip, good GPS, 80 % battery.
TripStateMsg w01State({int atMs = kAtMs}) => stateMsg(
  atMs: atMs,
  distanceM: 148200,
  distanceErrorM: 8,
  etaS: 7800,
  speedKmh: 57.6,
  progress: 0.62,
  alarmMarkerProgress: 0.97,
  predictedAlarmAtMs: atMs + 7200000,
  samplingTier: SamplingTierMsg.sparse,
  batteryPct: 80,
);

/// U08 / W02 view: GPS lost, estimating.
TripStateMsg estimatedState({int atMs = kAtMs}) => stateMsg(
  atMs: atMs,
  gps: GpsStatusMsg.lost,
  isEstimated: true,
  speedKmh: 28.4,
  distanceErrorM: 1200,
  distanceM: 148000,
  etaS: 7800,
  progress: 0.6,
  alarmMarkerProgress: 0.97,
  batteryPct: 80,
);

LowBatteryRiskMsg lowBatteryMsg({
  String tripId = kTripId,
  int levelPct = 18,
  int availableMin = 70,
  int neededMin = 120,
}) => LowBatteryRiskMsg(
  tripId: tripId,
  atMs: kAtMs,
  levelPct: levelPct,
  availableMin: availableMin,
  neededMin: neededMin,
);

TripEndedMsg endedMsg({
  String tripId = kTripId,
  TripOutcomeMsg outcome = TripOutcomeMsg.onTime,
  EndReasonMsg endReason = EndReasonMsg.dismissed,
}) => TripEndedMsg(
  atMs: kAtMs + 1000,
  trip: FinishedTripMsg(
    tripId: tripId,
    outcome: outcome,
    endReason: endReason,
    endedAtMs: kAtMs + 1000,
    startedAtMs: kAtMs - 3600000,
    snoozeCount: 0,
    travelledM: 0,
    vehicleGuess: VehicleKindMsg.train,
  ),
);
