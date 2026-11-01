import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Pumps [child] in a themed, localized app for widget tests.
Future<void> pumpNap(
  WidgetTester tester,
  Widget child, {
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1.0,
  Locale locale = const Locale('vi'),
  double width = 390,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: NapThemes.of(theme),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kAppSupportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Colors of [theme].
NapColors napColorsOf(NapThemeKind theme) => NapThemes.colorsOf(theme);
