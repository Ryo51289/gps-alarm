import 'package:flutter/foundation.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';

/// Routes uncaught Dart errors to [crash] (T29 §4.1, Firebase sample F8),
/// through the redaction of [CrashReporter]. Debug builds still print
/// framework errors to the console.
void installErrorHandlers(
  CrashReporter crash, {
  bool presentErrors = kDebugMode,
}) {
  FlutterError.onError = (details) {
    if (presentErrors) {
      FlutterError.presentError(details);
    }
    crash.recordFlutterError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    crash.recordFatal(error, stack);
    return true;
  };
}
