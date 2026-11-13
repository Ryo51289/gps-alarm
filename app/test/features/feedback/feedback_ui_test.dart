// T28.4 W01-W09: the "Góp ý" row of screen 12 and the fallback dialog.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/features/feedback/data/feedback_launcher.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../alarm_settings/helpers/alarm_settings_fakes.dart';

const Size _tall = Size(390, 3200);

DeviceInfoMsg _android35() => DeviceInfoMsg(
  platform: PlatformMsg.android,
  manufacturer: 'Google',
  brand: 'google',
  model: 'Pixel 8',
  osVersion: '15',
  androidSdkInt: 35,
);

/// Records the URIs and answers with [answer].
class _Launcher {
  new(this.answer);

  Future<bool> Function(Uri uri) answer;
  final List<Uri> uris = [];

  Future<bool> call(Uri uri) {
    uris.add(uri);
    return answer(uri);
  }
}

Future<AppHarness> _pump(
  WidgetTester tester,
  _Launcher launcher, {
  FakeCoreBridge? bridge,
  Locale locale = const Locale('vi'),
}) => pumpAppHarness(
  tester,
  bridge:
      bridge ??
      FakeCoreBridge(
        deviceInfoValue: _android35(),
        permissions: androidPermissions(),
      ),
  size: _tall,
  locale: locale,
  initialLocation: AppRoutes.settings,
  overrides: [
    appVersionProvider.overrideWith(
      (ref) => Future.value((version: '0.1.0', build: '1')),
    ),
    engineParamsReaderProvider.overrideWithValue(FakeEngineParamsReader()),
    feedbackLauncherProvider.overrideWithValue(launcher.call),
  ],
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder get _row => find.byKey(const ValueKey('settings-feedback'));

/// Decoded `subject` and `body` of a mailto URI built with encodeComponent.
({String subject, String body}) _fields(Uri uri) {
  final s = uri.toString();
  final parts = s.substring(s.indexOf('?') + 1).split('&');
  return (
    subject: Uri.decodeComponent(parts[0].substring('subject='.length)),
    body: Uri.decodeComponent(parts[1].substring('body='.length)),
  );
}

/// Records `Clipboard.setData` on the platform channel.
List<String> _mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>;
        copied.add(args['text']! as String);
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
  return copied;
}

Future<void> _openDialog(WidgetTester tester, {FakeCoreBridge? bridge}) async {
  final launcher = _Launcher((_) async => false);
  await _pump(tester, launcher, bridge: bridge);
  await _tap(tester, _row);
  expect(launcher.uris, hasLength(1));
  expect(find.text('Chưa mở được ứng dụng email'), findsOneWidget);
}

