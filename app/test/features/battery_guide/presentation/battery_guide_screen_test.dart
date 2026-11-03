// W15-W21, W22/W23 (screen 9): battery guide per brand and the 30 second
// background check (T21 §8; PRD §3 screen 9).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';

final int _nowMs = kHarnessNow.millisecondsSinceEpoch;

FakeCoreBridge _bridge({
  String manufacturer = 'Xiaomi',
  String brand = 'Redmi',
}) => FakeCoreBridge(
  deviceInfoValue: androidDevice(manufacturer: manufacturer, brand: brand),
)..backgroundCheckNowMs = _nowMs;

Future<AppHarness> _open(
  WidgetTester tester, {
  FakeCoreBridge? bridge,
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1,
  Size size = kHarnessSize,
}) async {
  // Pushed over screen 1, like the app does.
  final h = await pumpAppHarness(
    tester,
    bridge: bridge ?? _bridge(),
    theme: theme,
    textScale: textScale,
    size: size,
  );
  unawaited(h.router.push<void>(AppRoutes.batteryGuide));
  await tester.pumpAndSettle();
  return h;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

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

NapChip _chip(WidgetTester tester, String id) =>
    tester.widget<NapChip>(find.byKey(ValueKey('brand-$id')));

/// Steps 1..3 done: phase "done".
Future<void> _finishSteps(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await _tap(tester, find.text('Đã làm xong bước này'));
  }
}

Future<void> _startCheck(WidgetTester tester) async {
  await _finishSteps(tester, 3);
  await _tap(tester, find.text('Bắt đầu kiểm tra'));
}

