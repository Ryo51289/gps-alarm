// Tester T23 (adversarial, beyond the spec's TP/TW cases): Places billing
// and privacy through the real screen (router, controller, PlacesClient over
// MockClient). Counts Autocomplete / Place Details requests per session for
// the gestures a sleepy passenger actually makes: type then tap, type then
// clear, chip switching, rapid typing, double tap, Back mid-request.
//
// Billing model (spec §8, [PL-SESS], [PL-SP]): a session is N Autocomplete
// with one token, ended by ONE Place Details (field mask `location` only)
// with the same token. A token is never reused after its Details call.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';

import '../../../helpers/fake_core_bridge.dart';
import 'destination_harness.dart';

const _kAutocompleteMask =
    'suggestions.placePrediction.placeId,'
    'suggestions.placePrediction.text,'
    'suggestions.placePrediction.structuredFormat';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

bool _isAutocomplete(http.Request r) => r.url.path.endsWith(':autocomplete');

List<http.Request> _ac(DestinationHarness h) =>
    h.places.requests.where(_isAutocomplete).toList();

List<http.Request> _details(DestinationHarness h) =>
    h.places.requests.where((r) => !_isAutocomplete(r)).toList();

String _token(http.Request r) => _isAutocomplete(r)
    ? (jsonDecode(r.body) as Map)['sessionToken'] as String
    : r.url.queryParameters['sessionToken']!;

String _input(http.Request r) => (jsonDecode(r.body) as Map)['input'] as String;

/// Screen 2 with a seeded token source.
Future<DestinationHarness> _open(
  WidgetTester tester, {
  Locale locale = const Locale('vi'),
  FakeCoreBridge? bridge,
}) => pumpDestination(
  tester,
  locale: locale,
  bridge: bridge,
  overrides: [placesRandomProvider.overrideWithValue(Random(23))],
);

/// Types without waiting for the debounce.
Future<void> _key(WidgetTester tester, String text, [int ms = 0]) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _wait(WidgetTester tester, int ms) async {
  await tester.pump(Duration(milliseconds: ms));
  await tester.pumpAndSettle();
}

Future<void> _tapChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(NapChip, label);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

/// Opens the address chip with an empty query.
Future<void> _enterPlaces(WidgetTester tester) async {
  await tapVisible(tester, find.text('Tìm địa chỉ bằng Google Maps'));
}

