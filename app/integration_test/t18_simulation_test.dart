// T18 SI01–SI03: simulated trips on the real runtime (bundled trace, trip
// clock with a speed factor, in-process timers, real T16 alarm). Android
// emulator/device API 34+, dev flavor, location granted beforehand
// (P = android.permission):
//   adb shell pm grant app.napstop.dev P.ACCESS_FINE_LOCATION
//   adb shell pm grant app.napstop.dev P.ACCESS_COARSE_LOCATION
//   adb shell pm grant app.napstop.dev P.POST_NOTIFICATIONS
//   adb shell svc power stayon true   # SI01 runs ~9.5 minutes
//   flutter test integration_test/t18_simulation_test.dart -d <device-id>
// SI02 note for the tester: `adb shell dumpsys alarm | grep -A3 napstop`
// during the trip lists no alarm of the app (D5).
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

import 'support/sim_expectations.dart';

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final bridge = CoreBridge();

  testWidgets(
    'SI01 train Ha Noi - Dong Hoi at 60x rings on time',
    timeout: const Timeout(Duration(minutes: 13)),
    (tester) async {
      await cleanSlate(bridge);
      final catalog = await loadCatalog();
      final trace = catalog.byId(SimTraces.trainHnDh)!;
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);

      final tripId = _id('si01');
      final started = DateTime.now();
      await startSim(bridge, simConfig(tripId, trace), trace, 60);
      final current = await bridge.currentTrip();
      expect(
        current!.simulation,
        SimulationMsg(traceAsset: 'train_hn_dh', speedFactor: 60),
      );
      expect(current.config.tripId, tripId);

      final pre = await waitForUpdate<PreAlertMsg>(
        received,
        timeout: const Duration(minutes: 11),
      );
      final preT = traceSecond(received, pre.atMs);
      expect(
        preT,
        inInclusiveRange(
          kTrainPreAlertNotBefore,
          kTrainPreAlertNotAfter + kFgsSlackS,
        ),
      );
      final alarm = await waitForUpdate<AlarmMsg>(
        received,
        timeout: const Duration(minutes: 2),
      );
      final realToAlarm = DateTime.now().difference(started);
      final alarmT = traceSecond(received, alarm.atMs);
      expect(alarm.reason, AlarmReasonMsg.distance);
      expect(alarm.ringNow, isTrue);
      expect(
        alarmT,
        inInclusiveRange(
          kTrainAlarmNotBefore,
          kTrainAlarmNotAfter + kFgsSlackS,
        ),
      );
      // 33 700 s / 60 ≈ 9.4 min.
      expect(
        realToAlarm.inSeconds,
        inInclusiveRange(alarmT ~/ 60 - 30, alarmT ~/ 60 + 30),
        reason: 'real time to the alarm: $realToAlarm',
      );

      final mark = received.length;
      await bridge.dismiss(tripId);
      final ended = await waitForUpdate<TripEndedMsg>(received, from: mark);
      expect(ended.trip.outcome, TripOutcomeMsg.onTime);
      final pending = await bridge.pendingFinishedTrips();
      expect(pending.map((t) => t.tripId), contains(tripId));
      await bridge.ackFinishedTrips([tripId]);
      expect(await bridge.currentTrip(), isNull);
    },
  );

  testWidgets('SI02 bus at 600x rings within 15 s, stop ends it', (
    tester,
  ) async {
    await cleanSlate(bridge);
    final trace = (await loadCatalog()).byId(SimTraces.busHnBrt01)!;
    final received = <TripUpdateMsg>[];
    final sub = bridge.updates.listen(received.add);
    addTearDown(sub.cancel);

    final tripId = _id('si02');
    final started = DateTime.now();
    await startSim(bridge, simConfig(tripId, trace), trace, 600);
    final alarm = await waitForUpdate<AlarmMsg>(
      received,
      timeout: const Duration(seconds: 15),
    );
    expect(
      DateTime.now().difference(started),
      lessThan(const Duration(seconds: 15)),
    );
    expect(alarm.reason, AlarmReasonMsg.distance);
    expect(
      traceSecond(received, alarm.atMs),
      inInclusiveRange(kBusAlarmNotBefore, kBusAlarmNotAfter + kFgsSlackS),
    );

    final mark = received.length;
    await bridge.stopTrip(tripId);
    final ended = await waitForUpdate<TripEndedMsg>(received, from: mark);
    expect(ended.trip.endReason, EndReasonMsg.userStop);
    await bridge.ackFinishedTrips([tripId]);
  });

  testWidgets('SI03 a stub id or an unknown trace is simulation-unavailable', (
    tester,
  ) async {
    await cleanSlate(bridge);
    final trace = (await loadCatalog()).byId(SimTraces.busHnBrt01)!;
    for (final id in ['stub/normal', 'no_such_trace']) {
      await expectLater(
        bridge.startTrip(
          simConfig(_id('si03'), trace),
          destLat: trace.destination.lat,
          destLng: trace.destination.lng,
          simulation: SimulationMsg(traceAsset: id, speedFactor: 60),
        ),
        throwsA(
          isA<BridgeException>().having(
            (e) => e.code,
            'code',
            BridgeErrorCode.simulationUnavailable,
          ),
        ),
        reason: id,
      );
    }
    expect(await bridge.currentTrip(), isNull);
  });
}
