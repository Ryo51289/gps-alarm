// R02-R05: repositories over an in-memory database, and the database
// directory.
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/db/connection.dart';
import 'package:napstop/core/trip/data/saved_places_repository.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:path/path.dart' as p;

import '../../helpers/app_harness.dart';
import '../../helpers/trip_fixtures.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  group('R02 SavedPlacesRepository', () {
    test('watchAll follows upsert, remove and restore', () async {
      var now = DateTime.utc(2026, 11, 2, 12);
      final repo = DriftSavedPlacesRepository(db, clock: () => now);
      final emissions = <Map<SavedPlaceSlot, SavedPlace>>[];
      final sub = repo.watchAll().listen(emissions.add);
      addTearDown(sub.cancel);
      await pumpEventQueue();

      SavedPlace place(SavedPlaceSlot slot, TripDestination d, DateTime at) =>
          SavedPlace(
            slot: slot,
            destination: d,
            updatedAtMs: at.millisecondsSinceEpoch,
          );

      final t1 = now;
      await repo.upsert(SavedPlaceSlot.home, kGaDongHoi);
      await pumpEventQueue();
      now = DateTime.utc(2026, 11, 2, 13);
      final t2 = now;
      await repo.upsert(SavedPlaceSlot.home, kGaHue);
      await pumpEventQueue();
      await repo.upsert(SavedPlaceSlot.work, kHomeAddress);
      await pumpEventQueue();
      final oldWork = await repo.get(SavedPlaceSlot.work);
      await repo.remove(SavedPlaceSlot.work);
      await pumpEventQueue();
      await repo.restore(oldWork!);
      await pumpEventQueue();

      final a = place(SavedPlaceSlot.home, kGaDongHoi, t1);
      final b = place(SavedPlaceSlot.home, kGaHue, t2);
      final c = place(SavedPlaceSlot.work, kHomeAddress, t2);
      expect(emissions, [
        <SavedPlaceSlot, SavedPlace>{},
        {SavedPlaceSlot.home: a},
        {SavedPlaceSlot.home: b},
        {SavedPlaceSlot.home: b, SavedPlaceSlot.work: c},
        {SavedPlaceSlot.home: b},
        {SavedPlaceSlot.home: b, SavedPlaceSlot.work: c},
      ]);
      expect(await repo.get(SavedPlaceSlot.hometown), isNull);
    });

    test('invalid destination: ArgumentError without the value', () async {
      final repo = DriftSavedPlacesRepository(db);
      const bad = TripDestination(
        name: 'Secret Place',
        lat: 91,
        lng: 0,
        kind: DestinationKind.pin,
      );
      await expectLater(
        repo.upsert(SavedPlaceSlot.home, bad),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString',
            allOf(isNot(contains('Secret')), isNot(contains('91'))),
          ),
        ),
      );
      expect(await repo.get(SavedPlaceSlot.home), isNull);
    });
  });

  group('R03 TripsRepository', () {
    test('every field round-trips; delete; duplicate id fails', () async {
      final repo = DriftTripsRepository(db);
      const alarm = TripAlarmChoice(
        mode: AlarmModeMsg.distance,
        distanceThresholdM: 1500,
        preAlertEnabled: false,
      );
      final started = TripRecord.started(
        id: 'trip-42',
        draft: const TripDraft(
          destination: kGaDongHoi,
          source: DestinationSource.mapPin,
          vehicleHint: VehicleKindMsg.coach,
        ),
        alarm: alarm,
        startedAtMs: 1700000000000,
        simulated: true,
      );
      await repo.insertStarted(started);
      expect(await repo.byId('trip-42'), started);

      // T28 will write these from FinishedTripMsg.
      await db.customUpdate(
        'UPDATE trips SET ended_at = ?, result = ?, end_reason = ?, '
        'alarm_at = ?, alarm_reason = ?, dismissed_at = ?, snooze_count = ?, '
        'travelled_m = ?, vehicle_guess = ? WHERE id = ?',
        variables: [
          for (final v in [
            1700000900000,
            'cancelled',
            'user_stop',
            1700000800000,
            'smart_slow_distance',
            1700000850000,
            2,
            123456,
            'bus',
            'trip-42',
          ])
            Variable(v),
        ],
      );
      const full = TripRecord(
        id: 'trip-42',
        destination: kGaDongHoi,
        source: DestinationSource.mapPin,
        alarm: alarm,
        vehicleHint: VehicleKindMsg.coach,
        simulated: true,
        startedAtMs: 1700000000000,
        endedAtMs: 1700000900000,
        result: TripOutcomeMsg.cancelled,
        endReason: EndReasonMsg.userStop,
        alarmAtMs: 1700000800000,
        alarmReason: AlarmReasonMsg.smartSlowDistance,
        dismissedAtMs: 1700000850000,
        snoozeCount: 2,
        travelledM: 123456,
        vehicleGuess: VehicleKindMsg.bus,
      );
      expect(await repo.byId('trip-42'), full);

      await expectLater(repo.insertStarted(started), throwsA(anything));

      await repo.delete('trip-42');
      expect(await repo.byId('trip-42'), isNull);
      expect(await repo.byId('nope'), isNull);
    });

    test('insertStarted validates destination and alarm', () async {
      final repo = DriftTripsRepository(db);
      await expectLater(
        repo.insertStarted(
          sampleRecord(
            id: 'a',
            destination: const TripDestination(
              name: ' ',
              lat: 0,
              lng: 0,
              kind: DestinationKind.pin,
            ),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.insertStarted(
          sampleRecord(
            id: 'b',
            alarm: const TripAlarmChoice(
              mode: AlarmModeMsg.time,
              preAlertEnabled: true,
            ),
          ),
        ),
        throwsArgumentError,
      );
      expect(await repo.byId('a'), isNull);
      expect(await repo.byId('b'), isNull);
    });
  });

  test('R04 recent destinations: no simulated, dedup, newest first', () async {
    final repo = DriftTripsRepository(db);
    final emissions = <List<String>>[];
    for (final r in [
      sampleRecord(id: 'old-dh', startedAtMs: 10),
      sampleRecord(id: 'hue', destination: kGaHue, startedAtMs: 20),
      sampleRecord(
        id: 'sim',
        destination: kBenXeMyDinh,
        startedAtMs: 30,
        simulated: true,
      ),
      sampleRecord(id: 'new-dh', startedAtMs: 40),
      sampleRecord(id: 'home', destination: kHomeAddress, startedAtMs: 5),
    ]) {
      await repo.insertStarted(r);
    }
    final sub = repo
        .watchRecentDestinations()
        .map((list) => list.map((r) => r.id).toList())
        .listen(emissions.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(emissions.last, ['new-dh', 'hue', 'home']);

    await repo.insertStarted(
      sampleRecord(id: 'vinh', destination: kHometown, startedAtMs: 50),
    );
    await pumpEventQueue();
    expect(emissions, hasLength(2));
    expect(emissions.last, ['vinh', 'new-dh', 'hue']);
  });

  test('R05 appDatabaseDirectory is <support>/napstop_db, created', () async {
    final tmp = await Directory.systemTemp.createTemp('napstop_r05');
    addTearDown(() => tmp.delete(recursive: true));
    final dir = await appDatabaseDirectory(supportDirectory: () async => tmp);
    expect(dir.path, p.join(tmp.path, 'napstop_db'));
    expect(dir.existsSync(), isTrue);
    expect(kDatabaseDirName, 'napstop_db');
    expect(kDatabaseName, 'napstop');
    // Idempotent.
    final again = await appDatabaseDirectory(supportDirectory: () async => tmp);
    expect(again.path, dir.path);
  });
}
