// T28.3 tester (outside the spec, screen 4 on iOS, §6 + review #1): the
// alarm tile never claims "Kêu cả khi Im lặng" while the permissions are
// not read yet, follows a permission change on resume, and drops a stale
// claim when a later read fails.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_status_row.dart';

import '../../helpers/fake_core_bridge.dart';
import 'tracking_fixtures.dart';
import 'tracking_harness.dart';

const _ok = 'Kêu cả khi Im lặng';
const _risk = 'Cần tắt Im lặng';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);

/// A screen 4 bridge whose [permissionStatus] waits for [gate] when set.
/// Local to this file: the shared fake is not changed.
class _GatedBridge extends FakeCoreBridge {
  new()
    : super(
        active: activeMsg(state: w01State()),
        deviceStatusValue: deviceStatusMsg(
          batteryPct: 80,
          headphonesConnected: true,
        ),
      );

  Completer<void>? gate;
  int permissionReads = 0;

  @override
  Future<PermissionStatusMsg> permissionStatus() {
    permissionReads++;
    final g = gate;
    return g == null
        ? super.permissionStatus()
        : g.future.then((_) => super.permissionStatus());
  }
}

Finder _inRow(Finder f) =>
    find.descendant(of: find.byType(TrackingStatusRow), matching: f);

NapStatusTile _alarmTile(WidgetTester tester) => tester.widget<NapStatusTile>(
  find.ancestor(
    of: _inRow(find.text('Báo thức')),
    matching: find.byType(NapStatusTile),
  ),
);

Future<void> _resume(WidgetTester tester) async {
  tester.binding
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final (name, permissions, device, subtitle, tone) in [
    (
      'iOS 17, notifications only',
      iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      iosDevice(major: 17),
      _risk,
      NapTone.warning,
    ),
    (
      'iOS 27 + AlarmKit',
      iosPermissions(),
      iosDevice(major: 27),
      _ok,
      NapTone.neutral,
    ),
  ]) {
    testWidgets('TT01 $name: no subtitle while permissions are pending, '
        'then "$subtitle"', (tester) async {
      final bridge = _GatedBridge()
        ..permissions = permissions
        ..deviceInfoValue = device
        ..gate = Completer<void>();
      await pumpTracking(tester, bridge: bridge);
      expect(bridge.permissionReads, greaterThanOrEqualTo(1));
      // Pending: title only, neutral, no claim either way.
      expect(_inRow(find.text('Báo thức')), findsOneWidget);
      expect(_inRow(find.text(_ok)), findsNothing);
      expect(_inRow(find.text(_risk)), findsNothing);
      expect(_alarmTile(tester).subtitle, isNull);
      expect(_alarmTile(tester).tone, NapTone.neutral);
      expect(_inRow(find.byIcon(NapIcons.headphones)), findsNothing);

      bridge.gate!.complete();
      await tester.pump();
      await tester.pump();
      expect(_inRow(find.text(subtitle)), findsOneWidget);
      expect(_alarmTile(tester).tone, tone);
    }, variant: _ios);
  }

  testWidgets('TT02 AlarmKit revoked in Settings, back to the app: the tile '
      'turns to "$_risk" on resume', (tester) async {
    final bridge = _GatedBridge()
      ..permissions = iosPermissions()
      ..deviceInfoValue = iosDevice(major: 27);
    await pumpTracking(tester, bridge: bridge);
    expect(_inRow(find.text(_ok)), findsOneWidget);

    bridge.permissions = iosPermissions(alarmKit: PermissionStateMsg.denied);
    await _resume(tester);
    expect(_inRow(find.text(_ok)), findsNothing);
    expect(_inRow(find.text(_risk)), findsOneWidget);
    expect(_alarmTile(tester).tone, NapTone.warning);
  }, variant: _ios);

  testWidgets('TT03 a later read fails: the old "$_ok" is dropped, not kept', (
    tester,
  ) async {
    final bridge = _GatedBridge()
      ..permissions = iosPermissions()
      ..deviceInfoValue = iosDevice(major: 27);
    await pumpTracking(tester, bridge: bridge);
    expect(_inRow(find.text(_ok)), findsOneWidget);

    bridge.permissionStatusError = channelError();
    await _resume(tester);
    expect(_inRow(find.text(_ok)), findsNothing);
    expect(_inRow(find.text(_risk)), findsNothing);
    expect(_alarmTile(tester).subtitle, isNull);
    expect(_alarmTile(tester).tone, NapTone.neutral);
  }, variant: _ios);

  for (final (name, permissions, device, subtitle) in [
    ('iOS 26.0 exactly + AlarmKit', iosPermissions(), iosDevice(), _ok),
    (
      'iOS 25 (AlarmKit notApplicable)',
      iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      iosDevice(major: 25),
      _risk,
    ),
    (
      'iOS 26, AlarmKit not asked yet',
      iosPermissions(alarmKit: PermissionStateMsg.notDetermined),
      iosDevice(),
      _risk,
    ),
  ]) {
    testWidgets('TT04 boundary $name: "$subtitle"', (tester) async {
      final bridge = _GatedBridge()
        ..permissions = permissions
        ..deviceInfoValue = device;
      await pumpTracking(tester, bridge: bridge);
      expect(_inRow(find.text(subtitle)), findsOneWidget);
    }, variant: _ios);
  }

  for (final locale in const [Locale('vi'), Locale('en')]) {
    testWidgets('TT05 pending permissions, 320 px, text ×2, $locale: no '
        'overflow (title-only tile)', (tester) async {
      final bridge = _GatedBridge()
        ..permissions = iosPermissions(
          alarmKit: PermissionStateMsg.notApplicable,
        )
        ..deviceInfoValue = iosDevice(major: 17)
        ..gate = Completer<void>();
      await pumpTracking(
        tester,
        bridge: bridge,
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
      );
      await tester.ensureVisible(find.byType(TrackingStatusRow));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      bridge.gate!.complete();
      await tester.pump();
      await tester.pump();
      await tester.ensureVisible(find.byType(TrackingStatusRow));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        _inRow(
          find.text(locale.languageCode == 'vi' ? _risk : 'Turn off Silent'),
        ),
        findsOneWidget,
      );
    }, variant: _ios);
  }
}
