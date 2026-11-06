// T28.2 #3: historySyncProvider disposed (app closed, engine detached) or
// rebuilt while a sync run waits on the bridge. The run stops quietly: no
// UnmountedRefException escapes, nothing is written by the old instance, and
// the next instance still applies, acks and marks (D2, D3, D4 unchanged).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/history/data/history_sync.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';
import 'history_fakes.dart';

final DateTime _now = DateTime.fromMillisecondsSinceEpoch(1700001000000);

void main() {
  late FakeCoreBridge bridge;
  late ScriptedTripsRepository repo;
  late RecordingAnalyticsSink analytics;
  late RecordingCrashSink crash;
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previousOnError;

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [
      coreBridgeProvider.overrideWithValue(bridge),
      tripsRepositoryProvider.overrideWithValue(repo),
      telemetryProvider.overrideWithValue(recordingTelemetry(analytics, crash)),
      clockProvider.overrideWithValue(() => _now),
    ],
  );

  setUp(() {
    bridge = FakeCoreBridge();
    repo = ScriptedTripsRepository(bridge.calls);
    analytics = RecordingAnalyticsSink();
    crash = RecordingCrashSink();
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() => FlutterError.onError = previousOnError);

  test('disposed while waiting on currentTrip: completes normally, no mark, '
      'no crash key', () async {
    final gate = Completer<void>();
    bridge.currentTripGate = gate;
    final container = newContainer();
    final run = container.read(historySyncProvider).sync();
    await pumpEventQueue();
    expect(bridge.calls, contains('currentTrip'));

    container.dispose();
    gate.complete();

    await expectLater(run, completes);
    expect(repo.marks, isEmpty);
    expect(crash.keys.containsKey('trip_active'), isFalse);
    expect(reported, isEmpty);
  });

  test('disposed while waiting on the queue: nothing applied or acked; the '
      'next instance applies, acks and marks', () async {
    bridge.pending.add(finishedTrip('f1'));
    repo
      ..results['f1'] = ApplyFinishedResult.applied
      ..records['f1'] = sampleRecord(id: 'f1');
    final gate = Completer<void>();
    bridge.pendingGate = gate;
    final first = newContainer();
    final run = first.read(historySyncProvider).sync();
    await pumpEventQueue();

    first.dispose();
    bridge.pendingGate = null;
    gate.complete();
    await expectLater(run, completes);
    expect(bridge.calls, isNot(contains('apply:f1')));
    expect(bridge.ackCalls, isEmpty);
    expect(repo.marks, isEmpty);

    final second = newContainer();
    addTearDown(second.dispose);
    await second.read(historySyncProvider).sync();
    expect(bridge.ackCalls, [
      ['f1'],
    ]);
    expect(analytics.events.where((e) => e.$1 == 'trip_end'), hasLength(1));
    expect(repo.marks, hasLength(1));
    expect(reported, isEmpty);
  });

  test('rebuilt mid-run (bridge provider changed): the old run stops, a '
      'queued rerun never starts on it', () async {
    final gate = Completer<void>();
    bridge.currentTripGate = gate;
    final container = newContainer();
    addTearDown(container.dispose);
    final old = container.read(historySyncProvider);
    final run = old.sync();
    final again = old.sync(); // Schedules one more run after this one.
    await pumpEventQueue();

    container.invalidate(historySyncProvider);
    final fresh = container.read(historySyncProvider);
    expect(identical(fresh, old), isFalse);
    bridge.currentTripGate = null;
    gate.complete();
    await expectLater(Future.wait([run, again]), completes);
    expect(bridge.callCount('pendingFinishedTrips'), 1);
    expect(repo.marks, isEmpty);

    await fresh.sync();
    expect(repo.marks, hasLength(1));
    expect(reported, isEmpty);
  });

  test('sync() on a disposed instance does nothing', () async {
    final container = newContainer();
    final sync = container.read(historySyncProvider);
    container.dispose();
    await expectLater(sync.sync(), completes);
    expect(bridge.calls, isEmpty);
    expect(reported, isEmpty);
  });
}
