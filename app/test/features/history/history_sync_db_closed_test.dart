// T28.2 test report #2 (tester repro, kept as a regression test): the
// provider is disposed while a database write of HistorySync runs; disposing
// the container also closes the database, so the in-flight write fails
// ("This database has already been closed" → CouldNotRollBackException on
// the device). The run stops quietly: an error caused by its own disposal is
// not a non-fatal, and nothing is acked (D2: delivered again next time).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/history/data/history_sync.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';
import 'history_fakes.dart';

const String _closed = 'This database has already been closed';

/// applyFinished / markUnfinishedAsUnknown wait on their gate, then fail like
/// a closed database.
final class _ClosingRepo extends ScriptedTripsRepository {
  new(super.log);

  final Completer<void> applyGate = Completer<void>();
  final Completer<void> markGate = Completer<void>();

  @override
  Future<({ApplyFinishedResult result, TripRecord? record})> applyFinished(
    FinishedTripMsg f,
  ) async {
    log.add('apply:${f.tripId}');
    await applyGate.future;
    throw StateError(_closed);
  }

  @override
  Future<int> markUnfinishedAsUnknown({
    required String? exceptTripId,
    required int startedBeforeMs,
    required int endedAtMs,
  }) async {
    log.add('mark');
    await markGate.future;
    throw StateError(_closed);
  }
}

void main() {
  late FakeCoreBridge bridge;
  late _ClosingRepo repo;
  late RecordingCrashSink crash;
  late List<FlutterErrorDetails> reported;

  setUp(() {
    bridge = FakeCoreBridge();
    repo = _ClosingRepo(bridge.calls);
    crash = RecordingCrashSink();
    reported = [];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    addTearDown(() => FlutterError.onError = previous);
  });

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [
      coreBridgeProvider.overrideWithValue(bridge),
      tripsRepositoryProvider.overrideWithValue(repo),
      telemetryProvider.overrideWithValue(
        recordingTelemetry(RecordingAnalyticsSink(), crash),
      ),
      clockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(1700001000000),
      ),
    ],
  );

  test('disposed during applyFinished, DB closed under it: no non-fatal '
      'reported, nothing acked', () async {
    bridge.pending.add(finishedTrip('f1'));
    final container = newContainer();
    final run = container.read(historySyncProvider).sync();
    await pumpEventQueue();
    expect(bridge.calls, contains('apply:f1'));

    container.dispose(); // App closed: the DB provider closes the database.
    repo.applyGate.complete();

    await expectLater(run, completes);
    expect(bridge.ackCalls, isEmpty);
    expect(bridge.calls, isNot(contains('currentTrip')));
    expect(
      reported.map((d) => d.exception.toString()),
      isEmpty,
      reason: 'an error caused by our own disposal is not a non-fatal',
    );
  });

  test('disposed during orphan marking, DB closed under it: no non-fatal, '
      'no crash key', () async {
    final container = newContainer();
    final run = container.read(historySyncProvider).sync();
    await pumpEventQueue();
    expect(bridge.calls, contains('mark'));

    container.dispose();
    repo.markGate.complete();

    await expectLater(run, completes);
    expect(reported, isEmpty);
    expect(crash.keys.containsKey('trip_active'), isFalse);
  });

  test('not disposed: a failing apply is still reported (unchanged)', () async {
    bridge.pending.add(finishedTrip('f1'));
    final container = newContainer();
    addTearDown(container.dispose);
    final run = container.read(historySyncProvider).sync();
    await pumpEventQueue();
    repo
      ..applyGate.complete()
      ..markGate.complete();

    await expectLater(run, completes);
    expect(bridge.ackCalls, isEmpty);
    expect(reported, hasLength(2)); // historySync.apply + historySync.orphans
  });
}
