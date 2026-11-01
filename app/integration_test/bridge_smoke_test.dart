// I01 (spec T14): Dart <-> Android stub over the real platform channels.
// Run on an Android emulator/device (API 26+), flavor dev:
//   flutter test integration_test/bridge_smoke_test.dart -d <device-id>
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

/// Polls [received] (from index [from]) until an item matches [test].
Future<T> _waitFor<T extends TripUpdateMsg>(
  List<TripUpdateMsg> received, {
  required int from,
  bool Function(T)? test,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final item in received.skip(from)) {
      if (item is T && (test == null || test(item))) {
        return item;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('no $T within $timeout');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('I01 stub trip end to end', (tester) async {
    final bridge = CoreBridge();

    // Clean slate (a previous run may have left a trip or records).
    final leftover = await bridge.currentTrip();
    if (leftover != null) {
      await bridge.stopTrip(leftover.config.tripId);
    }
    final old = await bridge.pendingFinishedTrips();
    await bridge.ackFinishedTrips([for (final t in old) t.tripId]);

    final device = await bridge.deviceInfo();
    expect(device.platform, PlatformMsg.android);
    expect(device.androidSdkInt, greaterThanOrEqualTo(26));
    expect(device.iosMajor, isNull);

    final permissions = await bridge.permissionStatus();
    expect(permissions.alarmKit, PermissionStateMsg.notApplicable);
    expect(permissions.location, isNot(LocationAccessMsg.always));

    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);

    final tripId = 'i01-${DateTime.now().millisecondsSinceEpoch}';
    final config = TripConfigMsg(
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
    );
    await bridge.startTrip(
      config,
      destLat: 16.8163,
      destLng: 107.1003,
      simulation: SimulationMsg(traceAsset: StubTraces.normal, speedFactor: 60),
    );

    // Second start is refused.
    await expectLater(
      bridge.startTrip(config, destLat: 16.8, destLng: 107.1),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          BridgeErrorCode.tripActive,
        ),
      ),
    );

    final alarm = await _waitFor<AlarmMsg>(received, from: 0);
    expect(alarm.reason, AlarmReasonMsg.smartTime);
    expect(alarm.tripId, tripId);
    expect(alarm.snoozeAllowed, isTrue);

    final current = await bridge.currentTrip();
    expect(current, isNotNull);
    expect(current!.config.destinationName, 'Ga Đông Hà');
    expect(current.config, config);
    expect(current.state.phase, TripPhaseMsg.alarming);

    var mark = received.length;
    await bridge.snooze(tripId);
    await _waitFor<SnoozedMsg>(received, from: mark);
    final again = await _waitFor<AlarmMsg>(received, from: mark);
    expect(again.reason, AlarmReasonMsg.snoozeEnd);

    mark = received.length;
    await bridge.dismiss(tripId);
    final ended = await _waitFor<TripEndedMsg>(received, from: mark);
    expect(ended.trip.tripId, tripId);
    expect(ended.trip.outcome, TripOutcomeMsg.snoozed);
    expect(ended.trip.endReason, EndReasonMsg.dismissed);

    final pending = await bridge.pendingFinishedTrips();
    expect(pending.map((t) => t.tripId), contains(tripId));
    await bridge.ackFinishedTrips([tripId]);
    expect(await bridge.pendingFinishedTrips(), isEmpty);
    expect(await bridge.currentTrip(), isNull);

    // Unknown scenario.
    await expectLater(
      bridge.startTrip(
        config,
        destLat: 16.8,
        destLng: 107.1,
        simulation: SimulationMsg(traceAsset: 'assets/x.gpx', speedFactor: 60),
      ),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          BridgeErrorCode.simulationUnavailable,
        ),
      ),
    );
  });
}
