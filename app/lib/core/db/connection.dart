// PRIVACY: the database holds destination coordinates. It lives in its own
// directory, excluded from Android Auto Backup and device transfer
// (res/xml/data_extraction_rules.xml, res/xml/backup_rules.xml; T22 D5).
// iOS: T17 sets isExcludedFromBackup on the same directory.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File name without extension: `napstop.sqlite`.
const String kDatabaseName = 'napstop';

/// Directory under the app support directory, excluded from backup (D5).
const String kDatabaseDirName = 'napstop_db';

/// `<app support>/napstop_db`, created if missing. On Android the app support
/// directory is `Context.getFilesDir()` (backup domain `file`).
/// [supportDirectory] is for tests.
Future<Directory> appDatabaseDirectory({
  Future<Directory> Function() supportDirectory =
      getApplicationSupportDirectory,
}) async {
  final support = await supportDirectory();
  final dir = Directory(p.join(support.path, kDatabaseDirName));
  await dir.create(recursive: true);
  return dir;
}

/// Opens the app database lazily, on a background isolate.
QueryExecutor openAppDatabase() => driftDatabase(
  name: kDatabaseName,
  native: const DriftNativeOptions(databaseDirectory: appDatabaseDirectory),
);
