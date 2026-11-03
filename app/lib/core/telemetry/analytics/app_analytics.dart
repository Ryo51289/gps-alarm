import 'package:flutter/foundation.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/safe_call.dart';

/// The only way to send an Analytics event (T29 §2–§3).
final class AppAnalytics {
  new({
    required this._sink,
    required this._crash,
    required this._isEnabled,
    this.strict = kDebugMode,
  });

  final AnalyticsSink _sink;
  final CrashReporter _crash;
  final bool Function() _isEnabled;

  /// Debug/test: a guard violation throws [StateError] at the call site.
  /// Release: the event is dropped and reported as a non-fatal (names only).
  final bool strict;

  /// Fire-and-forget. The guard runs first, even with collection off, so a
  /// bad event shows up in debug before anyone opts in. Then nothing is
  /// sent unless `isEnabled` says so.
  void log(AnalyticsEvent event) {
    final name = event.name;
    final params = event.toParameters();
    final violation = checkAnalyticsEvent(name, params);
    if (violation != null) {
      if (strict) {
        throw StateError(violation.toString());
      }
      _crash.recordNonFatal(
        violation,
        null,
        NonFatalReason.analyticsGuardViolation,
      );
      return;
    }
    final bool enabled;
    try {
      enabled = _isEnabled();
    } on Object {
      return;
    }
    if (!enabled) {
      return;
    }
    fireAndForget(() => _sink.logEvent(name, params));
  }
}
