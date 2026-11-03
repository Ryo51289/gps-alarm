/// Telemetry entry point (T29): Analytics, Crashlytics, Remote Config and
/// consent, built once by `bootstrapTelemetry` and shared through
/// `telemetryProvider`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/storage/memory_key_value_store.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/analytics/app_analytics.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_controller.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_source.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';

export 'package:napstop/core/telemetry/analytics/analytics_event.dart';
export 'package:napstop/core/telemetry/analytics/app_analytics.dart';
export 'package:napstop/core/telemetry/consent/telemetry_consent.dart';
export 'package:napstop/core/telemetry/consent/telemetry_consent_controller.dart';
export 'package:napstop/core/telemetry/crash/crash_keys.dart';
export 'package:napstop/core/telemetry/crash/crash_reporter.dart';
export 'package:napstop/core/telemetry/remote_config/engine_params_source.dart';

final class Telemetry {
  new({
    required this.analytics,
    required this.crash,
    required this.engineParams,
    required this.consent,
    this.isNoop = false,
  });

  /// No Firebase: every sink does nothing and `engineParams.current()` is
  /// the engine defaults. Consent is still stored in [store] (in memory by
  /// default), so an answer given now applies once Firebase is configured.
  factory noop({
    TelemetryConsentStore? store,
    TelemetryConsent consent = TelemetryConsent.initial,
    AppFlavor flavor = AppFlavor.dev,
    bool consentLoaded = true,
  }) {
    final crash = CrashReporter(const NoopCrashSink());
    final controller = TelemetryConsentController(
      store: store ?? TelemetryConsentStore(MemoryKeyValueStore()),
      consent: consent,
      crashSink: const NoopCrashSink(),
      analyticsSink: const NoopAnalyticsSink(),
      flavor: flavor,
      isDebugBuild: kDebugMode,
      override: TelemetryOverride.fromEnvironment,
      loaded: consentLoaded,
    );
    return Telemetry(
      analytics: AppAnalytics(
        sink: const NoopAnalyticsSink(),
        crash: crash,
        isEnabled: () => controller.effective.analytics,
      ),
      crash: crash,
      engineParams: EngineParamsSource(
        const NoopRemoteConfigClient(),
        flavor: flavor,
        crash: crash,
      ),
      consent: controller,
      isNoop: true,
    );
  }

  final AppAnalytics analytics;
  final CrashReporter crash;
  final EngineParamsSource engineParams;
  final TelemetryConsentController consent;

  /// True when Firebase is not in use (not configured or init failed).
  final bool isNoop;

  AppLifecycleListener? _lifecycle;

  /// On each return to the foreground: Remote Config refresh (T29 §6) and a
  /// retry of an unsaved consent answer (round 4). Needs the widgets
  /// binding.
  void attachLifecycle() {
    _lifecycle ??= AppLifecycleListener(
      onResume: () {
        unawaited(engineParams.refresh());
        unawaited(consent.retryUnsaved());
      },
    );
  }

  void dispose() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
