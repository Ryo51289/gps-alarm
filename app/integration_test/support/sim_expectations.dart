// T18: shared helpers of the integration tests that run simulated trips on
// the real runtime (bundled traces of assets/sim, catalog.json). Expectation
// windows are the `expect[]` of fixtures/traces/<id>.expect.json (trace
// seconds); real time = trace seconds / speed (after the first alarm the
// trip runs at 1x, T18 D3).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

/// `train_hn_dh` / `distance_1000`: PreAlert window (trace s).
const int kTrainPreAlertNotBefore = 33435;
const int kTrainPreAlertNotAfter = 33470;

/// `train_hn_dh` / `distance_1000`: Alarm(DISTANCE) window (trace s).
const int kTrainAlarmNotBefore = 33680;
const int kTrainAlarmNotAfter = 33715;

/// Slack added to `notAfter` (T18 SI01): the FGS start runs at 1x before the
/// clock switches to the simulation speed (D2), so t is measured from the
/// first TripStateUpdateMsg, a few real seconds before trace t 0 at most.
const int kFgsSlackS = 5;

/// `bus_hn_brt01` / `distance_1000`: Alarm(DISTANCE) window (trace s).
const int kBusAlarmNotBefore = 2110;
const int kBusAlarmNotAfter = 2225;

/// `coach_gb_phuly_overshoot` / `distance_1000_overshoot` windows (trace s).
const int kOvershootAlarmNotBefore = 2335;
const int kOvershootAlarmNotAfter = 2360;
const int kOvershootNotBefore = 2605;
const int kOvershootNotAfter = 2680;

/// The bundled catalog (asset of the app under test).
Future<SimTraceCatalog> loadCatalog() => loadSimTraceCatalog(rootBundle);

/// Trip config of a simulated trip to the trace's destination.
TripConfigMsg simConfig(
  String tripId,
  SimTrace trace, {
  AlarmModeMsg mode = AlarmModeMsg.distance,
  int? distanceThresholdM = 1000,
  int? timeThresholdMin,
  bool preAlertEnabled = true,
}) => TripConfigMsg(
  tripId: tripId,
  destinationName: trace.destination.name ?? trace.destination.id,
  mode: mode,
  distanceThresholdM: mode == AlarmModeMsg.distance ? distanceThresholdM : null,
  timeThresholdMin: mode == AlarmModeMsg.time ? timeThresholdMin : null,
  preAlertEnabled: preAlertEnabled,
  vehicleHint: trace.vehicle,
  alarm: AlarmSettingsMsg(
    soundId: 'default',
    volume: 0.8,
    rampUp: true,
    vibration: VibrationMsg.medium,
    flash: false,
    preferHeadphones: false,
    dismissMethod: DismissMethodMsg.swipe,
  ),
);

/// Starts a simulated trip of [trace] at [speed] to its catalog
/// destination.
Future<void> startSim(
  CoreBridge bridge,
  TripConfigMsg config,
  SimTrace trace,
  double speed,
) => bridge.startTrip(
  config,
  destLat: trace.destination.lat,
  destLng: trace.destination.lng,
  simulation: SimulationMsg(traceAsset: trace.id, speedFactor: speed),
);

/// Trace second of [atMs] measured from the first TripStateUpdateMsg.
int traceSecond(List<TripUpdateMsg> received, int atMs) {
  final first = received.whereType<TripStateUpdateMsg>().first.state.atMs;
  return (atMs - first) ~/ 1000;
}

/// Polls [received] (from index [from]) until an item matches [test].
Future<T> waitForUpdate<T extends TripUpdateMsg>(
  List<TripUpdateMsg> received, {
  int from = 0,
  bool Function(T)? test,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final item in received.skip(from)) {
      if (item is T && (test == null || test(item))) {
        return item;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('no $T within $timeout');
}

/// Stops a leftover trip and acknowledges old records.
Future<void> cleanSlate(CoreBridge bridge) async {
  final leftover = await bridge.currentTrip();
  if (leftover != null) {
    await bridge.stopTrip(leftover.config.tripId);
  }
  final old = await bridge.pendingFinishedTrips();
  await bridge.ackFinishedTrips([for (final t in old) t.tripId]);
}
