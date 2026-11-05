// T28.3 PW06 (screen 4 on iOS, §6): the third tile shows the alarm channel,
// never headphones / alarm style.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/presentation/widgets/tracking_status_row.dart';

import '../../helpers/fake_core_bridge.dart';
import 'tracking_harness.dart';

final _ios = TargetPlatformVariant.only(TargetPlatform.iOS);
final _android = TargetPlatformVariant.only(TargetPlatform.android);

Finder _inRow(Finder f) =>
    find.descendant(of: find.byType(TrackingStatusRow), matching: f);

NapTone _toneOf(WidgetTester tester, String title) => tester
    .widget<NapStatusTile>(
      find.ancestor(of: find.text(title), matching: find.byType(NapStatusTile)),
    )
    .tone;

void main() {
  for (final (name, permissions, device, subtitle, tone) in [
    (
      'iOS 27 + AlarmKit',
      iosPermissions(),
      iosDevice(major: 27),
      'Kêu cả khi Im lặng',
      NapTone.neutral,
    ),
    (
      'iOS 17, notifications only',
      iosPermissions(alarmKit: PermissionStateMsg.notApplicable),
      iosDevice(major: 17),
      'Cần tắt Im lặng',
      NapTone.warning,
    ),
    (
      'iOS 26, AlarmKit denied',
      iosPermissions(alarmKit: PermissionStateMsg.denied),
      iosDevice(),
      'Cần tắt Im lặng',
      NapTone.warning,
    ),
  ]) {
    testWidgets('PW06 $name: alarm tile "$subtitle"', (tester) async {
      final bridge = trackingBridge()
        ..permissions = permissions
        ..deviceInfoValue = device;
      await pumpTracking(tester, bridge: bridge);
      expect(_inRow(find.text('Báo thức')), findsOneWidget);
      expect(_inRow(find.text(subtitle)), findsOneWidget);
      expect(_toneOf(tester, 'Báo thức'), tone);
      expect(_inRow(find.byIcon(NapIcons.alarm)), findsOneWidget);
      expect(_inRow(find.byIcon(NapIcons.headphones)), findsNothing);
      expect(find.text('Tai nghe'), findsNothing);
      expect(find.text('Đã cắm'), findsNothing);
    }, variant: _ios);
  }

  // Review T28.3 #1: unknown (not read yet, or permissionStatus() fails) is
  // no claim either way: the title only, neutral, never "Kêu cả khi Im lặng".
  testWidgets('PW06 iOS, permissions unreadable: no subtitle', (tester) async {
    final bridge = trackingBridge()
      ..permissions = iosPermissions()
      ..deviceInfoValue = iosDevice(major: 27)
      ..permissionStatusError = channelError();
    await pumpTracking(tester, bridge: bridge);
    expect(_inRow(find.text('Báo thức')), findsOneWidget);
    expect(_inRow(find.text('Kêu cả khi Im lặng')), findsNothing);
    expect(_inRow(find.text('Cần tắt Im lặng')), findsNothing);
    expect(_toneOf(tester, 'Báo thức'), NapTone.neutral);
    expect(
      tester
          .widget<NapStatusTile>(
            find.ancestor(
              of: find.text('Báo thức'),
              matching: find.byType(NapStatusTile),
            ),
          )
          .subtitle,
      isNull,
    );
    expect(_inRow(find.byIcon(NapIcons.headphones)), findsNothing);
  }, variant: _ios);

  testWidgets('PW06 iOS, device info unreadable: no subtitle', (tester) async {
    final bridge = trackingBridge()
      ..permissions = iosPermissions()
      ..deviceInfoError = channelError();
    await pumpTracking(tester, bridge: bridge);
    expect(_inRow(find.text('Báo thức')), findsOneWidget);
    expect(_inRow(find.text('Kêu cả khi Im lặng')), findsNothing);
    expect(_inRow(find.text('Cần tắt Im lặng')), findsNothing);
  }, variant: _ios);

  testWidgets('PW06 iOS, headphones unknown: still the alarm tile', (
    tester,
  ) async {
    final bridge = trackingBridge(headphones: null)
      ..permissions = iosPermissions()
      ..deviceInfoValue = iosDevice();
    await pumpTracking(tester, bridge: bridge);
    expect(_inRow(find.text('Kêu cả khi Im lặng')), findsOneWidget);
    expect(_inRow(find.byIcon(NapIcons.headphones)), findsNothing);
  }, variant: _ios);

  testWidgets('PW06 Android: the headphones tile as before', (tester) async {
    await pumpTracking(tester);
    expect(_inRow(find.text('Tai nghe')), findsOneWidget);
    expect(_inRow(find.text('Đã cắm')), findsOneWidget);
    expect(_inRow(find.text('Kêu cả khi Im lặng')), findsNothing);
  }, variant: _android);

  for (final locale in const [Locale('vi'), Locale('en')]) {
    testWidgets('PW06 iOS 320 px, text ×2, $locale: no overflow', (
      tester,
    ) async {
      final bridge = trackingBridge()
        ..permissions = iosPermissions(alarmKit: PermissionStateMsg.denied)
        ..deviceInfoValue = iosDevice();
      await pumpTracking(
        tester,
        bridge: bridge,
        size: const Size(320, 568),
        textScale: 2,
        locale: locale,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(TrackingStatusRow));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }, variant: _ios);
  }
}
