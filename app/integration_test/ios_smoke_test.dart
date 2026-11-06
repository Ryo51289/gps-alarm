// T01.2 CI05: iOS smoke test on the Simulator. The app starts and the
// Pigeon bridge answers (CoreBridgeStub before T17, the real runtime after).
// Run by the ios-sim job of .github/workflows/ios-compile.yml through
// integration_test/ios_suite.txt; skipped on Android. By hand on a Mac:
//   flutter test integration_test/ios_smoke_test.dart -d <simulator-udid>
// Touches no permission dialog and logs no coordinates.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/main.dart' as app;

/// Android runs nothing here: the same checks live in bridge_smoke_test.dart.
final bool _notIos = !Platform.isIOS;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts', skip: _notIos, (tester) async {
    await app.main();
    for (
      var i = 0;
      i < 100 && find.byType(NapStopApp).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NapStopApp), findsOneWidget);
    // A few frames past the first one: startup work must not throw.
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('deviceInfo reports iOS', skip: _notIos, (tester) async {
    final device = await CoreBridge().deviceInfo();
    expect(device.platform, PlatformMsg.ios);
    expect(device.androidSdkInt, isNull);
  });

  testWidgets('currentTrip answers', skip: _notIos, (tester) async {
    // Null (no trip) or a trip left by an earlier run: either way no error.
    await expectLater(CoreBridge().currentTrip(), completes);
  });

  testWidgets('pendingFinishedTrips answers', skip: _notIos, (tester) async {
    final pending = await CoreBridge().pendingFinishedTrips();
    expect(pending, isA<List<FinishedTripMsg>>());
  });

  // Diagnostics for the CI log, no assertion: what the runtime would refuse
  // (`BridgeException.toString` hides `details` on purpose). Prints state
  // names and the `permission-missing` list only, never a position.
  testWidgets('diag: permissions and startTrip probe', skip: _notIos, (
    tester,
  ) async {
    final bridge = CoreBridge();
    final s = await bridge.permissionStatus();
    debugPrint(
      'NAPSTOP_DIAG permissions: location=${s.location.name} '
      'precise=${s.precise.name} services=${s.locationServicesEnabled} '
      'notifications=${s.notifications.name} alarmKit=${s.alarmKit.name}',
    );
    final leftover = await bridge.currentTrip();
    if (leftover != null) {
      await bridge.stopTrip(leftover.config.tripId);
    }
    final tripId = 'diag-${DateTime.now().millisecondsSinceEpoch}';
    try {
      // Far from every fixture point used by the suite: no alarm.
      await bridge.startTrip(_probeConfig(tripId), destLat: 0.5, destLng: 0.5);
      debugPrint('NAPSTOP_DIAG startTrip probe: accepted');
      await bridge.stopTrip(tripId);
    } on BridgeException catch (e) {
      debugPrint(
        'NAPSTOP_DIAG startTrip probe: rejected ${e.rawCode} '
        'details=${e.details}',
      );
    }
    final old = await bridge.pendingFinishedTrips();
    await bridge.ackFinishedTrips([for (final t in old) t.tripId]);
  });
}

TripConfigMsg _probeConfig(String tripId) => TripConfigMsg(
  tripId: tripId,
  destinationName: 'diag',
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
