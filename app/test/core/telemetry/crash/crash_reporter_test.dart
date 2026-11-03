// T29 TC09–TC12: what reaches Crashlytics, and the T22 carry-over
// (reportNonFatal is a NON-fatal, type only).
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/telemetry/crash/crash_keys.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/crash/error_handlers.dart';

import '../telemetry_fakes.dart';

/// Throws while building, with a station name in the message.
final class _Throwing extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => throw StateError('Ga Đồng Hới');
}

/// Shaped like sqlite3's SqliteException: quotes the bound parameters.
final class _FakeSqliteException implements Exception {
  const new();

  @override
  String toString() =>
      'SqliteException(19): UNIQUE constraint failed, '
      'Causing statement: INSERT INTO trips VALUES (?, ?), '
      "parameters: ['Ga Đồng Hới', 17.4783]";
}

final class _Safe implements SafeDiagnostic {
  @override
  String toString() => '_Safe(rule at 21.0285123)';
}

void main() {
  group('TC09 recordNonFatal', () {
    test('type only, reason name, not fatal', () async {
      final (crash, sink) = recordingCrash();
      final st = StackTrace.current;
      crash.recordNonFatal(
        StateError('bad fix 21.0285123,105.8542 at Ga Huế'),
        st,
        NonFatalReason.pigeonCallFailed,
      );
      await pumpEventQueue();
      final e = sink.errors.single;
      expect(e.error, isA<RedactedError>());
      final r = e.error as RedactedError;
      expect(r.type, 'StateError');
      expect(r.message, isEmpty, reason: 'T22 N1: no message');
      expect(e.error.toString(), isNot(contains('21.0285')));
      expect(e.error.toString(), isNot(contains('105.8542')));
      expect(e.error.toString(), isNot(contains('Huế')));
      expect(e.reason, 'pigeonCallFailed');
      expect(e.fatal, isFalse);
      expect(e.stack, st);
    });

    test('a SafeDiagnostic keeps its redacted message', () async {
      final (crash, sink) = recordingCrash();
      crash.recordNonFatal(_Safe(), null, NonFatalReason.other);
      await pumpEventQueue();
      final r = sink.errors.single.error as RedactedError;
      expect(r.type, '_Safe');
      expect(r.message, '_Safe(rule at <num>)');
    });

    test('a failing sink never throws', () async {
      final (crash, sink) = recordingCrash();
      sink.throwOnCall = StateError('sdk');
      crash
        ..recordNonFatal(StateError('x'), null, NonFatalReason.other)
        ..recordFatal(StateError('x'), null)
        ..breadcrumb('x')
        ..setKey(CrashKey.flavor, 'dev');
      await pumpEventQueue();
    });
  });

  group('TC10 recordFlutterError', () {
    test('fatal, redacted, informationCollector never sent', () async {
      final (crash, sink) = recordingCrash();
      crash.recordFlutterError(
        FlutterErrorDetails(
          exception: Exception('at 16.4637211'),
          context: ErrorDescription('while drawing 21.0285123'),
          informationCollector: () => [DiagnosticsNode.message('Ga Đồng Hới')],
        ),
      );
      await pumpEventQueue();
      final e = sink.errors.single;
      expect(e.fatal, isTrue);
      expect(e.error.toString(), isNot(contains('16.4637')));
      expect(e.reason, isNot(contains('21.0285')));
      for (final text in sink.allText) {
        expect(text, isNot(contains('Đồng Hới')));
      }
    });

    test('round 2: a station key in the context never leaves', () async {
      final (crash, sink) = recordingCrash();
      crash.recordFlutterError(
        FlutterErrorDetails(
          exception: FlutterError('A RenderFlex overflowed in Ga Đồng Hới'),
          stack: StackTrace.current,
          library: 'widgets library',
          context: ErrorDescription(
            "building ResultRow-[<'station-osm:n7153190734'>]",
          ),
        ),
      );
      await pumpEventQueue();
      final e = sink.errors.single;
      expect(e.fatal, isTrue);
      expect(e.error.toString(), 'FlutterError');
      expect(e.reason, 'widgets library');
      expect(e.stack, isNotNull);
      for (final text in sink.allText) {
        expect(text, isNot(contains('osm:n')));
        expect(text, isNot(contains('Đồng Hới')));
      }
    });

    testWidgets('round 2: a real build error under a station key', (
      tester,
    ) async {
      final (crash, sink) = recordingCrash();
      final captured = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = captured.add;
      await tester.pumpWidget(
        const _Throwing(key: ValueKey('station-osm:n7153190734')),
      );
      FlutterError.onError = previous;
      expect(captured, isNotEmpty);
      // The framework context does name the key: exactly what must not leave.
      expect(
        captured.first.context?.toDescription(),
        contains('osm:n7153190734'),
      );
      captured.forEach(crash.recordFlutterError);
      await tester.pump();
      expect(sink.errors, isNotEmpty);
      for (final text in sink.allText) {
        expect(text, isNot(contains('osm:n')));
        expect(text, isNot(contains('Đồng Hới')));
      }
      expect(sink.errors.first.reason, 'widgets library');
    });

    test('round 2: default library; a Places id never leaves', () async {
      final (crash, sink) = recordingCrash();
      crash.recordFlutterError(
        FlutterErrorDetails(
          exception: StateError('place-ChIJ123'),
          context: ErrorDescription("building PlaceRow-[<'place-ChIJ123'>]"),
        ),
      );
      await pumpEventQueue();
      expect(sink.errors.single.reason, 'Flutter framework');
      expect(sink.allText.join(), isNot(contains('ChIJ123')));
    });

    test('round 2: a fatal SQLite error sends its type only', () async {
      final (crash, sink) = recordingCrash();
      final st = StackTrace.current;
      crash.recordFatal(const _FakeSqliteException(), st);
      await pumpEventQueue();
      final e = sink.errors.single;
      expect(e.error.toString(), '_FakeSqliteException');
      expect((e.error as RedactedError).message, isEmpty);
      expect(e.stack, st);
      for (final text in sink.allText) {
        expect(text, isNot(contains('Đồng Hới')));
        expect(text, isNot(contains('INSERT')));
      }
    });

    test('round 2: a RedactedError passed in keeps its type only', () async {
      final (crash, sink) = recordingCrash();
      crash.recordNonFatal(
        const RedactedError('X', 'Ga Huế'),
        null,
        NonFatalReason.other,
      );
      await pumpEventQueue();
      expect(sink.errors.single.error.toString(), 'X');
    });

    test(
      'T22 reportNonFatal → non-fatal, error type and call site only',
      () async {
        final (crash, sink) = recordingCrash();
        final reported = <FlutterErrorDetails>[];
        final previous = FlutterError.onError;
        FlutterError.onError = reported.add;
        addTearDown(() => FlutterError.onError = previous);
        reportNonFatal(
          'activeTripProvider',
          const FormatException('Ga Huế 16.4567'),
          StackTrace.current,
        );
        crash.recordFlutterError(reported.single);
        await pumpEventQueue();
        final e = sink.errors.single;
        expect(e.fatal, isFalse);
        expect(e.reason, kReportNonFatalReason);
        final r = e.error as RedactedError;
        expect(r.type, 'FormatException');
        expect(r.message, 'activeTripProvider');
        for (final text in sink.allText) {
          expect(text, isNot(contains('Huế')));
          expect(text, isNot(contains('16.4')));
        }
      },
    );
  });

  group('TC11 installErrorHandlers', () {
    late FlutterExceptionHandler? previousFlutter;
    late ErrorCallback? previousPlatform;

    setUp(() {
      previousFlutter = FlutterError.onError;
      previousPlatform = PlatformDispatcher.instance.onError;
    });

    tearDown(() {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    });

    test('platform errors are fatal and redacted, handled', () async {
      final (crash, sink) = recordingCrash();
      installErrorHandlers(crash, presentErrors: false);
      final handled = PlatformDispatcher.instance.onError!(
        StateError('x 21.0285123'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      await pumpEventQueue();
      final e = sink.errors.single;
      expect(e.fatal, isTrue);
      expect(e.reason, kUncaughtReason);
      expect(e.error.toString(), 'StateError');
    });

    test('FlutterError.onError goes through recordFlutterError', () async {
      final (crash, sink) = recordingCrash();
      installErrorHandlers(crash, presentErrors: false);
      FlutterError.onError!(
        FlutterErrorDetails(exception: StateError('y 16.4637211')),
      );
      reportNonFatal('x', StateError('z'), StackTrace.current);
      await pumpEventQueue();
      expect(sink.errors.map((e) => e.fatal), [true, false]);
      expect(sink.errors.first.error.toString(), isNot(contains('16.4637')));
    });
  });

  group('TC12 custom keys', () {
    test('wire names, limits', () {
      expect(CrashKey.values.length, lessThanOrEqualTo(kMaxCrashKeys));
      final wire = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      for (final k in CrashKey.values) {
        expect(wire.hasMatch(k.wire), isTrue, reason: k.wire);
      }
      expect(
        CrashKey.values.map((k) => k.wire).toSet(),
        hasLength(CrashKey.values.length),
      );
    });

    test('valid values reach the sink once; invalid are dropped', () async {
      final (crash, sink) = recordingCrash();
      crash
        ..setKey(CrashKey.tripPhase, 'tracking')
        ..setKey(CrashKey.tripPhase, 'tracking')
        ..setKey(CrashKey.tripActive, true)
        ..setKey(CrashKey.engineParamsId, '811c9dc5')
        ..setKey(CrashKey.permNotifications, 'na')
        ..setKey(CrashKey.tripPhase, 'walking')
        ..setKey(CrashKey.engineParamsId, '21.0285')
        ..setKey(CrashKey.simulated, 1.5)
        ..setKey(CrashKey.locale, 'fr');
      await pumpEventQueue();
      expect(sink.keys, {
        'trip_phase': 'tracking',
        'trip_active': true,
        'engine_params_id': '811c9dc5',
        'perm_notifications': 'na',
      });
      expect(sink.calls.where((c) => c == 'setCustomKey'), hasLength(4));
    });

    test('strict: an invalid value throws without the value', () {
      final (crash, _) = recordingCrash(strict: true);
      expect(
        () => crash.setKey(CrashKey.engineParamsId, '21.0285'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('engine_params_id'), isNot(contains('21.0285'))),
          ),
        ),
      );
      expect(() => crash.setKey(CrashKey.tripActive, 0.0), throwsStateError);
    });

    test('helpers', () {
      expect(crashLocaleOf('vi'), 'vi');
      expect(crashLocaleOf('en'), 'en');
      expect(crashLocaleOf('fr'), 'other');
      expect(crashAlarmModeOf(null), 'none');
    });

    test('breadcrumbs are redacted', () async {
      final (crash, sink) = recordingCrash();
      crash.breadcrumb('fix lat=21.02 at 105.8542123');
      await pumpEventQueue();
      expect(sink.logs.single, 'fix lat=<redacted> at <num>');
    });
  });
}
