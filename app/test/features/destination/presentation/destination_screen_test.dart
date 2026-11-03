// T23 TW01–TW24: screen 2 "Chọn điểm đến" in the whole app (router,
// providers), with a fake bridge, a fake map and Places over MockClient.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/data/saved_places_repository.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/destination/presentation/widgets/map_unavailable_placeholder.dart';
import 'package:napstop/features/destination/presentation/widgets/osm_attribution.dart';
import 'package:napstop/features/destination/presentation/widgets/result_row.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_station_catalog.dart';
import '../../../helpers/trip_fixtures.dart';
import 'destination_harness.dart';

Station station(String name) =>
    kTestStationCatalog.dataset.stations.firstWhere((s) => s.name == name);

final Station gaDongHoi = station('Ga Đồng Hới');

const String kPlacesEntryDongHoi = 'Tìm "dong hoi" bằng Google Maps';
const String kOsm = 'Dữ liệu ga/bến © OpenStreetMap contributors';

Finder rowTitled(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(NapListRow));

/// Station row titles in display order.
List<String> stationTitles(WidgetTester tester) => [
  for (final row in tester.widgetList<ResultRow>(find.byType(ResultRow)))
    if ((row.key! as ValueKey<String>).value.startsWith('station-')) row.title,
];

/// Feeds [text] to the field of screen 2 while it is hidden or exiting.
void lateKeystroke(WidgetTester tester, String text) {
  final field = find.descendant(
    of: find.byType(DestinationScreen, skipOffstage: false),
    matching: find.byType(TextField, skipOffstage: false),
  );
  expect(field, findsOneWidget, reason: 'screen 2 still in the tree');
  tester.widget<TextField>(field).onChanged!(text);
}

Future<void> selectDongHoi(WidgetTester tester) async {
  await typeQuery(tester, 'dong hoi');
  await tapVisible(tester, find.text('Ga Đồng Hới').first);
}

