// activeTripProvider algorithm (T22 §7.4).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/trip/trip_providers.dart';

import '../../helpers/fake_core_bridge.dart';

void main() {
  test('no trip: null, nothing else', () async {
    final bridge = FakeCoreBridge();
    final values = <ActiveTripSummary?>[];
    final sub = activeTripStream(bridge).listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(values, [null]);
  });

  test('bridge error on currentTrip counts as no trip', () async {
    final bridge = FakeCoreBridge()..currentTripError = channelError();
    expect(await activeTripStream(bridge).first, isNull);
  });

  test('running trip, phase change, other trip, end', () async {
    final bridge = FakeCoreBridge(active: activeTrip());
    final values = <ActiveTripSummary?>[];
    final sub = activeTripStream(bridge).listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    const hue = ActiveTripSummary(
      tripId: 'trip-1',
      destinationName: 'Ga Huế',
      phase: TripPhaseMsg.tracking,
    );
    expect(values, [hue]);

    bridge.emit(
      TripStateUpdateMsg(state: tripState(phase: TripPhaseMsg.alarming)),
    );
    await pumpEventQueue();
    expect(values.last, hue.copyWith(phase: TripPhaseMsg.alarming));
    final readsBefore = bridge.callCount('currentTrip');

    // Unrelated end: ignored.
    bridge.emit(tripEnded(tripId: 'other'));
    await pumpEventQueue();
    expect(values, hasLength(2));

    // A new trip id: re-read the snapshot for the name.
    bridge
      ..active = activeTrip(tripId: 'trip-2', destinationName: 'Ga Vinh')
      ..emit(TripStateUpdateMsg(state: tripState(tripId: 'trip-2')));
    await pumpEventQueue();
    expect(bridge.callCount('currentTrip'), readsBefore + 1);
    expect(values.last?.destinationName, 'Ga Vinh');

    bridge.emit(tripEnded(tripId: 'trip-2'));
    await pumpEventQueue();
    expect(values.last, isNull);
  });

  test('phase ended in an update: null', () async {
    final bridge = FakeCoreBridge(active: activeTrip());
    final values = <ActiveTripSummary?>[];
    final sub = activeTripStream(bridge).listen(values.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    bridge.emit(
      TripStateUpdateMsg(state: tripState(phase: TripPhaseMsg.ended)),
    );
    await pumpEventQueue();
    expect(values.last, isNull);
  });

  test('snapshot already ended: null', () async {
    final bridge = FakeCoreBridge(
      active: activeTrip(phase: TripPhaseMsg.ended),
    );
    expect(await activeTripStream(bridge).first, isNull);
  });

  const tracking = ActiveTripSummary(
    tripId: 'trip-1',
    destinationName: 'Ga Huế',
    phase: TripPhaseMsg.tracking,
  );

  test(
    'review #1: pause cancels the update subscription, resume re-reads',
    () async {
      final bridge = FakeCoreBridge(active: activeTrip());
      final values = <ActiveTripSummary?>[];
      final sub = activeTripStream(bridge).listen(values.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(bridge.hasListener, isTrue);
      expect(values, [tracking]);

      sub.pause();
      await pumpEventQueue();
      // Nothing is buffered while paused: nobody listens to the bridge.
      expect(bridge.hasListener, isFalse);
      for (var i = 0; i < 100; i++) {
        bridge.emit(
          TripStateUpdateMsg(state: tripState(phase: TripPhaseMsg.alarming)),
        );
      }
      bridge.active = activeTrip(phase: TripPhaseMsg.snoozed);
      final reads = bridge.callCount('currentTrip');

      sub.resume();
      await pumpEventQueue();
      expect(bridge.hasListener, isTrue);
      expect(bridge.callCount('currentTrip'), reads + 1);
      expect(values, [
        tracking,
        tracking.copyWith(phase: TripPhaseMsg.snoozed),
      ]);

      // Still following after resume.
      bridge.emit(tripEnded());
      await pumpEventQueue();
      expect(values.last, isNull);
    },
  );

  test(
    'review #1: through Riverpod, no bridge listener without listeners',
    () async {
      final bridge = FakeCoreBridge(active: activeTrip());
      final container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [coreBridgeProvider.overrideWithValue(bridge)],
      );
      final first = container.listen(activeTripProvider, (_, _) {});
      await pumpEventQueue();
      expect(bridge.hasListener, isTrue);
      expect(container.read(activeTripProvider).value, tracking);

      first.close();
      await pumpEventQueue();
      expect(bridge.hasListener, isFalse);

      bridge.active = activeTrip(phase: TripPhaseMsg.alarming);
      final second = container.listen(activeTripProvider, (_, _) {});
      addTearDown(second.close);
      await pumpEventQueue();
      expect(bridge.hasListener, isTrue);
      expect(
        container.read(activeTripProvider).value,
        tracking.copyWith(phase: TripPhaseMsg.alarming),
      );
    },
  );

  test(
    'review #3a: an update before the snapshot is applied after it',
    () async {
      final gate = Completer<void>();
      final bridge = FakeCoreBridge(active: activeTrip())
        ..currentTripGate = gate;
      final values = <ActiveTripSummary?>[];
      final sub = activeTripStream(bridge).listen(values.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      // Subscribed before the snapshot read completes.
      expect(bridge.hasListener, isTrue);
      expect(values, isEmpty);
      bridge.emit(
        TripStateUpdateMsg(state: tripState(phase: TripPhaseMsg.alarming)),
      );
      await pumpEventQueue();
      expect(values, isEmpty);

      gate.complete();
      await pumpEventQueue();
      expect(values, [
        tracking,
        tracking.copyWith(phase: TripPhaseMsg.alarming),
      ]);
    },
  );

  test('review #3b: cancel releases the subscription and returns', () async {
    final gate = Completer<void>();
    final bridge = FakeCoreBridge(active: activeTrip())..currentTripGate = gate;
    final sub = activeTripStream(bridge).listen((_) {});
    await pumpEventQueue();
    expect(bridge.hasListener, isTrue);
    // Snapshot still pending: cancel must not wait for it.
    await sub.cancel().timeout(const Duration(seconds: 1));
    expect(bridge.hasListener, isFalse);
    gate.complete();
    await pumpEventQueue();
  });

  test(
    'review #2: a non-bridge error is reported, later steps still run',
    () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      final bridge = FakeCoreBridge(active: activeTrip())
        ..currentTripError = StateError('Ga Huế 16.4567');
      final values = <ActiveTripSummary?>[];
      final sub = activeTripStream(bridge).listen(values.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();
      expect(values, [null]);
      expect(reported, hasLength(1));
      final error = reported.single.exception;
      expect(error, isA<NonFatalError>());
      // PRIVACY: the type only, never the message.
      expect(error.toString(), isNot(contains('Huế')));
      expect(error.toString(), isNot(contains('16.4')));
      expect(error.toString(), contains('StateError'));

      bridge
        ..currentTripError = null
        ..emit(TripStateUpdateMsg(state: tripState()));
      await pumpEventQueue();
      expect(values.last, tracking);
    },
  );
}
