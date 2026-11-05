// Tester (T28): edge and reverse cases of HistorySync over a REAL in-memory
// drift database (the coder's H06-H10 use a scripted repository):
// - overlapping triggers (app start + resume + TripEndedMsg at once) stay
//   idempotent: one result per row, `trip_end` exactly once per trip id;
// - two HistorySync instances (provider rebuilt) racing on the same row;
// - an orphan row is later filled with the real result (D2/D4 self-repair),
//   also when the trip ends between `pendingFinishedTrips` and `currentTrip`;
// - the running trip is never marked, whatever the number of syncs, a
//   failing `currentTrip`, or the grace boundary (exactly 120 s).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/history/data/history_sync.dart';
import 'package:napstop/features/history/domain/history_logic.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';
import 'history_fakes.dart';

const int _now = 1700001000000;
const int _grace = 120000;

void main() {
  late AppDatabase db;
  late DriftTripsRepository repo;
  late FakeCoreBridge bridge;
  late RecordingAnalyticsSink analytics;
  late Telemetry telemetry;
  var now = _now;

  HistorySync newSync() => HistorySync(
    bridge: bridge,
    repo: repo,
    telemetry: () => telemetry,
    nowMs: () => now,
  );

  setUp(() {
    now = _now;
    db = memoryDatabase();
    repo = DriftTripsRepository(db);
    bridge = FakeCoreBridge();
    analytics = RecordingAnalyticsSink();
    telemetry = recordingTelemetry(analytics, RecordingCrashSink());
  });
  tearDown(() => db.close());

  /// `trip_end` carries no trip id (privacy): count them.
  int tripEnds() => analytics.events.where((e) => e.$1 == 'trip_end').length;

  Future<TripRecord> row(String id) async => (await repo.byId(id))!;

  group('overlapping triggers stay idempotent', () {
    test('start + resume + TripEndedMsg at once: one result, one trip_end '
        'per trip, queue drained in 2 runs', () async {
      await repo.insertStarted(
        sampleRecord(id: 'A', startedAtMs: _now - 9000000),
      );
      await repo.insertStarted(
        sampleRecord(id: 'B', startedAtMs: _now - 8000000),
      );
      bridge.pending.add(finishedTrip('A'));
      final gate = Completer<void>();
      bridge.pendingGate = gate;
      final sync = newSync();

      // App start (post frame), resume and TripEndedMsg in the same turn.
      final calls = [sync.sync(), sync.sync(), sync.sync()];
      await pumpEventQueue();
      expect(bridge.callCount('pendingFinishedTrips'), 1);
      // B ends while the first run waits on the native queue.
      bridge.pending.add(
        finishedTrip('B', outcome: TripOutcomeMsg.missed, travelledM: 1000),
      );
      bridge.pendingGate = null;
      gate.complete();
      await Future.wait(calls);

      expect(bridge.callCount('pendingFinishedTrips'), 2);
      expect(bridge.pending, isEmpty);
      expect((await row('A')).result, TripOutcomeMsg.onTime);
      expect((await row('B')).result, TripOutcomeMsg.missed);
      expect(tripEnds(), 2);
      // Every call returned only after the extra run.
      expect(bridge.ackCalls.expand((a) => a).toSet(), {'A', 'B'});
    });

    test('a lost ack: the next run gets A again → alreadyApplied, '
        'no second trip_end, first result kept', () async {
      await repo.insertStarted(
        sampleRecord(id: 'A', startedAtMs: _now - 9000000),
      );
      bridge
        ..pending.add(finishedTrip('A'))
        ..ackError = channelError();
      final sync = newSync();
      await sync.sync();
      expect(bridge.pending, hasLength(1)); // ack lost
      // Native delivers it again, even with another outcome.
      bridge
        ..ackError = null
        ..pending.replaceRange(0, 1, [
          finishedTrip('A', outcome: TripOutcomeMsg.missed),
        ]);
      await Future.wait([sync.sync(), sync.sync()]);
      expect((await row('A')).result, TripOutcomeMsg.onTime);
      expect(tripEnds(), 1);
      expect(bridge.pending, isEmpty);
    });

    test('two HistorySync instances (provider rebuilt) race on the same row: '
        'one applied, trip_end once', () async {
      await repo.insertStarted(
        sampleRecord(id: 'A', startedAtMs: _now - 9000000),
      );
      bridge.pending.add(finishedTrip('A'));
      final gate = Completer<void>();
      bridge.pendingGate = gate;
      final s1 = newSync();
      final s2 = newSync();
      final both = [s1.sync(), s2.sync()];
      await pumpEventQueue();
      // Both read the queue before either acks.
      expect(bridge.callCount('pendingFinishedTrips'), 2);
      bridge.pendingGate = null;
      gate.complete();
      await Future.wait(both);
      expect((await row('A')).result, TripOutcomeMsg.onTime);
      expect(tripEnds(), 1);
      expect(bridge.pending, isEmpty);
    });

    test('ten rapid triggers during a run: at most one extra run', () async {
      final gate = Completer<void>();
      bridge.pendingGate = gate;
      final sync = newSync();
      final first = sync.sync();
      await pumpEventQueue();
      final more = [for (var i = 0; i < 10; i++) sync.sync()];
      bridge.pendingGate = null;
      gate.complete();
      await Future.wait([first, ...more]);
      expect(bridge.callCount('pendingFinishedTrips'), 2);
    });
  });

  group('orphan rows are filled later', () {
    test('orphan marked "unknown", then its FinishedTripMsg arrives: '
        'result and end time of the trip replace the mark', () async {
      await repo.insertStarted(
        sampleRecord(id: 'O', startedAtMs: _now - 10 * 60000),
      );
      final sync = newSync();
      await sync.sync();
      var r = await row('O');
      expect(r.result, isNull);
      expect(r.endedAtMs, _now);
      expect(
        historyStatusOf(r, activeTripId: null, activeKnown: true),
        HistoryStatus.unknown,
      );

      final f = finishedTrip('O', outcome: TripOutcomeMsg.cancelled);
      bridge.pending.add(f);
      now += 60000;
      await sync.sync();
      r = await row('O');
      expect(r.result, TripOutcomeMsg.cancelled);
      expect(r.endedAtMs, f.endedAtMs);
      expect(r.endReason, EndReasonMsg.userStop);
      expect(
        historyStatusOf(r, activeTripId: null, activeKnown: true),
        HistoryStatus.cancelled,
      );
      expect(tripEnds(), 1);
    });

    test('the trip ends between pendingFinishedTrips and currentTrip: '
        'marked once, then repaired by the TripEndedMsg sync', () async {
      await repo.insertStarted(
        sampleRecord(id: 'R', startedAtMs: _now - 3 * 3600000),
      );
      bridge
        ..active = activeTrip(tripId: 'R')
        ..currentTripGate = Completer<void>();
      final sync = newSync();
      final run = sync.sync();
      await pumpEventQueue();
      expect(bridge.calls, contains('currentTrip'));
      // Native: the trip ends now (queue filled, no active trip anymore).
      bridge
        ..active = null
        ..pending.add(finishedTrip('R'));
      final g = bridge.currentTripGate!;
      bridge.currentTripGate = null;
      g.complete();
      await run;
      // Race window: the row is an orphan for a moment.
      expect((await row('R')).endedAtMs, _now);
      expect((await row('R')).result, isNull);
      // TripEndedMsg → sync.
      await sync.sync();
      final r = await row('R');
      expect(r.result, TripOutcomeMsg.onTime);
      expect(r.endedAtMs, finishedTrip('R').endedAtMs);
      expect(tripEnds(), 1);
    });

    test('several orphans and a late result for only one of them', () async {
      for (final id in ['o1', 'o2', 'o3']) {
        await repo.insertStarted(
          sampleRecord(id: id, startedAtMs: _now - 3600000),
        );
      }
      final sync = newSync();
      await sync.sync();
      bridge.pending.add(finishedTrip('o2', outcome: TripOutcomeMsg.snoozed));
      await sync.sync();
      expect((await row('o1')).result, isNull);
      expect((await row('o2')).result, TripOutcomeMsg.snoozed);
      expect((await row('o3')).result, isNull);
      // A later sync never re-stamps an orphan's end time.
      now += 3600000;
      await sync.sync();
      expect((await row('o1')).endedAtMs, _now);
    });
  });

  group('the running trip is never "Không rõ kết quả"', () {
    test('many syncs (start, resumes, unrelated TripEndedMsg) with an old '
        'running trip: row untouched, status running', () async {
      await repo.insertStarted(
        sampleRecord(id: 'run', startedAtMs: _now - 9 * 3600000),
      );
      bridge.active = activeTrip(tripId: 'run');
      final sync = newSync();
      for (var i = 0; i < 6; i++) {
        now += 30 * 60000;
        await sync.sync();
      }
      final r = await row('run');
      expect(r.endedAtMs, isNull);
      expect(r.result, isNull);
      expect(
        historyStatusOf(r, activeTripId: 'run', activeKnown: true),
        HistoryStatus.running,
      );
    });

    test('currentTrip fails (native not ready): nothing is marked', () async {
      await repo.insertStarted(
        sampleRecord(id: 'run', startedAtMs: _now - 9 * 3600000),
      );
      bridge.currentTripError = channelError();
      await newSync().sync();
      expect((await row('run')).endedAtMs, isNull);
    });

    test('grace boundary: started exactly 120 s ago is not marked, '
        '120 001 ms ago is', () async {
      await repo.insertStarted(
        sampleRecord(id: 'edge', startedAtMs: _now - _grace),
      );
      await repo.insertStarted(
        sampleRecord(id: 'old', startedAtMs: _now - _grace - 1),
      );
      // A trip being started (T25 writes the row before startTrip): native
      // has no trip yet.
      await repo.insertStarted(
        sampleRecord(id: 'starting', startedAtMs: _now - 20000),
      );
      await newSync().sync();
      expect((await row('edge')).endedAtMs, isNull);
      expect((await row('starting')).endedAtMs, isNull);
      expect((await row('old')).endedAtMs, _now);
    });

    test(
      'a running row wrongly marked (currentTrip answered null) shows '
      'running again as soon as the trip is known, and gets its result',
      () async {
        await repo.insertStarted(
          sampleRecord(id: 'run', startedAtMs: _now - 3600000),
        );
        final sync = newSync();
        await sync.sync(); // native answered null: marked
        final marked = await row('run');
        expect(marked.endedAtMs, _now);
        expect(
          historyStatusOf(marked, activeTripId: 'run', activeKnown: true),
          HistoryStatus.running,
        );
        expect(canRestart(marked, HistoryStatus.running), isFalse);
        bridge.pending.add(finishedTrip('run', outcome: TripOutcomeMsg.missed));
        await sync.sync();
        expect((await row('run')).result, TripOutcomeMsg.missed);
      },
    );

    test('simulated running trip is protected the same way', () async {
      await repo.insertStarted(
        sampleRecord(id: 'sim', startedAtMs: _now - 3600000, simulated: true),
      );
      bridge.active = activeTrip(tripId: 'sim');
      await newSync().sync();
      expect((await row('sim')).endedAtMs, isNull);
    });
  });

  group('simulated trips stay out of the month stats', () {
    test('a simulated trip that ended through HistorySync is not counted; '
        'its trip_end says simulated', () async {
      final month = monthStartMs(DateTime(2026, 11, 20));
      final t0 = DateTime(2026, 11, 10, 8).millisecondsSinceEpoch;
      await repo.insertStarted(
        sampleRecord(id: 'sim', startedAtMs: t0, simulated: true),
      );
      await repo.insertStarted(sampleRecord(id: 'real', startedAtMs: t0 + 1));
      bridge.pending
        ..add(finishedTrip('sim', travelledM: 33000))
        ..add(finishedTrip('real', travelledM: 2000));
      now = DateTime(2026, 11, 20).millisecondsSinceEpoch;
      await newSync().sync();
      final real = await repo.watchRealTripsSince(month).first;
      expect(real.map((r) => r.id), ['real']);
      final stats = monthStats(real);
      expect(stats.tripCount, 1);
      expect(stats.travelledM, 2000);
      expect(stats.alarmed, 1);
      // Defensive filter of monthStats too (input not pre-filtered).
      final all = await repo.watchHistory().first;
      expect(all, hasLength(2));
      final s2 = monthStats(all);
      expect(s2.tripCount, 1);
      expect(s2.travelledM, 2000);
      final sims = analytics.events
          .where((e) => e.$1 == 'trip_end')
          .map((e) => e.$2['simulated'])
          .toList();
      expect(sims..sort(), [0, 1]);
    });

    test('only simulated trips this month: 0 trips, 0 km, no ratio', () {
      final s = monthStats([
        sampleRecord(id: 's1', simulated: true).copyWithResultForTest(),
      ]);
      expect(s.tripCount, 0);
      expect(s.travelledM, 0);
      expect(s.alarmed, 0);
    });
  });
}

extension on TripRecord {
  /// A finished simulated record without touching a database.
  TripRecord copyWithResultForTest() => TripRecord(
    id: id,
    destination: destination,
    source: source,
    alarm: alarm,
    vehicleHint: vehicleHint,
    simulated: simulated,
    startedAtMs: startedAtMs,
    endedAtMs: startedAtMs + 1000,
    result: TripOutcomeMsg.onTime,
    travelledM: 33000,
  );
}
