// T29 tester: bootstrap must never block or break the app (§7 "Độ tin cậy"):
// main() awaits it before runApp, so a throw or a hang here means no UI and
// no alarm setup at all. Covers: no options, init throwing (sync/async),
// init hanging past 3 s (and finishing or failing later), the consent store
// hanging, every SDK adapter throwing, Remote Config wiring through the
// bootstrap (intervals per flavor, fetch regardless of consent, one fetch
// at a time across resumes).
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_bootstrap.dart';

import '../../helpers/fake_key_value_store.dart';
import 'telemetry_fakes.dart';

const _options = FirebaseOptions(
  apiKey: 'test',
  appId: '1:0:android:0',
  messagingSenderId: '0',
  projectId: 'test',
);

const _event = BatteryGuideTestEvent(
  oem: OemTag.xiaomi,
  result: GuideTestResult.pass,
);

/// Never answers.
final class _HungKv implements KeyValueStore {
  @override
  Future<String?> getString(String k) => Completer<String?>().future;

  @override
  Future<int?> getInt(String k) => Completer<int?>().future;

  @override
  Future<void> setString(String k, String v) => Completer<void>().future;

  @override
  Future<void> setInt(String k, int v) => Completer<void>().future;
}

/// Every call throws synchronously.
final class _ThrowingAnalytics implements AnalyticsSink {
  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) =>
      throw StateError('plugin missing');

  @override
  Future<void> resetData() => throw StateError('plugin missing');

  @override
  Future<void> setCollectionEnabled({required bool enabled}) =>
      throw StateError('plugin missing');
}

