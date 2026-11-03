// W01-W14, W22, W23, W25: screen 0 (T21 §7; PRD §3.1).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:napstop/features/onboarding/presentation/widgets/permission_row.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/fake_key_value_store.dart';

const _allow = 'Cấp quyền';
const _settings = 'Mở Cài đặt';

DeviceInfoMsg _xiaomi() =>
    androidDevice(manufacturer: 'Xiaomi', brand: 'Redmi');

/// W01 data: location and notifications not asked yet, battery optimized.
FakeCoreBridge _w01Bridge() => FakeCoreBridge(
  deviceInfoValue: _xiaomi(),
  permissions: androidPermissions(
    location: LocationAccessMsg.notDetermined,
    precise: PermissionStateMsg.notDetermined,
    notifications: PermissionStateMsg.notDetermined,
    batteryOptimizationIgnored: PermissionStateMsg.denied,
  ),
);

Finder _row(String kind) => find.byKey(ValueKey('onboarding-$kind'));

Finder _inRow(String kind, String text) =>
    find.descendant(of: _row(kind), matching: find.text(text));

Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<AppHarness> _open(
  WidgetTester tester, {
  FakeCoreBridge? bridge,
  FakeKeyValueStore? store,
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1,
  Size size = kHarnessSize,
}) => pumpAppHarness(
  tester,
  bridge: bridge ?? _w01Bridge(),
  initialLocation: AppRoutes.onboarding,
  keyValueStore: store,
  theme: theme,
  textScale: textScale,
  size: size,
);

