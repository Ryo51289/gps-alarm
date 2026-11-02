// TC13: locale resolution (unsupported -> Vietnamese). TC14: commonBack.
// TC15: NapStopApp follows the platform brightness.
// T22: NapStopApp now needs a ProviderScope and starts on screen 1 instead of
// the brand placeholder; the assertions are unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/app.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/db/db_providers.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../helpers/app_harness.dart';
import '../helpers/fake_core_bridge.dart';

/// The real app with a fake bridge and an in-memory database. The container
/// is disposed at tear-down, after the widget tree (drift closes its query
/// streams with a timer).
Widget _app() {
  final db = memoryDatabase();
  final container = ProviderContainer.test(
    retry: (_, _) => null,
    overrides: [
      coreBridgeProvider.overrideWithValue(FakeCoreBridge()),
      appDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: const NapStopApp(flavor: AppFlavor.dev),
  );
}

void main() {
  test('TC13 supported locales: vi first, same set as gen-l10n', () {
    expect(kAppSupportedLocales.first, const Locale('vi'));
    // preferred-supported-locales in l10n.yaml: features that use the
    // generated list directly (MaterialApp.router in T22) also fall back to vi.
    expect(AppLocalizations.supportedLocales.first, const Locale('vi'));
    expect(
      kAppSupportedLocales.toSet(),
      AppLocalizations.supportedLocales.toSet(),
    );
  });

  for (final (device, expected) in const [
    (Locale('fr', 'FR'), 'vi'),
    (Locale('en', 'US'), 'en'),
  ]) {
    testWidgets('TC13 NapStopApp on a $device device -> $expected', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = [device];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(_app());
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HomeScreen));
      expect(Localizations.localeOf(context).languageCode, expected);
      expect(
        AppLocalizations.of(context).commonBack,
        expected == 'vi' ? 'Quay lại' : 'Back',
      );
    });
  }

  for (final (device, expected, back) in const [
    (Locale('fr', 'FR'), 'vi', 'Quay lại'),
    (Locale('en', 'US'), 'en', 'Back'),
    (Locale('vi', 'VN'), 'vi', 'Quay lại'),
  ]) {
    testWidgets('TC13/TC14 device $device -> $expected', (tester) async {
      tester.platformDispatcher.localesTestValue = [device];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      late Locale resolved;
      late String label;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: kAppSupportedLocales,
          home: Builder(
            builder: (context) {
              resolved = Localizations.localeOf(context);
              label = AppLocalizations.of(context).commonBack;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(resolved.languageCode, expected);
      expect(label, back);
    });
  }

  testWidgets('TC15 NapStopApp: light then dark background', (tester) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    Color scaffoldColor() => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(Scaffold),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(scaffoldColor().toARGB32(), 0xFFFFFFFF);
    final context = tester.element(find.byType(HomeScreen));
    expect(Theme.of(context).extension<NapColors>(), isNotNull);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(scaffoldColor().toARGB32(), 0xFF0F1115);
    expect(
      Theme.of(tester.element(find.byType(HomeScreen))).extension<NapColors>(),
      NapColors.dark,
    );
  });
}
