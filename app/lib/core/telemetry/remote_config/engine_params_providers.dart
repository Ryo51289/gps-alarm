import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';

/// Source of `trip_engine_params` (T25 §2.3). T29 overrides it with
/// `(ref) => ref.watch(telemetryProvider).engineParams`.
final engineParamsReaderProvider = Provider<EngineParamsReader>(
  (ref) => const DefaultEngineParamsReader(),
);
