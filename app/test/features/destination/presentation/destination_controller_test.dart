// T23 TP11–TP12 (+ pin and distance transitions): DestinationController with
// a MockClient for Places, in fake time (testWidgets) for the debounces.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_station_catalog.dart';

/// Places stand-in: records every request; autocomplete answers can be held.
class FakePlaces {
  final List<http.Request> requests = [];
  final List<Completer<void>> gates = [];
  bool holdNext = false;

  /// Place Details answers 500.
  bool failDetails = false;

  /// Holds Place Details until completed.
  Completer<void>? detailsGate;

  List<http.Request> get autocompletes =>
      requests.where((r) => r.url.path.endsWith(':autocomplete')).toList();
  List<http.Request> get details =>
      requests.where((r) => r.url.path.startsWith('/v1/places/')).toList();

  MockClient get client => MockClient((r) async {
    requests.add(r);
    if (r.url.path.endsWith(':autocomplete')) {
      if (holdNext) {
        holdNext = false;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
      }
      final input = (jsonDecode(r.body) as Map)['input'];
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'suggestions': [
              {
                'placePrediction': {
                  'placeId': 'id-$input',
                  'text': {'text': 'Result $input'},
                },
              },
            ],
          }),
        ),
        200,
      );
    }
    final gate = detailsGate;
    if (gate != null) {
      await gate.future;
    }
    if (failDetails) {
      return http.Response('{}', 500);
    }
    return http.Response(
      jsonEncode({
        'location': {'latitude': 13.98, 'longitude': 108.0},
      }),
      200,
    );
  });
}

String tokenOf(http.Request r) => r.url.path.endsWith(':autocomplete')
    ? (jsonDecode(r.body) as Map)['sessionToken'] as String
    : r.url.queryParameters['sessionToken']!;

String inputOf(http.Request r) =>
    (jsonDecode(r.body) as Map)['input'] as String;

/// Controller key of these tests (one controller per screen, review #12).
final Object _key = Object();

