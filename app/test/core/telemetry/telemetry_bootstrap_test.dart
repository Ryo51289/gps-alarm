// T29 TC20 (no Firebase → no-op, never throws) and the configured path
// with fake adapters (no network, no plugin).
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/firebase/firebase_options.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_bootstrap.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';

import '../../helpers/fake_key_value_store.dart';
import 'telemetry_fakes.dart';

const _options = FirebaseOptions(
  apiKey: 'test',
  appId: '1:0:android:0',
  messagingSenderId: '0',
  projectId: 'test',
);

/// A store whose reads take [delay] (cold start, T21 CQ1).
final class _SlowKv extends FakeKeyValueStore {
  new(this.delay, [super.values]);

  final Duration delay;

  @override
  Future<String?> getString(String key) =>
      Future<void>.delayed(delay).then((_) => super.getString(key));

  @override
  Future<int?> getInt(String key) =>
      Future<void>.delayed(delay).then((_) => super.getInt(key));
}

const Map<String, Object> _denied = {
  'telemetry.crash': 'denied',
  'telemetry.analytics': 'denied',
  'telemetry.consent_version': 1,
};

const Map<String, Object> _granted = {
  'telemetry.crash': 'granted',
  'telemetry.analytics': 'granted',
  'telemetry.consent_version': 1,
};

