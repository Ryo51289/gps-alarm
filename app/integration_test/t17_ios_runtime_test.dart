// T17 IC04 (docs/specs/T17.md): the real iOS trip runtime on the Simulator,
// Debug build (NAPSTOP_DIAG), fake alarm port (`napstop.diag.fakeAlarms`) and
// location granted by app/ios/scripts/ci-sim.sh. The ios-sim job sets the
// simulated location to `_hereLat, _hereLng` (integration_test/ios_suite.txt). Skipped on
// Android. By hand on a Mac:
//   xcrun simctl location <udid> set 17.4689199,106.5997285
//   flutter test integration_test/t17_ios_runtime_test.dart -d <udid>
// Logs no coordinates (the point is a public fixture station).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

final bool _notIos = !Platform.isIOS;

/// Ga Đồng Hới (fixtures/traces/train_hn_dh.expect.json destination); must
/// match the point of this file in integration_test/ios_suite.txt.
const double _hereLat = 17.4689199;
const double _hereLng = 106.5997285;

/// About 30 km north of the simulated point (0.27° of latitude).
const double _farLat = _hereLat + 0.27;

TripConfigMsg _config(String tripId) => TripConfigMsg(
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

Future<T> _waitFor<T extends TripUpdateMsg>(
  List<TripUpdateMsg> received, {
  bool Function(T)? test,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final item in received) {
      if (item is T && (test == null || test(item))) {
        return item;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('no $T within $timeout');
}

/// Stops a trip left by an earlier test and acknowledges old records.
Future<void> _cleanSlate(CoreBridge bridge) async {
  final leftover = await bridge.currentTrip();
  if (leftover != null) {
    await bridge.stopTrip(leftover.config.tripId);
  }
  final old = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([for (final t in old) t.tripId]);
}

String _id(String tag) => '$tag-${DateTime.now().millisecondsSinceEpoch}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'II01 start inside the alarm zone rings, dismiss ends on time',
    skip: _notIos,
    (tester) async {
      final bridge = CoreBridge();
      await _cleanSlate(bridge);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);
      final tripId = _id('ii01');

      await bridge.startTrip(
        _config(tripId),
        destLat: _hereLat,
        destLng: _hereLng,
      );
      final first = await _waitFor<TripStateUpdateMsg>(
        received,
        test: (u) => u.state.tripId == tripId,
        timeout: const Duration(seconds: 5),
      );
      expect(first.state.phase, TripPhaseMsg.acquiring);

      final alarm = await _waitFor<AlarmMsg>(
        received,
        test: (a) => a.tripId == tripId,
      );
      expect(alarm.ringNow, isTrue);

      await bridge.dismiss(tripId);
      final ended = await _waitFor<TripEndedMsg>(
        received,
        test: (e) => e.trip.tripId == tripId,
      );
      expect(ended.trip.outcome, TripOutcomeMsg.onTime);
      final pending = await bridge.pendingFinishedTrips();
      expect(pending.map((t) => t.tripId), contains(tripId));
      expect(await bridge.currentTrip(), isNull);
    },
  );

  testWidgets('II02 second start is refused while a trip runs', skip: _notIos, (
    tester,
  ) async {
    final bridge = CoreBridge();
    await _cleanSlate(bridge);
    final tripId = _id('ii02');
    await bridge.startTrip(
      _config(tripId),
      destLat: _farLat,
      destLng: _hereLng,
    );
    addTearDown(() => bridge.stopTrip(tripId));
    await expectLater(
      bridge.startTrip(
        _config(_id('ii02b')),
        destLat: _farLat,
        destLng: _hereLng,
      ),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          BridgeErrorCode.tripActive,
        ),
      ),
    );
  });

  testWidgets(
    'II03 + II04 far trip: no simulation echoed, stopTrip ends it cancelled',
    skip: _notIos,
    (tester) async {
      final bridge = CoreBridge();
      await _cleanSlate(bridge);
      final received = <TripUpdateMsg>[];
      final sub = bridge.updates.listen(received.add);
      addTearDown(sub.cancel);
      final tripId = _id('ii03');

      await bridge.startTrip(
        _config(tripId),
        destLat: _farLat,
        destLng: _hereLng,
      );
      final current = await bridge.currentTrip();
      expect(current, isNotNull);
      expect(current!.config.tripId, tripId);
      expect(current.simulation, isNull);

      await bridge.stopTrip(tripId);
      final ended = await _waitFor<TripEndedMsg>(
        received,
        test: (e) => e.trip.tripId == tripId,
      );
      expect(ended.trip.outcome, TripOutcomeMsg.cancelled);
      expect(await bridge.currentTrip(), isNull);
    },
  );

  testWidgets(
    'II05 a simulated trip is not available on iOS yet',
    skip: _notIos,
    (tester) async {
      final bridge = CoreBridge();
      await _cleanSlate(bridge);
      await expectLater(
        bridge.startTrip(
          _config(_id('ii05')),
          destLat: _farLat,
          destLng: _hereLng,
          simulation: SimulationMsg(
            traceAsset: 'bus_hn_brt01',
            speedFactor: 60,
          ),
        ),
        throwsA(
          isA<BridgeException>().having(
            (e) => e.code,
            'code',
            BridgeErrorCode.simulationUnavailable,
          ),
        ),
      );
      expect(await bridge.currentTrip(), isNull);
    },
  );
}