void main() {
  testWidgets('TW01 "dong hoi": Ga Đồng Hới first, Places entry, OSM', (
    tester,
  ) async {
    await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    final titles = stationTitles(tester);
    expect(titles.first, 'Ga Đồng Hới');
    expect(find.text('Ga tàu · Quảng Trị'), findsOneWidget);
    expect(find.text(kPlacesEntryDongHoi), findsOneWidget);
    expect(find.text(kOsm), findsOneWidget);
    // The Places entry is the last row, after every station row.
    final entryY = tester.getTopLeft(find.text(kPlacesEntryDongHoi)).dy;
    final lastStationY = tester.getTopLeft(find.text(titles.last).last).dy;
    expect(entryY, greaterThan(lastStationY));
  });

  testWidgets('TW02 distances shown from the native answer', (tester) async {
    final bridge = FakeCoreBridge(mapsConfig: MapsConfigMsg(apiKey: 'test-key'))
      ..distances = (pairs) => [
        for (var i = 0; i < pairs.length ~/ 2; i++) 402000,
      ];
    final h = await pumpDestination(tester, bridge: bridge);
    await typeQuery(tester, 'dong hoi');
    expect(find.text('Ga tàu · Quảng Trị · cách 402 km'), findsOneWidget);
    expect(h.bridge.distancesCalls, hasLength(1));
    final call = h.bridge.distancesCalls.single;
    expect(call.maxAgeMs, 1800000);
    expect(call.pairs.take(2), [gaDongHoi.lat, gaDongHoi.lng]);
    expect(call.pairs.length, 2 * stationTitles(tester).length);
  });

  testWidgets('TW03 no position: no distance, no new call within 30 s', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    await typeQuery(tester, 'dong h');
    expect(find.textContaining('cách'), findsNothing);
    expect(h.bridge.distancesCalls, hasLength(1));
  });

  testWidgets('TW04 no match: message and Places entry', (tester) async {
    await pumpDestination(tester);
    await typeQuery(tester, 'zzqx');
    expect(find.text('Không có ga, bến xe nào khớp "zzqx".'), findsOneWidget);
    expect(find.text('Tìm "zzqx" bằng Google Maps'), findsOneWidget);
    expect(find.text(kOsm), findsNothing);
  });

  testWidgets('TW05 empty and 1-letter query: Places entry, no station', (
    tester,
  ) async {
    await pumpDestination(tester);
    expect(find.text('Tìm địa chỉ bằng Google Maps'), findsOneWidget);
    expect(find.text('Gõ tên ga, bến xe hoặc địa chỉ.'), findsOneWidget);
    await typeQuery(tester, 'x');
    expect(find.text('Tìm "x" bằng Google Maps'), findsOneWidget);
    expect(stationTitles(tester), isEmpty);
  });

  testWidgets('TW06 catalog error, retry', (tester) async {
    var attempts = 0;
    await pumpDestination(
      tester,
      stationCatalog: () async {
        attempts++;
        if (attempts == 1) {
          throw const StationDataException('broken');
        }
        return kTestStationCatalog;
      },
    );
    expect(
      find.text(
        'Không tải được danh sách ga, bến xe. Bạn vẫn tìm được địa chỉ qua '
        'Google Maps.',
      ),
      findsOneWidget,
    );
    expect(find.text('Tìm địa chỉ bằng Google Maps'), findsOneWidget);
    await typeQuery(tester, 'dong hoi');
    expect(find.text(kPlacesEntryDongHoi), findsOneWidget);
    await tapVisible(tester, find.text('Thử lại'));
    expect(attempts, 2);
    expect(stationTitles(tester).first, 'Ga Đồng Hới');
  });

  testWidgets('TW07 tapping a row selects it and frames the map', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    final before = h.map.last.cameraRequestId;
    await selectDongHoi(tester);
    final row = tester.widget<NapListRow>(rowTitled('Ga Đồng Hới').first);
    expect(row.selected, isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(h.map.last.point, MapPoint(gaDongHoi.lat, gaDongHoi.lng));
    expect(h.map.last.radiusM, 1000);
    expect(h.map.last.cameraRequestId, before + 1);
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Báo trong vòng 1 km'), findsOneWidget);
  });

  testWidgets('TW08 confirm opens screen 3 with the draft', (tester) async {
    final h = await pumpDestination(tester);
    await selectDongHoi(tester);
    await tapVisible(tester, find.text('Chọn Ga Đồng Hới'));
    expect(h.app.location, AppRoutes.alarmSettings);
    final draft = h.app.extra! as TripDraft;
    expect(draft.destination, TripDestination.fromStation(gaDongHoi));
    expect(draft.source, DestinationSource.station);
    expect(draft.alarm, isNull);
    expect(draft.vehicleHint, VehicleKindMsg.train);
    // Back from screen 3 keeps the choice.
    h.app.router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
  });

  testWidgets('TW09 pick mode returns the destination; Back returns null', (
    tester,
  ) async {
    final h = await pumpDestination(tester, open: false);
    var result = homeContext(tester).pickDestination();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Lưu điểm này'), findsNothing);
    await selectDongHoi(tester);
    await tapVisible(tester, find.text('Chọn Ga Đồng Hới'));
    expect(await result, TripDestination.fromStation(gaDongHoi));
    expect(h.app.location, AppRoutes.home);

    result = homeContext(tester).pickDestination();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(await result, isNull);
  });

  testWidgets('TW10 nothing chosen: buttons disabled', (tester) async {
    await pumpDestination(tester);
    final confirm = find.ancestor(
      of: find.text('Chọn điểm đến'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    final save = find.ancestor(
      of: find.byIcon(Icons.bookmark_border),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(save).onPressed, isNull);
    expect(
      tester.getSemantics(confirm),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
  });

  testWidgets('TW11 long press drops a pin', (tester) async {
    final h = await pumpDestination(tester);
    h.map.last.onLongPress(const MapPoint(16.5, 107.5));
    await tester.pumpAndSettle();
    expect(find.text('Chọn Điểm đã ghim'), findsOneWidget);
    expect(h.map.last.point, const MapPoint(16.5, 107.5));
    await tapVisible(tester, find.text('Chọn Điểm đã ghim'));
    final draft = h.app.extra! as TripDraft;
    expect(draft.source, DestinationSource.mapPin);
    expect(draft.destination.kind, DestinationKind.pin);
    expect(draft.vehicleHint, VehicleKindMsg.unknown);
  });

  testWidgets('TW12 drag the pin, undo', (tester) async {
    final h = await pumpDestination(tester);
    await selectDongHoi(tester);
    const mPerDeg = 111195.08;
    final p300 = MapPoint(gaDongHoi.lat + 300 / mPerDeg, gaDongHoi.lng);
    h.map.last.onPinDragEnd(p300);
    await tester.pumpAndSettle();
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
    expect(h.map.last.point, p300);
    expect(find.text('Đã dời ghim 300 m.'), findsOneWidget);

    final p1200 = MapPoint(gaDongHoi.lat + 1200 / mPerDeg, gaDongHoi.lng);
    h.map.last.onPinDragEnd(p1200);
    await tester.pumpAndSettle();
    expect(find.text('Chọn Điểm đã ghim'), findsOneWidget);
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
    expect(h.map.last.point, p300);
  });

  testWidgets('TW13 no key: placeholder, choosing still works', (tester) async {
    final h = await pumpDestination(tester, mapsKey: null);
    expect(find.byType(MapUnavailablePlaceholder), findsOneWidget);
    expect(find.text('Bản đồ chưa sẵn sàng trong bản này.'), findsOneWidget);
    expect(h.map.builds, isEmpty);
    await selectDongHoi(tester);
    expect(find.text('Báo trong vòng 1 km'), findsNothing);
    await tapVisible(tester, find.text('Chọn Ga Đồng Hới'));
    expect(h.app.location, AppRoutes.alarmSettings);
  });

  testWidgets('TW14 Places entry: disclosure, suggestions, Google Maps', (
    tester,
  ) async {
    await pumpDestination(tester, locale: const Locale('en'));
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Search "duc long" with Google Maps'));
    expect(
      find.text(
        'What you type is sent to Google to find addresses. Your location is '
        'not sent.',
      ),
      findsOneWidget,
    );
    expect(find.text('Bến xe Đức Long'), findsOneWidget);
    expect(find.text('Đức Long Gia Lai'), findsOneWidget);
    expect(find.text('Google Maps'), findsOneWidget);
    expect(
      tester.widget<NapChip>(find.widgetWithText(NapChip, 'Address')).selected,
      isTrue,
    );
  });

  testWidgets('round 2 #2: Places entry shows "searching" at once', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    final entry = find.text(kPlacesEntryDongHoi);
    await tester.ensureVisible(entry);
    await tester.pumpAndSettle();
    await tester.tap(entry);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Đang tìm địa chỉ…'), findsOneWidget);
    expect(find.text('Gõ ít nhất 3 ký tự để tìm địa chỉ.'), findsNothing);
    expect(h.places.requests, isEmpty);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.places.autocompleteCount, 1);
  });

  testWidgets('round 3 B1: system Back inside the debounce sends nothing', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await tapVisible(tester, find.text('Tìm địa chỉ bằng Google Maps'));
    await tester.enterText(find.byType(TextField), 'ben xe duc');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.home);
    expect(h.places.requests, isEmpty);
  });

  testWidgets('round 3 B1: "Chọn …" inside the debounce, then Back resumes', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await selectDongHoi(tester);
    // Empty query first, so entering the chip does not search yet.
    await tester.tap(find.byTooltip('Xoá nội dung tìm'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Địa chỉ'));
    expect(h.places.requests, isEmpty);
    await tester.enterText(find.byType(TextField), 'ben xe duc');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Chọn Ga Đồng Hới'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
    expect(h.places.requests, isEmpty);

    // Back on screen 2: the search that was cut short runs again.
    h.app.router.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.places.autocompleteCount, 1);
    expect(find.text('Bến xe Đức Long'), findsOneWidget);
  });

  testWidgets('round 4 B2: late keystroke under screen 3 sends nothing', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await selectDongHoi(tester);
    await tester.tap(find.byTooltip('Xoá nội dung tìm'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Địa chỉ'));
    await tester.enterText(find.byType(TextField), 'ben xe du');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Chọn Ga Đồng Hới'));
    await tester.pump(const Duration(milliseconds: 16));
    // The keystroke typed just before leaving reaches screen 2's field late.
    lateKeystroke(tester, 'ben xe duc');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
    expect(h.places.requests, isEmpty);

    h.app.router.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.places.autocompleteCount, 1);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.places.autocompleteCount, 1);
  });

  testWidgets('round 4 B2: late keystroke after system Back sends nothing', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await tapVisible(tester, find.text('Tìm địa chỉ bằng Google Maps'));
    await tester.enterText(find.byType(TextField), 'ben xe du');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 16));
    // The keystroke typed just before leaving reaches screen 2's field late.
    lateKeystroke(tester, 'ben xe duc');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.home);
    expect(h.places.requests, isEmpty);
  });

  Future<void> backThenReopen(WidgetTester tester, DestinationHarness h) async {
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pump(const Duration(milliseconds: 100));
    // The old screen 2 still plays its exit animation.
    expect(find.byType(TextField, skipOffstage: false), findsWidgets);
    unawaited(h.app.router.push(AppRoutes.destination));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.destination);
  }

  void expectEmptyScreen(WidgetTester tester) {
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    expect(find.text('Gõ tên ga, bến xe hoặc địa chỉ.'), findsOneWidget);
    expect(find.text('Tìm địa chỉ bằng Google Maps'), findsOneWidget);
    expect(stationTitles(tester), isEmpty);
    expect(find.text('Chọn Ga Đồng Hới'), findsNothing);
    final confirm = find.ancestor(
      of: find.text('Chọn điểm đến'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(
      tester.widget<NapChip>(find.widgetWithText(NapChip, 'Tất cả')).selected,
      isTrue,
    );
  }

  testWidgets('round 5 #12: reopen while exiting after a choice is empty', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await selectDongHoi(tester);
    await backThenReopen(tester, h);
    expectEmptyScreen(tester);
    expect(h.places.requests, isEmpty);
  });

  testWidgets('round 5 #12: reopen while exiting the Address chip is empty', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await tapVisible(tester, find.text('Tìm địa chỉ bằng Google Maps'));
    await tester.enterText(find.byType(TextField), 'ben xe duc');
    await tester.pump(const Duration(milliseconds: 100));
    await backThenReopen(tester, h);
    expectEmptyScreen(tester);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.places.requests, isEmpty);
  });

  testWidgets('round 5 #14: a double tap on "Chọn …" opens screen 3 once', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await selectDongHoi(tester);
    final confirm = find.text('Chọn Ga Đồng Hới');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
    h.app.router.pop();
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.destination);
    // And "Chọn …" works again after coming back.
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
  });

  testWidgets('TW15 choosing a suggestion', (tester) async {
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    await tapVisible(tester, find.text('Bến xe Đức Long'));
    expect(h.map.last.point, const MapPoint(13.9833, 108));
    await tapVisible(tester, find.text('Chọn Bến xe Đức Long'));
    final draft = h.app.extra! as TripDraft;
    expect(draft.source, DestinationSource.places);
    expect(draft.destination.kind, DestinationKind.address);
    expect(draft.destination.detail, 'Gia Lai, Việt Nam');
    expect(draft.destination.lat, 13.9833);
  });

  testWidgets('TW16 location failure: snack bar, list stays', (tester) async {
    final h = await pumpDestination(tester);
    h.places.detailsError = const SocketException('offline');
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    await tapVisible(tester, find.text('Bến xe Đức Long'));
    expect(
      find.text('Không lấy được vị trí của địa chỉ này. Thử lại.'),
      findsOneWidget,
    );
    expect(find.text('Đức Long Gia Lai'), findsOneWidget);
    expect(find.text('Chọn điểm đến'), findsOneWidget);
  });

  testWidgets('TW17 Places errors; offline search still works', (tester) async {
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'duc long');
    h.places.autocompleteError = const SocketException('offline');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    expect(
      find.text('Không có mạng. Tìm ga, bến xe vẫn dùng được.'),
      findsOneWidget,
    );
    h.places
      ..autocompleteError = null
      ..autocompleteStatus = 403;
    await typeQuery(tester, 'duc long 1');
    expect(find.text('Tìm địa chỉ tạm thời không dùng được.'), findsOneWidget);
    h.places.autocompleteStatus = 429;
    await typeQuery(tester, 'duc long 2');
    expect(find.text('Tìm địa chỉ tạm thời không dùng được.'), findsOneWidget);

    await tapVisible(tester, find.text('Tất cả'));
    await typeQuery(tester, 'dong hoi');
    expect(stationTitles(tester).first, 'Ga Đồng Hới');
  });

  testWidgets('TW18 no key: Places not configured, no request', (tester) async {
    final h = await pumpDestination(tester, mapsKey: null);
    await tapVisible(tester, find.text('Tìm địa chỉ bằng Google Maps'));
    await typeQuery(tester, 'duc long');
    expect(find.text('Bản này chưa bật tìm địa chỉ.'), findsOneWidget);
    expect(h.places.requests, isEmpty);
  });

  testWidgets('TW19 typing in "Tất cả" never calls Places', (tester) async {
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    await typeQuery(tester, 'ben xe duc long');
    expect(h.places.requests, isEmpty);
  });

  testWidgets('TW20 save into a slot', (tester) async {
    final h = await pumpDestination(
      tester,
      seed: (c) => c
          .read(savedPlacesRepositoryProvider)
          .upsert(SavedPlaceSlot.home, kGaHue),
    );
    await selectDongHoi(tester);
    await tester.tap(find.byTooltip('Lưu điểm này'));
    await tester.pumpAndSettle();
    expect(find.text('Lưu vào'), findsOneWidget);
    expect(find.text('Đang là: Ga Huế'), findsOneWidget);
    expect(find.text('Chưa đặt'), findsNWidgets(2));
    await tester.tap(find.text('Nhà'));
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu vào Nhà'), findsOneWidget);
    final saved = await h.app
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.home);
    expect(saved?.destination, TripDestination.fromStation(gaDongHoi));
  });

  testWidgets('TW20 save failure', (tester) async {
    await pumpDestination(
      tester,
      overrides: [
        savedPlacesRepositoryProvider.overrideWithValue(_FailingRepo()),
      ],
    );
    await selectDongHoi(tester);
    await tester.tap(find.byTooltip('Lưu điểm này'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quê'));
    await tester.pumpAndSettle();
    expect(find.text('Không lưu được. Thử lại sau.'), findsOneWidget);
  });

  testWidgets('TW21 chips filter the kinds', (tester) async {
    await pumpDestination(tester);
    await tapVisible(tester, find.text('Ga tàu'));
    await typeQuery(tester, 'dong hoi');
    final trains = stationTitles(tester);
    expect(trains, isNotEmpty);
    for (final t in trains) {
      expect(t.startsWith('Ga '), isTrue, reason: t);
    }
    await tapVisible(tester, find.text('Bến xe'));
    await typeQuery(tester, 'nha trang');
    expect(stationTitles(tester).take(2).toSet(), {
      'Bến Xe Bắc Nha Trang',
      'Bến xe liên tỉnh phía Nam Nha Trang',
    });
  });

  testWidgets('TW22 OSM line opens the copyright page', (tester) async {
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    await tapVisible(tester, find.text(kOsm));
    expect(h.launcher.opened, [kOsmCopyrightUri]);
    expect(
      kOsmCopyrightUri.toString(),
      'https://www.openstreetmap.org/copyright',
    );
    h.launcher.result = false;
    await tapVisible(tester, find.text(kOsm));
    expect(h.launcher.opened, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('TW23 typing keeps the selection', (tester) async {
    await pumpDestination(tester);
    await selectDongHoi(tester);
    await typeQuery(tester, 'vinh');
    expect(find.text('Chọn Ga Đồng Hới'), findsOneWidget);
  });

  testWidgets(
    'TW24 destination_selected event',
    (tester) async {},
    skip: true, // T29 (telemetry) is not merged yet: no event to check (D11).
  );
}

class _FailingRepo implements SavedPlacesRepository {
  @override
  Stream<Map<SavedPlaceSlot, SavedPlace>> watchAll() => Stream.value(const {});

  @override
  Future<SavedPlace?> get(SavedPlaceSlot slot) async => null;

  @override
  Future<void> upsert(SavedPlaceSlot slot, TripDestination destination) =>
      Future.error(StateError('disk full'));

  @override
  Future<void> restore(SavedPlace place) => Future.error(StateError('x'));

  @override
  Future<void> remove(SavedPlaceSlot slot) => Future.error(StateError('x'));
}
