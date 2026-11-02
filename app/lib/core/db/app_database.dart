// PRIVACY: generated row classes (TripRow, SavedPlaceRow) print every column
// in toString(), coordinates included. Only lib/core/db and
// lib/core/trip/data may use them; never log them.
import 'package:drift/drift.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/db/connection.dart';
import 'package:napstop/core/db/converters.dart';
import 'package:napstop/core/db/tables.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';

part 'app_database.g.dart';

/// The app database (schema v1, T22 §5).
///
/// Changing the schema: edit the tables, bump [schemaVersion], run
/// `dart run drift_dev make-migrations`, write `onUpgrade: stepByStep(...)`
/// with the generated steps, commit the schema snapshot, steps and tests.
@DriftDatabase(tables: [Trips, SavedPlaces])
class AppDatabase extends _$AppDatabase {
  /// Defaults to the on-device file; tests pass `NativeDatabase.memory()`.
  new([QueryExecutor? executor]) : super(executor ?? openAppDatabase());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (m) => m.createAll());
}
