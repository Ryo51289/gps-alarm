// Manual helper for the T27 protocol (docs/test-protocols/T27.md): writes two
// `trips` rows that screen 8 reads by id (D7), then shows them. Not a test
// file: build it as the app's entry point, run it once, then install the
// normal dev build over it (`install -r` keeps the database).
//
//   flutter build apk --debug -t integration_test/manual/t27_seed_trips_probe.dart
//   adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
//   adb shell am start -n app.napstop.dev/app.napstop.MainActivity
//   adb logcat -d -s flutter | grep NAPSTOP_T27
//   flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-dev-debug.apk
//
// Rows (ids fixed, rewritten on every run):
//   t27-recent  started now        (screen 8 may open Maps by itself, D12)
//   t27-old     started 49 h ago   (never opens Maps by itself, MT5)
// Destination: Ga Đồng Hới (public station). Logs ids and ages only.
import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

const _tag = 'NAPSTOP_T27';

const TripDraft _dongHoi = TripDraft(
  destination: TripDestination(
    name: 'Ga Đồng Hới',
    lat: 17.4783,
    lng: 106.6003,
    kind: DestinationKind.train,
    detail: 'Quảng Bình',
  ),
  source: DestinationSource.station,
);

const TripAlarmChoice _alarm = TripAlarmChoice(
  mode: AlarmModeMsg.distance,
  distanceThresholdM: 1000,
  preAlertEnabled: true,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('T27 seed trips')),
    ),
  );
  final db = AppDatabase();
  final repo = DriftTripsRepository(db);
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final (id, age) in [
    ('t27-recent', Duration.zero),
    ('t27-old', const Duration(hours: 49)),
  ]) {
    await repo.delete(id);
    await repo.insertStarted(
      TripRecord.started(
        id: id,
        draft: _dongHoi,
        alarm: _alarm,
        startedAtMs: now - age.inMilliseconds,
      ),
    );
    final back = await repo.byId(id);
    final ageH = (now - (back?.startedAtMs ?? now)) / 3600000;
    debugPrint(
      '$_tag $id written=${back != null} ageH=${ageH.toStringAsFixed(1)}',
    );
  }
  await db.close();
  debugPrint('$_tag done');
}