void main() {
  testWidgets('B1 rapid typing then tap: 1 Autocomplete + 1 Details, one '
      'token, Details mask = location', (tester) async {
    final h = await _open(tester);
    await _enterPlaces(tester);
    const text = 'ben xe duc long';
    for (var n = 1; n <= text.length; n++) {
      // ~8 keys/s: every gap shorter than the 350 ms debounce.
      await _key(tester, text.substring(0, n), 120);
    }
    expect(h.places.requests, isEmpty);
    await _wait(tester, 400);
    expect(_ac(h).map(_input), [text]);

    await tapVisible(tester, find.text('Bến xe Đức Long'));
    expect(_ac(h), hasLength(1));
    final details = _details(h).single;
    expect(details.method, 'GET');
    expect(details.url.path, '/v1/places/p1');
    expect(details.url.queryParameters.keys.toSet(), {
      'sessionToken',
      'languageCode',
    });
    expect(details.headers['X-Goog-FieldMask'], 'location');
    expect(_token(details), _token(_ac(h).single));
    expect(_token(details), matches(_uuidV4));
    // Nothing else goes out after the session ended.
    await _wait(tester, 2000);
    expect(h.places.requests, hasLength(2));
  });

  testWidgets('B2 debounce boundary: 349 ms pauses send nothing, 350 ms '
      'sends the last text once', (tester) async {
    final h = await _open(tester);
    await _enterPlaces(tester);
    await _key(tester, 'ben', 349);
    await _key(tester, 'ben x', 349);
    await _key(tester, 'ben xe', 349);
    expect(h.places.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(_ac(h).map(_input), ['ben xe']);
  });

  testWidgets('B3 type then clear: a pending debounce is dropped; the open '
      'session keeps its token', (tester) async {
    final h = await _open(tester);
    await _enterPlaces(tester);
    await _key(tester, 'ben xe duc', 100);
    await tester.tap(find.byTooltip('Xoá nội dung tìm'));
    await _wait(tester, 1000);
    expect(h.places.requests, isEmpty);
    expect(find.text('Gõ ít nhất 3 ký tự để tìm địa chỉ.'), findsOneWidget);

    await _key(tester, 'ben xe duc');
    await _wait(tester, 400);
    final t1 = _token(_ac(h).single);
    await tester.tap(find.byTooltip('Xoá nội dung tìm'));
    await _wait(tester, 400);
    expect(find.text('Bến xe Đức Long'), findsNothing);
    await _key(tester, 'duc long');
    await _wait(tester, 400);
    expect(_ac(h).map(_input), ['ben xe duc', 'duc long']);
    // Same unfinished session (no Details yet): the token is kept.
    expect(_token(_ac(h).last), t1);
    await tapVisible(tester, find.text('Bến xe Đức Long'));
    expect(_token(_details(h).single), t1);
  });

  testWidgets('B4 chip switching: quick hops cost one request; leaving the '
      'address chip ends the session (new token)', (tester) async {
    final h = await _open(tester);
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Tìm "dong hoi" bằng Google Maps'));
    expect(h.places.requests, hasLength(1));
    final t1 = _token(_ac(h).single);

    // Hop away and back inside the debounce: one request, new token.
    await _tapChip(tester, 'Tất cả');
    await tester.pump(const Duration(milliseconds: 100));
    await _tapChip(tester, 'Địa chỉ');
    await tester.pump(const Duration(milliseconds: 100));
    await _tapChip(tester, 'Ga tàu');
    await tester.pump(const Duration(milliseconds: 100));
    await _tapChip(tester, 'Địa chỉ');
    await _wait(tester, 400);
    expect(_ac(h), hasLength(2));
    final t2 = _token(_ac(h).last);
    expect(t2, isNot(t1));

    // Typing under the station chips never reaches Google.
    await _tapChip(tester, 'Bến xe');
    await typeQuery(tester, 'ben xe duc long');
    await _tapChip(tester, 'Ga tàu');
    await typeQuery(tester, 'ga dong hoi');
    await _wait(tester, 1000);
    expect(_ac(h), hasLength(2));
    expect(_details(h), isEmpty);
  });

  testWidgets('B5 double tap on a suggestion: one Details', (tester) async {
    final h = await _open(tester);
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    final row = find.text('Bến xe Đức Long');
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.tap(row, warnIfMissed: false);
    await _wait(tester, 400);
    expect(_details(h), hasLength(1));
    expect(find.text('Chọn Bến xe Đức Long'), findsOneWidget);
  });

  testWidgets('B6 a second suggestion after a chosen one: a fresh token, '
      'never one already ended', (tester) async {
    final h = await _open(tester);
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    await tapVisible(tester, find.text('Bến xe Đức Long'));
    final ended = _token(_details(h).single);
    final second = find.text('Đức Long Gia Lai');
    expect(second, findsOneWidget, reason: 'list stays after a choice');
    await tapVisible(tester, second);
    expect(_details(h), hasLength(2));
    expect(_token(_details(h).last), isNot(ended));
    expect(_ac(h), hasLength(1));
    expect(find.text('Chọn Đức Long Gia Lai'), findsOneWidget);
    // Typing again opens a new session, distinct from both.
    await typeQuery(tester, 'duc long gia');
    expect(_ac(h), hasLength(2));
    expect(_token(_ac(h).last), isNot(ended));
    expect(_token(_ac(h).last), isNot(_token(_details(h).last)));
  });

  // BUG T23-B1 (test report T23): FAILS on the round-2 code. Back pops the
  // route at once, but screen 2 stays mounted ~500 ms for the exit
  // transition, so the controller (autoDispose) is disposed only after the
  // 350 ms debounce fired: one Autocomplete goes out after the user left,
  // in a session that can never end (billed as "Autocomplete Requests").
  // Spec §8: "leavePlaces() / dispose: ... huỷ debounce".
  testWidgets('B7a Back inside the debounce: no request after leaving', (
    tester,
  ) async {
    final h = await _open(tester);
    await _enterPlaces(tester);
    await _key(tester, 'ben xe duc', 100);
    await tester.tap(find.byTooltip('Quay lại'));
    await _wait(tester, 2000);
    expect(h.places.requests, isEmpty);
  });

  // Variant of BUG T23-B1 (orchestrator request): confirming pushes screen 3
  // on top while screen 2 stays alive below it, so a pending debounce would
  // still send an Autocomplete the user can no longer see.
  testWidgets('B7c "Chọn …" inside the debounce: no request after leaving', (
    tester,
  ) async {
    final h = await _open(tester);
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    await tapVisible(tester, find.text('Tìm "dong hoi" bằng Google Maps'));
    final before = h.places.requests.length;
    await _key(tester, 'ben xe duc', 100);
    final confirm = find.text('Chọn Ga Đồng Hới');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await _wait(tester, 2000);
    expect(h.app.location, '/alarm-settings');
    expect(h.places.requests, hasLength(before));
  });

  // Review T23 round 3 nit #11: pick mode (mode=pick) confirms with
  // pop(dest); a pending debounce must not fire after the pop.
  testWidgets('B7d pick mode: "Chọn …" inside the debounce sends nothing', (
    tester,
  ) async {
    final h = await pumpDestination(
      tester,
      open: false,
      overrides: [placesRandomProvider.overrideWithValue(Random(23))],
    );
    final result = homeContext(tester).pickDestination();
    await tester.pumpAndSettle();
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    await tester.tap(find.byTooltip('Xoá nội dung tìm'));
    await tester.pumpAndSettle();
    await _tapChip(tester, 'Địa chỉ');
    await tester.pumpAndSettle();
    expect(h.places.requests, isEmpty);
    await _key(tester, 'ben xe duc', 100);
    final confirm = find.text('Chọn Ga Đồng Hới');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await _wait(tester, 2000);
    expect((await result)?.name, 'Ga Đồng Hới');
    expect(h.app.location, '/home');
    expect(h.places.requests, isEmpty);
  });

  // BUG T23-B2 (test report T23, Lần 2): failed on the round-3 code. A query
  // change that reaches screen 2 after the pop (key events typed just before
  // a Back are applied asynchronously by the Android embedding; seen on the
  // emulator in 4 of 5 runs) must not re-arm the Places debounce while the
  // screen is still mounted for its exit animation. The late change is the
  // old screen's own TextField.onChanged, called during that animation.
  testWidgets('B7e a query change after Back does not search', (tester) async {
    final h = await _open(tester);
    await _enterPlaces(tester);
    await _key(tester, 'ben xe du', 100);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.app.location, '/home');
    final exitingField = find.descendant(
      of: find.byType(DestinationScreen, skipOffstage: false),
      matching: find.byType(TextField, skipOffstage: false),
    );
    expect(exitingField, findsOneWidget, reason: 'screen 2 still exiting');
    tester.widget<TextField>(exitingField).onChanged!('ben xe duc');
    await _wait(tester, 2000);
    expect(find.byType(DestinationScreen, skipOffstage: false), findsNothing);
    expect(h.places.requests, isEmpty);
  });

  testWidgets('B7b reopening screen 2 starts a new token', (tester) async {
    final h = await _open(tester);
    await _enterPlaces(tester);
    await _key(tester, 'ben xe duc');
    await _wait(tester, 400);
    final t1 = _token(_ac(h).single);
    await tester.tap(find.byTooltip('Quay lại'));
    await _wait(tester, 1000);
    unawaited(h.app.router.push('/destination'));
    await tester.pumpAndSettle();
    await _enterPlaces(tester);
    await _key(tester, 'ben xe duc');
    await _wait(tester, 400);
    expect(_ac(h), hasLength(2));
    expect(_token(_ac(h).last), isNot(t1));
    expect(_token(_ac(h).last), matches(_uuidV4));
  });

  testWidgets('B8 no user or station position in any request', (tester) async {
    final bridge = FakeCoreBridge(
      mapsConfig: MapsConfigMsg(
        apiKey: 'test-key',
        androidPackage: 'app.napstop.dev',
        androidCertSha1: 'A9993E364706816ABA3E25717850C26C9CD0D89D',
      ),
      // Distances known to Dart (rounded, native side).
      distances: (pairs) => [for (var i = 0; i < pairs.length ~/ 2; i++) 1200],
    );
    final h = await _open(tester, bridge: bridge);
    // A station chosen first: its point must not become a bias.
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    await tapVisible(tester, find.text('Tìm "dong hoi" bằng Google Maps'));
    await tapVisible(tester, find.text('Bến xe Đức Long'));
    expect(h.places.requests, hasLength(2));
    for (final r in h.places.requests) {
      final all = '${r.url} ${r.headers} ${r.body}';
      for (final banned in [
        'locationBias',
        'locationRestriction',
        'origin',
        'circle',
        'rectangle',
        'latitude',
        'longitude',
        '17.4', // Ga Đồng Hới
        '106.5',
        '1200',
      ]) {
        expect(all.contains(banned), isFalse, reason: '$banned in ${r.method}');
      }
      final expectedHeaders = {
        'x-goog-api-key',
        'x-goog-fieldmask',
        'x-android-package',
        'x-android-cert',
        if (_isAutocomplete(r)) 'content-type',
      };
      expect(
        r.headers.keys.map((k) => k.toLowerCase()).toSet(),
        expectedHeaders,
      );
      if (_isAutocomplete(r)) {
        expect(r.headers['X-Goog-FieldMask'], _kAutocompleteMask);
        expect((jsonDecode(r.body) as Map).keys.toSet(), {
          'input',
          'sessionToken',
          'languageCode',
          'regionCode',
          'includedRegionCodes',
        });
        expect(r.url.queryParameters, isEmpty);
      } else {
        expect(r.headers['X-Goog-FieldMask'], 'location');
        expect(r.body, isEmpty);
      }
    }
  });

  testWidgets('B9 English UI: languageCode en in both calls', (tester) async {
    final h = await _open(tester, locale: const Locale('en'));
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Search "duc long" with Google Maps'));
    await tapVisible(tester, find.text('Bến xe Đức Long'));
    expect((jsonDecode(_ac(h).single.body) as Map)['languageCode'], 'en');
    expect(_details(h).single.url.queryParameters['languageCode'], 'en');
  });

  testWidgets('B10 no key: chip, typing and hops never call Places; map '
      'placeholder; mapsConfig read once', (tester) async {
    final h = await pumpDestination(tester, mapsKey: null);
    expect(find.text('Bản đồ chưa sẵn sàng trong bản này.'), findsOneWidget);
    expect(h.map.builds, isEmpty);
    await _tapChip(tester, 'Địa chỉ');
    await tester.pumpAndSettle();
    expect(find.text('Bản này chưa bật tìm địa chỉ.'), findsOneWidget);
    await typeQuery(tester, 'ben xe duc long');
    for (final c in ['Tất cả', 'Địa chỉ', 'Bến xe', 'Địa chỉ']) {
      await _tapChip(tester, c);
      await _wait(tester, 400);
    }
    expect(find.text('Bản này chưa bật tìm địa chỉ.'), findsOneWidget);
    expect(h.places.requests, isEmpty);
    expect(h.map.builds, isEmpty);
    expect(h.bridge.callCount('mapsConfig'), 1);
    // Offline search and choosing still work without a key.
    await _tapChip(tester, 'Tất cả');
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
    expect(h.map.builds, isEmpty);
  });
}
