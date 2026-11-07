// T29.2 FU07, FU08: the on-device telemetry probe.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/storage/memory_key_value_store.dart';
import 'package:napstop/core/telemetry/analytics/analytics_catalog.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/diag/telemetry_probe.dart';
import 'package:napstop/core/telemetry/telemetry.dart';

import '../telemetry_fakes.dart';

typedef _Rig = ({
  Telemetry telemetry,
  RecordingAnalyticsSink analytics,
  RecordingCrashSink crash,
});

const _both = TelemetryConsent(
  crash: ConsentChoice.granted,
  analytics: ConsentChoice.granted,
  version: kConsentTextVersion,
);

_Rig _rig({
  AppFlavor flavor = AppFlavor.dev,
  TelemetryConsent consent = _both,
  bool isNoop = false,
}) {
  final analytics = RecordingAnalyticsSink();
  final crashSink = RecordingCrashSink();
  final crash = CrashReporter(crashSink);
  final controller = TelemetryConsentController(
    store: TelemetryConsentStore(MemoryKeyValueStore()),
    consent: consent,
    crashSink: crashSink,
    analyticsSink: analytics,
    flavor: flavor,
    isDebugBuild: false,
    override: TelemetryOverride.auto,
  );
  final telemetry = Telemetry(
    analytics: AppAnalytics(
      sink: analytics,
      crash: crash,
      isEnabled: () => controller.effective.analytics,
    ),
    crash: crash,
    engineParams: EngineParamsSource(
      FakeRemoteConfigClient(),
      flavor: flavor,
      crash: crash,
    ),
    consent: controller,
    isNoop: isNoop,
  );
  return (telemetry: telemetry, analytics: analytics, crash: crashSink);
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(resetTelemetryProbe);

  group('FU07', () {
    test('one valid event per catalog entry, nothing coordinate-like', () {
      final events = telemetryProbeEvents();
      final names = events.map((e) => e.name).toList();
      expect(names.toSet(), hasLength(names.length));
      expect(names.toSet(), kAnalyticsCatalog.keys.toSet());
      for (final e in events) {
        final params = e.toParameters();
        expect(checkAnalyticsEvent(e.name, params), isNull, reason: e.name);
        for (final v in params.values) {
          expect(looksLikeCoordinate(v), isFalse, reason: '${e.name}: $v');
        }
        if (kAnalyticsCatalog[e.name]!.containsKey('simulated')) {
          expect(params['simulated'], 1, reason: e.name);
        }
      }
    });

    test('dev + both consents: events, non-fatal, breadcrumb, fatal', () async {
      final r = _rig();
      final delays = <Duration>[];
      expect(
        runTelemetryProbe(
          r.telemetry,
          flavor: AppFlavor.dev,
          raiseLater: delays.add,
        ),
        isTrue,
      );
      await _flush();
      expect(r.analytics.events, hasLength(8));
      expect(
        r.analytics.events.map((e) => e.$1).toSet(),
        kAnalyticsCatalog.keys.toSet(),
      );
      expect(r.crash.errors, hasLength(1));
      final error = r.crash.errors.single;
      expect(error.fatal, isFalse);
      expect(error.reason, NonFatalReason.other.name);
      final redacted = error.error as RedactedError;
      expect(redacted.type, 'TelemetryProbeMarker');
      expect(redacted.message, 'T29.2 probe <num>,<num>');
      expect(r.crash.logs, ['T29.2 probe']);
      expect(delays, [const Duration(seconds: 20)]);

      // At most once per process.
      expect(
        runTelemetryProbe(
          r.telemetry,
          flavor: AppFlavor.dev,
          raiseLater: delays.add,
        ),
        isFalse,
      );
      await _flush();
      expect(r.analytics.events, hasLength(8));
      expect(r.crash.errors, hasLength(1));
      expect(delays, hasLength(1));
    });

    final refusals = <String, _Rig Function()>{
      'prod': () => _rig(flavor: AppFlavor.prod),
      'no-op telemetry': () => _rig(isNoop: true),
      'analytics off': () =>
          _rig(consent: _both.copyWith(analytics: ConsentChoice.denied)),
      'crash reports off': () =>
          _rig(consent: _both.copyWith(crash: ConsentChoice.denied)),
      'no answer yet': () => _rig(consent: TelemetryConsent.initial),
    };
    for (final MapEntry(key: name, value: make) in refusals.entries) {
      test('does nothing: $name', () async {
        final r = make();
        final flavor = name == 'prod' ? AppFlavor.prod : AppFlavor.dev;
        var raised = 0;
        expect(
          runTelemetryProbe(
            r.telemetry,
            flavor: flavor,
            raiseLater: (_) => raised++,
          ),
          isFalse,
        );
        await _flush();
        expect(r.analytics.calls.where((c) => c == 'logEvent'), isEmpty);
        expect(r.crash.errors, isEmpty);
        expect(r.crash.logs, isEmpty);
        expect(raised, 0);
      });
    }

    test('default raiseLater: an uncaught TelemetryProbeFatal', () async {
      final r = _rig();
      final uncaught = <Object>[];
      final done = Completer<void>();
      runZonedGuarded(
        () => runTelemetryProbe(
          r.telemetry,
          flavor: AppFlavor.dev,
          fatalDelay: const Duration(milliseconds: 1),
        ),
        (e, _) {
          uncaught.add(e);
          done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 5));
      expect(uncaught.single, isA<TelemetryProbeFatal>());
    });
  });

  group('FU08', () {
    test('kTelemetryProbe is false without the define', () {
      expect(kTelemetryProbe, isFalse);
    });

    test(
      'runTelemetryProbe( only in main.dart, inside if (kTelemetryProbe)',
      () {
        final callers = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) {
              final path = f.path.replaceAll(r'\', '/');
              return !path.endsWith('telemetry/diag/telemetry_probe.dart') &&
                  f.readAsStringSync().contains('runTelemetryProbe(');
            })
            .map((f) => f.path.replaceAll(r'\', '/'))
            .toList();
        expect(callers, ['lib/main.dart']);
        final main = File('lib/main.dart').readAsStringSync();
        expect(
          RegExp(r'if \(kTelemetryProbe\) \{\s*runTelemetryProbe\(')
              .allMatches(main),
          hasLength(1),
        );
        expect('runTelemetryProbe('.allMatches(main), hasLength(1));
      },
    );

    test('the probe imports no Firebase and names no coordinate', () {
      final src = File('lib/core/telemetry/diag/telemetry_probe.dart')
          .readAsStringSync();
      expect(src, isNot(contains('package:firebase_')));
      expect(
        RegExp(r'\b(lat|lng)\b', caseSensitive: false).hasMatch(src),
        isFalse,
      );
    });
  });
}
