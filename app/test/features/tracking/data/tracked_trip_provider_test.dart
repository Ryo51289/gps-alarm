// T26 P01-P11: trackedTripProvider algorithm and the CoreBridge replay fix.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../tracking_fixtures.dart';

/// Recording wrapper: the order of `updates` listens and `currentTrip`.
class _OrderBridge extends FakeCoreBridge {
  new({super.active});

  final List<String> order = [];

  @override
  Stream<TripUpdateMsg> get updates {
    order.add('updates');
    return super.updates;
  }

  @override
  Future<ActiveTripMsg?> currentTrip() {
    order.add('currentTrip');
    return super.currentTrip();
  }
}

void main() {
  var now = 5000;
  int clock() => now;

  setUp(() => now = 5000);

  Future<(List<TrackingStatus>, StreamSubscription<TrackingStatus>)> listen(
    FakeCoreBridge bridge,
  ) async {
    final values = <TrackingStatus>[];
    final sub = trackedTripStream(bridge, nowMs: clock).listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    return (values, sub);
  }

  TrackedTrip trip(TrackingStatus s) => (s as TrackingActive).trip;

  test('P01 snapshot: Active, updates listened before currentTrip', () async {
    final bridge = _OrderBridge(active: activeMsg(state: w01State()));
    final (values, _) = await listen(bridge);
    expect(values, hasLength(1));
    final t = trip(values.single);
    expect(t.tripId, kTripId);
    expect(t.state.distanceM, 148200);
    expect(t.receivedAtMs, 5000);
    expect(t.simulated, isFalse);
    expect(bridge.order, ['updates', 'currentTrip']);
    expect(t.toString(), 'TrackedTrip(tracking)', reason: 'no name, no km');
  });

  test('P02 newer state of the same trip', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final (values, _) = await listen(bridge);
    now = 9000;
    bridge.emit(
      TripStateUpdateMsg(state: stateMsg(atMs: kAtMs + 10, distanceM: 1200)),
    );
    await pumpEventQueue();
    final t = trip(values.last);
    expect(t.state.distanceM, 1200);
    expect(t.receivedAtMs, 9000);
    expect(bridge.callCount('currentTrip'), 1);
  });

  test('P03 an older replay is ignored', () async {
    final bridge = FakeCoreBridge(
      active: activeMsg(state: stateMsg(atMs: 2000)),
    );
    final (values, _) = await listen(bridge);
    bridge.emit(TripStateUpdateMsg(state: stateMsg(atMs: 1000)));
    await pumpEventQueue();
    expect(values, hasLength(1));
    expect(trip(values.last).state.atMs, 2000);
  });

  test('P04 GpsLost(neverAcquired), LowBatteryRisk, GpsRecovered', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final (values, _) = await listen(bridge);
    bridge
      ..emit(
        GpsLostMsg(
          tripId: kTripId,
          atMs: kAtMs,
          cause: GpsLostCauseMsg.neverAcquired,
        ),
      )
      ..emit(lowBatteryMsg(levelPct: 4, availableMin: 30, neededMin: 90));
    await pumpEventQueue();
    expect(trip(values.last).neverAcquired, isTrue);
    expect(trip(values.last).lowBattery?.availableMin, 30);
    bridge.emit(GpsRecoveredMsg(tripId: kTripId, atMs: kAtMs, lostForS: 3));
    await pumpEventQueue();
    expect(trip(values.last).neverAcquired, isFalse);
    expect(trip(values.last).lowBattery?.neededMin, 90, reason: 'kept');

    // Other trips and other causes are ignored.
    final count = values.length;
    bridge
      ..emit(
        GpsLostMsg(
          tripId: 'other',
          atMs: kAtMs,
          cause: GpsLostCauseMsg.neverAcquired,
        ),
      )
      ..emit(
        GpsLostMsg(
          tripId: kTripId,
          atMs: kAtMs,
          cause: GpsLostCauseMsg.noFixTimeout,
        ),
      );
    await pumpEventQueue();
    expect(values, hasLength(count));
  });

  test('neverAcquired clears once GPS is no longer noFixYet', () async {
    final bridge = FakeCoreBridge(
      active: activeMsg(
        state: stateMsg(
          phase: TripPhaseMsg.acquiring,
          gps: GpsStatusMsg.noFixYet,
        ),
      ),
    );
    final (values, _) = await listen(bridge);
    bridge.emit(
      GpsLostMsg(
        tripId: kTripId,
        atMs: kAtMs,
        cause: GpsLostCauseMsg.neverAcquired,
      ),
    );
    await pumpEventQueue();
    bridge.emit(
      TripStateUpdateMsg(
        state: stateMsg(
          atMs: kAtMs + 1,
          phase: TripPhaseMsg.acquiring,
          gps: GpsStatusMsg.noFixYet,
        ),
      ),
    );
    await pumpEventQueue();
    expect(trip(values.last).neverAcquired, isTrue);
    bridge.emit(TripStateUpdateMsg(state: stateMsg(atMs: kAtMs + 2)));
    await pumpEventQueue();
    expect(trip(values.last).neverAcquired, isFalse);
  });

  test('P05 TripEnded: Ended, later states of the trip ignored', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final (values, _) = await listen(bridge);
    bridge.emit(endedMsg());
    await pumpEventQueue();
    expect(
      values.last,
      const TrackingEnded(
        tripId: kTripId,
        outcome: TripOutcomeMsg.onTime,
        endReason: EndReasonMsg.dismissed,
      ),
    );
    final count = values.length;
    bridge.emit(TripStateUpdateMsg(state: stateMsg(atMs: kAtMs + 5)));
    await pumpEventQueue();
    expect(values, hasLength(count));
    expect(bridge.callCount('currentTrip'), 1);
  });

  test('ENDED view then TripEnded: the end reason is added', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final (values, _) = await listen(bridge);
    bridge
      ..emit(
        TripStateUpdateMsg(
          state: stateMsg(
            atMs: kAtMs + 5,
            phase: TripPhaseMsg.ended,
            outcome: TripOutcomeMsg.cancelled,
          ),
        ),
      )
      ..emit(
        endedMsg(
          outcome: TripOutcomeMsg.cancelled,
          endReason: EndReasonMsg.userStop,
        ),
      );
    await pumpEventQueue();
    expect(values.sublist(1), const [
      TrackingEnded(tripId: kTripId, outcome: TripOutcomeMsg.cancelled),
      TrackingEnded(
        tripId: kTripId,
        outcome: TripOutcomeMsg.cancelled,
        endReason: EndReasonMsg.userStop,
      ),
    ]);
  });

  test('P06 a new trip id re-reads the snapshot', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final (values, _) = await listen(bridge);
    bridge
      ..active = activeMsg(
        config: configMsg(tripId: 't2', destinationName: 'Ga Vinh'),
        state: stateMsg(tripId: 't2'),
      )
      ..emit(TripStateUpdateMsg(state: stateMsg(tripId: 't2')));
    await pumpEventQueue();
    expect(bridge.callCount('currentTrip'), 2);
    expect(trip(values.last).tripId, 't2');
    expect(trip(values.last).config.destinationName, 'Ga Vinh');
  });

  group('P07 snapshot outcomes', () {
    test('null → None', () async {
      final (values, _) = await listen(FakeCoreBridge());
      expect(values, [const TrackingNone()]);
    });

    test('ENDED → Ended', () async {
      final bridge = FakeCoreBridge(
        active: activeMsg(
          state: stateMsg(
            phase: TripPhaseMsg.ended,
            outcome: TripOutcomeMsg.missed,
          ),
        ),
      );
      final (values, _) = await listen(bridge);
      expect(values, [
        const TrackingEnded(tripId: kTripId, outcome: TripOutcomeMsg.missed),
      ]);
    });

    test('BridgeException → Error, nothing reported', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final (values, _) = await listen(
        FakeCoreBridge()..currentTripError = channelError(),
      );
      expect(values, [const TrackingError()]);
      expect(reported, isEmpty);
    });

    test('other error → Error + reportNonFatal (type only)', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      final (values, _) = await listen(
        FakeCoreBridge()..currentTripError = StateError('Ga Đồng Hới'),
      );
      expect(values, [const TrackingError()]);
      final error = reported.single.exception as NonFatalError;
      expect(error.errorType, 'StateError');
      expect(error.toString(), isNot(contains('Đồng Hới')));
    });
  });

  test('P08 pause cancels the subscription; resume re-reads', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final (values, sub) = await listen(bridge);
    expect(bridge.hasListener, isTrue);
    sub.pause();
    await pumpEventQueue();
    expect(bridge.hasListener, isFalse);
    for (var i = 1; i <= 3; i++) {
      bridge.emit(TripStateUpdateMsg(state: stateMsg(atMs: kAtMs + i)));
    }
    bridge.active = activeMsg(state: stateMsg(atMs: kAtMs + 50));
    sub.resume();
    await pumpEventQueue();
    expect(bridge.hasListener, isTrue);
    expect(bridge.callCount('currentTrip'), 2);
    expect(values, hasLength(2), reason: 'nothing buffered while paused');
    expect(trip(values.last).state.atMs, kAtMs + 50);
  });

  test('P09 CoreBridge: a new subscriber gets the view seen while every '
      'subscription was paused (T14 F2)', () async {
    final source = StreamController<TripUpdateMsg>.broadcast();
    addTearDown(source.close);
    final bridge = CoreBridge(updatesFactory: () => source.stream);
    final s1 = TripStateUpdateMsg(state: stateMsg(atMs: 1));
    final s2 = TripStateUpdateMsg(state: stateMsg(atMs: 2));
    final a = <TripUpdateMsg>[];
    final subA = bridge.updates.listen(a.add);
    addTearDown(subA.cancel);
    await pumpEventQueue();
    subA.pause();
    source
      ..add(s1)
      ..add(s2);
    await pumpEventQueue();

    final b = <TripUpdateMsg>[];
    final subB = bridge.updates.listen(b.add);
    addTearDown(subB.cancel);
    await pumpEventQueue();
    expect(b, [s2]);

    subA.resume();
    await pumpEventQueue();
    expect(a, [s1, s2], reason: "A's buffer is untouched");

    // Ended trip: forgotten; last subscriber gone: forgotten.
    source.add(endedMsg());
    await pumpEventQueue();
    final c = <TripUpdateMsg>[];
    final subC = bridge.updates.listen(c.add);
    await pumpEventQueue();
    expect(c, isEmpty);
    await subC.cancel();
    source.add(s1);
    await pumpEventQueue();
    await subA.cancel();
    await subB.cancel();
    expect(source.hasListener, isFalse, reason: 'memory cancelled too');
    final d = <TripUpdateMsg>[];
    final subD = bridge.updates.listen(d.add);
    await pumpEventQueue();
    expect(d, isEmpty);
    expect(source.hasListener, isTrue);
    await subD.cancel();
  });

  test('P11 acquiringSinceMs: first ACQUIRING time, kept, then null', () async {
    final bridge = FakeCoreBridge(
      active: activeMsg(state: stateMsg(phase: TripPhaseMsg.acquiring)),
    );
    final (values, _) = await listen(bridge);
    expect(trip(values.last).acquiringSinceMs, 5000);
    now = 65000;
    bridge.emit(
      TripStateUpdateMsg(
        state: stateMsg(atMs: kAtMs + 60000, phase: TripPhaseMsg.acquiring),
      ),
    );
    await pumpEventQueue();
    expect(trip(values.last).acquiringSinceMs, 5000);
    bridge.emit(TripStateUpdateMsg(state: stateMsg(atMs: kAtMs + 61000)));
    await pumpEventQueue();
    expect(trip(values.last).acquiringSinceMs, isNull);
  });

  test('provider: clock from clockProvider, no listener once closed', () async {
    final bridge = FakeCoreBridge(active: activeMsg());
    final container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        coreBridgeProvider.overrideWithValue(bridge),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(777),
        ),
      ],
    );
    final sub = container.listen(trackedTripProvider, (_, _) {});
    await pumpEventQueue();
    final status = container.read(trackedTripProvider).value;
    expect(trip(status!).receivedAtMs, 777);
    sub.close();
    await pumpEventQueue();
    expect(bridge.hasListener, isFalse);
  });
}
