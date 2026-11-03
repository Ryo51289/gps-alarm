// ignore_for_file: use_raw_strings (JSON escapes are spelled out on purpose)
// T29 tester: hostile `trip_engine_params` values and fetch scheduling.
// Reliability question: can a bad Remote Config value, or a slow/broken
// fetch, stop screen 3 from starting a trip (no wake-up)? `current()` is
// called synchronously when the trip is configured: it must never throw,
// never hang, and fall back to the engine defaults.
// Deterministic: fixed seeds, fake clients, no network.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_source.dart';

import '../telemetry_fakes.dart';

/// `{"a":{"a":…1…}}` with [depth] nested objects.
String _nestedObjects(int depth) =>
    '${'{"a":' * (depth - 1)}{"a":1}${'}' * (depth - 1)}';

/// `{"a":[[[…]]]}`: one object + [arrays] nested arrays.
String _nestedArrays(int arrays) => '{"a":${'[' * arrays}${']' * arrays}}';

/// A valid object of exactly [length] UTF-16 units.
String _objectOfLength(int length, {String fill = 'x'}) {
  const head = '{"k":"';
  const tail = '"}';
  final n = length - head.length - tail.length;
  final body = StringBuffer();
  while (body.length < n) {
    body.write(body.length + fill.length <= n ? fill : 'x');
  }
  return '$head$body$tail';
}

const List<String> _malformed = [
  '{',
  '}',
  '{"a":}',
  '{"a":1,}',
  '{,}',
  '{"a":01}',
  '{"a":NaN}',
  '{"a":Infinity}',
  '{"a":-Infinity}',
  "{'a':1}",
  '{a:1}',
  '{"a":1}garbage',
  '{"a":1} {"b":2}',
  '{"a":"\\ud800"}',
  '{"a":"\\udc00"}',
  '{"a":"\\u12"}',
  '{"a":"\\x41"}',
  '{"a":1e}',
  '{"a":-}',
  '{"a":.5}',
  '{"a":5.}',
  '{"a":+1}',
  '{"a":tru}',
  '{"a":nul}',
  '{"a":"line\nbreak"}',
  '{"a":"tab\there"}',
  '{"a" 1}',
  '{"a"::1}',
  '{"a":1}\u0000',
  '{"a":[1,2,]}',
  '{"a":[1 2]}',
  '{"a":"unterminated}',
  '{"a":"\\',
  'null',
  'true',
  'false',
  '"string"',
  '123',
  '-0.5',
  '[]',
  '[{"snoozeS":120}]',
  '/* comment */ {}',
  '{} // comment',
  '{"snoozeS":120',
  '{"snoozeS":120}}',
  '<html>502 Bad Gateway</html>',
];

/// [_malformed] plus values with invisible characters (built from code
/// points so the source stays ASCII): a BOM or a no-break space before the
/// object, and a trailing NUL.
List<String> _allMalformed() => [
  ..._malformed,
  '${String.fromCharCode(0xFEFF)}{}',
  '${String.fromCharCode(0xA0)}{}',
  '{"a":1}${String.fromCharCode(0)}',
];

