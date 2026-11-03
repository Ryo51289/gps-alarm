// W01-W13, W16-W18, W20-W22: screen 1 (T22 §9).
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/db/app_database.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/home/presentation/widgets/saved_place_tile.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/trip_fixtures.dart';

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _tile(SavedPlaceSlot slot) =>
    find.byWidgetPredicate((w) => w is SavedPlaceTile && w.slot == slot);

NapTone _badgeTone(WidgetTester tester, String label) => tester
    .widget<NapBadge>(
      find.byWidgetPredicate((w) => w is NapBadge && w.label == label),
    )
    .tone;

List<String> _badgeLabels(WidgetTester tester) => tester
    .widgetList<NapBadge>(find.byType(NapBadge))
    .map((b) => b.label)
    .toList();

void main() {
  testWidgets('W01 home with data', (tester) async {
    await pumpAppHarness(tester, seed: seedW01);
    expect(find.text('Chào buổi tối'), findsOneWidget);
    expect(find.text('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
    expect(find.text('Tìm ga, bến xe, địa chỉ…'), findsOneWidget);
    expect(
      find.descendant(
        of: _tile(SavedPlaceSlot.home),
        matching: find.text('Nhà'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tile(SavedPlaceSlot.home),
        matching: find.text(kHomeAddress.name),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tile(SavedPlaceSlot.hometown),
        matching: find.text(kHometown.name),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _tile(SavedPlaceSlot.work),
        matching: find.text('Thêm'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
    expect(find.text('Ga Huế'), findsOneWidget);
    expect(find.text('Tàu · Báo trước 15 phút'), findsNWidgets(2));
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    expect(_badgeLabels(tester), [
      'Vị trí: Khi dùng ứng dụng',
      'Pin 82%',
      'Âm lượng báo 100%',
    ]);
    expect(
      find.text('Nếu máy tự bật Chế độ ngủ, hãy cho phép Báo thức.'),
      findsOneWidget,
    );
    expect(find.text('Kiểm tra quyền'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('W02 search field opens screen 2, Back returns', (tester) async {
    final h = await pumpAppHarness(tester, seed: seedW01);
    await _tap(tester, find.text('Tìm ga, bến xe, địa chỉ…'));
    expect(h.location, AppRoutes.destination);
    expect(find.text('Chọn điểm đến'), findsOneWidget);
    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.home);
    expect(find.text('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
  });

  testWidgets('W03 one tap on a recent trip opens screen 3 prefilled', (
    tester,
  ) async {
    final h = await pumpAppHarness(
      tester,
      seed: (c) => seedData(c, trips: [sampleRecord(id: 'dh')]),
    );
    await _tap(tester, find.text('Ga Đồng Hới'));
    expect(h.location, AppRoutes.alarmSettings);
    expect(
      h.extra,
      const TripDraft(
        destination: kGaDongHoi,
        source: DestinationSource.recentTrip,
        alarm: kTime15,
        vehicleHint: VehicleKindMsg.train,
      ),
    );
    expect(find.text('Cài đặt báo thức'), findsOneWidget);
    expect(find.text('Ga Đồng Hới'), findsOneWidget);
    // T25: screen 3 shows the prefilled time threshold as its big value.
    expect(find.text('15 phút'), findsOneWidget);
    // PRD §4: tracking only starts when the user presses the start button.
    expect(h.bridge.callCount('startTrip'), 0);
  });

  testWidgets('W04 saved place opens screen 3 without alarm', (tester) async {
    final h = await pumpAppHarness(tester, seed: seedW01);
    await _tap(tester, _tile(SavedPlaceSlot.home));
    expect(h.location, AppRoutes.alarmSettings);
    final draft = h.extra! as TripDraft;
    expect(draft.source, DestinationSource.savedPlace);
    expect(draft.alarm, isNull);
    expect(draft.destination, kHomeAddress);
    expect(h.bridge.callCount('startTrip'), 0);
  });

  testWidgets('W05 empty slot picks a destination and saves it', (
    tester,
  ) async {
    TripDestination? next = kBenXeMyDinh;
    var picks = 0;
    final h = await pumpAppHarness(
      tester,
      overrides: [
        destinationPickerProvider.overrideWithValue((_) async {
          picks++;
          return next;
        }),
      ],
    );
    await _tap(tester, _tile(SavedPlaceSlot.work));
    expect(picks, 1);
    expect(h.location, AppRoutes.home);
    expect(
      find.descendant(
        of: _tile(SavedPlaceSlot.work),
        matching: find.text(kBenXeMyDinh.name),
      ),
      findsOneWidget,
    );
    final saved = await h
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.work);
    expect(saved?.destination, kBenXeMyDinh);
    expect(saved?.updatedAtMs, kHarnessNow.millisecondsSinceEpoch);

    // Backing out of the picker changes nothing.
    next = null;
    await _tap(tester, _tile(SavedPlaceSlot.hometown));
    expect(picks, 2);
    expect(
      await h.read(savedPlacesRepositoryProvider).get(SavedPlaceSlot.hometown),
      isNull,
    );
  });

  testWidgets('W06 long press: remove, undo, change', (tester) async {
    final h = await pumpAppHarness(
      tester,
      seed: seedW01,
      overrides: [
        destinationPickerProvider.overrideWithValue((_) async => kGaHue),
      ],
    );
    Finder homeName(String name) => find.descendant(
      of: _tile(SavedPlaceSlot.home),
      matching: find.text(name),
    );

    await tester.longPress(_tile(SavedPlaceSlot.home));
    await tester.pumpAndSettle();
    expect(find.text('Đổi địa điểm'), findsOneWidget);
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();
    expect(homeName('Thêm'), findsOneWidget);
    expect(find.text('Đã xoá Nhà'), findsOneWidget);

    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(homeName(kHomeAddress.name), findsOneWidget);
    final restored = await h
        .read(savedPlacesRepositoryProvider)
        .get(SavedPlaceSlot.home);
    expect(restored?.destination, kHomeAddress);

    await tester.longPress(_tile(SavedPlaceSlot.home));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi địa điểm'));
    await tester.pumpAndSettle();
    expect(homeName(kGaHue.name), findsOneWidget);
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W06b empty tiles have no long-press sheet', (tester) async {
    await pumpAppHarness(tester);
    await tester.longPress(_tile(SavedPlaceSlot.home));
    await tester.pumpAndSettle();
    expect(find.text('Đổi địa điểm'), findsNothing);
  });

  testWidgets('review #4: saved places loading: no tappable "Thêm"', (
    tester,
  ) async {
    final open = Completer<void>();
    final slow = AppDatabase(
      LazyDatabase(() async {
        await open.future;
        return NativeDatabase.memory();
      }),
    );
    var picks = 0;
    await pumpAppHarness(
      tester,
      db: slow,
      overrides: [
        destinationPickerProvider.overrideWithValue((_) async {
          picks++;
          return kGaHue;
        }),
      ],
    );
    expect(find.text('Thêm'), findsNothing);
    for (final slot in SavedPlaceSlot.values) {
      final tile = tester.widget<SavedPlaceTile>(_tile(slot));
      expect(tile.loading, isTrue);
      expect(tile.onTap, isNull);
    }
    final handle = tester.ensureSemantics();
    final semantics = tester.getSemantics(_tile(SavedPlaceSlot.home));
    expect(semantics.label, 'Nhà');
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
    handle.dispose();
    await tester.tap(_tile(SavedPlaceSlot.home));
    await tester.pumpAndSettle();
    expect(picks, 0);

    open.complete();
    await tester.pumpAndSettle();
    expect(find.text('Thêm'), findsNWidgets(3));
    await tester.tap(_tile(SavedPlaceSlot.home));
    await tester.pumpAndSettle();
    expect(picks, 1);
  });

  testWidgets('W07 empty database', (tester) async {
    await pumpAppHarness(tester);
    expect(find.text('Thêm'), findsNWidgets(3));
    expect(
      find.text('Chưa có chuyến nào. Tìm ga hoặc bến xe để bắt đầu.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('W08 location denied: blocked, opens screen 0, re-reads', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      permissions: androidPermissions(location: LocationAccessMsg.denied),
    );
    final h = await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Chưa thể bắt đầu chuyến đi'), findsOneWidget);
    expect(_badgeTone(tester, 'Vị trí: Chưa cho phép'), NapTone.danger);
    final reads = bridge.callCount('permissionStatus');
    await _tap(tester, find.text('Kiểm tra quyền'));
    expect(h.location, AppRoutes.onboarding);
    expect(find.text('Cấp quyền'), findsOneWidget);

    bridge.permissions = androidPermissions();
    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.home);
    expect(bridge.callCount('permissionStatus'), greaterThan(reads));
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
  });

  testWidgets('W09 Android warnings: chips in order, check permissions', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      permissions: androidPermissions(
        notifications: PermissionStateMsg.denied,
        exactAlarm: PermissionStateMsg.denied,
      ),
      deviceStatusValue: deviceStatusMsg(
        alarmMuted: true,
        interruptionFilter: InterruptionFilterMsg.none,
      ),
    );
    await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Nên kiểm tra trước khi ngủ'), findsOneWidget);
    expect(_badgeLabels(tester), [
      'Vị trí: Khi dùng ứng dụng',
      'Thông báo đang tắt',
      'Chưa cho báo thức chính xác',
      'Pin 82%',
      'Âm báo đang tắt',
      'Không làm phiền chặn báo thức',
    ]);
    expect(_badgeTone(tester, 'Âm báo đang tắt'), NapTone.danger);
    expect(find.text('Kiểm tra quyền'), findsOneWidget);
  });

  testWidgets('W09b DND total silence (T14.1 O1) alone: warns, no button', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      deviceStatusValue: deviceStatusMsg(
        alarmVolumePct: 0,
        alarmMuted: true,
        interruptionFilter: InterruptionFilterMsg.none,
      ),
    );
    await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Nên kiểm tra trước khi ngủ'), findsOneWidget);
    expect(_badgeTone(tester, 'Âm báo đang tắt'), NapTone.danger);
    expect(_badgeTone(tester, 'Không làm phiền chặn báo thức'), NapTone.danger);
    expect(find.text('Kiểm tra quyền'), findsNothing);
  });

  testWidgets('W10 battery optimization only: guide', (tester) async {
    final bridge = FakeCoreBridge(
      permissions: androidPermissions(
        batteryOptimizationIgnored: PermissionStateMsg.denied,
      ),
    );
    final h = await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    expect(_badgeTone(tester, 'Tối ưu pin đang bật'), NapTone.neutral);
    await _tap(tester, find.text('Xem hướng dẫn'));
    expect(h.location, AppRoutes.batteryGuide);
    expect(find.text('Tắt tối ưu pin'), findsOneWidget);
  });

  testWidgets('W11 resume re-reads permissions', (tester) async {
    final h = await pumpAppHarness(tester, seed: seedW01);
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    h.bridge.permissions = androidPermissions(
      location: LocationAccessMsg.denied,
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Chưa thể bắt đầu chuyến đi'), findsOneWidget);
  });

  testWidgets('W12 bridge error, then retry', (tester) async {
    final bridge = FakeCoreBridge()..permissionStatusError = channelError();
    await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Chưa kiểm tra được'), findsOneWidget);
    bridge.permissionStatusError = null;
    await _tap(tester, find.text('Thử lại'));
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('W12b deviceInfo error recovers on retry', (tester) async {
    final bridge = FakeCoreBridge()..deviceInfoError = channelError();
    await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Chưa kiểm tra được'), findsOneWidget);
    bridge.deviceInfoError = null;
    await _tap(tester, find.text('Thử lại'));
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
  });

  testWidgets('W13 running trip: card, busy snack bar, open, ended', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(active: activeTrip());
    final h = await pumpAppHarness(
      tester,
      bridge: bridge,
      seed: (c) => seedData(c, trips: [sampleRecord(id: 'dh')]),
    );
    expect(find.text('Đang theo dõi chuyến đi'), findsOneWidget);
    expect(find.text('Ga Huế'), findsOneWidget);

    await _tap(tester, find.text('Ga Đồng Hới'));
    expect(h.location, AppRoutes.home);
    expect(
      find.text('Đang có chuyến đi. Dừng chuyến đó trước khi đặt chuyến mới.'),
      findsOneWidget,
    );

    await _tap(tester, find.widgetWithText(NapButton, 'Mở'));
    expect(h.location, AppRoutes.tracking);

    h.router.go(AppRoutes.home);
    await tester.pumpAndSettle();
    expect(find.text('Đang theo dõi chuyến đi'), findsOneWidget);
    bridge.emit(tripEnded());
    await tester.pumpAndSettle();
    expect(find.text('Đang theo dõi chuyến đi'), findsNothing);
    expect(bridge.callCount('startTrip'), 0);
  });

  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    testWidgets('W16 a11y guidelines W01 (${theme.name})', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAppHarness(tester, seed: seedW01, theme: theme);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('W16 a11y guidelines W09 (${theme.name})', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAppHarness(
        tester,
        theme: theme,
        bridge: FakeCoreBridge(
          permissions: androidPermissions(
            notifications: PermissionStateMsg.denied,
            exactAlarm: PermissionStateMsg.denied,
          ),
          deviceStatusValue: deviceStatusMsg(
            alarmMuted: true,
            interruptionFilter: InterruptionFilterMsg.none,
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('W17 text scale 2.0: no overflow, equal tile heights', (
    tester,
  ) async {
    await pumpAppHarness(tester, seed: seedW01, textScale: 2);
    expect(tester.takeException(), isNull);
    final heights = SavedPlaceSlot.values
        .map((s) => tester.getSize(_tile(s)).height)
        .toSet();
    expect(heights, hasLength(1));
    expect(heights.single, greaterThanOrEqualTo(kSavedPlaceTileMinHeight));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
  });

  testWidgets('W18 semantics of tiles and headers', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpAppHarness(tester, seed: seedW01);
    final home = tester.getSemantics(_tile(SavedPlaceSlot.home));
    expect(home.label, 'Nhà, ${kHomeAddress.name}');
    expect(home.flagsCollection.isButton, isTrue);
    expect(home.hintOverrides?.onLongPressHint, 'Sửa hoặc xoá');
    final work = tester.getSemantics(_tile(SavedPlaceSlot.work));
    expect(work.label, 'Thêm Công ty');
    expect(work.hintOverrides?.onLongPressHint, isNull);
    expect(find.bySemanticsLabel('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Hôm nay bạn xuống ở đâu?'))
          .flagsCollection
          .isHeader,
      isTrue,
    );
    for (final header in ['Đã lưu', 'Chuyến gần đây']) {
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(header))
            .flagsCollection
            .isHeader,
        isTrue,
        reason: header,
      );
    }
    final recent = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^Ga Đồng Hới')),
    );
    expect(recent.hintOverrides?.onTapHint, 'Đặt lại chuyến này');
    handle.dispose();
  });

  testWidgets('W20 iOS 26: AlarmKit off, no volume/DND/sleep hint', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.denied),
      deviceInfoValue: iosDevice(),
      deviceStatusValue: DeviceStatusMsg(
        batteryPct: 64,
        charging: false,
        interruptionFilter: InterruptionFilterMsg.unknown,
      ),
    );
    await pumpAppHarness(tester, bridge: bridge);
    expect(_badgeLabels(tester), [
      'Vị trí: Khi dùng ứng dụng',
      'Báo thức không kêu khi Im lặng',
      'Pin 64%',
    ]);
    expect(
      _badgeTone(tester, 'Báo thức không kêu khi Im lặng'),
      NapTone.danger,
    );
    expect(
      find.text('Nếu máy tự bật Chế độ ngủ, hãy cho phép Báo thức.'),
      findsNothing,
    );
  });

  testWidgets('W21 deviceStatus error: location chip only', (tester) async {
    final bridge = FakeCoreBridge()..deviceStatusError = channelError();
    await pumpAppHarness(tester, bridge: bridge);
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    expect(_badgeLabels(tester), ['Vị trí: Khi dùng ứng dụng']);
  });

  testWidgets('W22 database error: tiles locked, search still works', (
    tester,
  ) async {
    final broken = AppDatabase(
      LazyDatabase(() async => throw StateError('disk full')),
    );
    final h = await pumpAppHarness(tester, db: broken);
    expect(find.text('Không đọc được chuyến gần đây.'), findsOneWidget);
    for (final slot in SavedPlaceSlot.values) {
      expect(tester.widget<SavedPlaceTile>(_tile(slot)).onTap, isNull);
    }
    expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    await _tap(tester, find.text('Tìm ga, bến xe, địa chỉ…'));
    expect(h.location, AppRoutes.destination);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a place fails: snack bar, tile unchanged', (
    tester,
  ) async {
    await pumpAppHarness(
      tester,
      overrides: [
        destinationPickerProvider.overrideWithValue(
          (_) async => const TripDestination(
            name: 'Bad',
            lat: 99,
            lng: 0,
            kind: DestinationKind.pin,
          ),
        ),
      ],
    );
    await _tap(tester, _tile(SavedPlaceSlot.home));
    expect(find.text('Không lưu được. Thử lại sau.'), findsOneWidget);
    expect(
      find.descendant(
        of: _tile(SavedPlaceSlot.home),
        matching: find.text('Thêm'),
      ),
      findsOneWidget,
    );
  });
}
