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

DeviceInfoMsg androidDevice({
  int sdk = 34,
  String manufacturer = 'Google',
  String brand = 'google',
}) => DeviceInfoMsg(
  platform: PlatformMsg.android,
  manufacturer: manufacturer,
  brand: brand,
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
  bool? headphonesConnected,
}) => DeviceStatusMsg(
  batteryPct: batteryPct,
  charging: charging,
  alarmVolumePct: alarmVolumePct,
  alarmMuted: alarmMuted,
  interruptionFilter: interruptionFilter,
  priorityAllowsAlarms: priorityAllowsAlarms,
  headphonesConnected: headphonesConnected,
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

  /// Answers [requestPermission]; null returns [permissions] (T21).
  PermissionStatusMsg Function(PermissionKindMsg kind)? requestPermissionResult;

  /// Thrown by [requestPermission] when set (T21).
  Object? requestPermissionError;

  /// When set, [requestPermission] waits for it before answering (T21 W08).
  Completer<void>? requestGate;

  /// Returned by [openSettings] (T21).
  bool openSettingsResult = true;

  /// Thrown by [openSettings] when set (T21).
  Object? openSettingsError;

  /// Arguments of every [requestPermission] / [openSettings] call (T21).
  final List<PermissionKindMsg> requestCalls = [];
  final List<SettingsTargetMsg> openSettingsCalls = [];

  /// Returned by [backgroundCheck] (T21 screen 9).
  BackgroundCheckMsg? backgroundCheckValue;

  /// Answers [startBackgroundCheck]; null returns a record due in `delay`
  /// from [backgroundCheckNowMs], and stores it in [backgroundCheckValue].
  BackgroundCheckMsg Function(Duration delay)? startBackgroundCheckResult;
  Object? startBackgroundCheckError;

  /// "Now" of the default [startBackgroundCheck] record.
  int backgroundCheckNowMs = 1700000000000;

  /// When set, [startBackgroundCheck] waits for it before answering (T21).
  Completer<void>? startBackgroundCheckGate;

  /// Arguments of every [startBackgroundCheck] call.
  final List<Duration> startBackgroundCheckCalls = [];
  Object? deviceInfoError;
  Object? deviceStatusError;
  Object? currentTripError;
  Object? startTripError;

  final List<String> calls = [];

  /// Arguments of every [startTrip] call, in order (T25).
  final List<StartTripCall> startTripCalls = [];

  /// When set, [startTrip] waits for it before answering (T25 W13).
  Completer<void>? startTripGate;
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
  }) {
    startTripCalls.add((
      config: config,
      destLat: destLat,
      destLng: destLng,
      simulation: simulation,
    ));
    final gate = startTripGate;
    if (gate == null) {
      return _answer('startTrip', startTripError, () {
        // T26: like native, a started trip is in the snapshot (screen 4
        // reads it). Gated (late) answers leave [active] to the test.
        if (startTripSetsActive) {
          active ??= ActiveTripMsg(
            config: config,
            state: tripState(
              tripId: config.tripId,
              phase: TripPhaseMsg.acquiring,
            ),
            simulation: simulation,
          );
        }
      });
    }
    calls.add('startTrip');
    return gate.future.then((_) {
      final error = startTripError;
      return error == null ? null : Future<void>.error(error);
    });
  }

  @override
  Future<void> stopTrip(String tripId) {
    stopTripCalls.add(tripId);
    return _action('stopTrip', stopTripError);
  }

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
  Future<void> setBatteryChoice(String tripId, BatteryChoiceMsg choice) {
    batteryChoiceCalls.add((tripId: tripId, choice: choice));
    return _action('setBatteryChoice', setBatteryChoiceError);
  }

  @override
  Future<void> dismiss(String tripId) {
    dismissCalls.add(tripId);
    return _action('dismiss', dismissError);
  }

  // ------------------------------------------------------------ T26

  /// A successful, ungated [startTrip] sets [active] when it is null.
  bool startTripSetsActive = true;

  /// Arguments of [stopTrip], [dismiss], [setBatteryChoice] and
  /// [previewSound], in order.
  final List<String> stopTripCalls = [];
  final List<String> dismissCalls = [];
  final List<({String tripId, BatteryChoiceMsg choice})> batteryChoiceCalls =
      [];
  final List<({String soundId, double volume})> previewSoundCalls = [];

  Object? stopTripError;
  Object? dismissError;
  Object? setBatteryChoiceError;
  Object? previewSoundError;

  /// When set, [stopTrip], [dismiss] and [setBatteryChoice] wait for it.
  Completer<void>? actionGate;

  Future<void> _action(String method, Object? error) {
    final gate = actionGate;
    if (gate == null) {
      return _answer(method, error, () {});
    }
    calls.add(method);
    return gate.future.then((_) => error == null ? null : Future.error(error));
  }

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
  Future<PermissionStatusMsg> requestPermission(PermissionKindMsg kind) {
    requestCalls.add(kind);
    PermissionStatusMsg answer() {
      final next = requestPermissionResult?.call(kind);
      if (next != null) {
        permissions = next;
      }
      return permissions;
    }

    final gate = requestGate;
    if (gate == null) {
      return _answer('requestPermission', requestPermissionError, answer);
    }
    calls.add('requestPermission');
    return gate.future.then((_) {
      final error = requestPermissionError;
      return error == null
          ? answer()
          : Future<PermissionStatusMsg>.error(error);
    });
  }

  @override
  Future<bool> openSettings(SettingsTargetMsg target) {
    openSettingsCalls.add(target);
    return _answer('openSettings', openSettingsError, () => openSettingsResult);
  }

  @override
  Future<BackgroundCheckMsg> startBackgroundCheck(Duration delay) {
    startBackgroundCheckCalls.add(delay);
    BackgroundCheckMsg answer() {
      final record =
          startBackgroundCheckResult?.call(delay) ??
          BackgroundCheckMsg(
            scheduledAtMs: backgroundCheckNowMs,
            dueAtMs: backgroundCheckNowMs + delay.inMilliseconds,
            exact: true,
          );
      backgroundCheckValue = record;
      return record;
    }

    final gate = startBackgroundCheckGate;
    if (gate == null) {
      return _answer('startBackgroundCheck', startBackgroundCheckError, answer);
    }
    calls.add('startBackgroundCheck');
    return gate.future.then((_) {
      final error = startBackgroundCheckError;
      return error == null ? answer() : Future<BackgroundCheckMsg>.error(error);
    });
  }

  @override
  Future<BackgroundCheckMsg?> backgroundCheck() =>
      _answer('backgroundCheck', null, () => backgroundCheckValue);

  @override
  Future<void> cancelBackgroundCheck() =>
      _answer('cancelBackgroundCheck', null, () {
        backgroundCheckValue = null;
      });

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
  Future<void> previewSound(String soundId, double volume) {
    previewSoundCalls.add((soundId: soundId, volume: volume));
    return _answer('previewSound', previewSoundError, () {});
  }

  @override
  Future<void> stopPreview() => _answer('stopPreview', null, () {});

  /// Returned once by [consumeLaunchAction] (then cleared), like native (T27).
  LaunchActionMsg? launchAction;

  /// Returned by [showAlarmScreen] (T27).
  bool showAlarmScreenResult = false;

  /// Arguments of every [showAlarmScreen] / [setAppLocale] call.
  final List<String> showAlarmScreenCalls = [];
  final List<String?> setAppLocaleCalls = [];

  @override
  Future<LaunchActionMsg?> consumeLaunchAction() =>
      _answer('consumeLaunchAction', null, () {
        final action = launchAction;
        launchAction = null;
        return action;
      });

  @override
  Future<bool> showAlarmScreen(String tripId) {
    showAlarmScreenCalls.add(tripId);
    return _answer('showAlarmScreen', null, () => showAlarmScreenResult);
  }

  @override
  Future<void> setAppLocale(String? languageTag) {
    setAppLocaleCalls.add(languageTag);
    return _answer('setAppLocale', null, () {});
  }
}

/// One [FakeCoreBridge.startTrip] call.
typedef StartTripCall = ({
  TripConfigMsg config,
  double destLat,
  double destLng,
  SimulationMsg? simulation,
});

/// The error a failing Pigeon channel produces (T14 §4).
BridgeException channelError() => const BridgeException(
  BridgeErrorCode.channelError,
  rawCode: 'channel-error',
);
