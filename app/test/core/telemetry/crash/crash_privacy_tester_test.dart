// T29 tester: every error path to Crashlytics, with payloads that carry
// station keys, Places ids, SQL parameters, destination names and
// coordinates. Orchestrator rule (review round 1 #1): a report is only the
// error TYPE + the stack + `FlutterErrorDetails.library` (or a fixed
// reason); the only message allowed is a SafeDiagnostic's / the literal
// `where` of reportNonFatal.
//
// Paths: FlutterError.onError (framework + reportNonFatal),
// PlatformDispatcher.onError (direct, and real uncaught root-zone errors:
// microtask, Future, Timer, a failed `compute` isolate), recordFatal,
// recordNonFatal, AppLog breadcrumbs (release).
import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:napstop/core/diagnostics/report_error.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/crash/error_handlers.dart';

import '../telemetry_fakes.dart';

/// Strings that must never reach the sink.
const List<String> _secrets = [
  'osm:n7153190734',
  'osm:',
  'ChIJ0T2NLikpdTERKxE8d61aX_E',
  'ChIJ',
  'Ga Đồng Hới',
  'Đồng Hới',
  'Bến xe Mỹ Đình',
  'Mỹ Đình',
  'nhà bà ngoại',
  '21.0285',
  '105.8542',
  '17.4783',
  '21,0285',
  'INSERT',
  'SELECT',
  'parameters',
  'Causing statement',
  '7PH7+3R',
  'dong hoi',
];

/// Shaped like sqlite3's SqliteException: quotes the statement and its
/// bound parameters (destination name + coordinates).
final class _SqliteLike implements Exception {
  const new();

  @override
  String toString() =>
      'SqliteException(2067): UNIQUE constraint failed: saved_places.name\n'
      '  Causing statement: INSERT INTO saved_places (name, lat, lng) '
      'VALUES (?, ?, ?), parameters: Ga Đồng Hới, 17.4783, 106.6013';
}

/// A drift-style wrapper whose message embeds another error.
final class _WrappedError extends Error {
  new(this.inner);

  final Object inner;

  @override
  String toString() => 'Wrapped: $inner (station osm:n7153190734)';
}

/// A FlutterError the framework would build for a widget under a key.
FlutterErrorDetails _frameworkDetails({String? library = 'widgets library'}) =>
    FlutterErrorDetails(
      exception: FlutterError.fromParts([
        ErrorSummary('A RenderFlex overflowed in Ga Đồng Hới 21.0285123'),
        ErrorDescription("ResultRow-[<'station-osm:n7153190734'>]"),
        ErrorHint('place-ChIJ0T2NLikpdTERKxE8d61aX_E'),
      ]),
      stack: StackTrace.current,
      library: library,
      context: ErrorDescription(
        "building ResultRow-[<'station-osm:n7153190734'>] "
        "→ PlaceRow-[<'place-ChIJ0T2NLikpdTERKxE8d61aX_E'>]",
      ),
      informationCollector: () => [
        DiagnosticsNode.message('Ga Đồng Hới'),
        DiagnosticsNode.message('Bến xe Mỹ Đình 21.0285,105.8542'),
      ],
    );

/// Every payload an uncaught error could carry.
List<Object> _payloads() => [
  StateError('bad fix 21.0285123,105.8542 near Ga Đồng Hới'),
  ArgumentError.value('osm:n7153190734', 'stationId', 'unknown station'),
  RangeError.range(21, 0, 1, 'stationIndex', 'Ga Đồng Hới'),
  const FormatException(
    'Unexpected character',
    '{"name":"Ga Đồng Hới","lat":17.4783}',
    9,
  ),
  PlatformException(
    code: 'start_failed',
    message: 'destination Ga Đồng Hới rejected',
    details: {'lat': 21.0285, 'placeId': 'ChIJ0T2NLikpdTERKxE8d61aX_E'},
    stacktrace: 'at TripService(Ga Đồng Hới)',
  ),
  const _SqliteLike(),
  _WrappedError(const _SqliteLike()),
  Exception('nhà bà ngoại 7PH7+3R'),
  TimeoutException('places query "dong hoi" timed out', Duration.zero),
  'Ga Đồng Hới 21.0285', // a thrown String
  <String, Object>{'name': 'Bến xe Mỹ Đình', 'lat': 21.0285}, // a thrown Map
  AsyncError(StateError('Ga Đồng Hới'), StackTrace.empty),
];

/// What may legitimately reach the sink as the error text.
final RegExp _typeOnly = RegExp(r'^[A-Za-z_$][\w$]*(<[\w$<>, ?]*>)?$');

