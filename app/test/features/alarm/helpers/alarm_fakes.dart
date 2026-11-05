// Fakes of the T27 widget tests. Not a test file.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/telemetry.dart';

import '../../../core/telemetry/telemetry_fakes.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/fake_key_value_store.dart';

/// Telemetry on a recording Analytics sink, collection forced on, strict.
(Telemetry, RecordingAnalyticsSink) recordingTelemetry() {
  final a = RecordingAnalyticsSink();
  final c = RecordingCrashSink();
  final crash = CrashReporter(c);
  final controller = TelemetryConsentController(
    store: TelemetryConsentStore(FakeKeyValueStore()),
    consent: TelemetryConsent.initial,
    crashSink: c,
    analyticsSink: a,
    flavor: AppFlavor.dev,
    isDebugBuild: false,
    override: TelemetryOverride.on,
  );
  return (
    Telemetry(
      analytics: AppAnalytics(
        sink: a,
        crash: crash,
        isEnabled: () => controller.effective.analytics,
      ),
      crash: crash,
      engineParams: EngineParamsSource(
        FakeRemoteConfigClient(),
        flavor: AppFlavor.dev,
      ),
      consent: controller,
    ),
    a,
  );
}

/// Records the URIs it is asked to open; answers [result] or throws [error].
class FakeMapsLauncher {
  final List<Uri> opened = [];
  bool result = true;
  Object? error;

  /// When set, every call waits for it (double-tap tests).
  Completer<void>? gate;

  Future<bool> call(Uri uri) async {
    opened.add(uri);
    final g = gate;
    if (g != null) {
      await g.future;
    }
    final e = error;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return result;
  }
}

/// Collects what `reportNonFatal` / `FlutterError.reportError` sends while
/// a test runs. Call [restore] in a tear-down.
class ReportedErrors {
  new() {
    _previous = FlutterError.onError;
    FlutterError.onError = (d) => texts.add(d.toString());
  }

  final List<String> texts = [];
  FlutterExceptionHandler? _previous;

  void restore() => FlutterError.onError = _previous;
}

/// A ringing state of [tripId] (screen 5, arriving by default).
TripStateMsg ringingState({
  String tripId = 'trip-1',
  TripPhaseMsg phase = TripPhaseMsg.alarming,
  bool ringing = true,
  int snoozeCount = 0,
  int? overshootPastM,
  AlarmReasonMsg? reason = AlarmReasonMsg.distance,
  int? distanceM = 1200,
}) => tripState(tripId: tripId, phase: phase)
  ..alarmRinging = ringing
  ..snoozeCount = snoozeCount
  ..overshootPastM = overshootPastM
  ..alarmReason = reason
  ..distanceM = distanceM;

/// The running trip of [state] (destination Ga Đồng Hới).
ActiveTripMsg ringingTrip(
  TripStateMsg state, {
  String destinationName = 'Ga Đồng Hới',
  DismissMethodMsg dismissMethod = DismissMethodMsg.swipe,
  String? engineParamsJson,
}) {
  final trip = activeTrip(
    tripId: state.tripId,
    destinationName: destinationName,
  )..state = state;
  trip.config
    ..engineParamsJson = engineParamsJson
    ..alarm.dismissMethod = dismissMethod;
  return trip;
}