Future<void> _resume(WidgetTester tester) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.paused)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('W01 first run, Xiaomi', (tester) async {
    await _open(tester);
    expect(find.text('Để không bao giờ lỡ trạm'), findsOneWidget);
    expect(
      find.text(
        'NapStop cần vài quyền để vẫn báo được khi bạn khoá màn hình và ngủ.',
      ),
      findsOneWidget,
    );
    expect(_inRow('location', _allow), findsOneWidget);
    expect(_inRow('notifications', _allow), findsOneWidget);
    expect(_row('fullScreenIntent'), findsNothing);
    expect(_row('exactAlarm'), findsNothing);
    expect(find.text('Xem hướng dẫn cho Xiaomi (3 bước)'), findsOneWidget);
    expect(find.text('Máy Xiaomi hay tự tắt app chạy nền'), findsOneWidget);
    expect(find.text('Tiếp tục'), findsOneWidget);
    expect(
      find.text('Vị trí chỉ dùng trên máy, không gửi lên máy chủ.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Quay lại'), findsNothing);
    expect(find.byType(NapScreenHeader), findsNothing);
  });

  testWidgets('W02 explainer before the location dialog', (tester) async {
    final bridge = _w01Bridge()
      ..requestPermissionResult = (kind) => androidPermissions(
        notifications: PermissionStateMsg.notDetermined,
        batteryOptimizationIgnored: PermissionStateMsg.denied,
      );
    await _open(tester, bridge: bridge);
    await _tap(tester, _inRow('location', _allow));
    expect(_inSheet('Cho phép dùng vị trí'), findsOneWidget);
    expect(
      _inSheet('Hãy chọn "Khi dùng ứng dụng" và bật "Vị trí chính xác".'),
      findsOneWidget,
    );
    await _tap(tester, _inSheet('Để sau'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(bridge.requestCalls, isEmpty);

    await _tap(tester, _inRow('location', _allow));
    await _tap(tester, _inSheet('Tiếp tục'));
    expect(bridge.requestCalls, [PermissionKindMsg.location]);
    expect(_inRow('location', 'Đã bật'), findsOneWidget);
    expect(_inRow('location', 'Vị trí chính xác đang bật'), findsOneWidget);
  });

  testWidgets('W03 denied: Settings directly; not opened: snack bar', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      permissions: androidPermissions(location: LocationAccessMsg.denied),
    )..openSettingsResult = false;
    await _open(tester, bridge: bridge);
    await _tap(tester, _inRow('location', _settings));
    expect(find.byType(BottomSheet), findsNothing);
    expect(bridge.openSettingsCalls, [SettingsTargetMsg.appDetails]);
    expect(
      find.text(
        'Không mở được Cài đặt. Hãy mở Cài đặt của máy và tìm NapStop.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('W04 approximate: ask for precise, then Settings', (
    tester,
  ) async {
    final bridge =
        FakeCoreBridge(
            permissions: androidPermissions(
              precise: PermissionStateMsg.notDetermined,
            ),
          )
          ..requestPermissionResult = (_) =>
              androidPermissions(precise: PermissionStateMsg.denied);
    await _open(tester, bridge: bridge);
    expect(
      _inRow('location', 'Đang là vị trí gần đúng, có thể lệch vài km'),
      findsOneWidget,
    );
    await _tap(tester, _inRow('location', 'Bật Chính xác'));
    expect(_inSheet('Bật vị trí chính xác'), findsOneWidget);
    await _tap(tester, _inSheet('Tiếp tục'));
    expect(bridge.requestCalls, [PermissionKindMsg.location]);
    expect(_inRow('location', _settings), findsOneWidget);
  });

  testWidgets('W05 location services off: no sheet', (tester) async {
    final bridge = FakeCoreBridge(
      permissions: androidPermissions(locationServicesEnabled: false),
    );
    await _open(tester, bridge: bridge);
    await _tap(tester, _inRow('location', 'Bật định vị'));
    expect(find.byType(BottomSheet), findsNothing);
    expect(bridge.openSettingsCalls, [SettingsTargetMsg.locationServices]);
  });

  for (final (kind, target, title) in [
    (
      'fullScreenIntent',
      SettingsTargetMsg.fullScreenIntent,
      'Báo thức toàn màn hình',
    ),
    ('exactAlarm', SettingsTargetMsg.exactAlarm, 'Cho phép đặt báo thức'),
  ]) {
    testWidgets('W06/W07 $kind: sheet, Settings, row stays after resume', (
      tester,
    ) async {
      final bridge = FakeCoreBridge(
        permissions: androidPermissions(
          fullScreenIntent: kind == 'fullScreenIntent'
              ? PermissionStateMsg.denied
              : PermissionStateMsg.granted,
          exactAlarm: kind == 'exactAlarm'
              ? PermissionStateMsg.denied
              : PermissionStateMsg.granted,
        ),
      );
      await _open(tester, bridge: bridge);
      await _tap(tester, _inRow(kind, _settings));
      expect(_inSheet(title), findsOneWidget);
      await _tap(tester, _inSheet(_settings));
      expect(bridge.openSettingsCalls, [target]);
      bridge.permissions = androidPermissions();
      await _resume(tester);
      expect(_row(kind), findsOneWidget);
      expect(_inRow(kind, 'Đã bật'), findsOneWidget);
    });
  }

  testWidgets('W08 one request at a time; buttons locked while waiting', (
    tester,
  ) async {
    final bridge = _w01Bridge()..requestGate = Completer<void>();
    await _open(tester, bridge: bridge);
    await _tap(tester, _inRow('location', _allow));
    await _tap(tester, _inSheet('Tiếp tục'));
    final buttons = tester.widgetList<NapButton>(
      find.descendant(
        of: find.byType(PermissionRow),
        matching: find.byType(NapButton),
      ),
    );
    expect(buttons, isNotEmpty);
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    await tester.tap(_inRow('notifications', _allow), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(bridge.requestCalls, [PermissionKindMsg.location]);
    bridge.requestGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('W08 request-in-progress from native: no snack bar', (
    tester,
  ) async {
    final bridge = _w01Bridge()
      ..requestPermissionError = const BridgeException(
        BridgeErrorCode.requestInProgress,
        rawCode: 'request-in-progress',
      );
    await _open(tester, bridge: bridge);
    await _tap(tester, _inRow('notifications', _allow));
    await _tap(tester, _inSheet('Tiếp tục'));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('request error: snack bar and a fresh read', (tester) async {
    final bridge = _w01Bridge()..requestPermissionError = channelError();
    await _open(tester, bridge: bridge);
    final before = bridge.callCount('permissionStatus');
    await _tap(tester, _inRow('notifications', _allow));
    await _tap(tester, _inSheet('Tiếp tục'));
    expect(
      find.text('Không mở được hộp thoại quyền. Thử lại.'),
      findsOneWidget,
    );
    expect(bridge.callCount('permissionStatus'), before + 1);
  });

  testWidgets('W09 resume re-reads the permissions', (tester) async {
    final h = await _open(tester);
    final before = h.bridge.callCount('permissionStatus');
    h.bridge.permissions = androidPermissions();
    await _resume(tester);
    expect(h.bridge.callCount('permissionStatus'), before + 1);
    expect(_inRow('location', 'Đã bật'), findsOneWidget);
    expect(_inRow('notifications', 'Đã bật'), findsOneWidget);
  });

  testWidgets('W10 first run, location denied: never blocks', (tester) async {
    final store = FakeKeyValueStore();
    final h = await _open(
      tester,
      store: store,
      bridge: FakeCoreBridge(
        permissions: androidPermissions(location: LocationAccessMsg.denied),
      ),
    );
    expect(
      find.text('Còn mục cần bật trước khi bắt đầu chuyến đi.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Tiếp tục'));
    expect(store.values[kOnboardingKey], 1);
    expect(h.location, AppRoutes.home);
  });

  testWidgets('W11 from the home card: back button, "Xong" pops', (
    tester,
  ) async {
    final h = await pumpAppHarness(
      tester,
      bridge: FakeCoreBridge(
        permissions: androidPermissions(exactAlarm: PermissionStateMsg.denied),
      ),
    );
    final before = h.bridge.callCount('permissionStatus');
    await _tap(tester, find.text('Kiểm tra quyền'));
    expect(h.location, AppRoutes.onboarding);
    expect(find.byTooltip('Quay lại'), findsOneWidget);
    expect(find.text('Cấp quyền'), findsWidgets);
    expect(find.text('Tiếp tục'), findsNothing);
    await _tap(tester, find.text('Xong'));
    expect(h.location, AppRoutes.home);
    // Screen 0 read once, the home card once more after returning.
    expect(h.bridge.callCount('permissionStatus'), before + 2);
  });

  testWidgets('W12 iOS 26: AlarmKit row, no battery card', (tester) async {
    final bridge = FakeCoreBridge(
      deviceInfoValue: iosDevice(),
      permissions: iosPermissions(alarmKit: PermissionStateMsg.notDetermined),
    );
    await _open(tester, bridge: bridge);
    expect(_row('location'), findsOneWidget);
    expect(_row('notifications'), findsOneWidget);
    expect(_row('alarmKit'), findsOneWidget);
    expect(find.text('Tắt tối ưu pin cho NapStop'), findsNothing);
    await _tap(tester, _inRow('alarmKit', _allow));
    expect(_inSheet('Cho phép báo thức'), findsOneWidget);
    await _tap(tester, _inSheet('Tiếp tục'));
    expect(bridge.requestCalls, [PermissionKindMsg.alarmKit]);
  });

  testWidgets('W12 iOS: location services cannot be opened', (tester) async {
    final bridge = FakeCoreBridge(
      deviceInfoValue: iosDevice(),
      permissions: iosPermissions(locationServicesEnabled: false),
    )..openSettingsResult = false;
    await _open(tester, bridge: bridge);
    await _tap(tester, _inRow('location', 'Bật định vị'));
    expect(
      find.text(
        'Mở Cài đặt › Quyền riêng tư & Bảo mật › Dịch vụ định vị và bật lên.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('W13 read error: banner, retry, main button still works', (
    tester,
  ) async {
    final bridge = _w01Bridge()..permissionStatusError = channelError();
    await _open(tester, bridge: bridge);
    expect(find.text('Chưa đọc được quyền của máy.'), findsOneWidget);
    expect(
      tester
          .widget<NapButton>(find.widgetWithText(NapButton, 'Tiếp tục'))
          .onPressed,
      isNotNull,
    );
    bridge.permissionStatusError = null;
    await _tap(tester, find.text('Thử lại'));
    expect(find.text('Chưa đọc được quyền của máy.'), findsNothing);
    expect(_row('location'), findsOneWidget);
  });

  testWidgets('review #5: retry after a deviceInfo error reads it again', (
    tester,
  ) async {
    final bridge = _w01Bridge()..deviceInfoError = channelError();
    await _open(tester, bridge: bridge);
    expect(find.text('Chưa đọc được quyền của máy.'), findsOneWidget);
    bridge.deviceInfoError = null;
    await _tap(tester, find.text('Thử lại'));
    expect(find.text('Chưa đọc được quyền của máy.'), findsNothing);
    expect(_row('location'), findsOneWidget);
    expect(bridge.callCount('deviceInfo'), 2);
  });

  testWidgets('W14 battery card opens screen 9; back re-reads', (tester) async {
    final h = await _open(tester);
    final before = h.bridge.callCount('permissionStatus');
    await _tap(tester, find.text('Xem hướng dẫn cho Xiaomi (3 bước)'));
    expect(h.location, AppRoutes.batteryGuide);
    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.onboarding);
    expect(h.bridge.callCount('permissionStatus'), before + 1);
  });

  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    testWidgets('W22 a11y screen 0 (${theme.name})', (tester) async {
      final handle = tester.ensureSemantics();
      await _open(tester, theme: theme);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel('Cấp quyền: Thông báo'), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('W22 semantics: done row, header', (tester) async {
    final handle = tester.ensureSemantics();
    await _open(tester, bridge: FakeCoreBridge());
    expect(
      find.bySemanticsLabel(RegExp(r'^Thông báo\n.*\nĐã bật$', dotAll: true)),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Để không bao giờ lỡ trạm')),
      isSemantics(isHeader: true, label: 'Để không bao giờ lỡ trạm'),
    );
    handle.dispose();
  });

  testWidgets('W23 360x640 at text scale 2: no overflow, no illustration', (
    tester,
  ) async {
    final bridge = _w01Bridge()
      ..permissions = androidPermissions(
        location: LocationAccessMsg.notDetermined,
        precise: PermissionStateMsg.notDetermined,
        notifications: PermissionStateMsg.notDetermined,
        fullScreenIntent: PermissionStateMsg.denied,
        exactAlarm: PermissionStateMsg.denied,
        batteryOptimizationIgnored: PermissionStateMsg.denied,
      );
    await _open(
      tester,
      bridge: bridge,
      textScale: 2,
      size: const Size(360, 640),
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(NapIcons.sleep), findsNothing);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Xem hướng dẫn cho Xiaomi (3 bước)'),
      200,
      scrollable: scrollable,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Tiếp tục').hitTestable(), findsOneWidget);
  });

  testWidgets('W25 startupLocationProvider opens screen 0 as the root', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          startupLocationProvider.overrideWithValue(AppRoutes.onboarding),
          coreBridgeProvider.overrideWithValue(_w01Bridge()),
          keyValueStoreProvider.overrideWithValue(FakeKeyValueStore()),
        ],
        child: const NapStopApp(flavor: AppFlavor.dev),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    final context = tester.element(find.byType(OnboardingScreen));
    expect(GoRouter.of(context).canPop(), isFalse);
  });
}
