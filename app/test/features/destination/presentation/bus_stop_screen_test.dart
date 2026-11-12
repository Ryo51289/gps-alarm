// T24.3 BS-W01–BS-W06: bus stops on screen 2 (chip "Trạm buýt", the bus
// stop section under the stations on chip "Tất cả", selection, map props,
// Android without a map, big text, section states).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/data/destination_providers.dart';
import 'package:napstop/features/destination/data/station_repository.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/presentation/widgets/apple_destination_map.dart';
import 'package:napstop/features/destination/presentation/widgets/result_row.dart';

import 'address_controller_test.dart' show FakeAddressClient;
import 'bus_stop_controller_test.dart' show kFakeBusStops;
import 'destination_harness.dart';

const String _osm = 'Dữ liệu ga, bến, trạm buýt © OpenStreetMap contributors';

/// Titles of the rows whose key starts with [prefix], top to bottom.
List<String> _titles(WidgetTester tester, String prefix) => [
  for (final row in tester.widgetList<ResultRow>(find.byType(ResultRow)))
    if ((row.key! as ValueKey<String>).value.startsWith(prefix)) row.title,
];

Future<void> _chip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(NapChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('BS-W01 chip all: stations, then bus stops, one OSM line', (
    tester,
  ) async {
    await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
    await typeQuery(tester, 'kim ma');
    final stations = _titles(tester, 'station-');
    final stops = _titles(tester, 'bus-stop-');
    expect(stations, isNotEmpty, reason: 'Bến xe Kim Mã');
    expect(stops, ['Kim Mã']);
    final header = find.text('Trạm buýt').last;
    expect(
      tester.getTopLeft(header).dy,
      greaterThan(tester.getTopLeft(find.text(stations.last).first).dy),
    );
    final stopRow = find.byKey(const ValueKey('bus-stop-osm:n4'));
    expect(
      find.descendant(
        of: stopRow,
        matching: find.byIcon(Icons.signpost_outlined),
      ),
      findsOneWidget,
    );
    expect(find.text(_osm), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(_osm)).dy,
      greaterThan(tester.getTopLeft(stopRow).dy),
    );
    // Header is announced as a header.
    expect(tester.getSemantics(header), isSemantics(isHeader: true));
  });

  testWidgets('BS-W01 chip all: at most 5 bus stops; none under 3 letters', (
    tester,
  ) async {
    await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
    await typeQuery(tester, 'cho');
    expect(_titles(tester, 'bus-stop-'), hasLength(5));
    await typeQuery(tester, 'ch');
    expect(_titles(tester, 'bus-stop-'), isEmpty);
    expect(find.byKey(const ValueKey('bus-stop-section')), findsNothing);
  });

  testWidgets('"trạm buýt …" lists bus stops above the stations', (
    tester,
  ) async {
    await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
    await typeQuery(tester, 'tram buyt kim ma');
    final stop = find.byKey(const ValueKey('bus-stop-osm:n4'));
    expect(stop, findsOneWidget);
    final stations = _titles(tester, 'station-');
    if (stations.isNotEmpty) {
      expect(
        tester.getTopLeft(stop).dy,
        lessThan(tester.getTopLeft(find.text(stations.first).first).dy),
      );
    }
  });

  testWidgets('BS-W02 chip "Trạm buýt": select → 500 m, bus glyph, badge', (
    tester,
  ) async {
    final h = await pumpDestination(
      tester,
      busStopCatalog: () async => kFakeBusStops,
    );
    await _chip(tester, 'Trạm buýt');
    await typeQuery(tester, 'cho');
    expect(_titles(tester, 'station-'), isEmpty);
    expect(_titles(tester, 'bus-stop-'), hasLength(20));
    expect(find.text(_osm), findsOneWidget);
    final before = h.map.last.cameraRequestId;
    await typeQuery(tester, 'bach khoa');
    await tapVisible(tester, find.byKey(const ValueKey('bus-stop-osm:n1')));
    final props = h.map.last;
    expect(props.busStop, isTrue);
    expect(props.radiusM, 500);
    expect(props.cameraRequestId, before + 1);
    expect(props.point, const MapPoint(21.00512, 105.84321));
    expect(find.text('Báo trong vòng 500 m'), findsOneWidget);
    expect(find.text('Chọn Đại học Bách khoa'), findsOneWidget);
    expect(
      destinationMapState(props, dark: false).glyph,
      MapPinGlyph.bus,
      reason: 'iOS map gets the bus glyph',
    );
    final row = tester.widget<NapListRow>(
      find.descendant(
        of: find.byKey(const ValueKey('bus-stop-osm:n1')),
        matching: find.byType(NapListRow),
      ),
    );
    expect(row.selected, isTrue);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bus-stop-osm:n2')),
        matching: find.byIcon(Icons.check),
      ),
      findsNothing,
      reason: 'same name, other stop',
    );
    expect(find.text('Trạm buýt · Hà Nội · tuyến 03, 14'), findsOneWidget);
  });

  testWidgets('BS-W03 station 1 km → bus stop 500 m → station 1 km', (
    tester,
  ) async {
    final h = await pumpDestination(
      tester,
      busStopCatalog: () async => kFakeBusStops,
    );
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    expect(h.map.last.radiusM, 1000);
    expect(h.map.last.busStop, isFalse);
    expect(destinationMapState(h.map.last, dark: false).glyph, isNull);
    await typeQuery(tester, 'kim ma');
    await tapVisible(tester, find.byKey(const ValueKey('bus-stop-osm:n4')));
    expect(h.map.last.radiusM, 500);
    expect(h.map.last.busStop, isTrue);
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    expect(h.map.last.radiusM, 1000);
    expect(h.map.last.busStop, isFalse);
    expect(find.text('Báo trong vòng 1 km'), findsOneWidget);
  });

  testWidgets('BS-W04 Android (no map): chip and section work, no glyph', (
    tester,
  ) async {
    final h = await pumpDestination(
      tester,
      withMap: false,
      busStopCatalog: () async => kFakeBusStops,
    );
    expect(find.widgetWithText(NapChip, 'Trạm buýt'), findsOneWidget);
    await _chip(tester, 'Trạm buýt');
    await typeQuery(tester, 'kim ma');
    await tapVisible(tester, find.byKey(const ValueKey('bus-stop-osm:n4')));
    expect(h.map.builds, isEmpty);
    expect(find.text('Chọn Kim Mã'), findsOneWidget);
    expect(find.text('Báo trong vòng 500 m'), findsNothing);
    await tapVisible(tester, find.text('Chọn Kim Mã'));
    final draft = h.app.extra! as TripDraft;
    expect(draft.destination.kind, DestinationKind.bus);
    expect(draft.vehicleHint, VehicleKindMsg.bus);
  });

  for (final dark in [false, true]) {
    testWidgets('BS-W05 320×568, text 2.0, dark: $dark — no overflow', (
      tester,
    ) async {
      await pumpDestination(
        tester,
        textScale: 2,
        theme: dark ? NapThemeKind.dark : NapThemeKind.light,
        busStopCatalog: () async => kFakeBusStops,
      );
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      await _chip(tester, 'Trạm buýt');
      expect(tester.takeException(), isNull);
      await typeQuery(tester, 'kim ma');
      expect(tester.takeException(), isNull);
      await _chip(tester, 'Tất cả');
      await typeQuery(tester, 'bach khoa');
      expect(tester.takeException(), isNull);
      expect(find.text('Trạm buýt'), findsWidgets);
    });
  }

  testWidgets('BS-W01 with T23.5: stations → bus stops → Apple addresses', (
    tester,
  ) async {
    final client = FakeAddressClient();
    await pumpDestination(
      tester,
      busStopCatalog: () async => kFakeBusStops,
      overrides: [addressSearchClientProvider.overrideWithValue(client)],
    );
    await tester.enterText(find.byType(TextField), 'kim ma');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    final last = client.completes.last;
    last.done.complete(
      CompleteReply(
        gen: last.gen,
        status: AddressStatus.ok,
        items: const [
          AddressSuggestion(title: 'Phố Kim Mã', subtitle: 'Ba Đình, Hà Nội'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    final stations = _titles(tester, 'station-');
    expect(stations, isNotEmpty);
    double y(Finder f) => tester.getTopLeft(f).dy;
    final stationY = y(find.text(stations.last).first);
    final busHeaderY = y(find.text('Trạm buýt').last);
    final osmY = y(find.text(_osm));
    final addressHeaderY = y(find.text('Địa chỉ · Apple Maps'));
    expect(stationY, lessThan(busHeaderY));
    expect(busHeaderY, lessThan(osmY));
    expect(osmY, lessThan(addressHeaderY));
    expect(find.text(_osm), findsOneWidget);
    expect(find.byKey(const ValueKey('address-0')), findsOneWidget);
  });

  group('review #1: "no station" lines and bus stops', () {
    const noStation = 'Không có ga, bến xe nào khớp "bach khoa".';
    const pinHint =
        'Không có trong danh sách? Nhấn giữ trên bản đồ để ghim điểm đến.';

    testWidgets('bus stops match: no "no station" / pin lines', (tester) async {
      await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
      await typeQuery(tester, 'bach khoa');
      expect(_titles(tester, 'station-'), isEmpty);
      expect(_titles(tester, 'bus-stop-'), hasLength(3));
      expect(find.text(noStation), findsNothing);
      expect(find.text(pinHint), findsNothing);
      expect(find.text(_osm), findsOneWidget);
    });

    testWidgets('bus stops still loading: no "no station" line either', (
      tester,
    ) async {
      final load = Completer<StationCatalog>();
      await pumpDestination(tester, busStopCatalog: () => load.future);
      await tester.enterText(find.byType(TextField), 'bach khoa');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Đang tải trạm buýt…'), findsOneWidget);
      expect(find.text(noStation), findsNothing);
      load.complete(kFakeBusStops);
      await tester.pumpAndSettle();
    });

    testWidgets('nothing matches at all: both lines, no bus section', (
      tester,
    ) async {
      await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
      await typeQuery(tester, 'xyzq');
      expect(find.text('Không có ga, bến xe nào khớp "xyzq".'), findsOneWidget);
      expect(find.text(pinHint), findsOneWidget);
      expect(find.byKey(const ValueKey('bus-stop-section')), findsNothing);
      expect(find.text(_osm), findsNothing);
    });
  });

  group('BS-W06 section states', () {
    testWidgets('loading, then rows', (tester) async {
      final load = Completer<StationCatalog>();
      await pumpDestination(tester, busStopCatalog: () => load.future);
      await _chip(tester, 'Trạm buýt');
      await tester.enterText(find.byType(TextField), 'kim');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Đang tải trạm buýt…'), findsOneWidget);
      load.complete(kFakeBusStops);
      await tester.pumpAndSettle();
      expect(find.text('Đang tải trạm buýt…'), findsNothing);
      expect(_titles(tester, 'bus-stop-'), ['Kim Mã']);
    });

    testWidgets('start typing, empty', (tester) async {
      await pumpDestination(tester, busStopCatalog: () async => kFakeBusStops);
      await _chip(tester, 'Trạm buýt');
      expect(find.text('Gõ tên ga, bến xe hoặc trạm buýt.'), findsOneWidget);
      await typeQuery(tester, 'xyzq');
      expect(find.text('Không có trạm buýt nào khớp "xyzq".'), findsOneWidget);
      expect(find.text(_osm), findsNothing);
    });

    testWidgets('error with retry on the chip; hidden on chip all', (
      tester,
    ) async {
      var calls = 0;
      await pumpDestination(
        tester,
        busStopCatalog: () async {
          calls++;
          if (calls == 1) {
            throw const StationDataException('missing');
          }
          return kFakeBusStops;
        },
      );
      await typeQuery(tester, 'kim ma');
      expect(find.byKey(const ValueKey('bus-stop-section')), findsNothing);
      expect(_titles(tester, 'station-'), isNotEmpty);
      await _chip(tester, 'Trạm buýt');
      // The chip tap itself retried (D10).
      expect(calls, 2);
      expect(_titles(tester, 'bus-stop-'), ['Kim Mã']);
    });

    testWidgets('error banner and "Thử lại"', (tester) async {
      var calls = 0;
      await pumpDestination(
        tester,
        busStopCatalog: () async {
          calls++;
          if (calls == 1) {
            throw const StationDataException('missing');
          }
          return kFakeBusStops;
        },
      );
      await _chip(tester, 'Trạm buýt');
      await typeQuery(tester, 'kim ma');
      expect(find.text('Không tải được danh sách trạm buýt.'), findsOneWidget);
      await tapVisible(tester, find.text('Thử lại'));
      expect(calls, 2);
      expect(_titles(tester, 'bus-stop-'), ['Kim Mã']);
    });
  });
}