const _event = DestinationSelectedEvent(
  source: DestSourceTag.station,
  kind: DestKindTag.train,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('step A: no Firebase options for any flavor', () {
    for (final f in AppFlavor.values) {
      expect(firebaseOptionsFor(f), isNull);
    }
  });

  group('TC20 no-op', () {
    Future<void> expectNoop(Telemetry t) async {
      expect(t.isNoop, isTrue);
      expect(t.engineParams.current(), EngineParamsOverride.defaults);
      t.analytics.log(_event);
      await t.engineParams.refresh();
    }

    test('no options → init is never called', () async {
      var inits = 0;
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.dev,
        kv: FakeKeyValueStore(),
        init: (_) async => inits++,
      );
      await expectNoop(t);
      expect(inits, 0);
    });

    test('init throws → no-op', () async {
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.prod,
        kv: FakeKeyValueStore(),
        optionsFor: (_) => _options,
        init: (_) => Future.error(StateError('no google-services.json')),
      );
      await expectNoop(t);
    });

    test('options throw (iOS before §5) → no-op', () async {
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.prod,
        kv: FakeKeyValueStore(),
        optionsFor: (_) => throw UnsupportedError('ios'),
      );
      await expectNoop(t);
    });

    testWidgets('init hangs → no-op after 3 s', (tester) async {
      Telemetry? t;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.prod,
          kv: FakeKeyValueStore(),
          optionsFor: (_) => _options,
          init: (_) => Completer<void>().future,
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(t, isNull);
      await tester.pump(const Duration(seconds: 2));
      expect(t?.isNoop, isTrue);
    });

    test('consent read failure → initial, still no-op', () async {
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.dev,
        kv: FakeKeyValueStore()..error = StateError('disk'),
      );
      expect(t.consent.current, TelemetryConsent.initial);
      expect(t.consent.needsPrompt, isTrue);
    });

    test('a consent answer is stored even without Firebase', () async {
      final kv = FakeKeyValueStore();
      final t = await bootstrapTelemetry(flavor: AppFlavor.dev, kv: kv);
      await t.consent.update(crash: ConsentChoice.granted);
      expect(kv.values['telemetry.consent'], startsWith('crash=granted;'));
    });
  });

  group('configured (fake adapters)', () {
    late RecordingCrashSink crash;
    late RecordingAnalyticsSink analytics;
    late FakeRemoteConfigClient rc;

    setUp(() {
      crash = RecordingCrashSink();
      analytics = RecordingAnalyticsSink();
      rc = FakeRemoteConfigClient()..next = '{"snoozeS":120}';
    });

    Future<Telemetry> boot({
      Map<String, Object>? stored,
      TelemetryOverride override = TelemetryOverride.auto,
    }) async {
      final t = await bootstrapTelemetry(
        flavor: AppFlavor.prod,
        kv: FakeKeyValueStore(stored),
        optionsFor: (_) => _options,
        init: (_) async {},
        adapters: () => (crash: crash, analytics: analytics, remoteConfig: rc),
        override: override,
        isDebugBuild: false,
        installHandlers: false,
        languageCode: 'vi',
      );
      addTearDown(t.dispose);
      await pumpEventQueue();
      return t;
    }

    test('unknown consent: everything off, keys set, config fetched', () async {
      final t = await boot();
      expect(t.isNoop, isFalse);
      expect(crash.calls.first, 'setCollectionEnabled(false)');
      expect(crash.calls, isNot(contains('sendUnsentReports')));
      expect(crash.calls, isNot(contains('deleteUnsentReports')));
      expect(analytics.calls, ['setCollectionEnabled(false)']);
      expect(crash.keys, {
        'flavor': 'prod',
        'build_mode': kReleaseMode ? 'release' : 'debug',
        'locale': 'vi',
      });
      expect(rc.configureCalls, 1);
      expect(rc.minimumFetchInterval, const Duration(hours: 1));
      expect(rc.fetchCalls, 1);
      expect(t.engineParams.current().json, '{"snoozeS":120}');
      t.analytics.log(_event);
      await pumpEventQueue();
      expect(analytics.events, isEmpty, reason: 'opt-in: nothing yet');
    });

    test('granted consent: on, pending reports sent, events go out', () async {
      final t = await boot(
        stored: {
          'telemetry.crash': 'granted',
          'telemetry.analytics': 'granted',
          'telemetry.consent_version': 1,
        },
      );
      expect(crash.calls.take(2), [
        'setCollectionEnabled(true)',
        'sendUnsentReports',
      ]);
      t.analytics.log(_event);
      await pumpEventQueue();
      expect(analytics.events.single.$1, 'destination_selected');
    });

    test('revoking stops events immediately', () async {
      final t = await boot(
        stored: {
          'telemetry.crash': 'granted',
          'telemetry.analytics': 'granted',
          'telemetry.consent_version': 1,
        },
      );
      await t.consent.update(analytics: ConsentChoice.denied);
      t.analytics.log(_event);
      await pumpEventQueue();
      expect(analytics.events, isEmpty);
      expect(analytics.calls, contains('resetData'));
    });

    test('NAPSTOP_TELEMETRY=off wins over consent', () async {
      final t = await boot(
        stored: {
          'telemetry.crash': 'granted',
          'telemetry.analytics': 'granted',
          'telemetry.consent_version': 1,
        },
        override: TelemetryOverride.off,
      );
      expect(t.consent.effective, EffectiveCollection.none);
    });

    test('the provider exposes it; engine params read from it', () async {
      final t = await boot();
      final container = ProviderContainer(
        overrides: [telemetryProvider.overrideWithValue(t)],
      );
      addTearDown(container.dispose);
      expect(container.read(engineParamsReaderProvider), same(t.engineParams));
    });
  });

  group('round 2: consent read slower than 500 ms', () {
    late RecordingCrashSink crash;
    late RecordingAnalyticsSink analytics;

    Future<Telemetry> boot(WidgetTester tester, Map<String, Object> stored) {
      crash = RecordingCrashSink();
      analytics = RecordingAnalyticsSink();
      Telemetry? t;
      return () async {
        unawaited(
          bootstrapTelemetry(
            flavor: AppFlavor.prod,
            kv: _SlowKv(const Duration(milliseconds: 400), stored),
            optionsFor: (_) => _options,
            init: (_) async {},
            adapters: () => (
              crash: crash,
              analytics: analytics,
              remoteConfig: FakeRemoteConfigClient(),
            ),
            isDebugBuild: false,
            installHandlers: false,
            languageCode: 'vi',
          ).then((v) => t = v),
        );
        // 4 reads (single key absent, then 3 legacy keys) × 400 ms > 500 ms:
        // bootstrap gives up waiting.
        await tester.pump(const Duration(milliseconds: 600));
        expect(t, isNotNull);
        addTearDown(t!.dispose);
        return t!;
      }();
    }

    testWidgets('declined: not asked again, adopted once read', (tester) async {
      final t = await boot(tester, _denied);
      expect(t.consent.isLoaded, isFalse);
      expect(t.consent.needsPrompt, isFalse, reason: 'do not ask yet');
      expect(t.consent.effective, EffectiveCollection.none);
      var notified = 0;
      t.consent.addListener(() => notified++);
      await tester.pump(const Duration(seconds: 2));
      expect(t.consent.isLoaded, isTrue);
      expect(t.consent.current.crash, ConsentChoice.denied);
      expect(t.consent.needsPrompt, isFalse);
      expect(crash.calls, contains('deleteUnsentReports'));
      expect(notified, 1);
    });

    testWidgets('granted: collection switched on once read', (tester) async {
      final t = await boot(tester, _granted);
      t.analytics.log(_event);
      await tester.pump();
      expect(analytics.events, isEmpty, reason: 'not known yet: nothing');
      await tester.pump(const Duration(seconds: 2));
      expect(
        t.consent.effective,
        const EffectiveCollection(crash: true, analytics: true),
      );
      expect(crash.calls, contains('sendUnsentReports'));
      t.analytics.log(_event);
      await tester.pump();
      expect(analytics.events, hasLength(1));
    });

    testWidgets('never read: no prompt; unknown once read → prompt', (
      tester,
    ) async {
      final t = await boot(tester, const {});
      expect(t.consent.needsPrompt, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(t.consent.needsPrompt, isTrue);
    });

    testWidgets('an answer given before the read wins', (tester) async {
      final t = await boot(tester, _granted);
      await t.consent.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(t.consent.current.crash, ConsentChoice.denied);
      expect(t.consent.effective, EffectiveCollection.none);
    });

    testWidgets('no-op telemetry adopts it too', (tester) async {
      Telemetry? t;
      unawaited(
        bootstrapTelemetry(
          flavor: AppFlavor.dev,
          kv: _SlowKv(const Duration(milliseconds: 400), _denied),
        ).then((v) => t = v),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(t!.isNoop, isTrue);
      expect(t!.consent.isLoaded, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(t!.consent.current.crash, ConsentChoice.denied);
    });
  });

  test('default provider: a no-op, engine defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final t = container.read(telemetryProvider);
    expect(t.isNoop, isTrue);
    expect(
      container.read(engineParamsReaderProvider).current(),
      EngineParamsOverride.defaults,
    );
  });
}
