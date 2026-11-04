// Restore probe of the real trip runtime: compare with LM6 of T15
// (docs/test-protocols/T15.md). Since T18 a simulated trip is never restored
// after a process death (T18 D9), so the probe starts a REAL trip: grant
// location first and give the emulator a position (adb emu geo fix).
//
// Manual probe for T14.1 (protocol: docs/test-protocols/T14.1.md, P02): a
// 16 384-code-unit engineParamsJson survives a real process death byte for
// byte through the runtime snapshot. Not a test file: build it as the
// app's entry point, then kill/relaunch the process with adb and read logcat.
//
//   flutter build apk --debug -t integration_test/manual/engine_params_restore_probe.dart
//   adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
//   adb shell am start -n app.napstop.dev/app.napstop.MainActivity
//   adb shell am kill app.napstop.dev   (after pressing Home), or force-stop
//   adb shell am start -n app.napstop.dev/app.napstop.MainActivity
//   adb logcat -d -s flutter | grep NAPSTOP_T141
//
// First launch with no trip: starts a real trip carrying the value. Next
// launch: compares currentTrip().config.engineParamsJson with the value it
// rebuilds deterministically, logs match + length only (never the value),
// then stops the trip and acks it.
import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

const _tag = 'NAPSTOP_T141';
const _max = 16384;

void _log(String message) => debugPrint('$_tag $message');

String _awkwardJson(int length) {
  const head =
      '{"note": "Ga Đông Hà = a:b #c !d \\\\e\\n\\t \u{1F634}", '
      '"smartTargetS": 60.0, "pad": "';
  const tail = '"}\n';
  return '$head${'x' * (length - head.length - tail.length)}$tail';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('T14.1 engineParamsJson probe')),
    ),
  );
  final bridge = CoreBridge();
  final expected = _awkwardJson(_max);

  final trip = await bridge.currentTrip();
  if (trip == null) {
    final tripId = 't141-${DateTime.now().millisecondsSinceEpoch}';
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
        engineParamsJson: expected,
      ),
      destLat: 16.8163,
      destLng: 107.1003,
    );
    _log('started $tripId length=${expected.length}');
    return;
  }

  final got = trip.config.engineParamsJson;
  _log(
    'restored ${trip.config.tripId} match=${got == expected} '
    'length=${got?.length} phase=${trip.state.phase.name}',
  );
  await bridge.stopTrip(trip.config.tripId);
  final done = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([for (final t in done) t.tripId]);
  _log('stopped');
}
