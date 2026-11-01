// Tester additions for T14 (beyond I01): stub branches K11/K12 through the
// real platform channels, review M4 (currentTrip().simulation of a real trip)
// and M5 (a second subscriber of `updates`). Android emulator/device, dev:
//   flutter test integration_test/bridge_scenarios_test.dart -d <device-id>
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

TripConfigMsg _config(
  String tripId, {
  AlarmModeMsg mode = AlarmModeMsg.smart,
  int? distanceThresholdM,
}) => TripConfigMsg(
  tripId: tripId,
  destinationName: 'Ga Đông Hà',
  mode: mode,
  distanceThresholdM: distanceThresholdM,
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

Future<T> _waitFor<T extends TripUpdateMsg>(
  List<TripUpdateMsg> received, {
  int from = 0,
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

  // One bridge for the file: Pigeon creates the event channel once.
  final bridge = CoreBridge();

  testWidgets('K11 overshoot (DISTANCE 1000, 600x) over the bridge', (
    tester,
  ) async {
    await _cleanSlate(bridge);
    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);

    final tripId = _id('k11');
    await bridge.startTrip(
      _config(tripId, mode: AlarmModeMsg.distance, distanceThresholdM: 1000),
      destLat: 16.8163,
      destLng: 107.1003,
      simulation: SimulationMsg(
        traceAsset: StubTraces.overshoot,
        speedFactor: 600,
      ),
    );
    final alarm = await _waitFor<AlarmMsg>(received);
    expect(alarm.reason, AlarmReasonMsg.distance);
    final overshoot = await _waitFor<OvershootMsg>(received);
    expect(overshoot.pastM, greaterThanOrEqualTo(1000));
    expect(received.indexOf(alarm), lessThan(received.indexOf(overshoot)));
    expect(
      received.whereType<AlarmMsg>().length,
      1,
      reason: 'still ringing: no extra overshoot alarm',
    );
    final current = await bridge.currentTrip();
    expect(current!.state.phase, TripPhaseMsg.overshot);

    final mark = received.length;
    await bridge.dismiss(tripId);
    final ended = await _waitFor<TripEndedMsg>(received, from: mark);
    expect(ended.trip.outcome, TripOutcomeMsg.missed);
    await bridge.ackFinishedTrips([tripId]);
  });

  testWidgets('K12 no fix (600x): never acquired, then timeout alarm', (
    tester,
  ) async {
    await _cleanSlate(bridge);
    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);

    final tripId = _id('k12');
    final started = DateTime.now();
    await bridge.startTrip(
      _config(tripId),
      destLat: 16.8163,
      destLng: 107.1003,
      simulation: SimulationMsg(traceAsset: StubTraces.noFix, speedFactor: 600),
    );
    final lost = await _waitFor<GpsLostMsg>(received);
    expect(lost.cause, GpsLostCauseMsg.neverAcquired);
    expect(lost.lastFixAgeS, isNull);
    // TIMEOUT_S 14 400 s virtual = 24 s real.
    final alarm = await _waitFor<AlarmMsg>(
      received,
      timeout: const Duration(seconds: 35),
    );
    expect(alarm.reason, AlarmReasonMsg.timeout);
    final elapsed = DateTime.now().difference(started);
    expect(elapsed, greaterThanOrEqualTo(const Duration(seconds: 23)));
    final states = received.whereType<TripStateUpdateMsg>().map((u) => u.state);
    expect(states.every((s) => s.gps == GpsStatusMsg.noFixYet), isTrue);
    expect(states.every((s) => s.distanceM == null), isTrue);

    await bridge.stopTrip(tripId);
    await bridge.ackFinishedTrips([tripId]);
  });

  testWidgets('M4 real trip: currentTrip().simulation is null', (tester) async {
    await _cleanSlate(bridge);
    final tripId = _id('m4');
    await bridge.startTrip(_config(tripId), destLat: 16.8, destLng: 107.1);
    final current = await bridge.currentTrip();
    expect(current!.config.tripId, tripId);
    expect(current.simulation, isNull);
    await bridge.stopTrip(tripId);
    final pending = await bridge.pendingFinishedTrips();
    expect(
      pending.singleWhere((t) => t.tripId == tripId).outcome,
      TripOutcomeMsg.cancelled,
    );
    await bridge.ackFinishedTrips([tripId]);
    expect(await bridge.currentTrip(), isNull);
  });

  testWidgets('M5 a second subscriber starts with the latest state', (
    tester,
  ) async {
    await _cleanSlate(bridge);
    final first = <TripUpdateMsg>[];
    final sub1 = bridge.updates.listen(first.add);
    addTearDown(sub1.cancel);

    final tripId = _id('m5');
    await bridge.startTrip(
      _config(tripId),
      destLat: 16.8,
      destLng: 107.1,
      simulation: SimulationMsg(traceAsset: StubTraces.normal, speedFactor: 60),
    );
    await _waitFor<AlarmMsg>(first);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final latestBefore = first.whereType<TripStateUpdateMsg>().last.state;

    final second = <TripUpdateMsg>[];
    final sub2 = bridge.updates.listen(second.add);
    addTearDown(sub2.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(second, isNotEmpty, reason: 'replayed before the next tick');
    final replay = second.first as TripStateUpdateMsg;
    expect(replay.state.tripId, tripId);
    expect(replay.state.phase, TripPhaseMsg.alarming);
    expect(second.whereType<AlarmMsg>(), isEmpty, reason: 'no old events');
    expect(replay.state.atMs, greaterThanOrEqualTo(latestBefore.atMs));

    await bridge.stopTrip(tripId);
    await _waitFor<TripEndedMsg>(second);
    await sub2.cancel();
    final third = <TripUpdateMsg>[];
    final sub3 = bridge.updates.listen(third.add);
    addTearDown(sub3.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(third, isEmpty, reason: 'nothing after TripEndedMsg');
    await bridge.ackFinishedTrips([tripId]);
  });
}
