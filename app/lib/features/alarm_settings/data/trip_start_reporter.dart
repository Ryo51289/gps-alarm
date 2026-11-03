import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

/// Until T29: events are dropped; a failed history write is still reported
/// as a non-fatal (error type only, T22 `reportNonFatal`).
final class NoopTripStartReporter implements TripStartReporter {
  const new();

  @override
  void started(TripStartFacts facts) {}

  @override
  void blocked(TripStartBlockReason reason, {required bool simulated}) {}

  @override
  void configRejected(String rule) {}

  @override
  void historyWriteFailed(Object error, StackTrace stack) =>
      reportNonFatal('tripStart.history', error, stack);
}
