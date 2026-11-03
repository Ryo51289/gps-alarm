import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';

/// Thin Crashlytics adapter: the only file importing
/// `package:firebase_crashlytics` (TC22). Gets already-redacted data from
/// [CrashReporter]; never sets a user identifier.
final class FirebaseCrashSink implements CrashSink {
  new([this._injected]);

  final FirebaseCrashlytics? _injected;

  FirebaseCrashlytics get _c => _injected ?? FirebaseCrashlytics.instance;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required String reason,
    required bool fatal,
  }) => _c.recordError(
    error,
    stack,
    reason: reason,
    // `information` stays empty: no widget descriptions (T29 §4.2).
    printDetails: false,
    fatal: fatal,
  );

  @override
  Future<void> log(String message) => _c.log(message);

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _c.setCustomKey(key, value);

  @override
  Future<void> setCollectionEnabled({required bool enabled}) =>
      _c.setCrashlyticsCollectionEnabled(enabled);

  @override
  Future<void> sendUnsentReports() => _c.sendUnsentReports();

  @override
  Future<void> deleteUnsentReports() => _c.deleteUnsentReports();
}
