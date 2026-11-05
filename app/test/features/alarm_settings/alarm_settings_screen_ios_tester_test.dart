// T28.3 tester (outside the spec, screen 3 on iOS, §3): the "Kiểu báo" note
// while the permissions are being read, after a permission change on
// resume, and when the read fails.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/ios_alarm_style_note.dart';

import '../../helpers/fake_core_bridge.dart';
import 'helpers/alarm_settings_harness.dart';

const _alarmKitNote =
    'Dùng Báo thức của iPhone: kêu to cả khi máy để Im lặng. Tắt bằng nút '
    'Dừng trên màn khoá.';
const _noSilentNote =
    'Kêu theo âm lượng thông báo. Khi máy để Im lặng có thể không kêu.';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// [permissionStatus] waits for [gate] when set. Local to this file.
class _GatedBridge extends FakeCoreBridge {
  new({super.permissions, super.deviceInfoValue});

  Completer<void>? gate;

  @override
  Future<PermissionStatusMsg> permissionStatus() {
    final g = gate;
    return g == null
        ? super.permissionStatus()
        : g.future.then((_) => super.permissionStatus());
  }
}

Future<void> _showNote(WidgetTester tester) async {
  await tester.ensureVisible(find.byType(IosAlarmStyleNote));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('TS01 iOS 17, permissions read late: ends on the "may not '
      'ring in Silent" note', (tester) async {
    final bridge = _GatedBridge(
      permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      deviceInfoValue: iosDevice(major: 17),
    )..gate = Completer<void>();
    await pumpAlarmSettings(tester, bridge: bridge);
    await _showNote(tester);
    expect(find.byType(IosAlarmStyleNote), findsOneWidget);
    bridge.gate!.complete();
    await tester.pumpAndSettle();
    await _showNote(tester);
    expect(find.text(_noSilentNote), findsOneWidget);
    expect(find.text(_alarmKitNote), findsNothing);
  }, variant: _ios);

  testWidgets('TS02 AlarmKit revoked in Settings, back to screen 3: the '
      'note turns to "may not ring in Silent"', (tester) async {
    final bridge = _GatedBridge(
      permissions: iosPermissions(),
      deviceInfoValue: iosDevice(major: 27),
    );
    await pumpAlarmSettings(tester, bridge: bridge);
    await _showNote(tester);
    expect(find.text(_alarmKitNote), findsOneWidget);
    bridge.permissions = iosPermissions(alarmKit: PermissionStateMsg.denied);
    tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await _showNote(tester);
    expect(find.text(_noSilentNote), findsOneWidget);
    expect(find.text(_alarmKitNote), findsNothing);
  }, variant: _ios);

  // Finding #1 of the T28.3 test report (fixed in round 2): an iPhone on
  // iOS 17 has no AlarmKit, so even when the permission read fails screen 3
  // never says it rings in Silent mode; it says it may not.
  testWidgets(
    'TS03 iOS 17, permission read fails: no "rings in Silent" claim',
    (tester) async {
      final bridge = FakeCoreBridge(
        permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
        deviceInfoValue: iosDevice(major: 17),
      )..permissionStatusError = channelError();
      await pumpAlarmSettings(tester, bridge: bridge);
      await _showNote(tester);
      expect(find.text(_alarmKitNote), findsNothing);
      expect(find.text(_noSilentNote), findsOneWidget);
    },
    variant: _ios,
  );

  // Round 2: iOS 26+ while the permissions are still being read: the header
  // only, no claim either way; the right note once they are read.
  for (final (name, alarmKit, note) in [
    ('AlarmKit granted', PermissionStateMsg.granted, _alarmKitNote),
    ('AlarmKit denied', PermissionStateMsg.denied, _noSilentNote),
  ]) {
    testWidgets('TS05 iOS 27, $name, permissions pending: header only, then '
        'the note', (tester) async {
      final bridge = _GatedBridge(
        permissions: iosPermissions(alarmKit: alarmKit),
        deviceInfoValue: iosDevice(major: 27),
      )..gate = Completer<void>();
      await pumpAlarmSettings(tester, bridge: bridge);
      await _showNote(tester);
      expect(find.text('KIỂU BÁO'), findsOneWidget);
      expect(find.text(_alarmKitNote), findsNothing);
      expect(find.text(_noSilentNote), findsNothing);
      bridge.gate!.complete();
      await tester.pumpAndSettle();
      await _showNote(tester);
      expect(find.text(note), findsOneWidget);
    }, variant: _ios);
  }

  for (final locale in const [Locale('vi'), Locale('en')]) {
    testWidgets('TS04 pending permissions, 320 px, text ×2, $locale: no '
        'overflow', (tester) async {
      final bridge = _GatedBridge(
        permissions: iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
        deviceInfoValue: iosDevice(major: 17),
      )..gate = Completer<void>();
      await pumpAlarmSettings(
        tester,
        bridge: bridge,
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
      );
      await _showNote(tester);
      expect(tester.takeException(), isNull);
      bridge.gate!.complete();
      await tester.pumpAndSettle();
      await _showNote(tester);
      expect(tester.takeException(), isNull);
    }, variant: _ios);
  }
}
