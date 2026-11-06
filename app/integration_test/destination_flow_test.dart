// T23 TI02: Home → search → "dong hoi" → Ga Đồng Hới → screen 3, on an
// emulator or device, no API key needed (the map shows its placeholder).
// Forces the vi locale, so the device language does not matter. A locked
// screen still blocks the run (unlock the emulator first). Screen 0 is
// marked done first (T21 flag), so a fresh install opens Home (T28.2 #5):
//   flutter test integration_test/destination_flow_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/main.dart' as app;

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TI02 choose Ga Đồng Hới and reach screen 3', (tester) async {
    // The finders are Vietnamese: run in vi whatever the device language
    // (test report T23, TI02 note).
    tester.platformDispatcher
      ..localesTestValue = const [Locale('vi', 'VN')]
      ..localeTestValue = const Locale('vi', 'VN');
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await markOnboardingCompleted(createOnboardingStore());
    await app.main();
    await _pumpUntil(tester, find.text('Tìm ga, bến xe, địa chỉ…'));
    await tester.tap(find.text('Tìm ga, bến xe, địa chỉ…').first);
    await _pumpUntil(tester, find.byType(DestinationScreen));
    await tester.enterText(find.byType(TextField), 'dong hoi');
    await _pumpUntil(tester, find.text('Ga Đồng Hới'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.ensureVisible(find.text('Ga Đồng Hới').first);
    await tester.tap(find.text('Ga Đồng Hới').first);
    await _pumpUntil(tester, find.text('Chọn Ga Đồng Hới'));
    await tester.tap(find.text('Chọn Ga Đồng Hới'));
    await tester.pumpAndSettle();
    expect(find.byType(DestinationScreen), findsNothing);
    expect(find.text('Ga Đồng Hới'), findsWidgets);
  });
}
