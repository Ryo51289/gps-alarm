// T29 TC28: real bootstrap with collection forced on, every sample event
// goes through the guard, and each payload is checked right before the SDK
// (tee sink). Run on a device/emulator, dev flavor, with the define:
//   flutter test integration_test/telemetry_payload_test.dart \
//     --flavor dev --dart-define=NAPSTOP_TELEMETRY=on -d <device-id>
//
// Step A (no Firebase options yet): bootstrap runs with placeholder options
// and no-op SDK sinks behind the tee. Step B: the real Firebase sinks, so
// the events reach DebugView and the probe reaches Crashlytics (T29 §8).
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/app/firebase/firebase_options.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/storage/memory_key_value_store.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/analytics/firebase_analytics_sink.dart';
import 'package:napstop/core/telemetry/crash/firebase_crash_sink.dart';
import 'package:napstop/core/telemetry/remote_config/firebase_remote_config_client.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_bootstrap.dart';

import '../test/core/telemetry/telemetry_fakes.dart';

/// Checks then forwards each event; records collection switches.
final class _TeeSink implements AnalyticsSink {
  new(this._next);

  final AnalyticsSink _next;
  final List<(String, Map<String, Object>)> seen = [];
  final List<bool> collection = [];

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    expect(checkAnalyticsEvent(name, parameters), isNull, reason: name);
    for (final v in parameters.values) {
      expect(looksLikeCoordinate(v), isFalse, reason: '$name: $v');
    }
    seen.add((name, parameters));
    return _next.logEvent(name, parameters);
  }

  @override
  Future<void> setCollectionEnabled({required bool enabled}) {
    collection.add(enabled);
    return _next.setCollectionEnabled(enabled: enabled);
  }

  @override
  Future<void> resetData() => _next.resetData();
}

/// The redaction probe of T29 §8 step 3: Crashlytics must show `<num>`.
final class _T29Probe implements SafeDiagnostic {
  const new();

  @override
  String toString() => 'T29 probe 21.0285123,105.8542';
}

/// Step A only: bootstrap needs options to take the configured path.
const _placeholder = FirebaseOptions(
  apiKey: 'none',
  appId: '1:0:android:0',
  messagingSenderId: '0',
  projectId: 'none',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TC28 every sample event passes the guard at the SDK edge', (
    tester,
  ) async {
    final flavor = AppFlavor.current;
    expect(flavor, AppFlavor.dev, reason: 'run with --flavor dev');
    expect(
      TelemetryOverride.fromEnvironment,
      TelemetryOverride.on,
      reason: 'run with --dart-define=NAPSTOP_TELEMETRY=on',
    );
    final configured = firebaseOptionsFor(flavor) != null;
    final tee = _TeeSink(
      configured ? FirebaseAnalyticsSink() : const NoopAnalyticsSink(),
    );
    final telemetry = await bootstrapTelemetry(
      flavor: flavor,
      kv: MemoryKeyValueStore(),
      optionsFor: configured ? firebaseOptionsFor : (_) => _placeholder,
      init: configured ? defaultFirebaseInitializer : (_) async {},
      adapters: () => (
        crash: configured ? FirebaseCrashSink() : const NoopCrashSink(),
        analytics: tee,
        remoteConfig: configured
            ? FirebaseRemoteConfigClient()
            : const NoopRemoteConfigClient(),
      ),
      installHandlers: false,
    );
    addTearDown(telemetry.dispose);
    expect(telemetry.isNoop, isFalse);
    expect(
      telemetry.consent.effective,
      const EffectiveCollection(crash: true, analytics: true),
    );
    expect(tee.collection, [true], reason: 'collection really switched on');

    final samples = sampleEvents()..forEach(telemetry.analytics.log);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tee.seen, hasLength(samples.length));
    expect(
      tee.seen.map((e) => e.$1).toSet(),
      hasLength(8),
      reason: 'all 8 event names',
    );

    telemetry.crash.recordNonFatal(
      const _T29Probe(),
      StackTrace.current,
      NonFatalReason.other,
    );
    await tester.pump(const Duration(milliseconds: 100));
  });
}
