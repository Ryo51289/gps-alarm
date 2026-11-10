// T23.5 AS-C01..AS-C09: address search in DestinationController, fake
// client, fake time.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/address_search_client.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_station_catalog.dart';

/// Scripted client: every call waits for the test to answer it.
class FakeAddressClient implements AddressSearchClient {
  final List<({int gen, String query, Completer<CompleteReply> done})>
  completes = [];
  final List<({int gen, int index, Completer<ResolveReply> done})> resolves =
      [];
  int cancels = 0;

  @override
  Future<CompleteReply> complete({required int gen, required String query}) {
    final c = Completer<CompleteReply>();
    completes.add((gen: gen, query: query, done: c));
    return c.future;
  }

  @override
  Future<ResolveReply> resolve({required int gen, required int index}) {
    final c = Completer<ResolveReply>();
    resolves.add((gen: gen, index: index, done: c));
    return c.future;
  }

  @override
  Future<void> cancel() async => cancels++;
}

const _hanoi = MapPoint(21.03, 105.85);

CompleteReply _ok(int gen, [int n = 3]) => CompleteReply(
  gen: gen,
  status: AddressStatus.ok,
  items: [
    for (var i = 0; i < n; i++)
      AddressSuggestion(title: 'Phố $i', subtitle: 'Hà Nội'),
  ],
);

final Object _key = Object();

