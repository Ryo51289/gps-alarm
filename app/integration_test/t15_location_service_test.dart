// LI01–LI04 (spec T15): real trips through the Android trip runtime
// (foreground service `location`, Fused Location, interim alarm), flavor dev.
//
// Emulator API 34+ with Google Play services. Before running (P = package
// app.napstop.dev):
//   adb shell pm grant P android.permission.ACCESS_FINE_LOCATION
//   adb shell pm grant P android.permission.ACCESS_COARSE_LOCATION
//   adb shell pm grant P android.permission.POST_NOTIFICATIONS
//   adb emu geo fix <lng> <lat>     (e.g. adb emu geo fix 107.1003 16.8163)
//   flutter test integration_test/t15_location_service_test.dart \
//     -d <device-id> --dart-define=T15_LAT=16.8163 \
//     --dart-define=T15_LNG=107.1003
// Checks by hand / adb while it runs (docs/test-protocols/T15.md):
//   adb shell dumpsys activity services P   (LocationService, type location)
//   adb shell dumpsys alarm | grep P        (no alarm left after LI03)
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

const _lat = String.fromEnvironment('T15_LAT', defaultValue: '16.8163');
const _lng = String.fromEnvironment('T15_LNG', defaultValue: '107.1003');

/// Polls [received] (from index [from]) until an item matches [test].
Future<T> _waitFor<T extends TripUpdateMsg>(
  List<TripUpdateMsg> received, {
  required int from,
  bool Function(T)? test,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final item in received.skip(from)) {
      if (item is T && (test == null || test(item))) {
        return item;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('no $T within $timeout');
}

TripConfigMsg _config(String tripId) => TripConfigMsg(
  tripId: tripId,
  destinationName: 'Đích thử T15',
  mode: AlarmModeMsg.distance,
  distanceThresholdM: 1000,
  preAlertEnabled: false,
  vehicleHint: VehicleKindMsg.coach,
  alarm: AlarmSettingsMsg(
    soundId: 'default',
    volume: 0.8,
    rampUp: false,
    vibration: VibrationMsg.medium,
    flash: false,
    preferHeadphones: false,
    dismissMethod: DismissMethodMsg.swipe,
  ),
);

Future<void> _cleanSlate(CoreBridge bridge) async {
  final leftover = await bridge.currentTrip();
  if (leftover != null) {
    await bridge.stopTrip(leftover.config.tripId);
  }
  final old = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([for (final t in old) t.tripId]);
}

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final bridge = CoreBridge();
  final lat = double.parse(_lat);
  final lng = double.parse(_lng);

  testWidgets('LI01 start inside the alarm zone rings at once; dismiss '
      'ends the trip', (tester) async {
    await _cleanSlate(bridge);
    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);
    await tester.pump(const Duration(milliseconds: 500));
    final from = received.length;

    final tripId = _id('li01');
    await bridge.startTrip(_config(tripId), destLat: lat, destLng: lng);
    // T25 review round 2: the first state is sent before startTrip returns
    // (delivered through the event channel right after).
    final first = await _waitFor<TripStateUpdateMsg>(
      received,
      from: from,
      test: (u) => u.state.tripId == tripId,
      timeout: const Duration(seconds: 5),
    );
    expect(first.state.phase, isNot(TripPhaseMsg.ended));

    // PRD §4: starting inside the alarm zone rings right away.
    final alarm = await _waitFor<AlarmMsg>(
      received,
      from: from,
      test: (a) => a.tripId == tripId && a.ringNow,
    );
    expect(alarm.reason, AlarmReasonMsg.distance);
    final active = await bridge.currentTrip();
    expect(active?.config.tripId, tripId);
    expect(active?.simulation, isNull);
    expect(active?.state.alarmRinging, isTrue);

    await bridge.dismiss(tripId);
    final ended = await _waitFor<TripEndedMsg>(
      received,
      from: from,
      test: (e) => e.trip.tripId == tripId,
      timeout: const Duration(seconds: 10),
    );
    expect(ended.trip.outcome, TripOutcomeMsg.onTime);
    expect(await bridge.currentTrip(), isNull);
    final records = await bridge.pendingFinishedTrips();
    expect(records.map((r) => r.tripId), contains(tripId));
    await bridge.ackFinishedTrips([tripId]);
  });

  testWidgets('LI02 a second startTrip while a trip runs is trip-active', (
    tester,
  ) async {
    await _cleanSlate(bridge);
    final tripId = _id('li02');
    // 30 km north of the device: no alarm during the test.
    await bridge.startTrip(_config(tripId), destLat: lat + 0.27, destLng: lng);
    try {
      await bridge.startTrip(
        _config(_id('li02b')),
        destLat: lat + 0.27,
        destLng: lng,
      );
      fail('expected BridgeException(trip-active)');
    } on BridgeException catch (e) {
      expect(e.code, BridgeErrorCode.tripActive);
    }
    expect((await bridge.currentTrip())?.config.tripId, tripId);
    await bridge.stopTrip(tripId);
    await _cleanSlate(bridge);
  });

  testWidgets('LI03 stopTrip far from the destination is CANCELLED', (
    tester,
  ) async {
    await _cleanSlate(bridge);
    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);
    await tester.pump(const Duration(milliseconds: 500));
    final from = received.length;
    final tripId = _id('li03');
    await bridge.startTrip(_config(tripId), destLat: lat + 0.27, destLng: lng);
    // Wait for the first fix (TRACKING) so the trip really ran.
    await _waitFor<TripStateUpdateMsg>(
      received,
      from: from,
      test: (u) =>
          u.state.tripId == tripId && u.state.phase == TripPhaseMsg.tracking,
    );
    await bridge.stopTrip(tripId);
    final ended = await _waitFor<TripEndedMsg>(
      received,
      from: from,
      test: (e) => e.trip.tripId == tripId,
      timeout: const Duration(seconds: 10),
    );
    expect(ended.trip.outcome, TripOutcomeMsg.cancelled);
    expect(ended.trip.endReason, EndReasonMsg.userStop);
    await _cleanSlate(bridge);
  });

  testWidgets('LI04 a real trip has currentTrip().simulation == null', (
    tester,
  ) async {
    // Moved from bridge_scenarios_test.dart (M4, T14): needs the T15 runtime.
    await _cleanSlate(bridge);
    final tripId = _id('li04');
    await bridge.startTrip(_config(tripId), destLat: lat + 0.27, destLng: lng);
    final current = await bridge.currentTrip();
    expect(current?.config.tripId, tripId);
    expect(current?.simulation, isNull);
    await bridge.stopTrip(tripId);
    final pending = await bridge.pendingFinishedTrips();
    expect(
      pending.singleWhere((t) => t.tripId == tripId).outcome,
      TripOutcomeMsg.cancelled,
    );
    await _cleanSlate(bridge);
    expect(await bridge.currentTrip(), isNull);
  });
}
