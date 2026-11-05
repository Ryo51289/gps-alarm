// T28.3 PW03, PW04, PW07 (screen 12): on iOS only the sound and snooze are
// offered; volume follows the iPhone; no preview of the `system` sound.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/dismiss_method_picker.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/fake_key_value_store.dart';
import '../alarm_settings/helpers/alarm_settings_fakes.dart';

const Size _tall = Size(390, 3200);

const _volumeNote = 'Theo âm lượng của iPhone';
const _optionsNote =
    'Tăng dần, mức rung, đèn flash và ưu tiên tai nghe chưa có trên iPhone.';
const _snooze = 'Báo lại tối đa 1 lần, sau 1 phút';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

Future<AppHarness> _pump(
  WidgetTester tester, {
  Map<String, Object>? prefs,
  Size size = _tall,
  Locale locale = const Locale('vi'),
  double textScale = 1,
  String initialLocation = AppRoutes.settings,
}) => pumpAppHarness(
  tester,
  bridge: FakeCoreBridge(
    permissions: iosPermissions(),
    deviceInfoValue: iosDevice(major: 27),
  ),
  keyValueStore: FakeKeyValueStore(prefs),
  size: size,
  locale: locale,
  textScale: textScale,
  initialLocation: initialLocation,
  overrides: [
    appVersionProvider.overrideWith(
      (ref) => Future.value((version: '0.1.0', build: '1')),
    ),
    engineParamsReaderProvider.overrideWithValue(FakeEngineParamsReader()),
  ],
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PW03 iOS: no slider or Android-only rows, one note each', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('Âm lượng báo'), findsOneWidget);
    expect(find.text(_volumeNote), findsOneWidget);
    expect(find.text('Tăng dần âm lượng'), findsNothing);
    expect(find.text('Độ rung'), findsNothing);
    expect(find.text('Nhấp nháy đèn flash'), findsNothing);
    expect(find.text('Ưu tiên phát qua tai nghe'), findsNothing);
    expect(find.byType(NapSwitchRow), findsNWidgets(2)); // consent only
    expect(find.text(_optionsNote), findsOneWidget);
    // "Mặc định cho chuyến mới": no "Cách tắt báo" row.
    expect(find.text('Cách tắt báo'), findsNothing);
    expect(find.text('Báo lại tối đa'), findsOneWidget);
    // The volume row is a note, not a control.
    final row = tester.widget<NapListRow>(
      find.ancestor(
        of: find.text(_volumeNote),
        matching: find.byType(NapListRow),
      ),
    );
    expect(row.onTap, isNull);
    expect(row.chevron, isFalse);
  }, variant: _ios);

  testWidgets('PW03 iOS horn: "Nghe thử" plays', (tester) async {
    final h = await _pump(tester);
    expect(find.text('Còi tàu (mặc định)'), findsOneWidget);
    await _tap(tester, find.text('Nghe thử'));
    expect(h.bridge.previewCalls.single.soundId, 'horn');
  }, variant: _ios);

  testWidgets('PW03 iOS system: no "Nghe thử"', (tester) async {
    await _pump(tester, prefs: {PreferenceKeys.alarmSoundId: 'system'});
    expect(find.text('Âm báo thức của máy'), findsOneWidget);
    expect(find.text('Nghe thử'), findsNothing);
  }, variant: _ios);

  testWidgets('PW03 iOS sheet: picking system stores it, plays nothing', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _tap(tester, find.text('Âm báo thức'));
    await _tap(tester, find.text('Bíp'));
    expect(h.bridge.previewCalls.map((c) => c.soundId), ['beep']);
    await _tap(
      tester,
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Âm báo thức của máy'),
      ),
    );
    expect(h.read(appSettingsProvider).alarm.soundId, 'system');
    // No preview of `system`; the beep that played is stopped.
    expect(h.bridge.previewCalls.map((c) => c.soundId), ['beep']);
    expect(h.bridge.calls.last, 'stopPreview');
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(find.text('Nghe thử'), findsNothing);
    expect(h.bridge.previewCalls, hasLength(1));
  }, variant: _ios);

  testWidgets('PW03 Android system: "Nghe thử", slider and rows as before', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      prefs: {PreferenceKeys.alarmSoundId: 'system'},
    );
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text(_volumeNote), findsNothing);
    expect(find.text(_optionsNote), findsNothing);
    expect(find.text('Tăng dần âm lượng'), findsOneWidget);
    expect(find.text('Độ rung'), findsOneWidget);
    expect(find.text('Nhấp nháy đèn flash'), findsOneWidget);
    expect(find.text('Ưu tiên phát qua tai nghe'), findsOneWidget);
    expect(find.text('Cách tắt báo'), findsOneWidget);
    await _tap(tester, find.text('Nghe thử'));
    expect(h.bridge.previewCalls.single.soundId, 'system');
  }, variant: _android);

  testWidgets('PW04 iOS trip defaults: no dismiss picker, the snooze line', (
    tester,
  ) async {
    final h = await _pump(tester);
    unawaited(h.router.push<void>(AppRoutes.tripDefaults));
    await tester.pumpAndSettle();
    expect(find.text('Mặc định cho chuyến mới'), findsOneWidget);
    await tester.ensureVisible(find.text(_snooze));
    await tester.pumpAndSettle();
    expect(find.byType(DismissMethodPicker), findsNothing);
    expect(find.text('CÁCH TẮT BÁO'), findsNothing);
    expect(find.text(_snooze), findsOneWidget);
  }, variant: _ios);

  testWidgets('PW04 Android trip defaults: the dismiss picker', (tester) async {
    final h = await _pump(tester);
    unawaited(h.router.push<void>(AppRoutes.tripDefaults));
    await tester.pumpAndSettle();
    expect(find.byType(DismissMethodPicker), findsOneWidget);
  }, variant: _android);

  for (final locale in const [Locale('vi'), Locale('en')]) {
    testWidgets('PW07 screen 12 iOS 320 px, text ×2, $locale: no overflow', (
      tester,
    ) async {
      final h = await _pump(
        tester,
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
      );
      final scrollable = find.byType(Scrollable).first;
      for (var i = 0; i < 40; i++) {
        expect(tester.takeException(), isNull, reason: 'scroll step $i');
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      unawaited(h.router.push<void>(AppRoutes.tripDefaults));
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    }, variant: _ios);
  }
}
