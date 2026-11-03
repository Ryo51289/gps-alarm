// T29 TC18, TC19: EngineParamsSource (Remote Config `trip_engine_params`).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_source.dart';

import '../telemetry_fakes.dart';

void main() {
  group('TC18 settings and failures', () {
    for (final (flavor, interval) in [
      (AppFlavor.dev, const Duration(minutes: 5)),
      (AppFlavor.prod, const Duration(hours: 1)),
    ]) {
      test('configure (${flavor.name})', () async {
        final client = FakeRemoteConfigClient();
        await EngineParamsSource(client, flavor: flavor).initialize();
        expect(client.minimumFetchInterval, interval);
        expect(client.fetchTimeout, const Duration(seconds: 10));
        expect(client.defaults, {'trip_engine_params': ''});
      });
    }

    test('configure / fetch / getString errors never escape', () async {
      final client = FakeRemoteConfigClient('{"snoozeS":120}')
        ..configureError = StateError('x')
        ..fetchError = StateError('offline');
      final source = EngineParamsSource(client, flavor: AppFlavor.prod);
      await source.initialize();
      await source.refresh();
      expect(source.current().json, '{"snoozeS":120}', reason: 'old value');
      client.getError = StateError('sdk');
      expect(source.current(), EngineParamsOverride.defaults);
    });

    test('a hung fetch gives up after the timeout', () async {
      final client = FakeRemoteConfigClient('{}')..fetchGate = Completer();
      final source = EngineParamsSource(
        client,
        flavor: AppFlavor.dev,
        fetchTimeout: const Duration(milliseconds: 20),
      );
      await source.refresh().timeout(const Duration(seconds: 2));
      expect(source.current().json, '{}');
      // Review round 1 #7: the SDK call still runs, so a new refresh waits
      // for it instead of starting a second one.
      await source.refresh().timeout(const Duration(seconds: 2));
      expect(client.fetchCalls, 1);
      client.fetchGate!.complete();
      await pumpEventQueue();
      await source.refresh();
      expect(client.fetchCalls, 2, reason: 'finished: the next one fetches');
    });

    test('two concurrent refreshes → one client call', () async {
      final gate = Completer<void>();
      final client = FakeRemoteConfigClient()..fetchGate = gate;
      final source = EngineParamsSource(client, flavor: AppFlavor.dev);
      final a = source.refresh();
      final b = source.refresh();
      gate.complete();
      await Future.wait([a, b]);
      expect(client.fetchCalls, 1);
      await source.refresh();
      expect(client.fetchCalls, 2, reason: 'a later refresh fetches again');
    });

    test('the default timeout is 10 s', () {
      expect(kRemoteConfigFetchTimeout, const Duration(seconds: 10));
    });
  });

  test('TC19 a value read for a trip never changes', () async {
    final client = FakeRemoteConfigClient('{"snoozeS":120}');
    final source = EngineParamsSource(client, flavor: AppFlavor.prod);
    final a = source.current();
    client.next = '{"snoozeS":300}';
    await source.refresh();
    expect(a.json, '{"snoozeS":120}');
    final b = source.current();
    expect(b.json, '{"snoozeS":300}');
    expect(b.id, fnv1a32Hex('{"snoozeS":300}'));
    expect(b.id, isNot(a.id));
  });

  test('values are passed verbatim (60.0 kept)', () {
    const raw = '{"gpsLostMinS": 60.0}';
    final source = EngineParamsSource(
      FakeRemoteConfigClient(raw),
      flavor: AppFlavor.prod,
    );
    expect(source.current().json, raw);
  });

  test(
    'invalid value: defaults for the engine, one non-fatal per session',
    () async {
      final (crash, sink) = recordingCrash();
      final client = FakeRemoteConfigClient('not json {21.0285123}');
      final source = EngineParamsSource(
        client,
        flavor: AppFlavor.prod,
        crash: crash,
      );
      expect(source.current(), EngineParamsOverride.invalid);
      expect(source.current(), EngineParamsOverride.invalid);
      client.value = '[1]';
      expect(source.current(), EngineParamsOverride.invalid);
      await pumpEventQueue();
      expect(sink.errors, hasLength(1));
      final e = sink.errors.single;
      expect(e.reason, NonFatalReason.remoteConfigInvalid.name);
      expect(e.fatal, isFalse);
      for (final text in sink.allText) {
        expect(text, isNot(contains('not json')));
        expect(text, isNot(contains('21.0285')));
      }
    },
  );
}
