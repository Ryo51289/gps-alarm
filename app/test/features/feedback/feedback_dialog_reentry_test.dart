// T28.4 tester, review minor #1: while `Clipboard.setData` is pending, the
// fallback dialog must not pop a second time (that pops screen 12 itself).
// Kept in its own file: a failure here breaks the router of later tests.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/features/feedback/data/feedback_launcher.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../alarm_settings/helpers/alarm_settings_fakes.dart';

Finder get _row => find.byKey(const ValueKey('settings-feedback'));
Finder get _copy => find.byKey(const ValueKey('feedback-copy'));

/// Screen 12 with a launcher that always fails, so the dialog opens.
Future<void> _openDialog(WidgetTester tester) async {
  await pumpAppHarness(
    tester,
    bridge: FakeCoreBridge(
      deviceInfoValue: DeviceInfoMsg(
        platform: PlatformMsg.android,
        manufacturer: 'Google',
        brand: 'google',
        model: 'Pixel 8',
        osVersion: '15',
        androidSdkInt: 35,
      ),
      permissions: androidPermissions(),
    ),
    size: const Size(390, 3200),
    initialLocation: AppRoutes.settings,
    overrides: [
      appVersionProvider.overrideWith(
        (ref) => Future.value((version: '0.1.0', build: '1')),
      ),
      engineParamsReaderProvider.overrideWithValue(FakeEngineParamsReader()),
      feedbackLauncherProvider.overrideWithValue((_) async => false),
    ],
  );
  await tester.ensureVisible(_row);
  await tester.pumpAndSettle();
  await tester.tap(_row);
  await tester.pumpAndSettle();
  expect(find.text('Chưa mở được ứng dụng email'), findsOneWidget);
}

/// `Clipboard.setData` that stays pending until the completer completes
/// (a busy platform main thread).
(List<String>, Completer<void>) _mockSlowClipboard(WidgetTester tester) {
  final copied = <String>[];
  final gate = Completer<void>();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
        await gate.future;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return (copied, gate);
}

/// Screen 12 is still shown, with nothing over it.
void _expectStillOnSettings(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  expect(find.byType(AlertDialog), findsNothing);
  expect(_row, findsOneWidget);
  expect(find.text('Giấy phép & ghi công'), findsOneWidget);
}

void main() {
  testWidgets('TX01 double tap on copy while the clipboard is pending', (
    tester,
  ) async {
    final (copied, gate) = _mockSlowClipboard(tester);
    await _openDialog(tester);
    await tester.tap(_copy);
    await tester.pump();
    // A fixed dialog is already closing or ignores the second tap.
    await tester.tap(_copy, warnIfMissed: false);
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(copied, isNotEmpty);
    expect(copied.toSet(), {kFeedbackEmail});
    _expectStillOnSettings(tester);
  });

  testWidgets('TX02 copy then system back while the clipboard is pending', (
    tester,
  ) async {
    final (copied, gate) = _mockSlowClipboard(tester);
    await _openDialog(tester);
    await tester.tap(_copy);
    await tester.pump();
    // Back only while the dialog is still the open (interactive) route. A fix
    // that closes the dialog at once leaves no race; Back then would be a
    // plain Back on screen 12 (leaves the app), not the case under test.
    if (find.byType(AlertDialog).hitTestable().evaluate().isNotEmpty) {
      await tester.binding.handlePopRoute();
      await tester.pump();
    }
    gate.complete();
    await tester.pumpAndSettle();
    expect(copied, [kFeedbackEmail]);
    _expectStillOnSettings(tester);
  });

  // Review round 2 nit #1: the dialog is already closed when the clipboard
  // write fails (Android: `setPrimaryClip` throwing, e.g. SecurityException,
  // comes back as a PlatformException). The app must stay on screen 12 with
  // no framework error. An escaped PlatformException is tolerated (it lands
  // in PlatformDispatcher.onError -> Crashlytics, see the test report), any
  // other uncaught error fails.
  testWidgets('TX06 clipboard write fails after the dialog closed', (
    tester,
  ) async {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          calls.add(call.method);
          throw PlatformException(code: 'error', message: 'SecurityException');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _openDialog(tester);
    final escaped = <Object>[];
    await runZonedGuarded(
      () => tester.tap(_copy),
      (error, stack) => escaped.add(error),
    );
    await tester.pumpAndSettle();
    expect(calls, ['Clipboard.setData']);
    expect(escaped, everyElement(isA<PlatformException>()));
    _expectStillOnSettings(tester);
    // Screen 12 still works: the row opens the dialog again.
    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(find.text('Chưa mở được ứng dụng email'), findsOneWidget);
    // Record what the current build does, for the report.
    debugPrint('TX06 escaped errors: ${escaped.length}');
  });
}