void main() {
  late FakePlaces places;
  late FakeCoreBridge bridge;
  late ProviderContainer container;

  setUp(() {
    places = FakePlaces();
    bridge = FakeCoreBridge(mapsConfig: MapsConfigMsg(apiKey: 'test-key'));
    container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        coreBridgeProvider.overrideWithValue(bridge),
        stationCatalogProvider.overrideWith((ref) async => kTestStationCatalog),
        placesHttpClientProvider.overrideWithValue(places.client),
        placesRandomProvider.overrideWithValue(Random(7)),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 12)),
      ],
    )..listen(destinationControllerFamily(_key), (_, _) {});
  });

  DestinationController ctrl() =>
      container.read(destinationControllerFamily(_key).notifier);
  DestinationState state() => container.read(destinationControllerFamily(_key));

  Future<void> settle(WidgetTester tester, [int ms = 0]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.idle();
    await tester.pump();
  }

  Future<void> enterPlaces(WidgetTester tester) async {
    await settle(tester);
    ctrl().setFilter(DestinationFilter.places);
    await settle(tester);
  }

  testWidgets('TP11 one autocomplete per pause in typing', (tester) async {
    await enterPlaces(tester);
    expect(state().places, isA<PlacesUiTypeMore>());
    ctrl().setQuery('ben');
    await settle(tester, 100);
    ctrl().setQuery('ben x');
    await settle(tester, 100);
    ctrl().setQuery('ben xe d');
    await settle(tester, 100);
    expect(places.requests, isEmpty);
    await settle(tester, 350);
    expect(places.autocompletes.map(inputOf), ['ben xe d']);
    final r = state().places;
    expect(r, isA<PlacesUiResults>());
    expect(
      (r as PlacesUiResults).predictions.single.mainText,
      'Result ben xe d',
    );
  });

  testWidgets('TP12 stale answers dropped, one token per session', (
    tester,
  ) async {
    await enterPlaces(tester);
    places.holdNext = true;
    ctrl().setQuery('ben xe');
    await settle(tester, 400);
    expect(state().places, isA<PlacesUiLoading>());
    ctrl().setQuery('ben xe duc');
    await settle(tester, 400);
    expect(places.autocompletes.map(inputOf), ['ben xe', 'ben xe duc']);
    final t1 = tokenOf(places.autocompletes.first);
    expect(tokenOf(places.autocompletes.last), t1);
    // The old answer arrives last and is ignored.
    places.gates.single.complete();
    await settle(tester);
    final shown = state().places as PlacesUiResults;
    expect(shown.predictions.single.placeId, 'id-ben xe duc');

    expect(await ctrl().selectPrediction(shown.predictions.single), isTrue);
    await settle(tester);
    expect(tokenOf(places.details.single), t1);
    final sel = state().selection!;
    expect(sel.source, DestinationSource.places);
    expect(sel.destination.kind, DestinationKind.address);
    expect(sel.destination.lat, 13.98);
    expect(state().cameraRequestId, 1);

    ctrl().setQuery('ben xe duc l');
    await settle(tester, 400);
    final t2 = tokenOf(places.autocompletes.last);
    expect(t2, isNot(t1));

    ctrl()
      ..setFilter(DestinationFilter.all)
      ..setFilter(DestinationFilter.places);
    await settle(tester, 400);
    final t3 = tokenOf(places.autocompletes.last);
    expect(t3, isNot(t2));
    expect(t3, isNot(t1));

    final before = places.requests.length;
    ctrl().setQuery('be');
    await settle(tester, 400);
    expect(places.requests, hasLength(before));
    expect(state().places, isA<PlacesUiTypeMore>());
  });

  testWidgets('no key: not configured, no request', (tester) async {
    bridge.mapsConfigValue = MapsConfigMsg();
    container.invalidate(mapsConfigProvider);
    await enterPlaces(tester);
    ctrl().setQuery('ben xe duc long');
    await settle(tester, 400);
    expect(state().places, isA<PlacesUiNotConfigured>());
    expect(places.requests, isEmpty);
  });

  testWidgets('offline search never calls Places (D5)', (tester) async {
    await settle(tester);
    ctrl().setQuery('dong hoi');
    await settle(tester, 400);
    expect(state().offline.first.station.name, 'Ga Đồng Hới');
    expect(places.requests, isEmpty);
  });

  testWidgets('distances: one call, then hidden for 30 s after null', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('dong hoi');
    await settle(tester, 200);
    expect(bridge.distancesCalls, hasLength(1));
    expect(bridge.distancesCalls.single.maxAgeMs, kLastKnownMaxAgeMs);
    final rows = state().offline;
    expect(bridge.distancesCalls.single.pairs, [
      for (final m in rows) ...[m.station.lat, m.station.lng],
    ]);
    ctrl().setQuery('dong h');
    await settle(tester, 200);
    expect(bridge.distancesCalls, hasLength(1));
    expect(state().distanceByStationId, isEmpty);
  });

  testWidgets('distances are kept per station id', (tester) async {
    bridge.distances = (pairs) => [
      for (var i = 0; i < pairs.length ~/ 2; i++) 1000.0 * (i + 1),
    ];
    await settle(tester);
    ctrl().setQuery('dong hoi');
    await settle(tester, 200);
    final first = state().offline.first.station.id;
    expect(state().distanceByStationId[first], 1000);
    bridge.distancesError = channelError();
    ctrl().setQuery('vinh');
    await settle(tester, 200);
    expect(state().distanceByStationId[first], 1000);
  });

  testWidgets('pin: drop, move, undo', (tester) async {
    await settle(tester);
    ctrl().setQuery('dong hoi');
    await settle(tester, 200);
    final ga = state().offline.first.station;
    ctrl().selectStation(ga);
    expect(ctrl().isSelectedStation(ga), isTrue);
    final start = state().selection!;

    final near = MapPoint(ga.lat + 300 / 111195.08, ga.lng);
    final moved = ctrl().movePin(
      near,
      pinnedName: 'Điểm đã ghim',
      pinnedDetail: (p, m) => 'from $p',
    );
    expect(moved, closeTo(300, 1));
    expect(state().selection!.destination.name, ga.name);
    expect(state().selection!.anchor, start.anchor);
    expect(ctrl().isSelectedStation(ga), isTrue);

    final far = MapPoint(ga.lat + 1200 / 111195.08, ga.lng);
    ctrl().movePin(
      far,
      pinnedName: 'Điểm đã ghim',
      pinnedDetail: (p, m) => 'from $p',
    );
    final pinned = state().selection!;
    expect(pinned.destination.kind, DestinationKind.pin);
    expect(pinned.destination.detail, 'from ${ga.name}');
    expect(pinned.anchor, far);
    expect(ctrl().isSelectedStation(ga), isFalse);

    ctrl().undoPin();
    expect(state().selection!.destination.name, ga.name);
    expect(state().selection!.point, near);
    expect(state().undo, isNull);

    ctrl().dropPin(const MapPoint(16, 107), pinnedName: 'Điểm đã ghim');
    expect(state().selection!.source, DestinationSource.mapPin);
    expect(state().cameraRequestId, 1);
    ctrl().undoPin();
    expect(state().selection!.destination.name, ga.name);
  });

  testWidgets('location failure keeps the list, next tap opens a session', (
    tester,
  ) async {
    await enterPlaces(tester);
    ctrl().setQuery('duc long');
    await settle(tester, 400);
    final p = (state().places as PlacesUiResults).predictions.single;
    final t1 = tokenOf(places.autocompletes.single);
    places.failDetails = true;
    expect(await ctrl().selectPrediction(p), isFalse);
    expect(tokenOf(places.details.single), t1);
    final after = state();
    expect(after.selection, isNull);
    expect((after.places as PlacesUiResults).resolvingId, isNull);
    places.failDetails = false;
    expect(await ctrl().selectPrediction(p), isTrue);
    // The first session ended with the failed details call.
    expect(tokenOf(places.details.last), isNot(t1));
  });

  testWidgets('round 2 #1: a tap cancels the pending autocomplete', (
    tester,
  ) async {
    await enterPlaces(tester);
    ctrl().setQuery('ben xe duc');
    await settle(tester, 400);
    final p = (state().places as PlacesUiResults).predictions.single;
    expect(places.autocompletes, hasLength(1));
    places.detailsGate = Completer<void>();
    // One more letter, then a tap on the shown suggestion within 350 ms.
    ctrl().setQuery('ben xe duc l');
    await settle(tester, 100);
    final selected = ctrl().selectPrediction(p);
    await settle(tester, 400);
    expect(places.autocompletes, hasLength(1));
    final resolving = state().places as PlacesUiResults;
    expect(resolving.resolvingId, p.placeId);
    places.detailsGate!.complete();
    expect(await selected, isTrue);
    await settle(tester, 400);
    expect(places.autocompletes, hasLength(1));
    expect(state().selection!.source, DestinationSource.places);
  });

  testWidgets('round 2 #2: enough letters show Loading at once', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('dong hoi');
    await settle(tester, 200);
    ctrl().setFilter(DestinationFilter.places);
    await settle(tester, 10);
    expect(state().places, isA<PlacesUiLoading>());
    expect(places.requests, isEmpty);
    await settle(tester, 400);
    expect(state().places, isA<PlacesUiResults>());

    ctrl().setQuery('du');
    await settle(tester, 10);
    expect(state().places, isA<PlacesUiTypeMore>());
    ctrl().setQuery('duc');
    await settle(tester, 10);
    expect(state().places, isA<PlacesUiLoading>());
    await settle(tester, 400);
    expect(places.autocompletes.map(inputOf).last, 'duc');
  });

  testWidgets('round 2 nit 7: a failed mapsConfig is read again', (
    tester,
  ) async {
    bridge.mapsConfigError = channelError();
    container.invalidate(mapsConfigProvider);
    await enterPlaces(tester);
    expect(state().places, isA<PlacesUiNotConfigured>());
    bridge.mapsConfigError = null;
    ctrl()
      ..setFilter(DestinationFilter.all)
      ..setFilter(DestinationFilter.places);
    await settle(tester);
    expect(state().places, isA<PlacesUiTypeMore>());
    expect(bridge.callCount('mapsConfig'), 2);
  });

  testWidgets('round 4 B2: no new work after cancelPending, resume once', (
    tester,
  ) async {
    await enterPlaces(tester);
    ctrl().setQuery('ben xe du');
    await settle(tester, 100);
    ctrl()
      ..cancelPending()
      // A keystroke that reaches the field after Back.
      ..setQuery('ben xe duc');
    await settle(tester, 2000);
    expect(places.requests, isEmpty);
    expect(state().query, 'ben xe duc');
    expect(state().places, isA<PlacesUiLoading>());
    // Chip changes while suspended do not search either.
    ctrl()
      ..setFilter(DestinationFilter.all)
      ..setFilter(DestinationFilter.places);
    await settle(tester, 2000);
    expect(places.requests, isEmpty);

    ctrl().resume();
    await settle(tester, 400);
    expect(places.autocompletes.map(inputOf), ['ben xe duc']);
    await settle(tester, 2000);
    expect(places.requests, hasLength(1));
  });

  testWidgets('round 4 B2: no distance call while suspended', (tester) async {
    await settle(tester);
    ctrl()
      ..cancelPending()
      ..setQuery('dong hoi');
    await settle(tester, 500);
    expect(state().offline, isNotEmpty);
    expect(bridge.distancesCalls, isEmpty);
    ctrl().resume();
    await settle(tester, 200);
    expect(bridge.distancesCalls, hasLength(1));
  });

  testWidgets('round 4 B2: selectPrediction refused while suspended', (
    tester,
  ) async {
    await enterPlaces(tester);
    ctrl().setQuery('duc long');
    await settle(tester, 400);
    final p = (state().places as PlacesUiResults).predictions.single;
    ctrl().cancelPending();
    // Ignored silently: null, so the screen shows no snack bar (#13).
    expect(await ctrl().selectPrediction(p), isNull);
    await settle(tester, 400);
    expect(places.details, isEmpty);
  });
}
