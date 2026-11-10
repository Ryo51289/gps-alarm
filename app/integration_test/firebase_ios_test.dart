// T29.2 SI01: Firebase on the iOS Simulator with the real plugins. Debug
// build, collection off (Info.plist keys + debug build), every sample event
// still goes through the guard right before the real Analytics sink (tee),
// Remote Config fetch answers. Run by the ios-sim job through
// integration_test/ios_suite.txt; skipped on Android (no options there until
// T29 step B). Logs no coordinates.
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_bootstrap.dart';

import '../test/core/telemetry/telemetry_fakes.dart';

final bool _notIos = !Platform.isIOS;

/// Checks then forwards each event.
final class _TeeSink implements AnalyticsSink {
  new(this._next);

  final AnalyticsSink _next;
  final List<String> names = [];

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    expect(checkAnalyticsEvent(name, parameters), isNull, reason: name);
    for (final v in parameters.values) {
      expect(looksLikeCoordinate(v), isFalse, reason: name);
    }
    names.add(name);
    return _next.logEvent(name, parameters);
  }

  @override
  Future<void> setCollectionEnabled({required bool enabled}) =>
      _next.setCollectionEnabled(enabled: enabled);

  @override
  Future<void> resetData() => _next.resetData();
}

final class _Si01Probe implements SafeDiagnostic {
  const new();

  @override
  String toString() => 'T29.2 SI01';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SI01 Firebase on iOS: real SDK, collection off', skip: _notIos, (
    tester,
  ) async {
    // (1) options of this build.
    final options = firebaseOptionsFor(AppFlavor.current);
    expect(options, isNotNull);
    expect(options!.appId, contains(':ios:'));
    expect(options.iosBundleId, 'app.napstop');

    // (2) bootstrap with the real adapters, analytics behind the tee.
    final tee = _TeeSink(FirebaseAnalyticsSink());
    final watch = Stopwatch()..start();
    final telemetry = await bootstrapTelemetry(
      flavor: AppFlavor.current,
      kv: MemoryKeyValueStore(),
      override: TelemetryOverride.auto,
      adapters: () => (
        crash: FirebaseCrashSink(),
        analytics: tee,
        remoteConfig: FirebaseRemoteConfigClient(),
      ),
      installHandlers: false,
    );
    watch.stop();
    addTearDown(telemetry.dispose);
    expect(telemetry.isNoop, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    expect(telemetry.consent.effective, EffectiveCollection.none);

    // (3) Crashlytics opt-in (Info.plist + applyInitial).
    expect(FirebaseCrashlytics.instance.isCrashlyticsCollectionEnabled, false);

    // (4) every sample through AppAnalytics → tee → real sink (dropped by
    // the SDK: collection is off).
    final analytics = AppAnalytics(
      sink: tee,
      crash: telemetry.crash,
      isEnabled: () => true,
    );
    final samples = sampleEvents()..forEach(analytics.log);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tee.names, hasLength(samples.length));
    expect(tee.names.toSet(), hasLength(8));

    // (5) crash API calls do not throw.
    telemetry.crash
      ..setKey(CrashKey.tripActive, false)
      ..breadcrumb('T29.2 SI01')
      ..recordNonFatal(
        const _Si01Probe(),
        StackTrace.current,
        NonFatalReason.other,
      );
    await tester.pump(const Duration(milliseconds: 200));
    await FirebaseCrashSink().deleteUnsentReports();

    // (6) Remote Config fetch answers (never throws, 10 s inner timeout).
    await telemetry.engineParams.refresh().timeout(const Duration(seconds: 15));
    final id = telemetry.engineParams.current().id;
    expect(
      id == 'default' || RegExp(r'^[0-9a-f]{8}$').hasMatch(id),
      isTrue,
      reason: id,
    );
  });
}
