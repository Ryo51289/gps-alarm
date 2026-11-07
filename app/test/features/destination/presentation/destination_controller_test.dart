// T23 (pin and distance transitions), T23.2 (offline search only):
// DestinationController in fake time (testWidgets) for the debounce.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_station_catalog.dart';

/// Controller key of these tests (one controller per screen, review #12).
final Object _key = Object();

void main() {
  late FakeCoreBridge bridge;
  late ProviderContainer container;

  setUp(() {
    bridge = FakeCoreBridge();
    container = ProviderContainer.test(
      retry: (_, _) => null,
      overrides: [
        coreBridgeProvider.overrideWithValue(bridge),
        stationCatalogProvider.overrideWith((ref) async => kTestStationCatalog),
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

  testWidgets('offline search; chips keep their kind (T23.2 D2)', (
    tester,
  ) async {
    await settle(tester);
    ctrl().setQuery('dong hoi');
    await settle(tester, 400);
    expect(state().offline.first.station.name, 'Ga Đồng Hới');
    ctrl().setFilter(DestinationFilter.train);
    expect(state().filter, DestinationFilter.train);
    expect(
      state().offline.every((m) => m.station.kind == StationKind.train),
      isTrue,
    );
    ctrl().setFilter(DestinationFilter.coach);
    expect(
      state().offline.every((m) => m.station.kind != StationKind.train),
      isTrue,
    );
    ctrl().setFilter(DestinationFilter.all);
    expect(state().offline.first.station.name, 'Ga Đồng Hới');
    // PRIVACY: no query, no name.
    expect(state().toString(), isNot(contains('dong')));
    expect(state().toString(), isNot(contains('Đồng')));
    await settle(tester, 200);
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
}
