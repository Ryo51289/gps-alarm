import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/db/app_database.dart';

/// The app database, opened lazily on first query. Tests override it with
/// `AppDatabase(NativeDatabase.memory())`.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