const Set<String> _reasons = {
  'uncaught',
  'reportNonFatal',
  'widgets library',
  'rendering library',
  'Flutter framework',
  'napstop',
  'stationCatalogLoadFailed',
  'mapsLoadFailed',
  'pigeonCallFailed',
  'historyWriteFailed',
  'remoteConfigInvalid',
  'analyticsGuardViolation',
  'addressSearchFailed',
  'other',
};

void _expectClean(RecordingCrashSink sink, {bool allowWhere = false}) {
  expect(sink.errors, isNotEmpty);
  for (final e in sink.errors) {
    final r = e.error as RedactedError;
    expect(_typeOnly.hasMatch(r.type), isTrue, reason: 'type <${r.type}>');
    if (!allowWhere) {
      expect(r.message, isEmpty, reason: 'message <${r.message}>');
    }
    expect(_reasons, contains(e.reason), reason: 'reason <${e.reason}>');
  }
  for (final text in sink.allText) {
    for (final s in _secrets) {
      expect(text, isNot(contains(s)), reason: '<$s> in <$text>');
    }
  }
}

Future<Object> _throwInIsolate(String name) async =>
    throw StateError('isolate failed on $name 21.0285123');

void main() {
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

  group('direct API', () {
    test('recordFatal: every payload → type + stack only', () async {
      final (crash, sink) = recordingCrash();
      final st = StackTrace.current;
      for (final p in _payloads()) {
        crash.recordFatal(p, st);
      }
      await pumpEventQueue();
      expect(sink.errors, hasLength(_payloads().length));
      expect(sink.errors.every((e) => e.fatal && e.stack == st), isTrue);
      _expectClean(sink);
    });

    test('recordNonFatal: every payload × every reason → type only', () async {
      final (crash, sink) = recordingCrash();
      for (final reason in NonFatalReason.values) {
        for (final p in _payloads()) {
          crash.recordNonFatal(p, null, reason);
        }
      }
      await pumpEventQueue();
      expect(
        sink.errors,
        hasLength(_payloads().length * NonFatalReason.values.length),
      );
      expect(sink.errors.every((e) => !e.fatal), isTrue);
      _expectClean(sink);
    });

    test(
      'recordFlutterError: summary, context, hints, collector never sent',
      () async {
        final (crash, sink) = recordingCrash();
        crash
          ..recordFlutterError(_frameworkDetails())
          ..recordFlutterError(_frameworkDetails(library: null))
          ..recordFlutterError(_frameworkDetails(library: ''));
        for (final p in _payloads()) {
          crash.recordFlutterError(
            FlutterErrorDetails(
              exception: p,
              context: ErrorDescription('while saving Ga Đồng Hới'),
              library: 'rendering library',
            ),
          );
        }
        await pumpEventQueue();
        expect(sink.errors.map((e) => e.reason).take(3), [
          'widgets library',
          'uncaught',
          'uncaught',
        ]);
        _expectClean(sink);
      },
    );

    test('a library string with a coordinate is still redacted', () async {
      final (crash, sink) = recordingCrash();
      crash.recordFlutterError(
        FlutterErrorDetails(
          exception: StateError('x'),
          library: 'lib 21.0285123 ${'x' * 300}',
        ),
      );
      await pumpEventQueue();
      final reason = sink.errors.single.reason;
      expect(reason, isNot(contains('21.0285')));
      expect(reason.length, lessThanOrEqualTo(101));
    });
  });

  group('installed handlers', () {
    test('FlutterError.onError: framework errors and reportNonFatal', () async {
      final (crash, sink) = recordingCrash();
      installErrorHandlers(crash, presentErrors: false);
      FlutterError.onError!(_frameworkDetails());
      for (final p in _payloads()) {
        // A recovered error reported by app code: the call-site literal only.
        reportNonFatal('history.write', p, StackTrace.current);
      }
      await pumpEventQueue();
      expect(sink.errors.first.fatal, isTrue);
      final nonFatal = sink.errors.skip(1).toList();
      expect(nonFatal, hasLength(_payloads().length));
      for (final e in nonFatal) {
        expect(e.fatal, isFalse);
        expect(e.reason, kReportNonFatalReason);
        expect((e.error as RedactedError).message, 'history.write');
      }
      _expectClean(sink, allowWhere: true);
    });

    test(
      'PlatformDispatcher.onError: every payload, handled, type only',
      () async {
        final (crash, sink) = recordingCrash();
        installErrorHandlers(crash, presentErrors: false);
        for (final p in _payloads()) {
          expect(
            PlatformDispatcher.instance.onError!(p, StackTrace.current),
            isTrue,
          );
        }
        await pumpEventQueue();
        expect(sink.errors.every((e) => e.fatal), isTrue);
        expect(sink.errors.map((e) => e.reason).toSet(), {kUncaughtReason});
        _expectClean(sink);
      },
    );

    test('real uncaught root-zone errors (microtask, Future)', () async {
      final (crash, sink) = recordingCrash();
      installErrorHandlers(crash, presentErrors: false);
      Zone.root.run(() {
        scheduleMicrotask(
          () => throw StateError('microtask Ga Đồng Hới 21.0285123'),
        );
        unawaited(
          Future<void>.error(
            PlatformException(
              code: 'x',
              message: 'Bến xe Mỹ Đình',
              details: 'osm:n7153190734',
            ),
          ),
        );
      });
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // A Timer callback cannot be checked here: flutter_tester reports it
      // to the test suite instead of PlatformDispatcher.onError (device: TC32).
      expect(sink.errors, hasLength(2));
      expect(sink.errors.map((e) => e.error.toString()).toSet(), {
        'StateError',
        'PlatformException',
      });
      _expectClean(sink);
    });

    test('an isolate (compute) failure left unawaited: type only', () async {
      final (crash, sink) = recordingCrash();
      installErrorHandlers(crash, presentErrors: false);
      Zone.root.run(() {
        unawaited(compute(_throwInIsolate, 'Ga Đồng Hới'));
      });
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (sink.errors.isEmpty && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(sink.errors, hasLength(1));
      _expectClean(sink);
    });

    testWidgets('a real build error inside a keyed subtree', (tester) async {
      final (crash, sink) = recordingCrash();
      final captured = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = captured.add;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: KeyedSubtree(
            key: const ValueKey('station-osm:n7153190734'),
            child: Builder(
              key: const ValueKey('place-ChIJ0T2NLikpdTERKxE8d61aX_E'),
              builder: (_) =>
                  throw const FormatException('Ga Đồng Hới', 'nhà bà ngoại'),
            ),
          ),
        ),
      );
      FlutterError.onError = previous;
      expect(captured, isNotEmpty);
      captured.forEach(crash.recordFlutterError);
      await tester.pump();
      _expectClean(sink);
    });
  });

  group('AppLog breadcrumbs (release)', () {
    tearDown(() => AppLog.configure(isRelease: false, breadcrumb: (_) {}));

    test('attached errors become their type; stacks dropped', () async {
      final crumbs = <String>[];
      AppLog.configure(isRelease: true, breadcrumb: crumbs.add);
      final log = AppLog.named('t29tester');
      for (final p in _payloads()) {
        log
          ..severe('history write failed', p, StackTrace.current)
          ..warning('retrying', p)
          ..info('state', p);
      }
      log
        ..fine('fine Ga Đồng Hới') // below INFO: dropped
        ..info('fix 21.0285123,105.8542'); // numbers are masked
      await pumpEventQueue();
      expect(crumbs, hasLength(_payloads().length * 3 + 1));
      for (final c in crumbs) {
        for (final s in _secrets) {
          expect(c, isNot(contains(s)), reason: c);
        }
        expect(c, isNot(contains('#0')), reason: 'stack in <$c>');
      }
      expect(crumbs.last, contains('<num>'));
    });

    test('release: crumbs reach CrashReporter.breadcrumb redacted', () async {
      final (crash, sink) = recordingCrash();
      AppLog.configure(isRelease: true, breadcrumb: crash.breadcrumb);
      AppLog.named('t29tester').severe('x', const _SqliteLike());
      Logger('napstop.other').info('lat=21 lng=105.85');
      await pumpEventQueue();
      expect(sink.logs, hasLength(2));
      for (final l in sink.logs) {
        for (final s in _secrets) {
          expect(l, isNot(contains(s)), reason: l);
        }
      }
      expect(sink.logs.last, contains('lat=<redacted>'));
    });

    test('debug: never a breadcrumb', () async {
      final crumbs = <String>[];
      final console = <String>[];
      AppLog.configure(
        isRelease: false,
        breadcrumb: crumbs.add,
        console: (m, {required name, required level}) => console.add(m),
      );
      AppLog.named('t29tester').severe('x 21.0285123', const _SqliteLike());
      await pumpEventQueue();
      expect(crumbs, isEmpty);
      expect(console.single, isNot(contains('21.0285')));
    });
  });
}
