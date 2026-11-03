// T29 tester: the start-flow reporter must never break a trip start
// (T25 calls `started(facts)` right after `startTrip` succeeded, outside any
// try/catch). Every combination of facts the start flow can build, with
// every SDK call throwing, in strict (debug/test) mode: no throw, and every
// event that does go out passes the guard with no coordinate-like value.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/storage/memory_key_value_store.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/alarm_settings/data/trip_start_reporter.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

import '../../../core/telemetry/telemetry_fakes.dart';

/// Records what passes, then throws like a missing plugin.
final class _ThrowingAfterRecord extends RecordingAnalyticsSink {
  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    events.add((name, parameters));
    throw StateError('plugin missing');
  }
}

void main() {
  late _ThrowingAfterRecord analytics;
  late RecordingCrashSink crashSink;

  Telemetry telemetry() {
    analytics = _ThrowingAfterRecord();
    crashSink = RecordingCrashSink()..throwOnCall = StateError('missing');
    // strict = kDebugMode (true in tests): bad values would throw.
    final crash = CrashReporter(crashSink);
    final controller = TelemetryConsentController(
      store: TelemetryConsentStore(MemoryKeyValueStore()),
      consent: TelemetryConsent.initial,
      crashSink: crashSink,
      analyticsSink: const NoopAnalyticsSink(),
      flavor: AppFlavor.dev,
      isDebugBuild: false,
      override: TelemetryOverride.on,
    );
    return Telemetry(
      analytics: AppAnalytics(
        sink: analytics,
        crash: crash,
        isEnabled: () => controller.effective.analytics,
      ),
      crash: crash,
      engineParams: EngineParamsSource(
        const NoopRemoteConfigClient(),
        flavor: AppFlavor.dev,
      ),
      consent: controller,
    );
  }

  test('started(): every fact combination, strict, throwing SDK', () async {
    final t = telemetry();
    final reporter = TelemetryTripStartReporter(() => t);
    var n = 0;
    for (final mode in AlarmModeMsg.values) {
      for (final vehicle in VehicleKindMsg.values) {
        for (final source in DestinationSource.values) {
          for (final battery in <int?>[
            null,
            -5,
            0,
            5,
            6,
            15,
            16,
            50,
            51,
            100,
            255,
          ]) {
            for (final (d, m) in <(int?, int?)>[
              (null, null),
              (500, null),
              (1000, null),
              (1001, null),
              (25000, null),
              (null, 5),
              (null, 17),
              (null, 120),
              (1000, 15),
            ]) {
              for (final id in ['default', 'invalid', '811c9dc5']) {
                n++;
                expect(
                  () => reporter.started(
                    TripStartFacts(
                      mode: mode,
                      distanceThresholdM: d,
                      timeThresholdMin: m,
                      vehicleHint: vehicle,
                      destSource: source,
                      preAlert: n.isEven,
                      shortDistanceWarning: n.isOdd,
                      batteryPct: battery,
                      charging: n % 3 == 0,
                      simulated: n % 5 == 0,
                      paramsId: id,
                    ),
                  ),
                  returnsNormally,
                );
              }
            }
          }
        }
      }
    }
    await pumpEventQueue();
    expect(analytics.events, hasLength(n));
    for (final (name, params) in analytics.events) {
      expect(checkAnalyticsEvent(name, params), isNull);
      for (final v in params.values) {
        expect(looksLikeCoordinate(v), isFalse);
      }
    }
  });

  test('blocked / configRejected / historyWriteFailed never throw', () async {
    final t = telemetry();
    final reporter = TelemetryTripStartReporter(() => t);
    for (final r in TripStartBlockReason.values) {
      for (final sim in [true, false]) {
        expect(() => reporter.blocked(r, simulated: sim), returnsNormally);
      }
    }
    expect(() => reporter.configRejected('tripId: format'), returnsNormally);
    expect(
      () => reporter.historyWriteFailed(
        StateError('INSERT … Ga Đồng Hới 17.4783'),
        StackTrace.current,
      ),
      returnsNormally,
    );
    await pumpEventQueue();
    expect(analytics.events, hasLength(TripStartBlockReason.values.length * 2));
  });
}