void main() {
  testWidgets('W15 Xiaomi: detected, three steps, settings buttons', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(_chip(tester, 'xiaomi').selected, isTrue);
    expect(
      find.text('Đã nhận diện máy của bạn · chọn lại nếu sai'),
      findsOneWidget,
    );
    expect(find.text('BƯỚC 1/3'), findsOneWidget);
    expect(
      find.text('Đặt pin của NapStop thành "Không hạn chế"'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Cài đặt › Ứng dụng › Quản lý ứng dụng › NapStop › Tiết kiệm pin',
      ),
      findsOneWidget,
    );
    expect(find.text('Không hạn chế'), findsOneWidget);
    await _tap(tester, find.text('Mở Cài đặt của máy'));
    expect(h.bridge.openSettingsCalls, [SettingsTargetMsg.appDetails]);
    await _tap(tester, find.text('Đã làm xong bước này'));
    expect(find.text('BƯỚC 2/3'), findsOneWidget);
    await _tap(tester, find.text('Đã làm xong bước này'));
    expect(find.text('BƯỚC 3/3'), findsOneWidget);
    expect(find.text('Mở Cài đặt của máy'), findsNothing);
    await _tap(tester, find.text('Đã làm xong bước này'));
    expect(find.text('Xong 3 bước!'), findsOneWidget);
    expect(find.text('0:30'), findsOneWidget);
  });

  testWidgets('W15 settings page not opened: snack bar', (tester) async {
    final bridge = _bridge()..openSettingsResult = false;
    await _open(tester, bridge: bridge);
    await _tap(tester, find.text('Mở Cài đặt của máy'));
    expect(
      find.text(
        'Không mở được Cài đặt. Hãy mở Cài đặt của máy và tìm NapStop.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('W16 another chip restarts at its step 1', (tester) async {
    await _open(tester);
    await _tap(tester, find.text('Đã làm xong bước này'));
    expect(find.text('BƯỚC 2/3'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('brand-samsung')));
    expect(_chip(tester, 'samsung').selected, isTrue);
    expect(find.text('BƯỚC 1/3'), findsOneWidget);
    expect(find.text('Cài đặt › Ứng dụng › NapStop › Pin'), findsOneWidget);
    await _tap(tester, find.text('Đã làm xong bước này'));
    expect(
      find.text('Thêm NapStop vào "Ứng dụng không bao giờ ngủ"'),
      findsOneWidget,
    );
    expect(find.text('Mở Cài đặt của máy'), findsNothing);
  });

  testWidgets('W17 unknown brand: pick a brand, generic guide', (tester) async {
    await _open(
      tester,
      bridge: _bridge(manufacturer: 'Google', brand: 'google'),
    );
    expect(find.text('Chọn hãng điện thoại của bạn'), findsOneWidget);
    expect(_chip(tester, 'generic').selected, isTrue);
    expect(find.text('Khác'), findsOneWidget);
    expect(find.text('BƯỚC 1/2'), findsOneWidget);
    expect(find.byKey(const ValueKey('step-bar-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('step-bar-2')), findsNothing);
  });

  testWidgets('W17 realme: its chip first and selected', (tester) async {
    await _open(
      tester,
      bridge: _bridge(manufacturer: 'realme', brand: 'realme'),
    );
    expect(_chip(tester, 'realme').selected, isTrue);
    final chips = tester
        .widgetList<NapChip>(find.byType(NapChip))
        .map((c) => c.label)
        .toList();
    expect(chips, ['Realme', 'Xiaomi', 'Samsung', 'Oppo', 'Vivo', 'Khác']);
  });

  testWidgets('W18 check passes after resume; "Xong" pops', (tester) async {
    final h = await _open(tester);
    await _startCheck(tester);
    expect(h.bridge.startBackgroundCheckCalls, [const Duration(seconds: 30)]);
    expect(find.text('Huỷ kiểm tra'), findsOneWidget);
    expect(find.text('0:30'), findsOneWidget);
    // Chips are locked while running.
    expect(_chip(tester, 'samsung').onTap, isNull);
    h.bridge.backgroundCheckValue = BackgroundCheckMsg(
      scheduledAtMs: _nowMs,
      dueAtMs: _nowMs + 30000,
      firedAtMs: _nowMs + 31000,
      screenOnAtFire: false,
      exact: true,
    );
    await _resume(tester);
    expect(
      find.text('Đạt: điện thoại đã rung khi màn hình khoá.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Xong'));
    expect(h.location, AppRoutes.home);
    expect(h.bridge.callCount('cancelBackgroundCheck'), 0);
  });

  testWidgets('W19a cancel', (tester) async {
    final h = await _open(tester);
    await _startCheck(tester);
    await _tap(tester, find.text('Huỷ kiểm tra'));
    expect(h.bridge.callCount('cancelBackgroundCheck'), 1);
    expect(find.text('Bắt đầu kiểm tra'), findsOneWidget);
  });

  testWidgets('W19b leaving while running cancels', (tester) async {
    final h = await _open(tester);
    await _startCheck(tester);
    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.home);
    expect(h.bridge.callCount('cancelBackgroundCheck'), 1);
  });

  testWidgets('review #4: leaving before start answers cancels after it', (
    tester,
  ) async {
    final bridge = _bridge()..startBackgroundCheckGate = Completer<void>();
    final h = await _open(tester, bridge: bridge);
    await _finishSteps(tester, 3);
    await _tap(tester, find.text('Bắt đầu kiểm tra'));
    // A second tap while waiting does not start a second check.
    await _tap(tester, find.text('Bắt đầu kiểm tra'));
    expect(bridge.startBackgroundCheckCalls, hasLength(1));
    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.home);
    expect(bridge.callCount('cancelBackgroundCheck'), 0);
    bridge.startBackgroundCheckGate!.complete();
    await tester.pumpAndSettle();
    expect(bridge.calls.where((c) => c.contains('BackgroundCheck')), [
      'startBackgroundCheck',
      'cancelBackgroundCheck',
    ]);
    expect(bridge.backgroundCheckValue, isNull);
  });

  testWidgets('W19c not fired 60 s after due: failed, retry starts again', (
    tester,
  ) async {
    // The record is already 65 s past due when the first tick reads it.
    final bridge = _bridge()..backgroundCheckNowMs = _nowMs - 95000;
    await _open(tester, bridge: bridge);
    await _startCheck(tester);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(
      find.text('Không thấy rung. Làm lại các bước rồi thử lại.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Thử lại'));
    expect(bridge.startBackgroundCheckCalls, hasLength(2));
  });

  for (final (label, fired, screenOn, text) in [
    (
      'W19d late',
      20000,
      false,
      'Rung muộn 20 giây. Máy có thể đang hạn chế NapStop.',
    ),
    (
      'W19e screen on',
      1000,
      true,
      'Đã rung, nhưng màn hình chưa khoá. Thử lại và khoá màn hình.',
    ),
  ]) {
    testWidgets(label, (tester) async {
      final h = await _open(tester);
      await _startCheck(tester);
      h.bridge.backgroundCheckValue = BackgroundCheckMsg(
        scheduledAtMs: _nowMs,
        dueAtMs: _nowMs + 30000,
        firedAtMs: _nowMs + 30000 + fired,
        screenOnAtFire: screenOn,
        exact: true,
      );
      await _resume(tester);
      expect(find.text(text), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.text('Xem lại hướng dẫn'), findsOneWidget);
    });
  }

  testWidgets('W20 a recent result opens directly; an old one does not', (
    tester,
  ) async {
    final bridge = _bridge()
      ..backgroundCheckValue = BackgroundCheckMsg(
        scheduledAtMs: _nowMs - 150000,
        dueAtMs: _nowMs - 120000,
        firedAtMs: _nowMs - 119000,
        screenOnAtFire: false,
        exact: true,
      );
    await _open(tester, bridge: bridge);
    expect(
      find.text('Đạt: điện thoại đã rung khi màn hình khoá.'),
      findsOneWidget,
    );
  });

  testWidgets('W20 a record 11 minutes old: step 1', (tester) async {
    final bridge = _bridge()
      ..backgroundCheckValue = BackgroundCheckMsg(
        scheduledAtMs: _nowMs - 660000,
        dueAtMs: _nowMs - 630000,
        firedAtMs: _nowMs - 629000,
        screenOnAtFire: false,
        exact: true,
      );
    await _open(tester, bridge: bridge);
    expect(find.text('BƯỚC 1/3'), findsOneWidget);
  });

  testWidgets('W21 iOS: nothing to do', (tester) async {
    await _open(tester, bridge: FakeCoreBridge(deviceInfoValue: iosDevice()));
    expect(find.text('iPhone không cần bước này.'), findsOneWidget);
    expect(find.byType(NapChip), findsNothing);
  });

  testWidgets('catalog error: banner, retry loads again', (tester) async {
    var loads = 0;
    final h = await pumpAppHarness(
      tester,
      bridge: _bridge(),
      batteryGuides: () {
        loads++;
        return Future.error(const FormatException('bad guides'));
      },
    );
    unawaited(h.router.push<void>(AppRoutes.batteryGuide));
    await tester.pumpAndSettle();
    expect(find.text('Không tải được hướng dẫn.'), findsOneWidget);
    final before = loads;
    await _tap(tester, find.text('Thử lại'));
    expect(loads, before + 1);
    expect(find.text('Không tải được hướng dẫn.'), findsOneWidget);
  });

  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    testWidgets('W22 a11y screen 9 step 1 and result (${theme.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final h = await _open(tester, theme: theme);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(find.bySemanticsLabel('Bước 1 trên 3'), findsOneWidget);
      expect(find.bySemanticsLabel('Cần chọn: Không hạn chế'), findsOneWidget);
      expect(find.bySemanticsLabel('BƯỚC 1/3'), findsNothing);
      expect(
        tester.getSemantics(
          find.text('Đặt pin của NapStop thành "Không hạn chế"'),
        ),
        isSemantics(isHeader: true),
      );
      await _startCheck(tester);
      h.bridge.backgroundCheckValue = BackgroundCheckMsg(
        scheduledAtMs: _nowMs,
        dueAtMs: _nowMs + 30000,
        firedAtMs: _nowMs + 31000,
        screenOnAtFire: false,
        exact: true,
      );
      await _resume(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('W23 360x640 at text scale 2: every phase fits', (tester) async {
    final h = await _open(tester, textScale: 2, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    await _startCheck(tester);
    expect(tester.takeException(), isNull);
    h.bridge.backgroundCheckValue = BackgroundCheckMsg(
      scheduledAtMs: _nowMs,
      dueAtMs: _nowMs + 30000,
      firedAtMs: _nowMs + 50000,
      screenOnAtFire: false,
      exact: true,
    );
    await _resume(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Thử lại').hitTestable(), findsOneWidget);
  });
}
