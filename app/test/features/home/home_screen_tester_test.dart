// Tester additions for T22 (docs/test-reports/T22.md): adversarial cases
// around the acceptance criteria that W01-W22 do not pin down yet.
// - One-tap restart for every alarm mode, in vi and en, repeatable.
// - "Sẵn sàng" card: muted alarm, DND, low battery, loading, error,
//   recovery on resume (the M01 flow, automated).
// - Worst-case layout at text scale 2.0 (vi/en, 390 and 320 wide).
// - Running trip that appears or ends while screen 1 is shown.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show DebugSemanticsDumpOrder, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
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

List<String> _badgeLabels(WidgetTester tester) => tester
    .widgetList<NapBadge>(find.byType(NapBadge))
    .map((b) => b.label)
    .toList();

NapTone _badgeTone(WidgetTester tester, String label) => tester
    .widget<NapBadge>(
      find.byWidgetPredicate((w) => w is NapBadge && w.label == label),
    )
    .tone;

void _resume(WidgetTester tester) {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

const TripAlarmChoice _distance1500 = TripAlarmChoice(
  mode: AlarmModeMsg.distance,
  distanceThresholdM: 1500,
  preAlertEnabled: false,
);

const TripAlarmChoice _smart = TripAlarmChoice(
  mode: AlarmModeMsg.smart,
  distanceThresholdM: 1000,
  timeThresholdMin: 15,
  preAlertEnabled: true,
);

/// A bridge whose permissionStatus() waits for [gate] (loading state).
class _GatedBridge extends FakeCoreBridge {
  final Completer<void> gate = Completer<void>();

  @override
  Future<PermissionStatusMsg> permissionStatus() async {
    await gate.future;
    return await super.permissionStatus();
  }
}

void main() {
  group('one-tap restart (TASKS T22, D7)', () {
    for (final (locale, subtitle, summary) in [
      ('vi', 'Tàu · Báo trước 1,5 km', 'Báo trước 1,5 km'),
      ('en', 'Train · Alert 1.5 km before', 'Alert 1.5 km before'),
    ]) {
      testWidgets('distance 1500 m, pre-alert off ($locale)', (tester) async {
        final h = await pumpAppHarness(
          tester,
          locale: Locale(locale),
          seed: (c) => seedData(
            c,
            trips: [sampleRecord(id: 'dh', alarm: _distance1500)],
          ),
        );
        expect(find.text(subtitle), findsOneWidget);
        await _tap(tester, find.text('Ga Đồng Hới'));
        expect(h.location, AppRoutes.alarmSettings);
        expect(
          h.extra,
          const TripDraft(
            destination: kGaDongHoi,
            source: DestinationSource.recentTrip,
            alarm: _distance1500,
            vehicleHint: VehicleKindMsg.train,
          ),
        );
        // The draft keeps the detail too (screen 3 shows the province).
        expect((h.extra! as TripDraft).destination.detail, 'Quảng Trị');
        expect(find.text(summary), findsOneWidget);
        expect(h.bridge.callCount('startTrip'), 0);
      });
    }

    testWidgets('smart, coach: thresholds and hint survive the restart', (
      tester,
    ) async {
      final h = await pumpAppHarness(
        tester,
        seed: (c) => seedData(
          c,
          trips: [
            sampleRecord(id: 'md', destination: kBenXeMyDinh, alarm: _smart),
          ],
        ),
      );
      expect(find.text('Xe khách · Báo thông minh'), findsOneWidget);
      await _tap(tester, find.text('Bến xe Mỹ Đình'));
      final draft = h.extra! as TripDraft;
      expect(draft.alarm, _smart);
      expect(draft.vehicleHint, VehicleKindMsg.coach);
      expect(draft.source, DestinationSource.recentTrip);
      expect(find.text('Báo thông minh'), findsOneWidget);
    });

    testWidgets('restart, Back, restart again: same draft both times', (
      tester,
    ) async {
      final h = await pumpAppHarness(
        tester,
        seed: (c) => seedData(c, trips: [sampleRecord(id: 'dh')]),
      );
      await _tap(tester, find.text('Ga Đồng Hới'));
      final first = h.extra;
      await _tap(tester, find.byTooltip('Quay lại'));
      expect(h.location, AppRoutes.home);
      expect(find.text('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
      await _tap(tester, find.text('Ga Đồng Hới'));
      expect(h.location, AppRoutes.alarmSettings);
      expect(h.extra, first);
      expect(h.bridge.callCount('startTrip'), 0);
    });

    testWidgets('recent list: newest 3 real destinations, simulated hidden', (
      tester,
    ) async {
      await pumpAppHarness(
        tester,
        seed: (c) => seedData(
          c,
          trips: [
            sampleRecord(
              id: 'sim',
              destination: kGaVinhSim,
              startedAtMs: 60,
              simulated: true,
            ),
            sampleRecord(id: 'dh2', startedAtMs: 50),
            sampleRecord(id: 'hue', destination: kGaHue, startedAtMs: 40),
            sampleRecord(id: 'md', destination: kBenXeMyDinh, startedAtMs: 30),
            sampleRecord(id: 'dh1', startedAtMs: 20),
            sampleRecord(
              id: 'home',
              destination: kHomeAddress,
              startedAtMs: 10,
            ),
          ],
        ),
      );
      final rows = tester
          .widgetList<NapListRow>(find.byType(NapListRow))
          .map((r) => r.title)
          .toList();
      expect(rows, ['Ga Đồng Hới', 'Ga Huế', 'Bến xe Mỹ Đình']);
      expect(find.text(kGaVinhSim.name), findsNothing);
    });

    testWidgets(
      'blocked readiness does not hide the restart (screen 3 checks)',
      (tester) async {
        final h = await pumpAppHarness(
          tester,
          bridge: FakeCoreBridge(
            permissions: androidPermissions(location: LocationAccessMsg.denied),
          ),
          seed: (c) => seedData(c, trips: [sampleRecord(id: 'dh')]),
        );
        expect(find.text('Chưa thể bắt đầu chuyến đi'), findsOneWidget);
        await _tap(tester, find.text('Ga Đồng Hới'));
        expect(h.location, AppRoutes.alarmSettings);
        expect(h.bridge.callCount('startTrip'), 0);
      },
    );
  });

  group('"Sẵn sàng" card: things that silence the alarm', () {
    testWidgets('alarmMuted at 70 %: red "Âm báo đang tắt", no volume chip', (
      tester,
    ) async {
      await pumpAppHarness(
        tester,
        bridge: FakeCoreBridge(
          deviceStatusValue: deviceStatusMsg(
            alarmVolumePct: 70,
            alarmMuted: true,
          ),
        ),
      );
      expect(find.text('Nên kiểm tra trước khi ngủ'), findsOneWidget);
      expect(find.text('Sẵn sàng cho chuyến đi'), findsNothing);
      expect(_badgeTone(tester, 'Âm báo đang tắt'), NapTone.danger);
      expect(find.text('Âm lượng báo 70%'), findsNothing);
      // Volume is not a permission: no "Kiểm tra quyền" button (S2 R3).
      expect(find.text('Kiểm tra quyền'), findsNothing);
    });

    testWidgets('alarmMuted with unknown percent still warns', (tester) async {
      await pumpAppHarness(
        tester,
        bridge: FakeCoreBridge(
          deviceStatusValue: deviceStatusMsg(
            alarmVolumePct: null,
            alarmMuted: true,
          ),
        ),
      );
      expect(find.text('Nên kiểm tra trước khi ngủ'), findsOneWidget);
      expect(_badgeTone(tester, 'Âm báo đang tắt'), NapTone.danger);
    });

    for (final (filter, allows, blocks) in [
      (InterruptionFilterMsg.none, null, true),
      (InterruptionFilterMsg.priority, false, true),
      (InterruptionFilterMsg.priority, true, false),
      (InterruptionFilterMsg.alarms, null, false),
    ]) {
      testWidgets('DND ${filter.name} allowsAlarms=$allows (en)', (
        tester,
      ) async {
        await pumpAppHarness(
          tester,
          locale: const Locale('en'),
          bridge: FakeCoreBridge(
            deviceStatusValue: deviceStatusMsg(
              interruptionFilter: filter,
              priorityAllowsAlarms: allows,
            ),
          ),
        );
        expect(
          find.text('Do Not Disturb blocks alarms'),
          blocks ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(blocks ? 'Check before you sleep' : 'Ready for your trip'),
          findsOneWidget,
        );
        if (blocks) {
          expect(
            _badgeTone(tester, 'Do Not Disturb blocks alarms'),
            NapTone.danger,
          );
        }
      });
    }

    for (final (pct, charging, label, tone, title) in [
      (
        20,
        false,
        'Pin 20% · nên sạc',
        NapTone.warning,
        'Nên kiểm tra trước khi ngủ',
      ),
      (
        5,
        null,
        'Pin 5% · nên sạc',
        NapTone.warning,
        'Nên kiểm tra trước khi ngủ',
      ),
      (
        15,
        true,
        'Pin 15% · đang sạc',
        NapTone.neutral,
        'Sẵn sàng cho chuyến đi',
      ),
      (21, false, 'Pin 21%', NapTone.neutral, 'Sẵn sàng cho chuyến đi'),
    ]) {
      testWidgets('battery $pct % charging=$charging', (tester) async {
        await pumpAppHarness(
          tester,
          bridge: FakeCoreBridge(
            deviceStatusValue: deviceStatusMsg(
              batteryPct: pct,
              charging: charging,
            ),
          ),
        );
        expect(_badgeTone(tester, label), tone);
        expect(find.text(title), findsOneWidget);
      });
    }

    testWidgets('loading: "Đang kiểm tra…", no chip, no button; then ready', (
      tester,
    ) async {
      final bridge = _GatedBridge();
      await pumpAppHarness(tester, bridge: bridge);
      expect(find.text('Đang kiểm tra…'), findsOneWidget);
      expect(find.byType(NapBadge), findsNothing);
      expect(find.text('Kiểm tra quyền'), findsNothing);
      expect(find.text('Thử lại'), findsNothing);
      // Screen 1 itself is usable while the card loads.
      expect(find.text('Hôm nay bạn xuống ở đâu?'), findsOneWidget);
      bridge.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Đang kiểm tra…'), findsNothing);
      expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    });

    testWidgets('unexpected error (not BridgeException): error state, retry', (
      tester,
    ) async {
      final bridge = FakeCoreBridge()
        ..permissionStatusError = StateError('decode');
      await pumpAppHarness(tester, bridge: bridge);
      expect(find.text('Chưa kiểm tra được'), findsOneWidget);
      expect(find.text('Sẵn sàng cho chuyến đi'), findsNothing);
      expect(tester.takeException(), isNull);
      bridge.permissionStatusError = null;
      await _tap(tester, find.text('Thử lại'));
      expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    });

    testWidgets('error state recovers on resume without tapping retry', (
      tester,
    ) async {
      final bridge = FakeCoreBridge()..permissionStatusError = channelError();
      await pumpAppHarness(tester, bridge: bridge);
      expect(find.text('Chưa kiểm tra được'), findsOneWidget);
      bridge.permissionStatusError = null;
      _resume(tester);
      await tester.pumpAndSettle();
      expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    });

    testWidgets('M01 automated: DND on, low battery, then off, via resume', (
      tester,
    ) async {
      final h = await pumpAppHarness(tester, seed: seedW01);
      expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);

      // User turns on "total silence" and unplugs at 15 % while away.
      h.bridge.deviceStatusValue = deviceStatusMsg(
        batteryPct: 15,
        alarmVolumePct: 0,
        alarmMuted: true,
        interruptionFilter: InterruptionFilterMsg.none,
      );
      _resume(tester);
      await tester.pumpAndSettle();
      expect(_badgeLabels(tester), [
        'Vị trí: Khi dùng ứng dụng',
        'Pin 15% · nên sạc',
        'Âm báo đang tắt',
        'Không làm phiền chặn báo thức',
      ]);
      expect(find.text('Nên kiểm tra trước khi ngủ'), findsOneWidget);

      // Back to normal.
      h.bridge.deviceStatusValue = deviceStatusMsg();
      _resume(tester);
      await tester.pumpAndSettle();
      expect(_badgeLabels(tester), [
        'Vị trí: Khi dùng ứng dụng',
        'Pin 82%',
        'Âm lượng báo 100%',
      ]);
      expect(find.text('Sẵn sàng cho chuyến đi'), findsOneWidget);
    });

    testWidgets('card is re-read when coming back from screen 9', (
      tester,
    ) async {
      final bridge = FakeCoreBridge(
        permissions: androidPermissions(
          batteryOptimizationIgnored: PermissionStateMsg.denied,
        ),
      );
      await pumpAppHarness(tester, bridge: bridge);
      expect(find.text('Tối ưu pin đang bật'), findsOneWidget);
      await _tap(tester, find.text('Xem hướng dẫn'));
      bridge.permissions = androidPermissions();
      await _tap(tester, find.byTooltip('Quay lại'));
      expect(find.text('Tối ưu pin đang bật'), findsNothing);
      expect(find.text('Xem hướng dẫn'), findsNothing);
    });

    testWidgets('card reads the title first, then the chips in order (M03)', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // exactAlarm denied: the card also gets the "Kiểm tra quyền" button.
      await pumpAppHarness(
        tester,
        bridge: FakeCoreBridge(
          permissions: androidPermissions(
            exactAlarm: PermissionStateMsg.denied,
          ),
          deviceStatusValue: deviceStatusMsg(alarmMuted: true),
        ),
      );
      final title = tester.getSemantics(
        find.bySemanticsLabel('Nên kiểm tra trước khi ngủ'),
      );
      final card = title.parent!;
      // The card container has no label of its own: nothing is read twice
      // and nothing is read before the title.
      expect(card.label, isEmpty);
      expect(card.flagsCollection.isHeader, isFalse);

      // Labelled nodes of the card, in traversal order (a labelled node is
      // read as one item; its subtree is not visited).
      final read = <SemanticsNode>[];
      void visit(SemanticsNode node) {
        for (final child in node.debugListChildrenInOrder(
          DebugSemanticsDumpOrder.traversalOrder,
        )) {
          if (child.label.isNotEmpty) {
            read.add(child);
          } else {
            visit(child);
          }
        }
      }

      visit(card);
      expect(read.map((n) => n.label).toList(), [
        'Nên kiểm tra trước khi ngủ',
        'Vị trí: Khi dùng ứng dụng',
        'Chưa cho báo thức chính xác',
        'Pin 82%',
        'Âm báo đang tắt',
        'Nếu máy tự bật Chế độ ngủ, hãy cho phép Báo thức.',
        'Kiểm tra quyền',
      ]);
      expect(
        read.where((n) => n.flagsCollection.isHeader).map((n) => n.label),
        ['Nên kiểm tra trước khi ngủ'],
      );
      expect(read.last.flagsCollection.isButton, isTrue);
      handle.dispose();
    });

    // Repro of bug B1 (docs/test-reports/T22.md). Spec §9.4: the card is a
    // container, only its title is a header, chips are read one by one.
    // Before round 3 the title's `header: true` landed on the container
    // node, so the whole card was one node announced as a heading.
    testWidgets(
      'B1: only the card title is a header; chips are separate nodes',
      skip: false,
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpAppHarness(
          tester,
          bridge: FakeCoreBridge(
            deviceStatusValue: deviceStatusMsg(alarmMuted: true),
          ),
        );
        final title = tester.getSemantics(
          find.bySemanticsLabel('Nên kiểm tra trước khi ngủ'),
        );
        expect(title.flagsCollection.isHeader, isTrue);
        final chip = tester.getSemantics(
          find.bySemanticsLabel('Âm báo đang tắt'),
        );
        expect(chip.flagsCollection.isHeader, isFalse);
        handle.dispose();
      },
    );
  });

  group('text scale 2.0, worst case', () {
    for (final (locale, width) in [
      ('vi', 390.0),
      ('en', 390.0),
      ('vi', 320.0),
      ('en', 320.0),
    ]) {
      testWidgets('$locale ${width.toInt()} wide: no overflow, all reachable', (
        tester,
      ) async {
        final bridge = FakeCoreBridge(
          active: activeTrip(destinationName: 'Ga Sài Gòn'),
          permissions: androidPermissions(
            notifications: PermissionStateMsg.denied,
            exactAlarm: PermissionStateMsg.denied,
            fullScreenIntent: PermissionStateMsg.denied,
            batteryOptimizationIgnored: PermissionStateMsg.denied,
          ),
          deviceStatusValue: deviceStatusMsg(
            batteryPct: 12,
            alarmVolumePct: 0,
            alarmMuted: true,
            interruptionFilter: InterruptionFilterMsg.none,
          ),
        );
        await pumpAppHarness(
          tester,
          bridge: bridge,
          textScale: 2,
          locale: Locale(locale),
          size: Size(width, 844),
          seed: (c) => seedData(
            c,
            places: const {
              SavedPlaceSlot.home: kLongName,
              SavedPlaceSlot.hometown: kHometown,
              SavedPlaceSlot.work: kBenXeMyDinh,
            },
            trips: [
              sampleRecord(id: 'a', destination: kLongName, startedAtMs: 30),
              sampleRecord(id: 'b', destination: kGaHue, startedAtMs: 20),
              sampleRecord(id: 'c', destination: kBenXeMyDinh, startedAtMs: 10),
            ],
          ),
        );
        expect(tester.takeException(), isNull);
        final heights = SavedPlaceSlot.values
            .map((s) => tester.getSize(_tile(s)).height)
            .toSet();
        expect(heights, hasLength(1));
        final button = locale == 'vi' ? 'Kiểm tra quyền' : 'Check permissions';
        await tester.scrollUntilVisible(
          find.text(button),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(
          find.text(locale == 'vi' ? 'Cấp quyền' : 'Permissions'),
          findsOneWidget,
        );
      });
    }
  });

  group('running trip while screen 1 is shown', () {
    testWidgets('trip started elsewhere appears, then ends via phase', (
      tester,
    ) async {
      final bridge = FakeCoreBridge();
      final h = await pumpAppHarness(
        tester,
        bridge: bridge,
        seed: (c) => seedData(c, trips: [sampleRecord(id: 'dh')]),
      );
      expect(find.text('Đang theo dõi chuyến đi'), findsNothing);

      bridge
        ..active = activeTrip(tripId: 'trip-2', destinationName: 'Ga Vinh')
        ..emit(TripStateUpdateMsg(state: tripState(tripId: 'trip-2')));
      await tester.pumpAndSettle();
      expect(find.text('Đang theo dõi chuyến đi'), findsOneWidget);
      expect(find.text('Ga Vinh'), findsOneWidget);

      // A restart is refused while the trip runs.
      await _tap(tester, find.text('Ga Đồng Hới'));
      expect(h.location, AppRoutes.home);

      bridge
        ..active = null
        ..emit(
          TripStateUpdateMsg(
            state: tripState(tripId: 'trip-2', phase: TripPhaseMsg.ended),
          ),
        );
      await tester.pumpAndSettle();
      expect(find.text('Đang theo dõi chuyến đi'), findsNothing);
      await _tap(tester, find.text('Ga Đồng Hới'));
      expect(h.location, AppRoutes.alarmSettings);
    });

    testWidgets('saved place while a trip runs: busy snack bar, "Mở" opens 4', (
      tester,
    ) async {
      final h = await pumpAppHarness(
        tester,
        bridge: FakeCoreBridge(active: activeTrip()),
        seed: seedW01,
      );
      await _tap(tester, _tile(SavedPlaceSlot.home));
      expect(h.location, AppRoutes.home);
      expect(
        find.text(
          'Đang có chuyến đi. Dừng chuyến đó trước khi đặt chuyến mới.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(SnackBarAction, 'Mở'));
      await tester.pumpAndSettle();
      expect(h.location, AppRoutes.tracking);
      expect(h.bridge.callCount('startTrip'), 0);
    });

    testWidgets('trip ended while screen 4 covered home: card gone on return', (
      tester,
    ) async {
      final bridge = FakeCoreBridge(active: activeTrip());
      final h = await pumpAppHarness(tester, bridge: bridge);
      await _tap(tester, find.widgetWithText(NapButton, 'Mở'));
      expect(h.location, AppRoutes.tracking);
      // The trip ends while home is not shown (no listener on updates).
      bridge
        ..active = null
        ..emit(tripEnded());
      await tester.pumpAndSettle();
      h.router.go(AppRoutes.home);
      await tester.pumpAndSettle();
      expect(find.text('Đang theo dõi chuyến đi'), findsNothing);
    });
  });

  testWidgets('W01 in English', (tester) async {
    await pumpAppHarness(tester, seed: seedW01, locale: const Locale('en'));
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Where are you getting off today?'), findsOneWidget);
    expect(find.text('Search stations, addresses…'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Train · Alert 15 min before'), findsNWidgets(2));
    expect(find.text('Ready for your trip'), findsOneWidget);
    expect(_badgeLabels(tester), [
      'Location: While using',
      'Battery 82%',
      'Alarm volume 100%',
    ]);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Trips'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}

const TripDestination kGaVinhSim = TripDestination(
  name: 'Ga Vinh (giả lập)',
  lat: 18.6796,
  lng: 105.6813,
  kind: DestinationKind.train,
);

/// Long Vietnamese name (wraps at text scale 2.0).
const TripDestination kLongName = TripDestination(
  name: 'Bến xe khách trung tâm thành phố Đà Nẵng mới',
  lat: 16.0544,
  lng: 108.2022,
  kind: DestinationKind.coach,
  detail: 'Đà Nẵng',
);
