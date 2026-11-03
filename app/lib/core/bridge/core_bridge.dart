// PRIVACY (T10 §10, T14 §10): never log Pigeon messages. Their generated
// toString() prints every field, including TripConfigMsg.destinationName.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:napstop/core/bridge/bridge_exception.dart';
import 'package:napstop/core/bridge/core_api.g.dart';

export 'bridge_exception.dart';
export 'core_api.g.dart';

/// Thin wrapper over the generated Pigeon API (spec T14 §8): one shared
/// update stream, and [PlatformException] mapped to [BridgeException].
///
/// Not final so widget tests of later tasks can implement it.
class CoreBridge {
  new({
    TripHostApi? tripApi,
    PermissionHostApi? permissionApi,
    AlarmHostApi? alarmApi,
    Stream<TripUpdateMsg> Function()? updatesFactory,
  }) : _trip = tripApi ?? TripHostApi(),
       _permission = permissionApi ?? PermissionHostApi(),
       _alarm = alarmApi ?? AlarmHostApi(),
       _updatesFactory = updatesFactory ?? tripUpdates;

  final TripHostApi _trip;
  final PermissionHostApi _permission;
  final AlarmHostApi _alarm;
  final Stream<TripUpdateMsg> Function() _updatesFactory;

  /// The one broadcast stream of trip updates. Pigeon creates a new event
  /// channel per `tripUpdates()` call, so it is created once, lazily. The
  /// native side only sends while someone listens (T14 §2).
  ///
  /// Every subscriber starts with the latest [TripStateUpdateMsg]: the native
  /// side replays it on `onListen`, which only the first subscriber triggers,
  /// so later subscribers get the last one this bridge has seen. Never an old
  /// event, nothing once that trip's [TripEndedMsg] has arrived, and nothing
  /// left over after every subscriber has cancelled (review T14 M5).
  late final Stream<TripUpdateMsg> updates = _replayLatestState(
    _broadcast(_updatesFactory()),
  );

  /// Latest view, kept only while somebody listens and the trip has not ended.
  TripStateUpdateMsg? _latestState;
  int _subscribers = 0;

  static Stream<T> _broadcast<T>(Stream<T> s) =>
      s.isBroadcast ? s : s.asBroadcastStream();

  Stream<TripUpdateMsg> _replayLatestState(
    Stream<TripUpdateMsg> source,
  ) => Stream<TripUpdateMsg>.multi((controller) {
    final latest = _latestState;
    if (latest != null) {
      controller.add(latest);
    }
    _subscribers++;
    final subscription = source.listen(
      (update) {
        _remember(update);
        controller.add(update);
      },
      onError: controller.addError,
      onDone: controller.closeSync,
    );
    controller
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = () {
        if (--_subscribers == 0) {
          // Native stops sending; the next first subscriber gets its replay.
          _latestState = null;
        }
        return subscription.cancel();
      };
  }, isBroadcast: true);

  void _remember(TripUpdateMsg update) {
    switch (update) {
      case TripStateUpdateMsg():
        _latestState = update;
      case TripEndedMsg(:final trip)
          when _latestState?.state.tripId == trip.tripId:
        _latestState = null;
      default:
        break;
    }
  }

  /// Starts a trip. Coordinates are plain parameters on purpose: no Pigeon
  /// class may hold them (T14 D5).
  Future<void> startTrip(
    TripConfigMsg config, {
    required double destLat,
    required double destLng,
    SimulationMsg? simulation,
  }) => _guard(() => _trip.startTrip(config, destLat, destLng, simulation));

  Future<void> stopTrip(String tripId) => _guard(() => _trip.stopTrip(tripId));

  /// The running trip, read from the native snapshot, or null.
  Future<ActiveTripMsg?> currentTrip() => _guard(_trip.currentTrip);

  Future<void> setBatteryChoice(String tripId, BatteryChoiceMsg choice) =>
      _guard(() => _trip.setBatteryChoice(tripId, choice));

  Future<void> dismiss(String tripId) => _guard(() => _trip.dismiss(tripId));

  Future<void> snooze(String tripId) => _guard(() => _trip.snooze(tripId));

  /// Ended trips not yet acknowledged, oldest first (T14 D12).
  Future<List<FinishedTripMsg>> pendingFinishedTrips() =>
      _guard(_trip.pendingFinishedTrips);

  Future<void> ackFinishedTrips(List<String> tripIds) =>
      _guard(() => _trip.ackFinishedTrips(tripIds));

  Future<PermissionStatusMsg> permissionStatus() => _guard(_permission.status);

  Future<PermissionStatusMsg> requestPermission(PermissionKindMsg kind) =>
      _guard(() => _permission.request(kind));

  Future<bool> openSettings(SettingsTargetMsg target) =>
      _guard(() => _permission.openSettings(target));

  Future<DeviceInfoMsg> deviceInfo() => _guard(_permission.deviceInfo);

  /// Battery, alarm stream volume and Do Not Disturb, read live (T14.1). Used
  /// by the home "Sẵn sàng" card (T22) and screen 3 / `trip_start` (T25).
  /// Unreadable items are null (iOS: battery only).
  Future<DeviceStatusMsg> deviceStatus() => _guard(_permission.deviceStatus);

  /// Maps/Places key and app identity of this build (T23 D4). PRIVACY: never
  /// log the result (its toString prints the key).
  Future<MapsConfigMsg> mapsConfig() => _guard(_permission.mapsConfig);

  /// Metres from the last known position to each (lat, lng) pair of [pairs],
  /// or null (no permission, location off, no fix younger than [maxAgeMs]).
  /// The user's position never reaches Dart (T23 D9).
  Future<List<double>?> distancesFromLastKnownM(
    List<double> pairs,
    int maxAgeMs,
  ) => _guard(() => _permission.distancesFromLastKnownM(pairs, maxAgeMs));

  Future<void> previewSound(String soundId, double volume) =>
      _guard(() => _alarm.previewSound(soundId, volume));

  Future<void> stopPreview() => _guard(_alarm.stopPreview);

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw BridgeException(
        BridgeErrorCode.fromWire(e.code),
        rawCode: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }
}

/// Stub scenarios for UI work before T15/T18 (Android stub only), passed as
/// `SimulationMsg.traceAsset`.
abstract final class StubTraces {
  static const normal = 'stub/normal';
  static const gpsLost = 'stub/gps_lost';
  static const lowBattery = 'stub/low_battery';
  static const overshoot = 'stub/overshoot';
  static const noFix = 'stub/no_fix';
}
