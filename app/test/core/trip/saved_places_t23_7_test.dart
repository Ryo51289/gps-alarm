// T23.7: changing a filled slot persists for every destination kind and every
// slot, and survives closing and reopening the database file (app restart).
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/data/saved_places_repository.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:path/path.dart' as p;

import '../../helpers/trip_fixtures.dart';

/// One destination per kind; the address and bus stop mimic T23.5 / T24.3
/// (long Vietnamese detail, no detail).
const Map<DestinationKind, TripDestination> _byKind = {
  DestinationKind.train: kGaDongHoi,
  DestinationKind.coach: kBenXeMyDinh,
  DestinationKind.bus: TripDestination(
    name: 'Trạm buýt Kim Mã',
    lat: 21.0313,
    lng: 105.8237,
    kind: DestinationKind.bus,
    detail: 'Hà Nội',
  ),
  DestinationKind.address: TripDestination(
    name: '54 Nguyễn Trãi',
    lat: 21.0003,
    lng: 105.8167,
    kind: DestinationKind.address,
    detail: 'Thượng Đình, Thanh Xuân, Hà Nội, Việt Nam',
  ),
  DestinationKind.pin: TripDestination(
    name: 'Điểm đã ghim',
    lat: 10.7769,
    lng: 106.7009,
    kind: DestinationKind.pin,
  ),
};

void main() {
  late Directory dir;
  late File file;

  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('t23_7_');
    file = File(p.join(dir.path, 'napstop.sqlite'));
  });
  tearDown(() => dir.delete(recursive: true));

  AppDatabase open() => AppDatabase(NativeDatabase(file));

  for (final slot in SavedPlaceSlot.values) {
    for (final kind in DestinationKind.values) {
      test(
        '${slot.name}: change to ${kind.name} persists after reopen',
        () async {
          var now = DateTime.utc(2026, 11, 12, 8);
          var db = open();
          var repo = DriftSavedPlacesRepository(db, clock: () => now);
          // A slot that already holds a value (update, not insert).
          await repo.upsert(slot, kHometown);
          final emissions = <Map<SavedPlaceSlot, SavedPlace>>[];
          final sub = repo.watchAll().listen(emissions.add);
          await pumpEventQueue();

          now = DateTime.utc(2026, 11, 12, 9);
          final next = _byKind[kind]!;
          await repo.upsert(slot, next);
          await pumpEventQueue();
          expect(emissions.last[slot]?.destination, next);
          await sub.cancel();
          await db.close();

          db = open();
          addTearDown(db.close);
          repo = DriftSavedPlacesRepository(db);
          final saved = await repo.get(slot);
          expect(saved?.destination, next);
          expect(saved?.updatedAtMs, now.millisecondsSinceEpoch);
          expect((await repo.watchAll().first)[slot]?.destination, next);
          // Other slots untouched.
          for (final other in SavedPlaceSlot.values.where((s) => s != slot)) {
            expect(await repo.get(other), isNull);
          }
        },
      );
    }
  }

  test('all three slots changed in turn, every kind, survive reopen', () async {
    var db = open();
    var repo = DriftSavedPlacesRepository(db);
    for (final slot in SavedPlaceSlot.values) {
      await repo.upsert(slot, kHometown);
    }
    const kinds = DestinationKind.values;
    for (var i = 0; i < kinds.length * 2; i++) {
      final slot = SavedPlaceSlot.values[i % SavedPlaceSlot.values.length];
      await repo.upsert(slot, _byKind[kinds[i % kinds.length]]!);
    }
    final before = await repo.watchAll().first;
    await db.close();

    db = open();
    addTearDown(db.close);
    repo = DriftSavedPlacesRepository(db);
    expect(await repo.watchAll().first, before);
    expect(before.length, 3);
  });
}
