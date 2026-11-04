// Manual probe for T14 M01 and the lifecycle checks of review M1 (protocol:
// docs/test-protocols/T14.md). Not a test file: build it as the app's entry
// point, then kill/relaunch the process with adb and read logcat.
//
//   flutter build apk --debug -t integration_test/manual/bridge_restore_probe.dart
//   adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
//   adb shell am start -n app.napstop.dev/app.napstop.MainActivity
//   adb logcat -s flutter
//
// Restore probe of the real trip runtime: LM6 of T15 (docs/test-protocols/T15.md).
//
// First launch with no trip: starts a stub trip (stub/normal at 1x).
// Every later launch: prints what currentTrip() restored, then listens to
// `updates` and prints how long the first TripStateUpdateMsg took. Logs only
// the trip id, enums and times: never the destination name or coordinates.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

const _tag = 'NAPSTOP_PROBE';

void _log(String message) => debugPrint('$_tag $message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('T14 bridge probe')),
    ),
  );
  final bridge = CoreBridge();
  final launchedAt = DateTime.now();

  final trip = await bridge.currentTrip();
  if (trip == null) {
    final tripId = 'm01-${launchedAt.millisecondsSinceEpoch}';
    await bridge.startTrip(
      TripConfigMsg(
        tripId: tripId,
        destinationName: 'Ga Đông Hà',
        mode: AlarmModeMsg.smart,
        preAlertEnabled: true,
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
      ),
      destLat: 16.8163,
      destLng: 107.1003,
      // Since T15 a start without `simulation` is a real trip (T15 D14).
      simulation: SimulationMsg(traceAsset: StubTraces.normal, speedFactor: 1),
    );
    _log('started tripId=$tripId');
  } else {
    final s = trip.state;
    _log(
      'restored tripId=${trip.config.tripId} phase=${s.phase.name} '
      'simulation=${trip.simulation == null ? 'null' : 'set'} '
      'alarmInS=${((s.predictedAlarmAtMs ?? s.atMs) - s.atMs) ~/ 1000} '
      'travelledM=${s.travelledM}',
    );
  }

  var updates = 0;
  final listenAt = DateTime.now();
  bridge.updates.listen((u) {
    if (u is! TripStateUpdateMsg) {
      _log('event ${u.runtimeType}');
      return;
    }
    updates++;
    if (updates == 1) {
      final afterMs = DateTime.now().difference(listenAt).inMilliseconds;
      _log(
        'first-update afterMs=$afterMs '
        'phase=${u.state.phase.name} tripId=${u.state.tripId}',
      );
    } else if (updates % 5 == 0) {
      _log('update n=$updates phase=${u.state.phase.name}');
    }
  });
}
