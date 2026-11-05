// T28 H01-H05 (+ queries of screen 11): the history half of
// DriftTripsRepository over an in-memory database.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/trip_fixtures.dart';

void main() {
  late AppDatabase db;
  late DriftTripsRepository repo;

  setUp(() {
    db = memoryDatabase();
    repo = DriftTripsRepository(db);
  });
  tearDown(() => db.close());

  test('H01 applyFinished fills the result, keeps start and choice', () async {
    final start = sampleRecord(id: 'A');
    await repo.insertStarted(start);
    final f = finishedTrip('A');

    final (:result, :record) = await repo.applyFinished(f);

    expect(result, ApplyFinishedResult.applied);
    expect(record, isNotNull);
    final r = (await repo.byId('A'))!;
    expect(record, r);
    expect(r.result, TripOutcomeMsg.onTime);
    expect(r.endReason, EndReasonMsg.dismissed);
    expect(r.endedAtMs, f.endedAtMs);
    expect(r.alarmAtMs, f.alarmAtMs);
    expect(r.alarmReason, AlarmReasonMsg.distance);
    expect(r.dismissedAtMs, f.dismissedAtMs);
    expect(r.snoozeCount, 0);
    expect(r.travelledM, 498000);
    expect(r.vehicleGuess, VehicleKindMsg.train);
    // Never touched: the trip clock start of f differs on purpose (D2).
    expect(r.startedAtMs, start.startedAtMs);
    expect(r.destination, start.destination);
    expect(r.alarm, start.alarm);
    expect(r.source, start.source);
    expect(r.vehicleHint, start.vehicleHint);
  });

  test('H02 a second delivery is alreadyApplied; first result kept', () async {
    await repo.insertStarted(sampleRecord(id: 'A'));
    await repo.applyFinished(finishedTrip('A'));

    final again = await repo.applyFinished(finishedTrip('A'));
    final other = await repo.applyFinished(
      finishedTrip('A', outcome: TripOutcomeMsg.missed, travelledM: 1),
    );

    expect(again.result, ApplyFinishedResult.alreadyApplied);
    expect(again.record, isNull);
    expect(other.result, ApplyFinishedResult.alreadyApplied);
    final r = (await repo.byId('A'))!;
    expect(r.result, TripOutcomeMsg.onTime);
    expect(r.travelledM, 498000);
  });

  test('H03 no row: noRow, nothing inserted', () async {
    final (:result, :record) = await repo.applyFinished(finishedTrip('B'));
    expect(result, ApplyFinishedResult.noRow);
    expect(record, isNull);
    expect(await repo.byId('B'), isNull);
    expect(await db.select(db.trips).get(), isEmpty);
  });

  test('H04 markUnfinishedAsUnknown marks only old orphans', () async {
    const now = 1700001000000;
    await repo.insertStarted(sampleRecord(id: 'X', startedAtMs: now - 300000));
    await repo.insertStarted(sampleRecord(id: 'Y', startedAtMs: now - 30000));
    await repo.insertStarted(sampleRecord(id: 'Z', startedAtMs: now - 300000));
    await repo.insertStarted(sampleRecord(id: 'W', startedAtMs: now - 300000));
    await repo.applyFinished(finishedTrip('W'));
    final w = await repo.byId('W');

    final n = await repo.markUnfinishedAsUnknown(
      exceptTripId: 'Z',
      startedBeforeMs: now - kOrphanGrace.inMilliseconds,
      endedAtMs: now,
    );

    expect(n, 1);
    final x = (await repo.byId('X'))!;
    expect(x.endedAtMs, now);
    expect(x.result, isNull);
    expect((await repo.byId('Y'))!.endedAtMs, isNull);
    expect((await repo.byId('Z'))!.endedAtMs, isNull);
    expect(await repo.byId('W'), w);
    // Running again changes nothing (ended_at is set).
    expect(
      await repo.markUnfinishedAsUnknown(
        exceptTripId: null,
        startedBeforeMs: now - kOrphanGrace.inMilliseconds,
        endedAtMs: now + 1,
      ),
      1, // Z only: no running trip is excluded any more.
    );
    expect((await repo.byId('X'))!.endedAtMs, now);
  });

  test('H05 a marked orphan still takes a late result (self-repair)', () async {
    const now = 1700001000000;
    await repo.insertStarted(sampleRecord(id: 'X', startedAtMs: now - 300000));
    await repo.markUnfinishedAsUnknown(
      exceptTripId: null,
      startedBeforeMs: now - 120000,
      endedAtMs: now,
    );

    final (:result, :record) = await repo.applyFinished(
      finishedTrip('X', outcome: TripOutcomeMsg.cancelled, endedAtMs: now + 5),
    );

    expect(result, ApplyFinishedResult.applied);
    expect(record!.result, TripOutcomeMsg.cancelled);
    expect(record.endedAtMs, now + 5);
  });

  test('watchHistory: newest first, simulated included, limited', () async {
    await repo.insertStarted(sampleRecord(id: 'a', startedAtMs: 1));
    await repo.insertStarted(
      sampleRecord(id: 'b', startedAtMs: 3, simulated: true),
    );
    await repo.insertStarted(sampleRecord(id: 'c', startedAtMs: 2));

    final all = await repo.watchHistory().first;
    expect(all.map((r) => r.id), ['b', 'c', 'a']);
    final two = await repo.watchHistory(limit: 2).first;
    expect(two.map((r) => r.id), ['b', 'c']);
  });

  test('watchRealTripsSince: real trips from the given start only', () async {
    await repo.insertStarted(sampleRecord(id: 'old', startedAtMs: 99));
    await repo.insertStarted(sampleRecord(id: 'edge', startedAtMs: 100));
    await repo.insertStarted(
      sampleRecord(id: 'sim', startedAtMs: 150, simulated: true),
    );
    await repo.insertStarted(sampleRecord(id: 'new', startedAtMs: 200));

    final rows = await repo.watchRealTripsSince(100).first;
    expect(rows.map((r) => r.id), ['new', 'edge']);
  });

  test('the stream follows applyFinished', () async {
    await repo.insertStarted(sampleRecord(id: 'A'));
    final seen = <List<TripRecord>>[];
    final sub = repo.watchHistory().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    await repo.applyFinished(finishedTrip('A'));
    await pumpEventQueue();
    expect(seen.last.single.result, TripOutcomeMsg.onTime);
  });
}
