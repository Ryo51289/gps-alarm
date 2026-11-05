// Schema v1 (T22 §5.2). Changing a table means a new schema version and a
// migration (see app/README.md "drift"). Times are INTEGER epoch ms UTC, like
// Pigeon; no DateTimeColumn.
import 'package:drift/drift.dart';
import 'package:napstop/core/db/converters.dart';

/// Trip history. Start columns are written by T25 before `startTrip`; result
/// columns by T28 from `FinishedTripMsg` (null while the trip runs).
@DataClassName('TripRow')
@TableIndex(name: 'trips_started_at', columns: {#startedAt})
class Trips extends Table {
  @override
  String get tableName => 'trips';

  // --- set at start (T25) ---

  /// tripId sent in TripConfigMsg.
  TextColumn get id => text().withLength(min: 1, max: 64)();
  TextColumn get destinationName => text().withLength(min: 1, max: 200)();

  /// Province or address line, display only.
  TextColumn get destinationDetail => text().nullable()();
  TextColumn get destinationKind =>
      text().map(const DestinationKindConverter())();
  RealColumn get destLat => real()();
  RealColumn get destLng => real()();
  TextColumn get destSource => text().map(const DestinationSourceConverter())();
  TextColumn get mode => text().map(const AlarmModeConverter())();
  IntColumn get distanceThresholdM => integer().nullable()();
  IntColumn get timeThresholdMin => integer().nullable()();
  BoolColumn get preAlertEnabled => boolean()();
  TextColumn get vehicleHint => text().map(const VehicleKindConverter())();
  BoolColumn get simulated => boolean().withDefault(const Constant(false))();
  IntColumn get startedAt => integer()();

  // --- set when the trip ends (T28); null while running ---
  //
  // For a simulated trip, ended_at / alarm_at / dismissed_at are the values
  // of FinishedTripMsg, i.e. VIRTUAL trip-clock times (T18 D14): use them for
  // durations only, never show them as wall-clock times when `simulated`.
  // An orphan row (T28 D4) has ended_at set and result still null.

  IntColumn get endedAt => integer().nullable()();
  TextColumn get result =>
      text().nullable().map(const TripOutcomeConverter())();
  TextColumn get endReason =>
      text().nullable().map(const EndReasonConverter())();
  IntColumn get alarmAt => integer().nullable()();
  TextColumn get alarmReason =>
      text().nullable().map(const AlarmReasonConverter())();
  IntColumn get dismissedAt => integer().nullable()();
  IntColumn get snoozeCount => integer().withDefault(const Constant(0))();
  IntColumn get travelledM => integer().nullable()();
  TextColumn get vehicleGuess =>
      text().nullable().map(const VehicleKindConverter())();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The three saved places of screen 1, one row per slot.
@DataClassName('SavedPlaceRow')
class SavedPlaces extends Table {
  @override
  String get tableName => 'saved_places';

  /// home | hometown | work.
  TextColumn get slot => text().map(const SavedPlaceSlotConverter())();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get detail => text().nullable()();
  TextColumn get kind => text().map(const DestinationKindConverter())();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {slot};
}
