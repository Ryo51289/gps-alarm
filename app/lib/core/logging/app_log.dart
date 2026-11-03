/// The app logger (T29 §4.3), on `package:logging`.
///
/// At EVERY level (T10 §10): a message never holds coordinates, a
/// destination or saved place name, or a search text. [redact] below is
/// only a safety net for numbers; it cannot recognise names.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:logging/logging.dart';
import 'package:napstop/core/telemetry/crash/safe_diagnostic.dart';
import 'package:napstop/core/telemetry/redaction/redactor.dart';

/// Where debug/profile records go; `dart:developer` by default.
typedef ConsoleSink = void Function(
  String message, {
  required String name,
  required int level,
});

void _developerConsole(
  String message, {
  required String name,
  required int level,
}) => developer.log(message, name: name, level: level);

abstract final class AppLog {
  /// `Logger('napstop.<name>')`.
  static Logger named(String name) => Logger('napstop.$name');

  static StreamSubscription<LogRecord>? _subscription;

  /// Once at bootstrap (again in tests: the previous listener is removed).
  ///
  /// Release: level INFO; each record ≥ INFO becomes a Crashlytics
  /// breadcrumb `redact("[LEVEL] name: message")`, nothing on the console.
  /// An attached error is written as its TYPE only (T29 round 2: its
  /// `toString()` can quote SQL parameters or station ids), except a
  /// [SafeDiagnostic] (redacted message).
  /// Debug/profile: level ALL, every record goes to [console] after
  /// [redact] (with `error.toString()`, never the object itself);
  /// [breadcrumb] is not called. Stack traces are dropped.
  static void configure({
    required bool isRelease,
    required void Function(String) breadcrumb,
    ConsoleSink console = _developerConsole,
  }) {
    unawaited(_subscription?.cancel());
    Logger.root.level = isRelease ? Level.INFO : Level.ALL;
    _subscription = Logger.root.onRecord.listen((record) {
      final error = record.error;
      if (isRelease) {
        if (record.level >= Level.INFO) {
          final suffix = switch (error) {
            null => '',
            SafeDiagnostic() => ' | $error',
            _ => ' | ${error.runtimeType}',
          };
          breadcrumb(
            redact(
              '[${record.level.name}] ${record.loggerName}: '
              '${record.message}$suffix',
            ),
          );
        }
      } else {
        final text = error == null
            ? record.message
            : '${record.message} | $error';
        console(
          redact(text),
          name: record.loggerName,
          level: record.level.value,
        );
      }
    });
  }
}
