// T28.4 U14-U17: copied snackbar rule and collectFeedbackDiagnostics.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/features/feedback/data/feedback_launcher.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';

import '../../helpers/fake_core_bridge.dart';

void main() {
  test('U14 showCopiedSnackFor', () {
    expect(showCopiedSnackFor(androidDevice(sdk: 33)), isFalse);
    expect(showCopiedSnackFor(androidDevice(sdk: 35)), isFalse);
    expect(showCopiedSnackFor(androidDevice(sdk: 32)), isTrue);
    expect(showCopiedSnackFor(iosDevice()), isTrue);
    expect(showCopiedSnackFor(null), isTrue);
    final noSdk = androidDevice()..androidSdkInt = null;
    expect(showCopiedSnackFor(noSdk), isTrue);
  });

  test('U15 every source answers at once', () async {
    final device = androidDevice();
    final permissions = androidPermissions();
    final d = await collectFeedbackDiagnostics(
      version: () async => (version: '0.1.0', build: '7'),
      device: () async => device,
      permissions: () async => permissions,
      paramsId: () => 'a1b2c3d4',
      appLanguage: AppLanguage.en,
      deviceLocale: 'vi-VN',
      flavor: AppFlavor.prod,
    );
    expect(d.appVersion, '0.1.0');
    expect(d.appBuild, '7');
    expect(d.device, same(device));
    expect(d.permissions, same(permissions));
    expect(d.paramsId, 'a1b2c3d4');
    expect(d.appLanguage, AppLanguage.en);
    expect(d.deviceLocale, 'vi-VN');
    expect(d.flavor, AppFlavor.prod);
  });

  // testWidgets: the fake clock of the test zone (virtual time).
  testWidgets('U16 hung, failing and throwing sources give null in ≤ 1 s', (
    tester,
  ) async {
    final never = Completer<PermissionStatusMsg>();
    FeedbackDiagnostics? result;
    Object? error;
    unawaited(
      collectFeedbackDiagnostics(
        version: () async => (version: '0.1.0', build: '1'),
        device: () async =>
            throw const BridgeException(BridgeErrorCode.internal, rawCode: 'X'),
        permissions: () => never.future,
        paramsId: () => throw StateError('reader'),
        appLanguage: AppLanguage.system,
        deviceLocale: 'vi-VN',
        flavor: AppFlavor.dev,
      ).then((d) => result = d, onError: (Object e) => error = e),
    );
    await tester.pump(const Duration(milliseconds: 999));
    expect(result, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    expect(error, isNull);
    expect(result, isNotNull);
    expect(result!.permissions, isNull);
    expect(result!.device, isNull);
    expect(result!.paramsId, isNull);
    expect(result!.appVersion, '0.1.0');
  });

  test('U17 version throws → no version, no build', () async {
    final d = await collectFeedbackDiagnostics(
      version: () => Future.error(StateError('package info')),
      device: () async => iosDevice(),
      permissions: () async => iosPermissions(),
      paramsId: () => 'default',
      appLanguage: AppLanguage.vi,
      deviceLocale: 'vi-VN',
      flavor: AppFlavor.dev,
    );
    expect(d.appVersion, isNull);
    expect(d.appBuild, isNull);
    expect(d.device, isNotNull);
    expect(d.paramsId, 'default');
  });
}
