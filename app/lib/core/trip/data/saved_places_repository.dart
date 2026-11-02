// PRIVACY: never log rows or destinations here (coordinates, T22 §12).
import 'package:drift/drift.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';

/// The three saved places of screen 1 (T22 §7.1).
abstract interface class SavedPlacesRepository {
  /// Current places by slot; emits again after every change.
  Stream<Map<SavedPlaceSlot, SavedPlace>> watchAll();

  Future<SavedPlace?> get(SavedPlaceSlot slot);

  /// Inserts or replaces the slot (T22 add/change, T23 "Lưu điểm").
  /// `updatedAt` is the repository clock. Invalid destination:
  /// [ArgumentError].
  Future<void> upsert(SavedPlaceSlot slot, TripDestination destination);

  /// Restores an exact earlier value (undo after [remove]).
  Future<void> restore(SavedPlace place);

  Future<void> remove(SavedPlaceSlot slot);
}

final class DriftSavedPlacesRepository implements SavedPlacesRepository {
  new(this._db, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  @override
  Stream<Map<SavedPlaceSlot, SavedPlace>> watchAll() => _db
      .select(_db.savedPlaces)
      .watch()
      .map((rows) => {for (final r in rows) r.slot: _toDomain(r)});

  @override
  Future<SavedPlace?> get(SavedPlaceSlot slot) async {
    final row = await (_db.select(
      _db.savedPlaces,
    )..where((t) => t.slot.equalsValue(slot))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<void> upsert(SavedPlaceSlot slot, TripDestination destination) =>
      _write(
        SavedPlace(
          slot: slot,
          destination: destination,
          updatedAtMs: _clock().millisecondsSinceEpoch,
        ),
      );

  @override
  Future<void> restore(SavedPlace place) => _write(place);

  @override
  Future<void> remove(SavedPlaceSlot slot) => (_db.delete(
    _db.savedPlaces,
  )..where((t) => t.slot.equalsValue(slot))).go();

  Future<void> _write(SavedPlace place) async {
    final d = place.destination;
    if (!d.isValid) {
      throw ArgumentError('invalid destination', 'destination');
    }
    await _db
        .into(_db.savedPlaces)
        .insertOnConflictUpdate(
          SavedPlacesCompanion.insert(
            slot: place.slot,
            name: d.name,
            detail: Value(d.detail),
            kind: d.kind,
            lat: d.lat,
            lng: d.lng,
            updatedAt: place.updatedAtMs,
          ),
        );
  }

  static SavedPlace _toDomain(SavedPlaceRow r) => SavedPlace(
    slot: r.slot,
    destination: TripDestination(
      name: r.name,
      lat: r.lat,
      lng: r.lng,
      kind: r.kind,
      detail: r.detail,
    ),
    updatedAtMs: r.updatedAt,
  );
}
