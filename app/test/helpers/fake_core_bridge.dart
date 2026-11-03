// Shared fake of CoreBridge for widget tests (T22; reused by T21, T23,
// T25-T28). Not a test file.
import 'dart:async';

import 'package:napstop/core/bridge/core_bridge.dart';

/// Android permissions; everything granted by default.
PermissionStatusMsg androidPermissions({
  LocationAccessMsg location = LocationAccessMsg.whileInUse,
  PermissionStateMsg precise = PermissionStateMsg.granted,
  bool locationServicesEnabled = true,
  PermissionStateMsg notifications = PermissionStateMsg.granted,
  PermissionStateMsg fullScreenIntent = PermissionStateMsg.granted,
  PermissionStateMsg exactAlarm = PermissionStateMsg.granted,
  PermissionStateMsg batteryOptimizationIgnored = PermissionStateMsg.granted,
}) => PermissionStatusMsg(
  location: location,
  precise: precise,
  locationServicesEnabled: locationServicesEnabled,
  notifications: notifications,
  fullScreenIntent: fullScreenIntent,
  exactAlarm: exactAlarm,
  batteryOptimizationIgnored: batteryOptimizationIgnored,
  alarmKit: PermissionStateMsg.notApplicable,
);

/// iOS permissions; location, notifications and AlarmKit granted by default.
PermissionStatusMsg iosPermissions({
  LocationAccessMsg location = LocationAccessMsg.whileInUse,
  PermissionStateMsg precise = PermissionStateMsg.granted,
  bool locationServicesEnabled = true,
  PermissionStateMsg notifications = PermissionStateMsg.granted,
  PermissionStateMsg alarmKit = PermissionStateMsg.granted,
}) => PermissionStatusMsg(
  location: location,
  precise: precise,
  locationServicesEnabled: locationServicesEnabled,
  notifications: notifications,
  fullScreenIntent: PermissionStateMsg.notApplicable,
  exactAlarm: PermissionStateMsg.notApplicable,
  batteryOptimizationIgnored: PermissionStateMsg.notApplicable,
  alarmKit: alarmKit,
);

DeviceInfoMsg androidDevice({int sdk = 34}) => DeviceInfoMsg(
  platform: PlatformMsg.android,
  manufacturer: 'Google',
  brand: 'google',
  model: 'Pixel 8',
  osVersion: '14',
  androidSdkInt: sdk,
);

DeviceInfoMsg iosDevice({int major = 26}) => DeviceInfoMsg(
  platform: PlatformMsg.ios,
  manufacturer: 'Apple',
  brand: 'Apple',
  model: 'iPhone',
  osVersion: '$major.0',
  iosMajor: major,
);

/// Defaults: battery 82 % not charging, alarm volume 100 %, DND off.
DeviceStatusMsg deviceStatusMsg({
  int? batteryPct = 82,
  bool? charging = false,
  int? alarmVolumePct = 100,
  bool? alarmMuted = false,
  InterruptionFilterMsg interruptionFilter = InterruptionFilterMsg.all,
  bool? priorityAllowsAlarms,
}) => DeviceStatusMsg(
  batteryPct: batteryPct,
  charging: charging,
  alarmVolumePct: alarmVolumePct,
  alarmMuted: alarmMuted,
  interruptionFilter: interruptionFilter,
  priorityAllowsAlarms: priorityAllowsAlarms,
);

TripStateMsg tripState({
  String tripId = 'trip-1',
  TripPhaseMsg phase = TripPhaseMsg.tracking,
}) => TripStateMsg(
  tripId: tripId,
  atMs: 1700000000000,
  phase: phase,
  gps: GpsStatusMsg.ok,
  locationCause: AvailabilityCauseMsg.available,
  isEstimated: false,
  fallbackStatus: FallbackStatusMsg.notSet,
  batteryRisk: false,
  preAlertFired: false,
  alarmRinging: false,
  snoozeCount: 0,
  vehicleGuess: VehicleKindMsg.unknown,
  travelledM: 0,
);

ActiveTripMsg activeTrip({
  String tripId = 'trip-1',
  String destinationName = 'Ga Huế',
  TripPhaseMsg phase = TripPhaseMsg.tracking,
}) => ActiveTripMsg(
  config: TripConfigMsg(
    tripId: tripId,
    destinationName: destinationName,
    mode: AlarmModeMsg.smart,
    preAlertEnabled: true,
    vehicleHint: VehicleKindMsg.train,
    alarm: AlarmSettingsMsg(
      soundId: 'default',
      volume: 1,
      rampUp: true,
      vibration: VibrationMsg.strong,
      flash: false,
      preferHeadphones: false,
      dismissMethod: DismissMethodMsg.swipe,
    ),
  ),
  state: tripState(tripId: tripId, phase: phase),
);

TripEndedMsg tripEnded({String tripId = 'trip-1'}) => TripEndedMsg(
  atMs: 1700000100000,
  trip: FinishedTripMsg(
    tripId: tripId,
    outcome: TripOutcomeMsg.cancelled,
    endReason: EndReasonMsg.userStop,
    endedAtMs: 1700000100000,
    startedAtMs: 1700000000000,
    snoozeCount: 0,
    travelledM: 0,
    vehicleGuess: VehicleKindMsg.unknown,
  ),
);

