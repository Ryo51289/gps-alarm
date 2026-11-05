// T18.1 SIC02, SIC03 (docs/specs/T18.1.md): simulated trips on the real iOS
// runtime (bundled trace, trip clock with a speed factor, virtual event
// queue), Simulator, Debug build, fake alarm port (`napstop.diag.fakeAlarms`)
// and location granted by app/ios/scripts/ci-sim.sh (the keep-alive session
// needs it, D9). Skipped on Android (T18 SI01–SI03 cover it). By hand on a Mac:
//   flutter test integration_test/t18_1_ios_simulation_test.dart -d <udid>
// Logs no coordinates.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

import 'support/sim_expectations.dart';

final bool _notIos = !Platform.isIOS;

String _id(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final bridge = CoreBridge();

  testWidgets(
    'SIC02 bus at 600x rings DISTANCE within 15 s, 5 runs out of 5',
    skip: _notIos,
    timeout: const Timeout(Duration(minutes: 5)),
    (tester) async {
      final trace = (await loadCatalog()).byId(SimTraces.busHnBrt01)!;
      for (var run = 1; run <= 5; run++) {
        await cleanSlate(bridge);
        final received = <TripUpdateMsg>[];
        final sub = bridge.updates.listen(received.add);

        final tripId = _id('sic02-$run');
        final started = DateTime.now();
        await startSim(bridge, simConfig(tripId, trace), trace, 600);
        final current = await bridge.currentTrip();
        expect(
          current!.simulation,
          SimulationMsg(traceAsset: 'bus_hn_brt01', speedFactor: 600),
          reason: 'run $run',
        );
        final alarm = await waitForUpdate<AlarmMsg>(
          received,
          timeout: const Duration(seconds: 15),
        );
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(seconds: 15)),
          reason: 'run $run',
        );
        expect(alarm.reason, AlarmReasonMsg.distance, reason: 'run $run');
        expect(alarm.ringNow, isTrue, reason: 'run $run');
        expect(
          traceSecond(received, alarm.atMs),
          inInclusiveRange(kBusAlarmNotBefore, kBusAlarmNotAfter + kFgsSlackS),
          reason: 'run $run',
        );

        final mark = received.length;
        await bridge.stopTrip(tripId);
        final ended = await waitForUpdate<TripEndedMsg>(received, from: mark);
        expect(ended.trip.endReason, EndReasonMsg.userStop, reason: 'run $run');
        await bridge.ackFinishedTrips([tripId]);
        await sub.cancel();
      }
      expect(await bridge.currentTrip(), isNull);
    },
  );

  testWidgets(
    'SIC03 a stub id or an unknown trace is simulation-unavailable',
    skip: _notIos,
    (tester) async {
      await cleanSlate(bridge);
      final trace = (await loadCatalog()).byId(SimTraces.busHnBrt01)!;
      for (final id in ['stub/normal', 'no_such_trace']) {
        await expectLater(
          bridge.startTrip(
            simConfig(_id('sic03'), trace),
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
    },
  );
}
