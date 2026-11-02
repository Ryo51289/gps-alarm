import 'package:flutter/foundation.dart';

/// Reports an unexpected, recovered error without its content.
///
/// PRIVACY: only the error type and [where] are reported; messages of
/// decoding errors can quote fields such as a destination name. Goes to
/// `FlutterError.onError` (console in debug; T29 forwards it to Crashlytics).
void reportNonFatal(String where, Object error, StackTrace stack) {
  FlutterError.reportError(
    FlutterErrorDetails(
      exception: NonFatalError(where, error.runtimeType.toString()),
      stack: stack,
      library: 'napstop',
    ),
  );
}

/// What [reportNonFatal] reports instead of the original error.
@immutable
final class NonFatalError implements Exception {
  const new(this.where, this.errorType);

  final String where;
  final String errorType;

  @override
  String toString() => 'NonFatalError($where: $errorType)';
}
