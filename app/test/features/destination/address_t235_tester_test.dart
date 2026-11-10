// T23.5 tester tests (beyond the spec): privacy of what crosses the channel,
// platform gating, boundary values, long and combining-mark text, retry of
// the same text, late answers after dispose, many fast strings.
//
// Mutation list of docs/test-reports/T23.5.md: every mutation must be caught
// by at least one test; the ones added here close the holes found by the
// first mutation run (channel arguments exactness, provider gating).

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/features/destination/data/address_search_client.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/test_station_catalog.dart';
import 'presentation/address_controller_test.dart' show FakeAddressClient;

AddressSuggestion _s(String t, [String s = '']) =>
    AddressSuggestion(title: t, subtitle: s);

CompleteReply _ok(int gen, [int n = 3]) => CompleteReply(
  gen: gen,
  status: AddressStatus.ok,
  items: [for (var i = 0; i < n; i++) _s('Phố $i', 'Hà Nội')],
);

final Object _key = Object();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------ channel
  group('what crosses the channel (privacy, D11)', () {
    const channel = MethodChannel(kAddressSearchChannel);
    final calls = <MethodCall>[];
    Object? answer;

    setUp(() {
      calls.clear();
      answer = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return answer;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('complete: exactly v, gen, query, region = Vietnam box', () async {
      answer = {'gen': 7, 'status': 'ok', 'items': <Object?>[]};
      await const MethodChannelAddressSearchClient().complete(
        gen: 7,
        query: 'kim ma',
      );
      final args = calls.single.arguments as Map;
      expect(args.keys.toSet(), {'v', 'gen', 'query', 'region'});
      final region = args['region'] as Map;
      expect(region.keys.toSet(), {'s', 'w', 'n', 'e'});
      expect(region, {
        's': kVietnamBounds.south,
        'w': kVietnamBounds.west,
        'n': kVietnamBounds.north,
        'e': kVietnamBounds.east,
      });
      // The box is the fixed box of the spec (D4), not a position.
      expect(kVietnamBounds.south, 8.3);
      expect(kVietnamBounds.north, 23.6);
      expect(kVietnamBounds.west, 102.0);
      expect(kVietnamBounds.east, 109.7);
    });

    test('resolve and cancel carry no position either', () async {
      answer = {'status': 'ok', 'lat': 21.0, 'lng': 105.8, 'country': 'VN'};
      await const MethodChannelAddressSearchClient().resolve(gen: 1, index: 2);
      expect((calls.single.arguments as Map).keys.toSet(), {
        'v',
        'gen',
        'index',
      });
      answer = null;
      await const MethodChannelAddressSearchClient().cancel();
      expect(calls.last.arguments, isNull);
    });

    testWidgets('a whole search flow only calls complete/resolve/cancel', (
      tester,
    ) async {
      final container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
          stationCatalogProvider.overrideWith(
            (ref) async => kTestStationCatalog,
          ),
          addressSearchClientProvider.overrideWithValue(
            const MethodChannelAddressSearchClient(),
          ),
          addressSearchEnabledProvider.overrideWithValue(true),
        ],
      )..listen(destinationControllerFamily(_key), (_, _) {});
      answer = {
        'gen': 1,
        'status': 'ok',
        'items': [
          {'t': 'Phố A', 's': 'Hà Nội'},
        ],
      };
      final c = container.read(destinationControllerFamily(_key).notifier)
        ..setQuery('kim ma');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.idle();
      await tester.pump();
      answer = {'status': 'ok', 'lat': 21.0, 'lng': 105.8, 'country': 'VN'};
      expect(await c.selectAddress(0), AddressPick.picked);
      c.cancelPending();
      await tester.idle();
      expect(calls.map((c) => c.method).toSet(), {
        'complete',
        'resolve',
        'cancel',
      });
      for (final call in calls) {
        final a = call.arguments;
        if (a is Map) {
          expect(
            a.keys.toSet().intersection({
              'lat',
              'lng',
              'latitude',
              'longitude',
              'location',
              'position',
              'center',
              'userLocation',
            }),
            isEmpty,
            reason: call.method,
          );
        }
      }
    });
  });

  // ------------------------------------------------------------ platform
  group('platform gating (Android never calls the channel)', () {
    const channel = MethodChannel(kAddressSearchChannel);
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    ProviderContainer real({required bool map}) => ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
        stationCatalogProvider.overrideWith((ref) async => kTestStationCatalog),
        destinationMapBuilderProvider.overrideWithValue(
          map ? (props) => const SizedBox() : null,
        ),
      ],
    )..listen(destinationControllerFamily(_key), (_, _) {});

    test('android: client null, section off, even with a map', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final c = real(map: true);
        expect(c.read(addressSearchClientProvider), isNull);
        expect(c.read(addressSearchEnabledProvider), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('iOS: client present; section needs the map (D10)', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        expect(
          real(map: true).read(addressSearchClientProvider),
          isA<MethodChannelAddressSearchClient>(),
        );
        expect(real(map: true).read(addressSearchEnabledProvider), isTrue);
        expect(real(map: false).read(addressSearchEnabledProvider), isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('android: typing never reaches the channel', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final c = real(map: true);
        c.read(destinationControllerFamily(_key).notifier)
          ..setQuery('nguyen trai')
          ..setFilter(DestinationFilter.all)
          ..setQuery('nguyen trai ha noi')
          ..cancelPending();
        await tester.pump(const Duration(seconds: 2));
        await tester.idle();
        expect(calls, isEmpty);
        expect(
          c.read(destinationControllerFamily(_key)).address,
          isA<AddressHidden>(),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('iOS without a map: typing never reaches the channel', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final c = real(map: false);
        c
            .read(destinationControllerFamily(_key).notifier)
            .setQuery('nguyen trai');
        await tester.pump(const Duration(seconds: 2));
        await tester.idle();
        expect(calls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('iOS with a map: typing does reach the channel (control)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final c = real(map: true);
        c
            .read(destinationControllerFamily(_key).notifier)
            .setQuery('nguyen trai');
        await tester.pump(const Duration(seconds: 2));
        await tester.idle();
        expect(calls.map((c) => c.method), ['complete']);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  // ------------------------------------------------------------ pure
  group('boundaries (pure)', () {
    test('shouldSearchAddresses: exactly 3 letters/digits', () {
      bool go(String q) =>
          shouldSearchAddresses(query: q, filter: DestinationFilter.all);
      expect(go('ab'), isFalse);
      expect(go('abc'), isTrue);
      expect(go('ab!'), isFalse);
      expect(go('a1b'), isTrue);
      expect(go('Đà'), isFalse);
      expect(go('Đà N'), isTrue);
      expect(go('   '), isFalse);
      expect(go(''), isFalse);
      for (final f in DestinationFilter.values) {
        expect(
          shouldSearchAddresses(query: 'abcd', filter: f),
          f == DestinationFilter.all,
          reason: f.name,
        );
      }
    });

    test('isSupportedDestination: box edges and the two archipelagos', () {
      bool ok(double lat, double lng, [String? c]) =>
          isSupportedDestination(MapPoint(lat, lng), country: c);
      expect(ok(8.3, 102), isTrue);
      expect(ok(23.6, 109.7), isTrue);
      expect(ok(8.29, 105), isFalse);
      expect(ok(23.61, 105), isFalse);
      expect(ok(15, 101.99), isFalse);
      expect(ok(15, 109.71), isFalse);
      // Hoang Sa / Truong Sa: east of the box, whatever the country says.
      expect(ok(16.5, 112), isFalse);
      expect(ok(16.5, 112, 'VN'), isFalse);
      expect(ok(10, 114, 'VN'), isFalse);
      expect(ok(8.7, 111.9), isFalse);
      // Country: case-insensitive VN only.
      expect(ok(21, 105.8, 'vn'), isTrue);
      expect(ok(21, 105.8, 'Vn'), isTrue);
      expect(ok(21, 105.8, ''), isFalse);
      expect(ok(11.5, 105, 'KH'), isFalse);
      expect(ok(16, 105, 'LA'), isFalse);
      expect(ok(22.82, 108.32, 'CN'), isFalse);
      expect(ok(21, 105.8, 'VNM'), isFalse);
    });

    test('isBlockedSuggestion: tokens, case, marks; street names pass', () {
      for (final blocked in [
        _s('TRUNG QUỐC'),
        _s('x', 'trung quoc'),
        _s('Sansha City'),
        _s('Nansha Islands'),
        _s('PARACEL Islands'),
        _s('Spratly Islands'),
        _s('Hainan, China'),
        _s('Xisha'),
        _s('Hải Nam', 'Trung Quốc'),
        _s('Trung Quốc'), // NFD
        _s('Tam Sa', '三沙'),
        _s('a', '海南'),
        _s('中国'),
      ]) {
        expect(isBlockedSuggestion(blocked), isTrue, reason: blocked.title);
      }
      for (final fine in [
        _s('Hoàng Sa'),
        _s('Hoàng Sa', 'Sơn Trà, Đà Nẵng'),
        _s('HOÀNG SA', 'Quận 1, TP HCM'),
        _s('Hoang Sa'),
        _s('Trường Sa', 'Phú Nhuận'),
        _s('Truong Sa', 'Quận 3'),
        _s('Huyện đảo Trường Sa', 'Khánh Hòa'),
        _s('Huyện đảo Hoàng Sa', 'Đà Nẵng'),
        _s('Quốc lộ 1', 'Trung tâm'),
        _s('Chinatown'),
        _s('Hà Nội'),
      ]) {
        expect(isBlockedSuggestion(fine), isFalse, reason: fine.title);
      }
    });

    test('visibleSuggestions keeps native indexes around blocked rows', () {
      final rows = visibleSuggestions([
        _s('Nanjing', 'China'),
        _s('A'),
        _s('中国'),
        _s('B'),
      ]);
      expect(rows.map((r) => (r.nativeIndex, r.suggestion.title)), [
        (1, 'A'),
        (3, 'B'),
      ]);
      expect(visibleSuggestions(const []), isEmpty);
    });

    test('addressQueryOf: exactly 64 stays, 65 is cut, no split pair', () {
      expect(addressQueryOf('a' * 64), 'a' * 64);
      expect(addressQueryOf('a' * 65), 'a' * 64);
      expect(addressQueryOf('  ${'a' * 64}  '), 'a' * 64);
      expect(addressQueryOf('${'a' * 63}  b'), 'a' * 63);
      // 64th rune is an emoji (2 UTF-16 units): kept whole.
      final e = addressQueryOf('${'a' * 63}😀zzz');
      expect(e.runes.length, 64);
      expect(e.codeUnits.length, 65);
      expect(e.runes.last, 0x1F600);
      // 100 emoji: 64 runes, valid UTF-16.
      final many = addressQueryOf('😀' * 100);
      expect(many.runes.length, 64);
      expect(many.codeUnits.length, 128);
    });

    test('addressQueryOf: combining marks (NFD) count as runes (R2-2)', () {
      // 70 x "e" + U+0301: 140 runes, the cut is by rune like Swift
      // unicodeScalars. The result never exceeds 64 scalars, is valid, and
      // the folded text still holds only "e".
      final nfd = 'é' * 70;
      final cut = addressQueryOf(nfd);
      expect(cut.runes.length, lessThanOrEqualTo(kMaxAddressQueryRunes));
      expect(cut.runes.length, 64);
      expect(cut, 'é' * 32);
      // An odd cut point drops the mark of the last letter only.
      final odd = addressQueryOf('x${'é' * 70}');
      expect(odd.runes.length, 64);
      expect(odd.runes.last, 0x65);
      // Composed Vietnamese (NFC), 70 letters: first 64 intact.
      final nfc = 'ễ' * 70;
      expect(addressQueryOf(nfc), 'ễ' * 64);
      // ZWJ family emoji = 7 scalars: cut by scalar, <= 64, no throw.
      final family = '👨‍👩‍👧' * 20;
      expect(addressQueryOf(family).runes.length, lessThanOrEqualTo(64));
      // Folding makes NFC and NFD of the same text equal for the search gate.
      expect(
        shouldSearchAddresses(query: 'Nguyễn', filter: DestinationFilter.all),
        isTrue,
      );
    });

    test('addressDestination: 199/200 boundary with a surrogate pair', () {
      const p = MapPoint(21.03, 105.85);
      // Pair occupies units 199-200 (1-based): cannot fit, drop it.
      final d = addressDestination(_s('${'a' * 199}😀tail', 'b' * 199), p);
      expect(d.name.length, 199);
      expect(d.isValid, isTrue);
      // Pair occupies units 198-199: fits, whole.
      final d2 = addressDestination(_s('${'a' * 198}😀tail'), p);
      expect(d2.name.length, 200);
      expect(d2.name.codeUnitAt(199), inInclusiveRange(0xDC00, 0xDFFF));
      expect(d2.isValid, isTrue);
      expect(addressDestination(_s('x', '   '), p).detail, isNull);
    });

    test('literal spec constants (mutation run 1: tests used the constants '
        'themselves and could not see them drift)', () {
      expect(kAddressThrottleCooldown, const Duration(seconds: 30)); // D14
      expect(kMaxAddressItems, 15); // spec §3
      expect(kAddressDisplayLimit, 5); // D5
      expect(kMaxAddressQueryRunes, 64); // spec §3
      expect(kMinAddressQueryChars, 3); // D5
      // 20 items from native: exactly 15 survive the decoder, in order.
      final r = decodeCompleteReply({
        'gen': 1,
        'status': 'ok',
        'items': [
          for (var i = 0; i < 20; i++) {'t': 'T$i', 's': ''},
        ],
      });
      expect(r!.items.length, 15);
      expect(r.items.first.title, 'T0');
      expect(r.items.last.title, 'T14');
    });

    test('isBlockedSuggestion: each archipelago token alone is enough', () {
      // Mutation run 1: dropping the "hainan" token was not noticed because
      // every sample also carried "China" or "Trung Quoc".
      for (final t in [
        'Hainan',
        'hainan sheng',
        'Sansha',
        'Xisha',
        'Nansha',
        'Paracel',
        'Spratly',
        'China',
      ]) {
        expect(isBlockedSuggestion(_s(t)), isTrue, reason: t);
        expect(isBlockedSuggestion(_s('x', t)), isTrue, reason: 'sub $t');
      }
    });

    test('toString of every state and reply prints no text or number', () {
      const secret = 'Số 25 ngõ 120 Hoàng Quốc Việt';
      final rows = visibleSuggestions([_s(secret, 'Cầu Giấy')]);
      final all = <Object>[
        _s(secret, 'Cầu Giấy'),
        CompleteReply(gen: 5, status: AddressStatus.ok, items: [_s(secret)]),
        const ResolveReply(
          status: AddressStatus.ok,
          point: MapPoint(21.0123, 105.8123),
          country: 'VN',
        ),
        const AddressHidden(),
        AddressLoading(rows),
        AddressResults(rows, resolvingIndex: 0),
        const AddressEmpty(),
        const AddressOffline(),
        const AddressThrottled(),
        const AddressUnavailable(),
        const AddressSearchProtocolException(),
      ];
      for (final o in all) {
        final t = o.toString();
        expect(t, isNot(contains('Hoàng')), reason: t);
        expect(t, isNot(contains('Cầu')), reason: t);
        expect(t, isNot(contains('21.01')), reason: t);
        expect(t, isNot(contains('105.81')), reason: t);
      }
    });
  });

  // ------------------------------------------------------------ controller
  group('controller scenarios', () {
    late FakeAddressClient client;
    late ProviderContainer container;
    late DateTime now;
    late RecordingCrashSink crashSink;
    final base = Telemetry.noop();

    ProviderContainer newContainer() => ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
        stationCatalogProvider.overrideWith((ref) async => kTestStationCatalog),
        clockProvider.overrideWithValue(() => now),
        addressSearchClientProvider.overrideWithValue(client),
        addressSearchEnabledProvider.overrideWithValue(true),
        telemetryProvider.overrideWithValue(
          Telemetry(
            analytics: base.analytics,
            crash: CrashReporter(crashSink),
            engineParams: base.engineParams,
            consent: base.consent,
          ),
        ),
      ],
    )..listen(destinationControllerFamily(_key), (_, _) {});

    setUp(() {
      client = FakeAddressClient();
      now = DateTime(2026, 11, 10, 12);
      crashSink = RecordingCrashSink();
      container = newContainer();
    });

    DestinationController ctrl() =>
        container.read(destinationControllerFamily(_key).notifier);
    DestinationState state() =>
        container.read(destinationControllerFamily(_key));

    Future<void> settle(WidgetTester tester, [int ms = 0]) async {
      await tester.pump(Duration(milliseconds: ms));
      await tester.idle();
      await tester.pump();
    }

    testWidgets('R2-1 retry of the same text after a network error', (
      tester,
    ) async {
      await settle(tester);
      // airplane mode: first "abc" fails with network.
      ctrl().setQuery('abc');
      await settle(tester, 450);
      expect(client.completes.single.query, 'abc');
      client.completes.single.done.complete(
        CompleteReply(
          gen: client.completes.single.gen,
          status: AddressStatus.network,
        ),
      );
      await settle(tester);
      expect(state().address, isA<AddressOffline>());
      // airplane off; the user changes the chip and goes back.
      ctrl().setFilter(DestinationFilter.train);
      expect(state().address, isA<AddressHidden>());
      ctrl().setFilter(DestinationFilter.all);
      expect(state().address, isA<AddressLoading>());
      await settle(tester, 450);
      // A new request with the SAME text and a NEW generation goes out:
      // the native side must not rely on the old snapshot.
      expect(client.completes.length, 2);
      expect(client.completes.last.query, 'abc');
      expect(
        client.completes.last.gen,
        greaterThan(client.completes.first.gen),
      );
      client.completes.last.done.complete(_ok(client.completes.last.gen));
      await settle(tester);
      expect(state().address, isA<AddressResults>());
    });

    testWidgets('R2-1 "ab" then "abc": exactly one request, for "abc"', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('ab');
      await settle(tester, 450);
      expect(client.completes, isEmpty);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      expect(client.completes.map((c) => c.query), ['abc']);
    });

    testWidgets(
      'R2-1 an "ok, 0 items" answer shows Empty, then a retry works',
      (tester) async {
        // This is what a spurious empty update of the completer would look like
        // to Dart: the screen says "no address found" until the next change.
        await settle(tester);
        ctrl().setQuery('abc');
        await settle(tester, 450);
        client.completes.last.done.complete(
          CompleteReply(
            gen: client.completes.last.gen,
            status: AddressStatus.ok,
          ),
        );
        await settle(tester);
        expect(state().address, isA<AddressEmpty>());
        ctrl().setQuery('abcd');
        await settle(tester, 450);
        client.completes.last.done.complete(_ok(client.completes.last.gen));
        await settle(tester);
        expect(state().address, isA<AddressResults>());
      },
    );

    testWidgets('throttled: no request for 30 s, exactly then one', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      client.completes.last.done.complete(
        CompleteReply(
          gen: client.completes.last.gen,
          status: AddressStatus.throttled,
        ),
      );
      await settle(tester);
      expect(state().address, isA<AddressThrottled>());
      final sent = client.completes.length;
      // Literal 30 s (D14), not the constant: a constant changed to 10 or 29
      // must be seen (mutation run 1).
      now = now.add(const Duration(seconds: 29));
      ctrl().setQuery('abcd');
      await settle(tester, 450);
      expect(client.completes.length, sent, reason: '29 s: still resting');
      expect(state().address, isA<AddressThrottled>());
      now = now.add(const Duration(seconds: 1));
      ctrl().setQuery('abcde');
      await settle(tester, 450);
      expect(client.completes.length, sent + 1, reason: '30 s: may ask again');
    });

    testWidgets('throttled while resolving: later complete still rests', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      client.completes.last.done.complete(_ok(client.completes.last.gen));
      await settle(tester);
      final f = ctrl().selectAddress(0);
      client.resolves.last.done.complete(
        const ResolveReply(status: AddressStatus.throttled),
      );
      expect(await f, AddressPick.failed);
      final sent = client.completes.length;
      ctrl().setQuery('abcd');
      await settle(tester, 450);
      expect(client.completes.length, sent);
    });

    testWidgets('30 distinct strings, one every 500 ms: only the last shows', (
      tester,
    ) async {
      await settle(tester);
      for (var i = 0; i < 30; i++) {
        ctrl().setQuery('phố số ${'x' * (i + 1)}');
        await settle(tester, 500);
      }
      expect(client.completes.length, 30);
      final gens = client.completes.map((c) => c.gen).toList();
      expect(gens, [for (var i = 1; i <= 30; i++) i]);
      // Answers arrive in reverse order: only the newest is applied.
      for (final c in client.completes.reversed) {
        c.done.complete(
          CompleteReply(
            gen: c.gen,
            status: AddressStatus.ok,
            items: [_s('R${c.gen}')],
          ),
        );
      }
      await settle(tester);
      final rows = (state().address as AddressResults).rows;
      expect(rows.single.suggestion.title, 'R30');
    });

    testWidgets('30 strings typed in a burst: one request', (tester) async {
      await settle(tester);
      for (var i = 0; i < 30; i++) {
        ctrl().setQuery('phố ${'x' * (i + 1)}');
        await settle(tester, 100);
      }
      await settle(tester, 450);
      expect(client.completes.length, 1);
    });

    testWidgets('a row tapped while Loading is ignored; a double tap too', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      client.completes.last.done.complete(_ok(client.completes.last.gen));
      await settle(tester);
      ctrl().setQuery('abcd'); // Loading(previous rows)
      expect(state().address, isA<AddressLoading>());
      expect(await ctrl().selectAddress(0), AddressPick.ignored);
      expect(client.resolves, isEmpty);
      await settle(tester, 450);
      client.completes.last.done.complete(_ok(client.completes.last.gen));
      await settle(tester);
      final first = ctrl().selectAddress(0);
      expect(await ctrl().selectAddress(1), AddressPick.ignored);
      expect(client.resolves.length, 1);
      client.resolves.single.done.complete(
        const ResolveReply(
          status: AddressStatus.ok,
          point: MapPoint(21.03, 105.85),
        ),
      );
      expect(await first, AddressPick.picked);
    });

    testWidgets('answers after dispose do not throw', (tester) async {
      await settle(tester);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      final pending = client.completes.last;
      container.dispose();
      pending.done.complete(_ok(pending.gen));
      await settle(tester);
      expect(client.cancels, greaterThan(0), reason: 'dispose cancels native');
      expect(tester.takeException(), isNull);
    });

    testWidgets('resolve answer after dispose does not throw', (tester) async {
      await settle(tester);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      client.completes.last.done.complete(_ok(client.completes.last.gen));
      await settle(tester);
      final f = ctrl().selectAddress(0);
      container.dispose();
      client.resolves.single.done.complete(
        const ResolveReply(
          status: AddressStatus.ok,
          point: MapPoint(21.03, 105.85),
        ),
      );
      expect(await f, AddressPick.ignored);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an address outside the area never becomes a selection', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('abc');
      await settle(tester, 450);
      client.completes.last.done.complete(_ok(client.completes.last.gen));
      await settle(tester);
      for (final (point, country) in const [
        (MapPoint(16.5, 111.6), null),
        (MapPoint(16.5, 112), 'VN'),
        (MapPoint(10, 114), null),
        (MapPoint(21.03, 105.85), 'CN'),
        (MapPoint(22.82, 108.32), 'CN'),
      ]) {
        final f = ctrl().selectAddress(0);
        client.resolves.last.done.complete(
          ResolveReply(
            status: AddressStatus.ok,
            point: point,
            country: country,
          ),
        );
        expect(await f, AddressPick.outsideArea);
        expect(state().selection, isNull);
      }
      // ok without a point (should not happen) is a failure, not a pick.
      final f = ctrl().selectAddress(0);
      client.resolves.last.done.complete(
        const ResolveReply(status: AddressStatus.ok),
      );
      expect(await f, AddressPick.failed);
      expect(state().selection, isNull);
    });

    testWidgets('blocked suggestions never appear, whatever Apple sends', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('tam sa');
      await settle(tester, 450);
      client.completes.last.done.complete(
        CompleteReply(
          gen: client.completes.last.gen,
          status: AddressStatus.ok,
          items: [
            _s('Tam Sa', 'Hải Nam, Trung Quốc'),
            _s('三沙市'),
            _s('Xisha Islands'),
            _s('Đường Hoàng Sa', 'Đà Nẵng'),
          ],
        ),
      );
      await settle(tester);
      final rows = (state().address as AddressResults).rows;
      expect(rows.map((r) => r.suggestion.title), ['Đường Hoàng Sa']);
      expect(rows.single.nativeIndex, 3);
      // All blocked: shows Empty.
      ctrl().setQuery('tam sa x');
      await settle(tester, 450);
      client.completes.last.done.complete(
        CompleteReply(
          gen: client.completes.last.gen,
          status: AddressStatus.ok,
          items: [_s('三沙市'), _s('Paracel Islands')],
        ),
      );
      await settle(tester);
      expect(state().address, isA<AddressEmpty>());
    });

    testWidgets('channel error with typed text and coordinates in it: the '
        'report keeps only the type (item 4: guard not weakened)', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('nguyen trai ha noi');
      await settle(tester, 450);
      client.completes.last.done.completeError(
        PlatformException(
          code: 'search_failed',
          message: 'query nguyen trai ha noi at 21.0285123,105.8412345',
          details: {'query': 'nguyen trai', 'lat': 21.0285123},
          stacktrace: 'at AddressSearchService(nguyen trai)',
        ),
      );
      await settle(tester);
      expect(state().address, isA<AddressUnavailable>());
      expect(crashSink.errors.length, 1);
      final e = crashSink.errors.single;
      expect(e.reason, 'addressSearchFailed');
      expect(e.reason, NonFatalReason.addressSearchFailed.name);
      final joined = crashSink.allText.join(' | ');
      for (final secret in [
        'nguyen',
        'trai',
        '21.02',
        '105.84',
        'search_failed',
      ]) {
        expect(joined, isNot(contains(secret)), reason: secret);
      }
      // A second error is not reported again (once per controller).
      ctrl().setQuery('nguyen trai ha noi 2');
      await settle(tester, 450);
      client.completes.last.done.completeError(
        PlatformException(code: 'again'),
      );
      await settle(tester);
      expect(crashSink.errors.length, 1);
    });

    testWidgets('debounce edge: nothing at 399 ms, one request at 400 ms', (
      tester,
    ) async {
      await settle(tester);
      expect(kAddressDebounce, const Duration(milliseconds: 400));
      ctrl().setQuery('abc');
      await tester.pump(const Duration(milliseconds: 399));
      await tester.idle();
      expect(client.completes, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.idle();
      expect(client.completes.length, 1);
    });

    testWidgets('3-letter edge: "ab" sends nothing at any time, "abc" sends', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('ab');
      await settle(tester, 2000);
      expect(client.completes, isEmpty);
      expect(state().address, isA<AddressHidden>());
      ctrl().setQuery('abc');
      await settle(tester, 400);
      expect(client.completes.length, 1);
    });
  });
}