/// A [CoreBridge] with settable results. Set an `...Error` field to make the
/// matching call throw it. [calls] records method names in call order.
class FakeCoreBridge implements CoreBridge {
  new({
    PermissionStatusMsg? permissions,
    DeviceInfoMsg? deviceInfoValue,
    this.deviceStatusValue,
    this.active,
    MapsConfigMsg? mapsConfig,
    this.distances,
  }) : permissions = permissions ?? androidPermissions(),
       deviceInfoValue = deviceInfoValue ?? androidDevice(),
       mapsConfigValue = mapsConfig ?? MapsConfigMsg() {
    deviceStatusValue ??= deviceStatusMsg();
  }

  PermissionStatusMsg permissions;
  DeviceInfoMsg deviceInfoValue;
  DeviceStatusMsg? deviceStatusValue;

  /// Returned by [mapsConfig]; no key by default (map placeholder, Places
  /// "not configured"), like a CI build (T23).
  MapsConfigMsg mapsConfigValue;

  /// Answers [distancesFromLastKnownM] from the requested pairs; null
  /// answers null (no position).
  List<double>? Function(List<double> pairs)? distances;

  /// Arguments of every [distancesFromLastKnownM] call, in order.
  final List<({List<double> pairs, int maxAgeMs})> distancesCalls = [];

  Object? mapsConfigError;
  Object? distancesError;

  /// Returned by [currentTrip].
  ActiveTripMsg? active;

  Object? permissionStatusError;
  Object? deviceInfoError;
  Object? deviceStatusError;
  Object? currentTripError;
  Object? startTripError;

  final List<String> calls = [];
  final StreamController<TripUpdateMsg> _updates =
      StreamController<TripUpdateMsg>.broadcast();

  /// Number of calls to [method].
  int callCount(String method) => calls.where((c) => c == method).length;

  /// Sends [update] to every listener of [updates].
  void emit(TripUpdateMsg update) => _updates.add(update);

  /// Whether anybody listens to [updates] right now.
  bool get hasListener => _updates.hasListener;

  /// When set, [currentTrip] waits for it before answering (ordering tests).
  Completer<void>? currentTripGate;

  Future<void> close() => _updates.close();

  Future<T> _answer<T>(String method, Object? error, T Function() value) {
    calls.add(method);
    if (error != null) {
      return Future<T>.error(error);
    }
    return Future<T>.value(value());
  }

  @override
  Stream<TripUpdateMsg> get updates => _updates.stream;

  @override
  Future<void> startTrip(
    TripConfigMsg config, {
    required double destLat,
    required double destLng,
    SimulationMsg? simulation,
  }) => _answer('startTrip', startTripError, () {});

  @override
  Future<void> stopTrip(String tripId) => _answer('stopTrip', null, () {});

  @override
  Future<ActiveTripMsg?> currentTrip() {
    final gate = currentTripGate;
    if (gate == null) {
      return _answer('currentTrip', currentTripError, () => active);
    }
    calls.add('currentTrip');
    return gate.future.then<ActiveTripMsg?>((_) {
      final error = currentTripError;
      return error == null ? active : Future<ActiveTripMsg?>.error(error);
    });
  }

  @override
  Future<void> setBatteryChoice(String tripId, BatteryChoiceMsg choice) =>
      _answer('setBatteryChoice', null, () {});

  @override
  Future<void> dismiss(String tripId) => _answer('dismiss', null, () {});

  @override
  Future<void> snooze(String tripId) => _answer('snooze', null, () {});

  @override
  Future<List<FinishedTripMsg>> pendingFinishedTrips() =>
      _answer('pendingFinishedTrips', null, () => const []);

  @override
  Future<void> ackFinishedTrips(List<String> tripIds) =>
      _answer('ackFinishedTrips', null, () {});

  @override
  Future<PermissionStatusMsg> permissionStatus() =>
      _answer('permissionStatus', permissionStatusError, () => permissions);

  @override
  Future<PermissionStatusMsg> requestPermission(PermissionKindMsg kind) =>
      _answer('requestPermission', null, () => permissions);

  @override
  Future<bool> openSettings(SettingsTargetMsg target) =>
      _answer('openSettings', null, () => true);

  @override
  Future<DeviceInfoMsg> deviceInfo() =>
      _answer('deviceInfo', deviceInfoError, () => deviceInfoValue);

  @override
  Future<DeviceStatusMsg> deviceStatus() => _answer(
    'deviceStatus',
    deviceStatusError,
    () =>
        deviceStatusValue ??
        DeviceStatusMsg(interruptionFilter: InterruptionFilterMsg.unknown),
  );

  @override
  Future<MapsConfigMsg> mapsConfig() =>
      _answer('mapsConfig', mapsConfigError, () => mapsConfigValue);

  @override
  Future<List<double>?> distancesFromLastKnownM(
    List<double> pairs,
    int maxAgeMs,
  ) {
    distancesCalls.add((pairs: List.unmodifiable(pairs), maxAgeMs: maxAgeMs));
    return _answer(
      'distancesFromLastKnownM',
      distancesError,
      () => distances?.call(pairs),
    );
  }

  @override
  Future<void> previewSound(String soundId, double volume) =>
      _answer('previewSound', null, () {});

  @override
  Future<void> stopPreview() => _answer('stopPreview', null, () {});
}

/// The error a failing Pigeon channel produces (T14 §4).
BridgeException channelError() => const BridgeException(
  BridgeErrorCode.channelError,
  rawCode: 'channel-error',
);
