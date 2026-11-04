// Tester additions for T14 (beyond I01): K11 through the real platform
// channels (M4 moved to t15_location_service_test.dart LI04) and M5 (a second
// subscriber of `updates`). Since T18 (SI04) they run simulated trips on the
// real runtime; K12 (stub/no_fix) is gone: no bundled trace never gets a fix,
// the JVM test SM24 covers NEVER_ACQUIRED -> TIMEOUT. Android
// emulator/device, dev, location granted (adb shell pm grant ...):
//   flutter test integration_test/bridge_scenarios_test.dart -d <device-id>
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

import 'support/sim_expectations.dart';

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

  testWidgets(
    'K11 overshoot (coach_gb_phuly_overshoot, DISTANCE 1000, 60x)',
    timeout: const Timeout(Duration(minutes: 8)),
    (tester) async {
      await _cleanSlate(bridge);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);

      final tripId = _id('k11');
      final trace = (await loadCatalog()).byId(
        SimTraces.coachGbPhulyOvershoot,
      )!;
      await startSim(bridge, simConfig(tripId, trace), trace, 60);
      final alarm = await _waitFor<AlarmMsg>(
        received,
        timeout: const Duration(minutes: 1),
      );
      final sinceAlarm = Stopwatch()..start();
      expect(alarm.reason, AlarmReasonMsg.distance);
      // After the alarm the trip runs at 1x (T18 D3): the overshoot comes a few
      // real minutes later, while the alarm still rings (T16 rings 5 minutes).
      // Tester T18 (TS01, JVM): alarm at trace 2341 s, overshoot at 2625 s, so
      // ~284 s real after the ring, 16 s before the T16 auto-stop (300 s). A
      // debug `ring_max_override` left on the device (T16 protocol) shortens
      // the ring and adds Alarm(OVERSHOOT) (TR33): clear it before this test.
      final overshoot = await _waitFor<OvershootMsg>(
        received,
        timeout: const Duration(minutes: 6),
      );
      final gapS = sinceAlarm.elapsedMilliseconds / 1000;
      expect(overshoot.pastM, greaterThanOrEqualTo(1000));
      expect(received.indexOf(alarm), lessThan(received.indexOf(overshoot)));
      expect(
        received.whereType<AlarmMsg>().length,
        1,
        reason:
            'still ringing: no extra overshoot alarm (overshoot ${gapS}s '
            'after the alarm; T16 ring max 300 s)',
      );
      final current = await bridge.currentTrip();
      expect(current!.state.phase, TripPhaseMsg.overshot);

      final mark = received.length;
      await bridge.dismiss(tripId);
      final ended = await _waitFor<TripEndedMsg>(received, from: mark);
      expect(ended.trip.outcome, TripOutcomeMsg.missed);
      await bridge.ackFinishedTrips([tripId]);
    },
  );

  // M4 (a real trip has `currentTrip().simulation == null`) moved to
  // t15_location_service_test.dart as LI04: it needs the T15 runtime.

  testWidgets('M5 a second subscriber starts with the latest state', (
    tester,
  ) async {
    await _cleanSlate(bridge);
    final first = <TripUpdateMsg>[];
    final sub1 = bridge.updates.listen(first.add);
    addTearDown(sub1.cancel);

    final tripId = _id('m5');
    final trace = (await loadCatalog()).byId(SimTraces.busHnBrt01)!;
    await startSim(bridge, simConfig(tripId, trace), trace, 600);
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
