// T23 TW01–TW24, T23.2 RW01–RW07: screen 2 "Chọn điểm đến" in the whole app
// (router, providers), with a fake bridge and a fake map (offline search only).
import 'dart:async';

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
  testWidgets('TW01 "dong hoi": Ga Đồng Hới first, OSM last', (tester) async {
    await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    final titles = stationTitles(tester);
    expect(titles.first, 'Ga Đồng Hới');
    expect(find.text('Ga tàu · Quảng Trị'), findsOneWidget);
    expect(find.text(kOsm), findsOneWidget);
    // The attribution follows every station row; no row after the stations
    // (the Places entry is gone, T23.2).
    final osmY = tester.getTopLeft(find.text(kOsm)).dy;
    final lastStationY = tester.getTopLeft(find.text(titles.last).last).dy;
    expect(osmY, greaterThan(lastStationY));
    expect(find.byType(NapListRow), findsNWidgets(titles.length));
  });

  testWidgets('RW01 three chips, no address chip', (tester) async {
    await pumpDestination(tester);
    final chips = tester.widgetList<NapChip>(find.byType(NapChip));
    expect(chips.map((c) => c.label), ['Tất cả', 'Ga tàu', 'Bến xe']);
  });

  testWidgets('TW02 distances shown from the native answer', (tester) async {
    final bridge = FakeCoreBridge()
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

  testWidgets('TW04 no match: message, nothing else', (tester) async {
    await pumpDestination(tester);
    await typeQuery(tester, 'zzqx');
    expect(find.text('Không có ga, bến xe nào khớp "zzqx".'), findsOneWidget);
    expect(find.byType(NapListRow), findsNothing);
    expect(find.text(kOsm), findsNothing);
  });

  testWidgets('TW05 empty and 1-letter query: hint, no station', (
    tester,
  ) async {
    await pumpDestination(tester);
    expect(find.text('Gõ tên ga hoặc bến xe.'), findsOneWidget);
    await typeQuery(tester, 'x');
    expect(find.text('Gõ tên ga hoặc bến xe.'), findsOneWidget);
    expect(stationTitles(tester), isEmpty);
    expect(find.byType(NapListRow), findsNothing);
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
    expect(find.text('Không tải được danh sách ga, bến xe.'), findsOneWidget);
    await typeQuery(tester, 'dong hoi');
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

  testWidgets('TW13/RW03 no map builder: placeholder, choosing still works', (
    tester,
  ) async {
    final h = await pumpDestination(tester, withMap: false);
    expect(find.byType(MapUnavailablePlaceholder), findsOneWidget);
    expect(find.text('Bản đồ chưa có trong bản này.'), findsOneWidget);
    expect(h.map.builds, isEmpty);
    await selectDongHoi(tester);
    expect(find.text('Báo trong vòng 1 km'), findsNothing);
    expect(
      find.text('Nhấn giữ trên bản đồ để ghim, kéo ghim để chỉnh.'),
      findsNothing,
    );
    final confirm = find.ancestor(
      of: find.text('Chọn Ga Đồng Hới'),
      matching: find.byType(FilledButton),
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tapVisible(tester, find.text('Chọn Ga Đồng Hới'));
    expect(h.app.location, AppRoutes.alarmSettings);
    final draft = h.app.extra! as TripDraft;
    expect(draft.destination, TripDestination.fromStation(gaDongHoi));
  });

  testWidgets('RW02 no Google, no address, no Places row in any state', (
    tester,
  ) async {
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
    final forbidden = RegExp('google|địa chỉ|address', caseSensitive: false);
    void expectClean(String state) {
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final text = t.data ?? t.textSpan?.toPlainText() ?? '';
        expect(forbidden.hasMatch(text), isFalse, reason: '$state: <$text>');
      }
      // The search field has its own icon; no row may carry one (Places row).
      expect(
        find.descendant(
          of: find.byType(NapListRow),
          matching: find.byIcon(NapIcons.search),
        ),
        findsNothing,
        reason: state,
      );
    }

    expectClean('catalog error');
    await tapVisible(tester, find.text('Thử lại'));
    expect(attempts, 2);
    expectClean('empty query');
    await typeQuery(tester, 'dong hoi');
    expect(stationTitles(tester), isNotEmpty);
    expectClean('rows');
    await typeQuery(tester, 'zzzz');
    expect(stationTitles(tester), isEmpty);
    expectClean('no match');
  });

  testWidgets(
    'RW06 system Back inside the distance debounce measures nothing',
    (tester) async {
      final h = await pumpDestination(tester);
      await tester.enterText(find.byType(TextField), 'vinh');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.binding.handlePopRoute();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(h.app.location, AppRoutes.home);
      expect(h.bridge.distancesCalls, isEmpty);
    },
  );

  /// A bridge that always knows the distance, so no 30 s block hides a call.
  FakeCoreBridge measuring() => FakeCoreBridge()
    ..distances = (pairs) => [for (var i = 0; i < pairs.length ~/ 2; i++) 5000];

  testWidgets('round 3 B1: "Chọn …" inside the debounce, then Back resumes', (
    tester,
  ) async {
    final h = await pumpDestination(tester, bridge: measuring());
    await selectDongHoi(tester);
    final before = h.bridge.distancesCalls.length;
    await tester.enterText(find.byType(TextField), 'vinh');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Chọn Ga Đồng Hới'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
    expect(h.bridge.distancesCalls, hasLength(before));

    // Back on screen 2: the measure that was cut short runs again.
    h.app.router.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.bridge.distancesCalls, hasLength(before + 1));
  });

  testWidgets('round 4 B2: late keystroke under screen 3 measures nothing', (
    tester,
  ) async {
    final h = await pumpDestination(tester, bridge: measuring());
    await selectDongHoi(tester);
    final before = h.bridge.distancesCalls.length;
    await tester.tap(find.text('Chọn Ga Đồng Hới'));
    await tester.pump(const Duration(milliseconds: 16));
    // A keystroke typed just before leaving reaches screen 2's field late.
    lateKeystroke(tester, 'vinh');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.alarmSettings);
    expect(h.bridge.distancesCalls, hasLength(before));

    h.app.router.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(h.bridge.distancesCalls, hasLength(before + 1));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(h.bridge.distancesCalls, hasLength(before + 1));
  });

  testWidgets('round 4 B2: late keystroke after system Back measures nothing', (
    tester,
  ) async {
    final h = await pumpDestination(tester, bridge: measuring());
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 16));
    // A keystroke typed just before leaving reaches screen 2's field late.
    lateKeystroke(tester, 'vinh');
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(h.app.location, AppRoutes.home);
    expect(h.bridge.distancesCalls, isEmpty);
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
    expect(find.text('Gõ tên ga hoặc bến xe.'), findsOneWidget);
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
  });

  testWidgets('round 5 #12: reopen while exiting another chip is empty', (
    tester,
  ) async {
    final h = await pumpDestination(tester);
    await tapVisible(tester, find.text('Ga tàu'));
    await tester.enterText(find.byType(TextField), 'vinh');
    await tester.pump(const Duration(milliseconds: 50));
    await backThenReopen(tester, h);
    expectEmptyScreen(tester);
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
