import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/data/trip_start_reporter.dart';
import 'package:napstop/features/alarm_settings/domain/trip_config_builder.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

/// Telemetry of the start flow (T29). Reads [telemetryProvider] lazily
/// (`ref.read` at each event) and watches nothing, so it never rebuilds
/// [tripStarterProvider] (T25 review R2-2). Tests override it.
final tripStartReporterProvider = Provider<TripStartReporter>(
  (ref) => TelemetryTripStartReporter(() => ref.read(telemetryProvider)),
);

/// New trip ids; tests override it with a fixed id.
final tripIdGeneratorProvider = Provider<String Function()>((ref) => newTripId);

final tripStarterProvider = Provider<TripStarter>((ref) {
  final clock = ref.watch(clockProvider);
  return TripStarter(
    bridge: ref.watch(coreBridgeProvider),
    trips: ref.watch(tripsRepositoryProvider),
    reporter: ref.watch(tripStartReporterProvider),
    newTripId: ref.watch(tripIdGeneratorProvider),
    nowMs: () => clock().millisecondsSinceEpoch,
  );
});
