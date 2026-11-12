// Tester T24.3 (round after review 1): the "no station" / "pin it yourself"
// lines come back when the bus stop section turns out empty or fails on
// chip "Tất cả" (the user must never be left with a blank list), and the
// 500 m boundary of a moved bus stop pin (kPinKeepIdentityM, D11).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_station_catalog.dart';
import 'bus_stop_controller_test.dart' show kFakeBusStops;
import 'destination_harness.dart';

const String _noStation = 'Không có ga, bến xe nào khớp "bach khoa".';
const String _pinHint =
    'Không có trong danh sách? Nhấn giữ trên bản đồ để ghim điểm đến.';
const String _loading = 'Đang tải trạm buýt…';

final Object _key = Object();

void main() {
  group('chip Tất cả, no station matches "bach khoa"', () {
    testWidgets('bus stops loading → load fails: both lines come back', (
      tester,
    ) async {
      final load = Completer<StationCatalog>();
      await pumpDestination(tester, busStopCatalog: () => load.future);
      await tester.enterText(find.byType(TextField), 'bach khoa');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_loading), findsOneWidget);
      expect(find.text(_noStation), findsNothing);
      load.completeError(const StationDataException('asset missing'));
      await tester.pumpAndSettle();
      expect(find.text(_loading), findsNothing);
      expect(find.byKey(const ValueKey('bus-stop-section')), findsNothing);
      expect(find.text(_noStation), findsOneWidget);
      expect(find.text(_pinHint), findsOneWidget);
    });

    testWidgets('bus stops loading → loaded, no match: both lines come back', (
      tester,
    ) async {
      final load = Completer<StationCatalog>();
      await pumpDestination(tester, busStopCatalog: () => load.future);
      await tester.enterText(find.byType(TextField), 'bach khoa');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(_noStation), findsNothing);
      load.complete(kEmptyBusStopCatalog);
      await tester.pumpAndSettle();
      expect(find.text(_noStation), findsOneWidget);
      expect(find.text(_pinHint), findsOneWidget);
      expect(find.byKey(const ValueKey('bus-stop-section')), findsNothing);
    });

    testWidgets('bus stops shown, then a query nothing matches: lines back', (
      tester,
    ) async {
      await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
      await typeQuery(tester, 'bach khoa');
      expect(find.text(_noStation), findsNothing);
      expect(find.byKey(const ValueKey('bus-stop-section')), findsOneWidget);
      await typeQuery(tester, 'xyzq');
      expect(find.text('Không có ga, bến xe nào khớp "xyzq".'), findsOneWidget);
      expect(find.text(_pinHint), findsOneWidget);
    });

    testWidgets('Android (no map): bus stops match, no "no station" line', (
      tester,
    ) async {
      await pumpDestination(
        tester,
        withMap: false,
        busStopCatalog: () async => kFakeBusStops,
      );
      await typeQuery(tester, 'bach khoa');
      expect(find.text(_noStation), findsNothing);
      expect(find.text(_pinHint), findsNothing);
      expect(find.byKey(const ValueKey('bus-stop-section')), findsOneWidget);
    });
  });

  group('moved bus stop pin: 500 m boundary', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer.test(
        retry: (_, _) => null,
        overrides: [
          coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
          stationCatalogProvider.overrideWith(
            (ref) async => kTestStationCatalog,
          ),
          busStopCatalogProvider.overrideWith((ref) async => kFakeBusStops),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 12, 12)),
        ],
      )..listen(destinationControllerFamily(_key), (_, _) {});
    });

    DestinationController ctrl() =>
        container.read(destinationControllerFamily(_key).notifier);
    DestinationState state() =>
        container.read(destinationControllerFamily(_key));

    Future<void> settle(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.idle();
      await tester.pump();
    }

    for (final (meters, kept) in [
      (499.0, true),
      (500.0 - 0.5, true),
      (500.5, false),
      (501.0, false),
    ]) {
      testWidgets('moved $meters m → bus stop kept: $kept', (tester) async {
        await settle(tester);
        ctrl().setQuery('bach khoa');
        await settle(tester);
        final stop = state().busStops.first.station;
        ctrl().selectStation(stop);
        final to = MapPoint(stop.lat + meters / 111195.08, stop.lng);
        final d = distanceM(MapPoint(stop.lat, stop.lng), to);
        expect(d, closeTo(meters, 0.2));
        ctrl().movePin(
          to,
          pinnedName: 'Điểm đã ghim',
          pinnedDetail: (p, m) => 'from $p',
        );
        final sel = state().selection!;
        expect(sel.busStop, kept);
        expect(
          sel.destination.kind,
          kept ? DestinationKind.bus : DestinationKind.pin,
        );
        expect(previewRadiusM(sel), kept ? 500 : 1000);
        await settle(tester);
      });
    }

    testWidgets('two moves of 400 m: measured from the stop, not chained', (
      tester,
    ) async {
      await settle(tester);
      ctrl().setQuery('bach khoa');
      await settle(tester);
      final stop = state().busStops.first.station;
      ctrl().selectStation(stop);
      void move(double m) => ctrl().movePin(
        MapPoint(stop.lat + m / 111195.08, stop.lng),
        pinnedName: 'Điểm đã ghim',
        pinnedDetail: (p, m) => 'from $p',
      );
      move(400);
      expect(state().selection!.busStop, isTrue);
      move(800);
      expect(state().selection!.busStop, isFalse);
      expect(previewRadiusM(state().selection), 1000);
      await settle(tester);
    });
  });
}