void main() {
  late FakeAddressClient client;
  late ProviderContainer container;
  late DateTime now;
  final reported = <FlutterErrorDetails>[];

  ProviderContainer newContainer({required bool enabled}) =>
      ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
          stationCatalogProvider.overrideWith(
            (ref) async => kTestStationCatalog,
          ),
          clockProvider.overrideWithValue(() => now),
          addressSearchClientProvider.overrideWithValue(client),
          addressSearchEnabledProvider.overrideWithValue(enabled),
        ],
      )..listen(destinationControllerFamily(_key), (_, _) {});

  setUp(() {
    client = FakeAddressClient();
    now = DateTime(2026, 11, 10, 12);
    reported.clear();
    container = newContainer(enabled: true);
  });

  /// The test binding replaces FlutterError.onError when a test starts.
  void capture() => FlutterError.onError = reported.add;

  DestinationController ctrl() =>
      container.read(destinationControllerFamily(_key).notifier);
  DestinationState state() => container.read(destinationControllerFamily(_key));

  Future<void> settle(WidgetTester tester, [int ms = 0]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.idle();
    await tester.pump();
  }

  /// Types [q], waits out the debounce, answers with [n] suggestions.
  Future<void> results(WidgetTester tester, String q, [int n = 3]) async {
    ctrl().setQuery(q);
    await settle(tester, 450);
    client.completes.last.done.complete(_ok(client.completes.last.gen, n));
    await settle(tester);
  }

  testWidgets('AS-C01 one request for a burst of typing', (tester) async {
    await settle(tester);
    ctrl().setQuery('kim');
    await settle(tester, 100);
    ctrl().setQuery('kim m');
    await settle(tester, 100);
    ctrl().setQuery('kim ma');
    expect(state().address, isA<AddressLoading>());
    await settle(tester, 100);
    expect(client.completes, isEmpty);
    await settle(tester, 450);
    expect(client.completes.length, 1);
    expect(client.completes.single.query, 'kim ma');
    expect(client.completes.single.gen, 1);
    client.completes.single.done.complete(_ok(1));
    await settle(tester);
    expect(state().address, isA<AddressResults>());
    expect((state().address as AddressResults).rows.length, 3);
  });

  testWidgets('AS-C02 stale and superseded answers are dropped', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('abc');
    await settle(tester, 450);
    ctrl().setQuery('abcd');
    await settle(tester, 450);
    expect(client.completes.length, 2);
    client.completes[1].done.complete(_ok(2, 2));
    await settle(tester);
    client.completes[0].done.complete(_ok(1, 5));
    await settle(tester);
    expect((state().address as AddressResults).rows.length, 2);
    ctrl().setQuery('abcde');
    await settle(tester, 450);
    client.completes[2].done.complete(
      const CompleteReply(gen: 3, status: AddressStatus.superseded),
    );
    await settle(tester);
    expect(state().address, isA<AddressLoading>());
  });

  testWidgets('AS-C03 statuses and errors', (tester) async {
    capture();
    await settle(tester);
    Future<void> reply(String q, CompleteReply r) async {
      ctrl().setQuery(q);
      await settle(tester, 450);
      client.completes.last.done.complete(r);
      await settle(tester);
    }

    await reply(
      'abc',
      const CompleteReply(gen: 1, status: AddressStatus.network),
    );
    expect(state().address, isA<AddressOffline>());
    await reply(
      'abcd',
      const CompleteReply(gen: 2, status: AddressStatus.failed),
    );
    expect(state().address, isA<AddressUnavailable>());
    await reply(
      'abcde',
      const CompleteReply(gen: 3, status: AddressStatus.timeout),
    );
    expect(state().address, isA<AddressUnavailable>());
    // Throttled: 30 s without a request.
    await reply(
      'abcdef',
      const CompleteReply(gen: 4, status: AddressStatus.throttled),
    );
    expect(state().address, isA<AddressThrottled>());
    final sent = client.completes.length;
    ctrl().setQuery('abcdefg');
    await settle(tester, 450);
    expect(client.completes.length, sent);
    expect(state().address, isA<AddressThrottled>());
    now = now.add(kAddressThrottleCooldown + const Duration(seconds: 1));
    ctrl().setQuery('abcdefgh');
    await settle(tester, 450);
    expect(client.completes.length, sent + 1);
    // Channel errors: one report for two exceptions.
    client.completes.last.done.completeError(PlatformException(code: 'x'));
    await settle(tester);
    expect(state().address, isA<AddressUnavailable>());
    ctrl().setQuery('abcdefghi');
    await settle(tester, 450);
    client.completes.last.done.completeError(MissingPluginException());
    await settle(tester);
    expect(state().address, isA<AddressUnavailable>());
    expect(reported.length, 1);
    expect(reported.single.exception.toString(), isNot(contains('abc')));
  });

  testWidgets('AS-C04 hidden for other chips, short text', (tester) async {
    await settle(tester);
    ctrl().setFilter(DestinationFilter.train);
    ctrl().setQuery('abcd');
    await settle(tester, 450);
    expect(client.completes, isEmpty);
    expect(state().address, isA<AddressHidden>());
    ctrl().setFilter(DestinationFilter.all);
    await settle(tester, 450);
    client.completes.single.done.complete(_ok(1));
    await settle(tester);
    expect(state().address, isA<AddressResults>());
    ctrl().setFilter(DestinationFilter.train);
    expect(state().address, isA<AddressHidden>());
    expect(client.cancels, 1);
    ctrl().setFilter(DestinationFilter.all);
    ctrl().setQuery('ab');
    expect(state().address, isA<AddressHidden>());
  });

  testWidgets('AS-C04b a disabled controller never sends', (tester) async {
    container.dispose();
    container = newContainer(enabled: false);
    ctrl().setQuery('abcd');
    await settle(tester, 450);
    expect(client.completes, isEmpty);
    expect(state().address, isA<AddressHidden>());
  });

  testWidgets('AS-C05 picking an address selects it', (tester) async {
    await settle(tester);
    await results(tester, 'pho');
    final before = state().cameraRequestId;
    final f = ctrl().selectAddress(0);
    expect((state().address as AddressResults).resolvingIndex, 0);
    expect(client.resolves.single.gen, 1);
    client.resolves.single.done.complete(
      const ResolveReply(
        status: AddressStatus.ok,
        point: _hanoi,
        country: 'VN',
      ),
    );
    expect(await f, AddressPick.picked);
    final sel = state().selection!;
    expect(sel.destination.kind, DestinationKind.address);
    expect(sel.source, DestinationSource.places);
    expect(sel.anchor, _hanoi);
    expect(state().cameraRequestId, before + 1);
    expect(state().undo, isNull);
    expect((state().address as AddressResults).resolvingIndex, isNull);
    expect(
      ctrl().isSelectedAddress(
        const AddressSuggestion(title: 'Phố 0', subtitle: 'Hà Nội'),
      ),
      isTrue,
    );
  });

  testWidgets('AS-C06 outside area, offline, stale, errors', (tester) async {
    capture();
    await settle(tester);
    await results(tester, 'pho');
    Future<AddressPick> pick(ResolveReply r) {
      final f = ctrl().selectAddress(0);
      client.resolves.last.done.complete(r);
      return f;
    }

    expect(
      await pick(
        const ResolveReply(
          status: AddressStatus.ok,
          point: MapPoint(16.5, 111.6),
        ),
      ),
      AddressPick.outsideArea,
    );
    expect(
      await pick(
        const ResolveReply(
          status: AddressStatus.ok,
          point: _hanoi,
          country: 'CN',
        ),
      ),
      AddressPick.outsideArea,
    );
    expect(state().selection, isNull);
    expect(
      await pick(const ResolveReply(status: AddressStatus.network)),
      AddressPick.offline,
    );
    final sent = client.completes.length;
    expect(
      await pick(const ResolveReply(status: AddressStatus.stale)),
      AddressPick.failed,
    );
    await settle(tester, 450);
    expect(client.completes.length, sent + 1);
    client.completes.last.done.complete(_ok(client.completes.last.gen));
    await settle(tester);
    final f = ctrl().selectAddress(0);
    client.resolves.last.done.completeError(PlatformException(code: 'x'));
    expect(await f, AddressPick.failed);
    expect(state().address, isA<AddressUnavailable>());
  });

  testWidgets('AS-C07 typing on while resolving ignores the answer', (
    tester,
  ) async {
    await settle(tester);
    await results(tester, 'pho');
    final f = ctrl().selectAddress(0);
    ctrl().setQuery('phox');
    client.resolves.single.done.complete(
      const ResolveReply(status: AddressStatus.ok, point: _hanoi),
    );
    expect(await f, AddressPick.ignored);
    expect(state().selection, isNull);
    await settle(tester, 450);
  });

  testWidgets('AS-C08 cancelPending sends nothing more; resume is quiet', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('abcd');
    await settle(tester, 100);
    ctrl().cancelPending();
    await settle(tester, 600);
    expect(client.completes, isEmpty);
    expect(client.cancels, greaterThan(0));
    ctrl().resume();
    await settle(tester, 600);
    expect(client.completes, isEmpty);
    expect(state().address, isNot(isA<AddressLoading>()));
  });

  testWidgets('AS-C09 moving an address pin', (tester) async {
    await settle(tester);
    await results(tester, 'pho');
    final f = ctrl().selectAddress(0);
    client.resolves.single.done.complete(
      const ResolveReply(status: AddressStatus.ok, point: _hanoi),
    );
    await f;
    String detail(String place, double m) => 'Cách $place ${m.round()}';
    ctrl().movePin(
      MapPoint(_hanoi.lat + 300 / 111320, _hanoi.lng),
      pinnedName: 'Ghim',
      pinnedDetail: detail,
    );
    var d = state().selection!.destination;
    expect(d.name, 'Phố 0');
    expect(d.detail, 'Hà Nội');
    expect(state().selection!.source, DestinationSource.places);
    ctrl().movePin(
      MapPoint(_hanoi.lat + 800 / 111320, _hanoi.lng),
      pinnedName: 'Ghim',
      pinnedDetail: detail,
    );
    d = state().selection!.destination;
    expect(d.kind, DestinationKind.pin);
    expect(d.detail, startsWith('Cách Phố 0'));
  });

  testWidgets('AS-D08 DestinationState toString', (tester) async {
    await settle(tester);
    await results(tester, 'pho');
    expect(state().toString(), isNot(contains('Phố')));
    expect(state().address.toString(), 'AddressResults(3)');
  });
}