void main() {
  group('parseEngineParamsOverride: hostile values', () {
    test('malformed → invalid (never throws)', () {
      for (final raw in _allMalformed()) {
        expect(
          parseEngineParamsOverride(raw),
          EngineParamsOverride.invalid,
          reason: jsonEncode(raw),
        );
      }
    });

    test('a raw lone surrogate is invalid (engine grammar)', () {
      final raw = '{"a":"${String.fromCharCode(0xD800)}"}';
      expect(parseEngineParamsOverride(raw), EngineParamsOverride.invalid);
      final raw2 = '{"a":"${String.fromCharCode(0xDC00)}x"}';
      expect(parseEngineParamsOverride(raw2), EngineParamsOverride.invalid);
    });

    test('nesting: depth 64 accepted, 65 refused (C15), no stack blow-up', () {
      expect(parseEngineParamsOverride(_nestedObjects(64)).json, isNotNull);
      expect(
        parseEngineParamsOverride(_nestedObjects(65)),
        EngineParamsOverride.invalid,
      );
      expect(parseEngineParamsOverride(_nestedArrays(63)).json, isNotNull);
      expect(
        parseEngineParamsOverride(_nestedArrays(64)),
        EngineParamsOverride.invalid,
      );
      // As deep as fits in the 16 384-unit budget.
      final deep = _nestedArrays(8188);
      expect(deep.length, lessThanOrEqualTo(kEngineParamsMaxChars));
      expect(parseEngineParamsOverride(deep), EngineParamsOverride.invalid);
      // Deeper but oversized: refused before parsing.
      final sw = Stopwatch()..start();
      expect(
        parseEngineParamsOverride(_nestedArrays(500000)),
        EngineParamsOverride.invalid,
      );
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('size: 16 384 units accepted verbatim, 16 385 refused', () {
      for (final fill in ['x', 'ế', '😴']) {
        final ok = _objectOfLength(kEngineParamsMaxChars, fill: fill);
        expect(ok.length, kEngineParamsMaxChars);
        final parsed = parseEngineParamsOverride(ok);
        expect(identical(parsed.json, ok) || parsed.json == ok, isTrue);
        expect(parsed.id, fnv1a32Hex(ok));
        final over = _objectOfLength(kEngineParamsMaxChars + 1, fill: fill);
        expect(over.length, kEngineParamsMaxChars + 1);
        expect(parseEngineParamsOverride(over), EngineParamsOverride.invalid);
      }
      // 1 MB: refused quickly.
      final sw = Stopwatch()..start();
      expect(
        parseEngineParamsOverride(_objectOfLength(1 << 20)),
        EngineParamsOverride.invalid,
      );
      expect(sw.elapsedMilliseconds, lessThan(1000));
    });

    test('fuzz: never throws; accepted ⊂ RFC 8259 objects; ids stable', () {
      const alphabet = '{}[]":,. 0123456789-+eEtrufalsn\\/u\tabcxyzé';
      final rnd = Random(29);
      var accepted = 0;
      for (var i = 0; i < 20000; i++) {
        final len = 1 + rnd.nextInt(40);
        final s = String.fromCharCodes([
          for (var j = 0; j < len; j++)
            alphabet.codeUnitAt(rnd.nextInt(alphabet.length)),
        ]);
        final r = parseEngineParamsOverride(s);
        if (r.json != null) {
          accepted++;
          expect(r.json, s);
          expect(r.id, fnv1a32Hex(s));
          expect(jsonDecode(s), isA<Map<String, Object?>>(), reason: s);
        } else {
          expect(r.id, anyOf('default', 'invalid'));
        }
      }
      expect(accepted, greaterThanOrEqualTo(0));
    });

    test('fuzz: one-character mutations of a real value', () {
      const base =
          '{"gpsLostMinS": 60.0, "snoozeS": 300, "smartTargetS": 300, '
          '"smartSlowSpeedKmh": 5, "tiers": [1, 2, 3], "name": "Ga Huế"}';
      expect(parseEngineParamsOverride(base).json, base);
      final rnd = Random(2029);
      const chars = '{}[]":,.-0e \\x';
      for (var i = 0; i < 20000; i++) {
        final pos = rnd.nextInt(base.length);
        final s = switch (rnd.nextInt(3)) {
          0 => base.replaceRange(pos, pos + 1, ''),
          1 => base.replaceRange(pos, pos, chars[rnd.nextInt(chars.length)]),
          _ => base.replaceRange(
            pos,
            pos + 1,
            chars[rnd.nextInt(chars.length)],
          ),
        };
        final r = parseEngineParamsOverride(s);
        if (r.json != null) {
          expect(jsonDecode(s), isA<Map<String, Object?>>(), reason: s);
          expect(r.json, s, reason: 'verbatim');
        }
      }
    });
  });

  group('EngineParamsSource.current() on hostile active values', () {
    test('invalid → defaults for the engine, one names-only non-fatal', () {
      final client = FakeRemoteConfigClient();
      final (crash, sink) = recordingCrash();
      final source = EngineParamsSource(
        client,
        flavor: AppFlavor.prod,
        crash: crash,
      );
      final records = <LogRecord>[];
      final previous = Logger.root.level;
      Logger.root.level = Level.ALL;
      final sub = Logger.root.onRecord.listen(records.add);
      addTearDown(() {
        unawaited(sub.cancel());
        Logger.root.level = previous;
      });
      for (final raw in [
        ..._allMalformed(),
        _nestedArrays(8188),
        _objectOfLength(kEngineParamsMaxChars + 1),
      ]) {
        client.value = raw;
        final r = source.current();
        expect(r.json, isNull, reason: jsonEncode(raw));
        expect(r.id, 'invalid');
      }
      return pumpEventQueue().then((_) {
        expect(sink.errors, hasLength(1), reason: 'once per session');
        final e = sink.errors.single;
        expect(e.reason, NonFatalReason.remoteConfigInvalid.name);
        expect(e.fatal, isFalse);
        expect(e.error.toString(), contains('trip_engine_params'));
        for (final text in [
          ...sink.allText,
          ...records.map((r) => r.message),
        ]) {
          expect(text, isNot(contains('Bad Gateway')));
          expect(text, isNot(contains('snoozeS')));
        }
      });
    });

    test('a valid value after an invalid one is used verbatim', () {
      final client = FakeRemoteConfigClient('not json');
      final source = EngineParamsSource(client, flavor: AppFlavor.dev);
      expect(source.current(), EngineParamsOverride.invalid);
      client.value = '{"gpsLostMinS": 90.0}';
      expect(source.current().json, '{"gpsLostMinS": 90.0}');
      client.value = '   ';
      expect(source.current(), EngineParamsOverride.defaults);
    });

    test('getString throwing (sync, any type) → defaults', () {
      for (final e in <Object>[
        StateError('x'),
        ArgumentError('y'),
        const FormatException('z'),
        'string error',
        const StackOverflowError(),
      ]) {
        final client = FakeRemoteConfigClient()..getError = e;
        final source = EngineParamsSource(client, flavor: AppFlavor.prod);
        expect(source.current(), EngineParamsOverride.defaults);
      }
    });

    test('current() stays fast on a 16 KB value (main-thread budget)', () {
      final client = FakeRemoteConfigClient(
        _objectOfLength(kEngineParamsMaxChars),
      );
      final source = EngineParamsSource(client, flavor: AppFlavor.prod);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        source.current();
      }
      // ≤ 16 ms per frame: 20 parses well inside a few frames.
      expect(sw.elapsedMilliseconds / 20, lessThan(16));
    });
  });

  group('refresh(): scheduling', () {
    for (final flavor in AppFlavor.values) {
      test('settings (${flavor.name})', () async {
        final client = FakeRemoteConfigClient();
        await EngineParamsSource(client, flavor: flavor).initialize();
        expect(client.minimumFetchInterval, switch (flavor) {
          AppFlavor.dev => const Duration(minutes: 5),
          AppFlavor.prod => const Duration(hours: 1),
        });
        expect(client.fetchTimeout, const Duration(seconds: 10));
        expect(client.defaults, {'trip_engine_params': ''});
      });
    }

    test('a burst of refreshes while one is in flight → 1 SDK call', () async {
      final gate = Completer<void>();
      final client = FakeRemoteConfigClient()
        ..fetchGate = gate
        ..next = '{"snoozeS":120}';
      final source = EngineParamsSource(client, flavor: AppFlavor.prod);
      final all = [for (var i = 0; i < 50; i++) source.refresh()];
      expect(client.fetchCalls, 1);
      // Reading during the fetch gives the value active before it.
      expect(source.current(), EngineParamsOverride.defaults);
      gate.complete();
      await Future.wait(all);
      expect(client.fetchCalls, 1);
      expect(source.current().json, '{"snoozeS":120}');
    });

    test(
      'fetch failing sync/async never escapes, keeps the old value',
      () async {
        final client = FakeRemoteConfigClient('{"snoozeS":120}')
          ..fetchError = StateError('throttled');
        final source = EngineParamsSource(client, flavor: AppFlavor.prod);
        await source.refresh();
        await source.refresh();
        expect(client.fetchCalls, 2);
        expect(source.current().json, '{"snoozeS":120}');
      },
    );

    testWidgets('a hung SDK fetch: refresh returns after 10 s, no 2nd call '
        'until it ends', (tester) async {
      final gate = Completer<void>();
      final client = FakeRemoteConfigClient('{}')..fetchGate = gate;
      final source = EngineParamsSource(client, flavor: AppFlavor.prod);
      var done = false;
      unawaited(source.refresh().then((_) => done = true));
      await tester.pump(const Duration(seconds: 9));
      expect(done, isFalse);
      await tester.pump(const Duration(seconds: 1, milliseconds: 1));
      expect(done, isTrue, reason: '10 s timeout');
      // Still hung: resumes during the next minutes do not pile up calls.
      for (var i = 0; i < 5; i++) {
        unawaited(source.refresh());
        await tester.pump(const Duration(seconds: 30));
      }
      expect(client.fetchCalls, 1);
      expect(source.current().json, '{}');
      gate.complete();
      await tester.pump();
      unawaited(source.refresh());
      await tester.pump();
      expect(client.fetchCalls, 2);
    });
  });
}