final class _ThrowingRemoteConfig implements RemoteConfigClient {
  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) => throw StateError('plugin missing');

  @override
  Future<bool> fetchAndActivate() => throw StateError('plugin missing');

  @override
  String getString(String key) => throw StateError('plugin missing');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FlutterExceptionHandler? previousFlutter;
  setUp(() => previousFlutter = FlutterError.onError);
  tearDown(() => FlutterError.onError = previousFlutter);

  Future<void> expectNoop(Telemetry t) async {
    expect(t.isNoop, isTrue);
    expect(t.engineParams.current(), EngineParamsOverride.defaults);
    t.analytics.log(_event);
    t.crash
      ..recordFatal(StateError('x'), StackTrace.current)
      ..breadcrumb('y')
      ..setKey(CrashKey.tripActive, true);
    await t.engineParams.refresh();
    await t.consent.update(crash: ConsentChoice.granted);
  }

  group('no configuration (step A)', () {
    for (final flavor in AppFlavor.values) {
      test('${flavor.name}: real optionsFor → no-op, no init, no handlers, '
          'no adapters', () async {
        var inits = 0;
        var adapters = 0;
        final handler = FlutterError.onError;
        final t = await bootstrapTelemetry(
          flavor: flavor,
          kv: FakeKeyValueStore(),
          init: (_) async => inits++,
          adapters: () {
            adapters++;
            return firebaseAdapters();
          },
        );
        await expectNoop(t);
        expect(inits, 0);
        expect(adapters, 0);
        expect(
          FlutterError.onError,
          same(handler),
          reason: 'no-op must not hijack error handling',
        );
      });
    }

    test('the real Firebase adapters can be built without Firebase', () {
      // Lazy `instance` access: building them must not touch the plugin.
      expect(firebaseAdapters, returnsNormally);
    });

    test('init throwing synchronously → no-op', () async {
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.dev,
        kv: FakeKeyValueStore(),
        optionsFor: (_) => _options,
        init: (_) => throw UnsupportedError('no google-services.json'),
      );
      await expectNoop(t);
    });

    for (final e in <Object>[
      FirebaseException(plugin: 'core', message: 'no app'),
      StateError('x'),
      'a string',
      const StackOverflowError(),
    ]) {
      test('init failing with ${e.runtimeType} → no-op', () async {
        final t = await bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: FakeKeyValueStore(),
          optionsFor: (_) => _options,
          init: (_) => Future<void>.error(e),
        );
        await expectNoop(t);
      });
    }
  });

  group('init timing (3 s budget)', () {
    testWidgets('finishes at 2.9 s → configured', (tester) async {
      Telemetry? t;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: FakeKeyValueStore(),
          optionsFor: (_) => _options,
          init: (_) => Future<void>.delayed(const Duration(milliseconds: 2900)),
          adapters: () => (
            crash: RecordingCrashSink(),
            analytics: RecordingAnalyticsSink(),
            remoteConfig: FakeRemoteConfigClient(),
          ),
          installHandlers: false,
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(milliseconds: 2950));
      expect(t?.isNoop, isFalse);
      t!.dispose();
    });

    testWidgets('finishes at 3.1 s → no-op; the late success changes nothing', (
      tester,
    ) async {
      Telemetry? t;
      var adapters = 0;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: FakeKeyValueStore(),
          optionsFor: (_) => _options,
          init: (_) => Future<void>.delayed(const Duration(milliseconds: 3100)),
          adapters: () {
            adapters++;
            return (
              crash: RecordingCrashSink(),
              analytics: RecordingAnalyticsSink(),
              remoteConfig: FakeRemoteConfigClient(),
            );
          },
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(milliseconds: 3001));
      expect(t?.isNoop, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(adapters, 0);
    });

    testWidgets('fails at 5 s, after the timeout → no uncaught error', (
      tester,
    ) async {
      Telemetry? t;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: FakeKeyValueStore(),
          optionsFor: (_) => _options,
          init: (_) => Future<void>.delayed(
            const Duration(seconds: 5),
            () => throw StateError('late failure'),
          ),
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(seconds: 4));
      expect(t?.isNoop, isTrue);
      await tester.pump(const Duration(seconds: 2));
      // An unhandled late error would fail this test via the zone.
      expect(tester.takeException(), isNull);
    });

    testWidgets('consent store and init both hung → runApp after ≤ 3.5 s', (
      tester,
    ) async {
      Telemetry? t;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: _HungKv(),
          optionsFor: (_) => _options,
          init: (_) => Completer<void>().future,
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(milliseconds: 3400));
      expect(t, isNull);
      await tester.pump(const Duration(milliseconds: 150));
      expect(t?.isNoop, isTrue);
      expect(t!.consent.isLoaded, isFalse);
      expect(t!.consent.needsPrompt, isFalse);
      expect(t!.consent.effective, EffectiveCollection.none);
    });

    testWidgets('consent store hung, Firebase fine → configured at 0.5 s, '
        'nothing collected', (tester) async {
      final crash = RecordingCrashSink();
      final analytics = RecordingAnalyticsSink();
      Telemetry? t;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: _HungKv(),
          optionsFor: (_) => _options,
          init: (_) async {},
          adapters: () => (
            crash: crash,
            analytics: analytics,
            remoteConfig: FakeRemoteConfigClient(),
          ),
          isDebugBuild: false,
          installHandlers: false,
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(milliseconds: 510));
      expect(t?.isNoop, isFalse);
      addTearDown(t!.dispose);
      expect(crash.calls, isNot(contains('setCollectionEnabled(true)')));
      expect(analytics.calls, isNot(contains('setCollectionEnabled(true)')));
      t!.analytics.log(_event);
      await tester.pump();
      expect(analytics.events, isEmpty);
    });
  });

  test('every SDK adapter throwing → configured, app unaffected', () async {
    final crash = RecordingCrashSink()..throwOnCall = StateError('missing');
    final t = await bootstrapTelemetry(
      flavor: AppFlavor.dev,
      kv: FakeKeyValueStore(const {
        'telemetry.crash': 'granted',
        'telemetry.analytics': 'granted',
        'telemetry.consent_version': 1,
      }),
      optionsFor: (_) => _options,
      init: (_) async {},
      adapters: () => (
        crash: crash,
        analytics: _ThrowingAnalytics(),
        remoteConfig: _ThrowingRemoteConfig(),
      ),
      isDebugBuild: false,
      installHandlers: false,
    );
    addTearDown(t.dispose);
    expect(t.isNoop, isFalse);
    expect(t.engineParams.current(), EngineParamsOverride.defaults);
    t.analytics.log(_event);
    t.crash
      ..recordFatal(StateError('x'), null)
      ..recordNonFatal(StateError('x'), null, NonFatalReason.other)
      ..breadcrumb('x')
      ..setKey(CrashKey.tripActive, true);
    await t.engineParams.refresh();
    await t.consent.update(
      crash: ConsentChoice.denied,
      analytics: ConsentChoice.denied,
    );
    await pumpEventQueue();
  });

  group('Remote Config through the bootstrap', () {
    Future<(Telemetry, FakeRemoteConfigClient)> boot({
      required AppFlavor flavor,
      Map<String, Object>? stored,
      FakeRemoteConfigClient? client,
    }) async {
      final rc = client ?? FakeRemoteConfigClient();
      final t = await bootstrapTelemetry(
        flavor: flavor,
        kv: FakeKeyValueStore(stored),
        optionsFor: (_) => _options,
        init: (_) async {},
        adapters: () => (
          crash: RecordingCrashSink(),
          analytics: RecordingAnalyticsSink(),
          remoteConfig: rc,
        ),
        isDebugBuild: false,
        installHandlers: false,
      );
      addTearDown(t.dispose);
      return (t, rc);
    }

    for (final flavor in AppFlavor.values) {
      test('${flavor.name}: interval, timeout, defaults', () async {
        final (_, rc) = await boot(flavor: flavor);
        expect(rc.configureCalls, 1);
        expect(
          rc.minimumFetchInterval,
          flavor == AppFlavor.dev
              ? const Duration(minutes: 5)
              : const Duration(hours: 1),
        );
        expect(rc.fetchTimeout, const Duration(seconds: 10));
        expect(rc.defaults, {'trip_engine_params': ''});
      });
    }

    for (final stored in <String, Map<String, Object>>{
      'unknown': const {},
      'declined': const {
        'telemetry.crash': 'denied',
        'telemetry.analytics': 'denied',
        'telemetry.consent_version': 1,
      },
    }.entries) {
      test('consent ${stored.key}: still fetched (Q4)', () async {
        final (t, rc) = await boot(
          flavor: AppFlavor.prod,
          stored: stored.value,
          client: FakeRemoteConfigClient()..next = '{"snoozeS":240}',
        );
        await pumpEventQueue();
        expect(rc.fetchCalls, 1);
        expect(t.engineParams.current().json, '{"snoozeS":240}');
      });
    }

    testWidgets('startup fetch in flight + resumes → one SDK call', (
      tester,
    ) async {
      final gate = Completer<void>();
      final rc = FakeRemoteConfigClient()..fetchGate = gate;
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.prod,
        kv: FakeKeyValueStore(),
        optionsFor: (_) => _options,
        init: (_) async {},
        adapters: () => (
          crash: RecordingCrashSink(),
          analytics: RecordingAnalyticsSink(),
          remoteConfig: rc,
        ),
        isDebugBuild: false,
        installHandlers: false,
      );
      addTearDown(t.dispose);
      for (var i = 0; i < 3; i++) {
        tester.binding
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
          ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
          ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
          ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(seconds: 1));
      }
      expect(rc.fetchCalls, 1);
      gate.complete();
      await tester.pump();
      // Once finished, the next resume fetches again (the SDK applies its
      // own minimum interval).
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(rc.fetchCalls, 2);
    });
  });
}