void main() {
  testWidgets('W01 the row sits between permissions and licenses', (
    tester,
  ) async {
    await _pump(tester, _Launcher((_) async => true));
    expect(find.text('Góp ý'), findsOneWidget);
    expect(find.text('Gửi email cho nhóm phát triển'), findsOneWidget);
    final group = find.ancestor(of: _row, matching: find.byType(NapListGroup));
    expect(
      find.descendant(of: group, matching: find.text('Quyền & tối ưu pin')),
      findsOneWidget,
    );
    final yPermissions = tester.getTopLeft(find.text('Quyền & tối ưu pin')).dy;
    final yFeedback = tester.getTopLeft(find.text('Góp ý')).dy;
    final yLicenses = tester.getTopLeft(find.text('Giấy phép & ghi công')).dy;
    expect(yPermissions, lessThan(yFeedback));
    expect(yFeedback, lessThan(yLicenses));
    final size = tester.getSize(_row);
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(
      tester.getSemantics(_row),
      isSemantics(isButton: true, hasTapAction: true),
    );
  });

  testWidgets('W02 tap opens the composer with subject and device info', (
    tester,
  ) async {
    final launcher = _Launcher((_) async => true);
    await _pump(tester, launcher);
    await _tap(tester, _row);
    final uri = launcher.uris.single;
    expect(uri.scheme, 'mailto');
    expect(uri.path, kFeedbackEmail);
    final f = _fields(uri);
    expect(f.subject, '[NapStop] Góp ý — 0.1.0 (1)');
    expect(f.body, startsWith('Viết góp ý của bạn ở đây:'));
    expect(f.body, contains('OS: Android 15 (API 35)'));
    expect(f.body, contains('Device: Google Pixel 8'));
    expect(f.body, contains('Engine: default'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('W03 English subject and prompt', (tester) async {
    final launcher = _Launcher((_) async => true);
    await _pump(tester, launcher, locale: const Locale('en'));
    expect(find.text('Send feedback'), findsOneWidget);
    await _tap(tester, _row);
    final f = _fields(launcher.uris.single);
    expect(f.subject, '[NapStop] Feedback — 0.1.0 (1)');
    expect(f.body, startsWith('Write your feedback here:'));
  });

  testWidgets('W04 a second tap while busy is ignored', (tester) async {
    var pending = Completer<bool>();
    final launcher = _Launcher((_) => pending.future);
    await _pump(tester, launcher);
    await tester.ensureVisible(_row);
    await tester.pumpAndSettle();
    await tester.tap(_row);
    await tester.pump();
    await tester.tap(_row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(launcher.uris, hasLength(1));
    pending.complete(true);
    await tester.pumpAndSettle();
    pending = Completer<bool>()..complete(true);
    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(launcher.uris, hasLength(2));
  });

  testWidgets('W05 no mail app → dialog with the address', (tester) async {
    await _openDialog(tester);
    expect(find.text(kFeedbackEmail), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Đóng'), findsOneWidget);
    expect(find.text('Sao chép địa chỉ'), findsOneWidget);
  });

  testWidgets('W06 a throwing launcher → dialog, nothing uncaught', (
    tester,
  ) async {
    final launcher = _Launcher(
      (_) async => throw PlatformException(code: 'NO_ACTIVITY'),
    );
    await _pump(tester, launcher);
    await _tap(tester, _row);
    expect(launcher.uris, hasLength(1));
    expect(find.text('Chưa mở được ứng dụng email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('W06b the real launcher turns a PlatformException into false', () async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    // The url_launcher platform used by `flutter test`.
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      throw PlatformException(code: 'NO_ACTIVITY');
    });
    addTearDown(
      () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final container = ProviderContainer.test();
    final launch = container.read(feedbackLauncherProvider);
    expect(
      await launch(Uri.parse('mailto:$kFeedbackEmail?subject=x')),
      isFalse,
    );
    expect(calls, hasLength(1));
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['url'], 'mailto:$kFeedbackEmail?subject=x');
  });

  testWidgets('W07 copy on Android 13+: clipboard, no snackbar', (
    tester,
  ) async {
    final copied = _mockClipboard(tester);
    await _openDialog(tester);
    await _tap(tester, find.byKey(const ValueKey('feedback-copy')));
    expect(copied, [kFeedbackEmail]);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final (name, device) in [
    ('iOS', iosDevice()),
    ('Android 12L', androidDevice(sdk: 32)),
  ]) {
    testWidgets('W08 copy on $name: clipboard and snackbar', (tester) async {
      final copied = _mockClipboard(tester);
      await _openDialog(
        tester,
        bridge: FakeCoreBridge(
          deviceInfoValue: device,
          permissions: device.platform == PlatformMsg.ios
              ? iosPermissions()
              : androidPermissions(),
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('feedback-copy')));
      expect(copied, [kFeedbackEmail]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Đã sao chép địa chỉ'), findsOneWidget);
    });
  }

  for (final barrier in [false, true]) {
    final name = barrier ? 'barrier' : 'button';
    testWidgets('W09 close by $name: no copy, no snackbar', (tester) async {
      final copied = _mockClipboard(tester);
      await _openDialog(tester);
      if (barrier) {
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      } else {
        await _tap(tester, find.text('Đóng'));
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(copied, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
    });
  }
  testerMain();
}

// ---------------------------------------------------------------------------
// Tester additions (T28.4, beyond spec).
/// U13's checks, applied to the real ARB-built subject and body.
void _expectNoPrivateData(String subject, String body) {
  final coordinate = RegExp(r'-?\d{1,3}\.\d{4,}');
  const banned = [
    'lat',
    'lng',
    'lon',
    'trip',
    'destination',
    'place',
    'firebase',
    'installation',
  ];
  for (final text in [subject, body]) {
    expect(coordinate.hasMatch(text), isFalse, reason: text);
    for (final word in banned) {
      expect(text.toLowerCase(), isNot(contains(word)), reason: word);
    }
  }
}

void testerMain() {
  testWidgets('TX03 after copy and close, the row opens the dialog again', (
    tester,
  ) async {
    final copied = _mockClipboard(tester);
    final launcher = _Launcher((_) async => false);
    await _pump(tester, launcher);
    await _tap(tester, _row);
    await _tap(tester, find.byKey(const ValueKey('feedback-copy')));
    await _tap(tester, _row);
    expect(launcher.uris, hasLength(2));
    expect(find.text('Chưa mở được ứng dụng email'), findsOneWidget);
    expect(copied, [kFeedbackEmail]);
  });

  testWidgets('TX05 screen 12 gone before the launcher answers: no dialog', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final launcher = _Launcher((_) => pending.future);
    await _pump(tester, launcher);
    await tester.ensureVisible(_row);
    await tester.pumpAndSettle();
    await tester.tap(_row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(launcher.uris, hasLength(1));
    // The whole app (and screen 12) is unmounted, then "no mail app".
    await tester.pumpWidget(const SizedBox());
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('TX real ARB copy: privacy and size (review nit #3)', () {
    for (final locale in const [Locale('vi'), Locale('en')]) {
      for (final (name, device) in [
        ('Android', _android35()),
        ('iOS', iosDevice()),
      ]) {
        testWidgets('TX04 ${locale.languageCode} $name: no private data', (
          tester,
        ) async {
          final launcher = _Launcher((_) async => true);
          await _pump(
            tester,
            launcher,
            locale: locale,
            bridge: FakeCoreBridge(
              deviceInfoValue: device,
              permissions: device.platform == PlatformMsg.ios
                  ? iosPermissions()
                  : androidPermissions(),
            ),
          );
          await _tap(tester, _row);
          final uri = launcher.uris.single;
          final f = _fields(uri);
          _expectNoPrivateData(f.subject, f.body);
          expect(f.body.length, lessThan(700));
          expect(uri.toString().length, lessThan(2000));
          final raw = uri.toString();
          expect(raw, isNot(contains('+')));
          expect(raw, isNot(contains(' ')));
          expect(f.body, isNot(matches(RegExp('(?<!\r)\n'))));
        });
      }
    }
  });
}
