import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/telemetry/telemetry.dart';

/// The session's [Telemetry]. `main.dart` overrides it with the object of
/// `bootstrapTelemetry`; the default is a no-op, so widget tests need no
/// override. Never rebuilt: consent changes happen inside the object.
final telemetryProvider = Provider<Telemetry>((ref) => Telemetry.noop());
