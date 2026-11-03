import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';

/// Source of `trip_engine_params` (T25 §2.3, T29 §6): the session's
/// `EngineParamsSource` (engine defaults when telemetry is a no-op).
final engineParamsReaderProvider = Provider<EngineParamsReader>(
  (ref) => ref.watch(telemetryProvider).engineParams,
);
