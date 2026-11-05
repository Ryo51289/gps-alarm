// Manual driver for T27 MT1 (docs/test-protocols/T27.md) until screen 3 has
// a simulation entry: writes the `trips` row T25 would write, starts the
// simulated trip `coach_gb_phuly_overshoot` at 60x (DISTANCE 1 km), then
// runs the normal app. Not a test file: build it as the entry point.
//
//   flutter build apk --debug -t integration_test/manual/t27_mt1_probe.dart
//   adb install -r -g build/app/outputs/flutter-apk/app-dev-debug.apk
//   adb shell am start -n app.napstop.dev/app.napstop.MainActivity
//   adb logcat -s flutter | grep NAPSTOP_T27     # trip id
//
// Alarm ≈ 40 s after the start, overshoot ≈ 5 min later (1x after the first
// alarm, T18 D3). Lock the screen, wait for the native overshoot screen,
// press "Xem đường quay lại". Logs the trip id only.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/trip/data/trips_repository.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';
import 'package:napstop/main.dart' as app;

const _tag = 'NAPSTOP_T27';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bridge = CoreBridge();
  final running = await bridge.currentTrip();
  if (running == null) {
    final catalog = await loadSimTraceCatalog(rootBundle);
    final trace = catalog.byId(SimTraces.coachGbPhulyOvershoot)!;
    final tripId = 'mt1-${DateTime.now().millisecondsSinceEpoch}';
    final db = AppDatabase();
    await DriftTripsRepository(db).insertStarted(
      TripRecord.started(
        id: tripId,
        draft: TripDraft(
          destination: TripDestination(
            name: trace.destination.name ?? trace.destination.id,
            lat: trace.destination.lat,
            lng: trace.destination.lng,
            kind: DestinationKind.coach,
          ),
          source: DestinationSource.station,
        ),
        alarm: const TripAlarmChoice(
          mode: AlarmModeMsg.distance,
          distanceThresholdM: 1000,
          preAlertEnabled: true,
        ),
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
        simulated: true,
      ),
    );
    await db.close();
    await bridge.startTrip(
      TripConfigMsg(
        tripId: tripId,
        destinationName: trace.destination.name ?? trace.destination.id,
        mode: AlarmModeMsg.distance,
        distanceThresholdM: 1000,
        preAlertEnabled: true,
        vehicleHint: trace.vehicle,
        alarm: AlarmSettingsMsg(
          soundId: 'default',
          volume: 0.3,
          rampUp: false,
          vibration: VibrationMsg.light,
          flash: false,
          preferHeadphones: false,
          dismissMethod: DismissMethodMsg.swipe,
        ),
      ),
      destLat: trace.destination.lat,
      destLng: trace.destination.lng,
      simulation: SimulationMsg(traceAsset: trace.id, speedFactor: 60),
    );
    debugPrint('$_tag mt1 started $tripId');
  } else {
    debugPrint('$_tag mt1 trip already running ${running.config.tripId}');
  }
  await app.main();
}
