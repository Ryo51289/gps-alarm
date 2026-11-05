// T28.3 PW01, PW02, PW07 (screen 3): on iOS the alarm style and dismiss
// method are not offered (the system alarm ignores them, PLAN-ios Q2 = A).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/alarm_style_picker.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/dismiss_method_picker.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/ios_alarm_style_note.dart';

import '../../helpers/fake_core_bridge.dart';
import 'helpers/alarm_settings_harness.dart';

const _alarmKitNote =
    'Dùng Báo thức của iPhone: kêu to cả khi máy để Im lặng. Tắt bằng nút '
    'Dừng trên màn khoá.';
const _noSilentNote =
    'Kêu theo âm lượng thông báo. Khi máy để Im lặng có thể không kêu.';
const _snooze = 'Báo lại tối đa 1 lần, sau 1 phút';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

/// Scrolls the screen to its end so the last blocks are built.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.ensureVisible(find.text(_snooze));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('PW01 iOS + AlarmKit: no pickers, the iPhone alarm note', (
    tester,
  ) async {
    await pumpAlarmSettings(
      tester,
      bridge: FakeCoreBridge(
        permissions: iosPermissions(),
        deviceInfoValue: iosDevice(major: 27),
      ),
      // A stored Android-only choice is kept, only hidden (D4).
      prefs: {PreferenceKeys.tripDismiss: DismissMethodMsg.shake.name},
    );
    await _scrollToEnd(tester);
    expect(find.byType(AlarmStylePicker), findsNothing);
    expect(find.byType(DismissMethodPicker), findsNothing);
    expect(find.byType(IosAlarmStyleNote), findsOneWidget);
    expect(find.text('KIỂU BÁO'), findsOneWidget);
    expect(find.text(_alarmKitNote), findsOneWidget);
    expect(find.text(_noSilentNote), findsNothing);
    expect(find.text('CÁCH TẮT BÁO'), findsNothing);
    expect(find.text('Lắc máy'), findsNothing);
    expect(find.text(_snooze), findsOneWidget);
  }, variant: _ios);

  testWidgets('PW01 D4: the hidden stored values still reach startTrip', (
    tester,
  ) async {
    final h = await pumpAlarmSettings(
      tester,
      bridge: FakeCoreBridge(
        permissions: iosPermissions(),
        deviceInfoValue: iosDevice(major: 27),
      ),
      prefs: {
        PreferenceKeys.tripDismiss: DismissMethodMsg.math.name,
        PreferenceKeys.tripAlarmStyle: 'vibrateOnly',
      },
    );
    await tapVisible(tester, find.text('Bắt đầu theo dõi'));
    final alarm = h.bridge.startTripCalls.single.config.alarm;
    expect(alarm.dismissMethod, DismissMethodMsg.math);
    // vibrateOnly → volume 0 (T25 style mapping), unchanged on iOS.
    expect(alarm.volume, 0.0);
  }, variant: _ios);

  for (final (name, permissions, device) in [
    (
      'iOS 26, AlarmKit denied',
      iosPermissions(alarmKit: PermissionStateMsg.denied),
      iosDevice(),
    ),
    (
      'iOS 17, notifications only',
      iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      iosDevice(major: 17),
    ),
  ]) {
    testWidgets('PW01 $name: may stay quiet in Silent mode', (tester) async {
      await pumpAlarmSettings(
        tester,
        bridge: FakeCoreBridge(
          permissions: permissions,
          deviceInfoValue: device,
        ),
      );
      await _scrollToEnd(tester);
      expect(find.byType(AlarmStylePicker), findsNothing);
      expect(find.byType(DismissMethodPicker), findsNothing);
      expect(find.text('KIỂU BÁO'), findsOneWidget);
      expect(find.text(_noSilentNote), findsOneWidget);
      expect(find.text(_alarmKitNote), findsNothing);
      expect(find.text(_snooze), findsOneWidget);
    }, variant: _ios);
  }

  // Test report #1: unknown permissions on iOS 26+ claim nothing (header
  // only, like screen 4); iOS before 26 is "may not ring" even then.
  testWidgets('PW01 iOS 27, permission read fails: header only', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      permissions: iosPermissions(),
      deviceInfoValue: iosDevice(major: 27),
    )..permissionStatusError = channelError();
    await pumpAlarmSettings(tester, bridge: bridge);
    await _scrollToEnd(tester);
    expect(find.byType(IosAlarmStyleNote), findsOneWidget);
    expect(find.text('KIỂU BÁO'), findsOneWidget);
    expect(find.text(_alarmKitNote), findsNothing);
    expect(find.text(_noSilentNote), findsNothing);
    expect(find.text(_snooze), findsOneWidget);
  }, variant: _ios);

  testWidgets('PW01 iOS 17, permission read fails: may stay quiet', (
    tester,
  ) async {
    final bridge = FakeCoreBridge(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      deviceInfoValue: iosDevice(major: 17),
    )..permissionStatusError = channelError();
    await pumpAlarmSettings(tester, bridge: bridge);
    await _scrollToEnd(tester);
    expect(find.text(_noSilentNote), findsOneWidget);
    expect(find.text(_alarmKitNote), findsNothing);
  }, variant: _ios);

  testWidgets('PW02 Android: both pickers as before T28.3', (tester) async {
    await pumpAlarmSettings(tester);
    await _scrollToEnd(tester);
    expect(find.byType(AlarmStylePicker), findsOneWidget);
    expect(find.byType(DismissMethodPicker), findsOneWidget);
    expect(find.byType(IosAlarmStyleNote), findsNothing);
    expect(find.text('CÁCH TẮT BÁO'), findsOneWidget);
    expect(find.text(_alarmKitNote), findsNothing);
    expect(find.text(_snooze), findsOneWidget);
  }, variant: _android);

  for (final locale in const [Locale('vi'), Locale('en')]) {
    for (final ringsInSilent in [true, false]) {
      testWidgets('PW07 screen 3 iOS 320 px, text ×2, $locale, '
          'ringsInSilent $ringsInSilent: no overflow', (tester) async {
        await pumpAlarmSettings(
          tester,
          size: const Size(320, 568),
          textScale: 2,
          locale: locale,
          bridge: FakeCoreBridge(
            permissions: ringsInSilent
                ? iosPermissions()
                : iosPermissions(alarmKit: PermissionStateMsg.denied),
            deviceInfoValue: iosDevice(),
          ),
        );
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.byType(IosAlarmStyleNote));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 12; i++) {
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'scroll step $i');
        }
      }, variant: _ios);
    }
  }
}
