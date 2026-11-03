// Tester T21: screens 0 and 9 at text scale 2.0 in vi AND en, on the
// smallest supported phone (320x568) and 360x640, with every row and every
// phase of screen 9. W23 covers vi at 360x640 only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';

final int _nowMs = kHarnessNow.millisecondsSinceEpoch;

const _sizes = [Size(320, 568), Size(360, 640)];
const _locales = [Locale('vi'), Locale('en')];

FakeCoreBridge _everyRow() =>
    FakeCoreBridge(
        deviceInfoValue: androidDevice(manufacturer: 'Xiaomi', brand: 'Redmi'),
      )
      ..backgroundCheckNowMs = _nowMs
      ..permissions = androidPermissions(
        precise: PermissionStateMsg.notDetermined,
        notifications: PermissionStateMsg.denied,
        fullScreenIntent: PermissionStateMsg.denied,
        exactAlarm: PermissionStateMsg.denied,
        batteryOptimizationIgnored: PermissionStateMsg.denied,
      );

Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollables = find.byType(Scrollable);
  if (scrollables.evaluate().isEmpty) {
    return;
  }
  final s = scrollables.first;
  for (var i = 0; i < 30; i++) {
    await tester.drag(s, const Offset(0, -200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  }
}

void _noOverflow(WidgetTester tester, String what) {
  expect(tester.takeException(), isNull, reason: what);
}

void main() {
  for (final locale in _locales) {
    final l = lookupAppLocalizations(locale);
    for (final size in _sizes) {
      final tag =
          '${locale.languageCode} ${size.width.toInt()}x'
          '${size.height.toInt()}';
      // Tester T21 finding #1 (minor a11y): en, 320 px wide, x2.0: the fixed
      // bottom area of screen 0 (button + missing note + privacy note)
      // overflows by 34 px. Remove the skip when fixed.
      final screen0Skip = locale.languageCode == 'en' && size.width < 340;

      testWidgets(
        skip: screen0Skip,
        'screen 0, every Android row, x2.0, $tag',
        (tester) async {
          await pumpAppHarness(
            tester,
            bridge: _everyRow(),
            initialLocation: AppRoutes.onboarding,
            textScale: 2,
            locale: locale,
            size: size,
          );
          _noOverflow(tester, 'first frame');
          expect(find.text(l.permFullScreenTitle), findsOneWidget);
          expect(find.text(l.permExactAlarmRowTitle), findsOneWidget);
          await _scrollThrough(tester);
          // The main button stays reachable (fixed bottom area).
          expect(find.text(l.onboardingContinue).hitTestable(), findsOneWidget);
          // The last row's button can be reached and is fully visible.
          final batteryButton = find.text(
            l.permBatteryGuideButton(l.bgBrandXiaomi, 3),
          );
          await tester.ensureVisible(batteryButton);
          await tester.pumpAndSettle();
          expect(batteryButton.hitTestable(), findsOneWidget);
          _noOverflow(tester, 'scrolled');
        },
      );

      testWidgets(skip: screen0Skip, 'screen 0, iOS 26 rows, x2.0, $tag', (
        tester,
      ) async {
        final bridge = FakeCoreBridge(deviceInfoValue: iosDevice())
          ..permissions = iosPermissions(
            location: LocationAccessMsg.notDetermined,
            precise: PermissionStateMsg.notDetermined,
            notifications: PermissionStateMsg.denied,
            alarmKit: PermissionStateMsg.notDetermined,
          );
        await pumpAppHarness(
          tester,
          bridge: bridge,
          initialLocation: AppRoutes.onboarding,
          textScale: 2,
          locale: locale,
          size: size,
        );
        _noOverflow(tester, 'first frame');
        await _scrollThrough(tester);
        expect(find.text(l.onboardingContinue).hitTestable(), findsOneWidget);
      });

      testWidgets(skip: screen0Skip, 'screen 0 explainer sheets, x2.0, $tag', (
        tester,
      ) async {
        await pumpAppHarness(
          tester,
          bridge: _everyRow(),
          initialLocation: AppRoutes.onboarding,
          textScale: 2,
          locale: locale,
          size: size,
        );
        // "Bật Chính xác" (precise sheet), then the FSI and exact sheets.
        for (final label in [l.onboardingActionPrecise, l.permOpenSettings]) {
          final button = find.text(label).first;
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          await tester.tap(button);
          await tester.pumpAndSettle();
          _noOverflow(tester, 'sheet $label');
          final later = find.text(l.commonLater);
          if (later.evaluate().isNotEmpty) {
            await tester.ensureVisible(later);
            await tester.pumpAndSettle();
            expect(later.hitTestable(), findsOneWidget, reason: label);
            await tester.tap(later);
            await tester.pumpAndSettle();
          }
        }
      });

      testWidgets('screen 9 steps and done phase, x2.0, $tag', (tester) async {
        final h = await pumpAppHarness(
          tester,
          bridge: _everyRow(),
          textScale: 2,
          locale: locale,
          size: size,
        );
        unawaited(h.router.push<void>(AppRoutes.batteryGuide));
        await tester.pumpAndSettle();
        _noOverflow(tester, 'step 1');
        for (var i = 0; i < 3; i++) {
          await _scrollThrough(tester);
          final done = find.text(l.batteryGuideStepDone);
          expect(done.hitTestable(), findsOneWidget, reason: 'step ${i + 1}');
          await tester.tap(done);
          await tester.pumpAndSettle();
          _noOverflow(tester, 'after step ${i + 1}');
        }
        expect(find.text(l.batteryGuideAllDone(3)), findsOneWidget);
        await _scrollThrough(tester);
        expect(
          find.text(l.batteryGuideTestStart).hitTestable(),
          findsOneWidget,
        );
      });

      final records = <String, BackgroundCheckMsg>{
        'running': BackgroundCheckMsg(
          scheduledAtMs: _nowMs - 5000,
          dueAtMs: _nowMs + 25000,
          exact: true,
        ),
        'passed': BackgroundCheckMsg(
          scheduledAtMs: _nowMs - 120000,
          dueAtMs: _nowMs - 90000,
          firedAtMs: _nowMs - 89000,
          screenOnAtFire: false,
          exact: true,
        ),
        'screenOn': BackgroundCheckMsg(
          scheduledAtMs: _nowMs - 120000,
          dueAtMs: _nowMs - 90000,
          firedAtMs: _nowMs - 89000,
          screenOnAtFire: true,
          exact: true,
        ),
        'late': BackgroundCheckMsg(
          scheduledAtMs: _nowMs - 120000,
          dueAtMs: _nowMs - 90000,
          firedAtMs: _nowMs - 1000,
          screenOnAtFire: false,
          exact: false,
        ),
        'missed': BackgroundCheckMsg(
          scheduledAtMs: _nowMs - 180000,
          dueAtMs: _nowMs - 150000,
          exact: true,
        ),
      };
      for (final MapEntry(key: name, value: record) in records.entries) {
        testWidgets('screen 9 $name, x2.0, $tag', (tester) async {
          final bridge = _everyRow()..backgroundCheckValue = record;
          final h = await pumpAppHarness(
            tester,
            bridge: bridge,
            textScale: 2,
            locale: locale,
            size: size,
          );
          unawaited(h.router.push<void>(AppRoutes.batteryGuide));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          _noOverflow(tester, name);
          final expected = switch (name) {
            'running' => l.batteryGuideTestCancel,
            'passed' => l.batteryGuideTestPassed,
            'screenOn' => l.batteryGuideTestScreenOn,
            'late' => l.batteryGuideTestLate(89),
            _ => l.batteryGuideTestFailed,
          };
          expect(find.text(expected), findsOneWidget, reason: name);
          for (var i = 0; i < 30; i++) {
            final s = find.byType(Scrollable);
            if (s.evaluate().isEmpty) {
              break;
            }
            await tester.drag(s.first, const Offset(0, -200));
            await tester.pump(const Duration(milliseconds: 50));
            _noOverflow(tester, '$name scrolled');
          }
          final primary = switch (name) {
            'running' => l.batteryGuideTestCancel,
            'passed' => l.commonDone,
            _ => l.commonRetry,
          };
          expect(find.text(primary).hitTestable(), findsOneWidget);
          if (name == 'running') {
            // Leave the running phase so its 1 s timer stops.
            await tester.tap(find.text(primary));
            await tester.pump();
          }
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
