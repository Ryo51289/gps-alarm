/// Builds the session's [Telemetry] before `runApp` (T29 §7). Telemetry
/// never blocks or breaks the app: no Firebase options, a failed or slow
/// `Firebase.initializeApp` → no-op; no network before `runApp`.
library;

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:napstop/app/firebase/firebase_options.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/analytics/firebase_analytics_sink.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/crash/error_handlers.dart';
import 'package:napstop/core/telemetry/crash/firebase_crash_sink.dart';
import 'package:napstop/core/telemetry/remote_config/firebase_remote_config_client.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';
import 'package:napstop/core/telemetry/telemetry.dart';

typedef FirebaseInitializer = Future<void> Function(FirebaseOptions options);

Future<void> defaultFirebaseInitializer(FirebaseOptions options) =>
    Firebase.initializeApp(options: options);

/// The SDK adapters; tests pass fakes.
typedef TelemetryAdapters = ({
  CrashSink crash,
  AnalyticsSink analytics,
  RemoteConfigClient remoteConfig,
});

TelemetryAdapters firebaseAdapters() => (
  crash: FirebaseCrashSink(),
  analytics: FirebaseAnalyticsSink(),
  remoteConfig: FirebaseRemoteConfigClient(),
);

/// Longest wait for the stored consent before `runApp`.
const Duration kConsentReadTimeout = Duration(milliseconds: 500);

/// Longest wait for `Firebase.initializeApp` (cold start budget, RK9).
const Duration kFirebaseInitTimeout = Duration(seconds: 3);

String _buildMode() => kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

Future<Telemetry> bootstrapTelemetry({
  required AppFlavor flavor,
  FirebaseInitializer init = defaultFirebaseInitializer,
  FirebaseOptions? Function(AppFlavor) optionsFor = firebaseOptionsFor,
  TelemetryAdapters Function() adapters = firebaseAdapters,
  KeyValueStore? kv,
  TelemetryOverride? override,
  bool isDebugBuild = kDebugMode,
  bool isRelease = kReleaseMode,
  bool installHandlers = true,
  String? languageCode,
}) async {
  final store = TelemetryConsentStore(kv ?? SharedPreferencesKeyValueStore());
  // A slow read must not delay the first frame: until it arrives, collect
  // nothing and do not ask (`isLoaded == false`); it is adopted later.
  // `read()` never throws.
  final reading = store.read();
  var loaded = true;
  final consent = await reading.timeout(
    kConsentReadTimeout,
    onTimeout: () {
      loaded = false;
      return TelemetryConsent.initial;
    },
  );
  final logger = AppLog.named('telemetry');

  Telemetry adoptLate(Telemetry t) {
    if (!loaded) {
      unawaited(reading.then(t.consent.adoptLoaded));
    }
    return t;
  }

  Telemetry noop() {
    AppLog.configure(isRelease: isRelease, breadcrumb: (_) {});
    return adoptLate(
      Telemetry.noop(
        store: store,
        consent: consent,
        flavor: flavor,
        consentLoaded: loaded,
      )..attachLifecycle(),
    );
  }

  try {
    final options = optionsFor(flavor);
    if (options == null) {
      return noop();
    }
    await init(options).timeout(kFirebaseInitTimeout);
  } on Object {
    final telemetry = noop();
    logger.warning('firebase init failed');
    return telemetry;
  }

  final sinks = adapters();
  final crash = CrashReporter(sinks.crash);
  final controller = TelemetryConsentController(
    store: store,
    consent: consent,
    crashSink: sinks.crash,
    analyticsSink: sinks.analytics,
    flavor: flavor,
    isDebugBuild: isDebugBuild,
    override: override ?? TelemetryOverride.fromEnvironment,
    loaded: loaded,
  );
  await controller.applyInitial();
  if (installHandlers) {
    installErrorHandlers(crash);
  }
  AppLog.configure(isRelease: isRelease, breadcrumb: crash.breadcrumb);
  crash
    ..setKey(CrashKey.flavor, flavor.name)
    ..setKey(CrashKey.buildMode, _buildMode())
    ..setKey(
      CrashKey.locale,
      crashLocaleOf(
        languageCode ?? PlatformDispatcher.instance.locale.languageCode,
      ),
    );
  final params = EngineParamsSource(
    sinks.remoteConfig,
    flavor: flavor,
    crash: crash,
  );
  // Local settings only; the fetch below is the first network use.
  await params.initialize();
  unawaited(params.refresh());
  return adoptLate(
    Telemetry(
      analytics: AppAnalytics(
        sink: sinks.analytics,
        crash: crash,
        isEnabled: () => controller.effective.analytics,
      ),
      crash: crash,
      engineParams: params,
      consent: controller,
    )..attachLifecycle(),
  );
}
