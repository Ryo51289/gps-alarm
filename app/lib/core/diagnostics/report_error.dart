import 'package:flutter/foundation.dart';
import 'package:napstop/core/telemetry/crash/safe_diagnostic.dart';

/// Reports an unexpected, recovered error without its content.
///
/// PRIVACY: only the error type and [where] are reported; messages of
/// decoding errors can quote fields such as a destination name. Goes to
/// `FlutterError.onError`: the console in debug, and Crashlytics as a
/// NON-fatal (T29 `CrashReporter.recordFlutterError`, review T22 N1).
void reportNonFatal(String where, Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: NonFatalError(where, error.runtimeType.toString()),
      stack: stack,
      library: 'napstop',
    ),
  );
}

/// What [reportNonFatal] reports instead of the original error. Its text is
/// a call-site literal and a type name only, hence [SafeDiagnostic].
@immutable
final class NonFatalError implements Exception, SafeDiagnostic {
  const new(this.where, this.errorType);

  final String where;
  final String errorType;

  @override
  String toString() => 'NonFatalError($where: $errorType)';
}
