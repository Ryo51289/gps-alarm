// T17.1 PC05 (docs/specs/T17.1.md): the real iOS PermissionHostApi on the
// Simulator. Location granted by app/ios/scripts/ci-sim.sh (`simctl privacy
// grant location`); the ios-sim job sets the simulated location to
// `_hereLat, _hereLng` (integration_test/ios_suite.txt), about 1.23 km north of
// Ga Đồng Hới. Skipped on Android. By hand on a Mac:
//   xcrun simctl privacy <udid> grant location <bundle id>
//   xcrun simctl location <udid> set 17.4800199,106.5997285
//   flutter test integration_test/t17_1_ios_permissions_test.dart -d <udid>
// Logs no coordinates and no distances (the points are public fixture data).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

final bool _notIos = !Platform.isIOS;

/// Ga Đồng Hới (fixtures/traces/train_hn_dh.expect.json destination).
const double _stationLat = 17.4689199;
const double _stationLng = 106.5997285;

/// Simulated position: 0.0111° north of the station, 1 234 m on a sphere,
/// about 1 228 m on the WGS 84 ellipsoid; both round to 1 200 m. Must match
/// the point of this file in integration_test/ios_suite.txt.
const double _hereLat = 17.4800199;

/// `maxAgeMs` of the call (spec PC05).
const int _maxAgeMs = 600000;

TripConfigMsg _warmUpConfig(String tripId) => TripConfigMsg(
  tripId: tripId,
  destinationName: 'Ga Đồng Hới',
  mode: AlarmModeMsg.distance,
  distanceThresholdM: 1000,
  preAlertEnabled: false,
  vehicleHint: VehicleKindMsg.train,
  alarm: AlarmSettingsMsg(
    soundId: 'default',
    volume: 0.8,
    rampUp: true,
    vibration: VibrationMsg.medium,
    flash: false,
    preferHeadphones: false,
    dismissMethod: DismissMethodMsg.swipe,
  ),
);

/// Polls `CoreBridge.distancesFromLastKnownM` for up to [timeout].
Future<List<double>?> _poll(
  CoreBridge bridge, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final d = await bridge.distancesFromLastKnownM([
      _stationLat,
      _stationLng,
    ], _maxAgeMs);
    if (d != null || DateTime.now().isAfter(deadline)) {
      return d;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'PC05 status() reads the granted location permission',
    skip: _notIos,
    (tester) async {
      final s = await CoreBridge().permissionStatus();
      expect(
        s.location,
        anyOf(LocationAccessMsg.whileInUse, LocationAccessMsg.always),
      );
      expect(s.precise, PermissionStateMsg.granted);
      expect(s.locationServicesEnabled, isTrue);
      // T21 §9: Android-only items, never notApplicable for precise.
      expect(s.fullScreenIntent, PermissionStateMsg.notApplicable);
      expect(s.exactAlarm, PermissionStateMsg.notApplicable);
      expect(s.batteryOptimizationIgnored, PermissionStateMsg.notApplicable);
    },
  );

  testWidgets('PC05 openSettings(locationServices) is false', skip: _notIos, (
    tester,
  ) async {
    expect(
      await CoreBridge().openSettings(SettingsTargetMsg.locationServices),
      isFalse,
    );
    expect(
      await CoreBridge().openSettings(SettingsTargetMsg.exactAlarm),
      isFalse,
    );
  });

  testWidgets(
    'PC05 distancesFromLastKnownM: rounded distance to the station',
    skip: _notIos,
    (tester) async {
      final bridge = CoreBridge();
      var d = await _poll(bridge);
      if (d == null) {
        // No cached fix yet on a fresh Simulator: a short trip makes Core
        // Location fetch one (the app's own updates), then the cache is read.
        final leftover = await bridge.currentTrip();
        if (leftover != null) {
          await bridge.stopTrip(leftover.config.tripId);
        }
        final tripId = 'pc05-${DateTime.now().millisecondsSinceEpoch}';
        await bridge.startTrip(
          _warmUpConfig(tripId),
          destLat: _stationLat + 0.27,
          destLng: _stationLng,
        );
        try {
          d = await _poll(bridge, timeout: const Duration(seconds: 30));
        } finally {
          await bridge.stopTrip(tripId);
          final ended = await bridge.pendingFinishedTrips();
          await bridge.ackFinishedTrips([for (final t in ended) t.tripId]);
        }
      }
      expect(d, isNotNull, reason: 'no cached position on the Simulator');
      expect(d, hasLength(1));
      // 1 200 m expected; one rounding step either way (RK-T171-2).
      expect(d!.single, inInclusiveRange(1100.0, 1300.0));
      expect(d.single % 100, 0, reason: 'rounded to 100 m from 1 km on');
      expect(_hereLat - _stationLat, closeTo(0.0111, 1e-9));
    },
  );

  testWidgets('PC05 invalid pairs give null', skip: _notIos, (tester) async {
    final bridge = CoreBridge();
    for (final pairs in <List<double>>[
      [],
      [_stationLat],
      [91, _stationLng],
      [_stationLat, 181],
    ]) {
      expect(
        await bridge.distancesFromLastKnownM(pairs, _maxAgeMs),
        isNull,
        reason: 'count ${pairs.length}',
      );
    }
    expect(
      await bridge.distancesFromLastKnownM([_stationLat, _stationLng], 0),
      isNull,
    );
  });
}
