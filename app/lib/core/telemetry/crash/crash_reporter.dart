/// Everything sent to Crashlytics goes through [CrashReporter] (T29 §4).
///
/// PRIVACY (orchestrator decision after review T29 round 1, replaces §4.2
/// for fatals): every report, fatal or not, carries only the error TYPE,
/// the stack trace and `FlutterErrorDetails.library`. Never `toString()`,
/// `exceptionAsString()`, the error context or summary: redaction cannot
/// recognise an OSM station id in a widget key (`station-osm:n…`), a Places
/// id or SQL parameters (destination names). The only exception is an app
/// error marked [SafeDiagnostic] (fixed, hand-written message). Flutter's
/// `informationCollector` is never sent.
library;

import 'package:flutter/foundation.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/telemetry/crash/crash_keys.dart';
import 'package:napstop/core/telemetry/crash/safe_diagnostic.dart';
import 'package:napstop/core/telemetry/redaction/redactor.dart';
import 'package:napstop/core/telemetry/safe_call.dart';

export 'package:napstop/core/telemetry/crash/safe_diagnostic.dart';

/// Why a recovered error is reported; sent as the `reason` (its name).
enum NonFatalReason {
  stationCatalogLoadFailed,
  mapsLoadFailed,
  pigeonCallFailed,
  historyWriteFailed,
  remoteConfigInvalid,
  analyticsGuardViolation,
  other,
}

/// What the sink receives instead of the original error.
@immutable
final class RedactedError implements Exception {
  const new(this.type, this.message);

  /// `runtimeType` of the original error (Dart is not obfuscated in MVP).
  final String type;

  /// Empty, or a redacted message.
  final String message;

  @override
  String toString() => message.isEmpty ? type : '$type: $message';
}

/// Crashlytics or a test double. Implemented by `FirebaseCrashSink`, the
/// only file importing `package:firebase_crashlytics`.
abstract interface class CrashSink {
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required String reason,
    required bool fatal,
  });

  Future<void> log(String message);

  Future<void> setCustomKey(String key, Object value);

  Future<void> setCollectionEnabled({required bool enabled});

  Future<void> sendUnsentReports();

  Future<void> deleteUnsentReports();
}

/// No Firebase (not configured, init failed, tests).
final class NoopCrashSink implements CrashSink {
  const new();

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required String reason,
    required bool fatal,
  }) async {}

  @override
  Future<void> log(String message) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async {}

  @override
  Future<void> sendUnsentReports() async {}

  @override
  Future<void> deleteUnsentReports() async {}
}

/// What may leave the device for [error]: its `runtimeType`, plus the
/// redacted `toString()` of a [SafeDiagnostic] only. A [RedactedError]
/// passed in keeps its type only.
RedactedError redactedErrorOf(Object error) => switch (error) {
  RedactedError(:final type) => RedactedError(type, ''),
  SafeDiagnostic() => RedactedError(
    error.runtimeType.toString(),
    redact(error.toString()),
  ),
  _ => RedactedError(error.runtimeType.toString(), ''),
};

/// Reason of a [reportNonFatal] error.
const String kReportNonFatalReason = 'reportNonFatal';

/// Reason of an error no handler caught.
const String kUncaughtReason = 'uncaught';

/// Fire-and-forget front of a [CrashSink]: never throws (except the
/// [strict] check of [setKey]), never waits.
final class CrashReporter {
  new(this._sink, {this.strict = kDebugMode});

  final CrashSink _sink;

  /// Debug/test: a rejected custom key value throws instead of being
  /// dropped silently.
  final bool strict;

  final Map<CrashKey, Object> _keys = {};

  /// A recovered error: type + stack (+ the message of a
  /// [SafeDiagnostic]).
  void recordNonFatal(Object error, StackTrace? stack, NonFatalReason reason) {
    final redacted = redactedErrorOf(error);
    fireAndForget(
      () =>
          _sink.recordError(redacted, stack, reason: reason.name, fatal: false),
    );
  }

  /// An error nothing caught (`PlatformDispatcher.onError`): type + stack.
  void recordFatal(Object error, StackTrace? stack) {
    final redacted = redactedErrorOf(error);
    fireAndForget(
      () => _sink.recordError(
        redacted,
        stack,
        reason: kUncaughtReason,
        fatal: true,
      ),
    );
  }

  /// `FlutterError.onError`. A [NonFatalError] (T22 `reportNonFatal`) is a
  /// non-fatal with the original error type and its call site (a code
  /// literal). Any other error is fatal (as in the Firebase sample): type,
  /// stack and `library` only, as the reason.
  void recordFlutterError(FlutterErrorDetails details) {
    final exception = details.exception;
    if (exception is NonFatalError) {
      final redacted = RedactedError(
        exception.errorType,
        redact(exception.where),
      );
      fireAndForget(
        () => _sink.recordError(
          redacted,
          details.stack,
          reason: kReportNonFatalReason,
          fatal: false,
        ),
      );
      return;
    }
    final redacted = redactedErrorOf(exception);
    final library = details.library;
    final reason = library == null || library.isEmpty
        ? kUncaughtReason
        : redact(library, maxLength: 100);
    fireAndForget(
      () => _sink.recordError(
        redacted,
        details.stack,
        reason: reason,
        fatal: true,
      ),
    );
  }

  /// A log line attached to the next report.
  void breadcrumb(String message) =>
      fireAndForget(() => _sink.log(redact(message)));

  /// Sets [key] when [value] is allowed and differs from the last value
  /// set. A rejected value is dropped (strict: [StateError], without the
  /// value).
  void setKey(CrashKey key, Object value) {
    if (!key.accepts(value)) {
      if (strict) {
        throw StateError('crash key ${key.wire}: rejected value');
      }
      return;
    }
    if (_keys[key] == value) {
      return;
    }
    _keys[key] = value;
    fireAndForget(() => _sink.setCustomKey(key.wire, value));
  }
}
