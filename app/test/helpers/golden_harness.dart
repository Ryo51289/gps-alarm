import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Test font: square glyphs with exact metrics, the same on every OS.
const String kGoldenFontFamily = 'FlutterTest';

/// Wireframe screen width.
const double kGoldenWidth = 390;

/// Key of the boundary that golden tests capture.
const Key kGoldenBoundaryKey = ValueKey('nap-golden-boundary');

/// Pumps [section] at 390 px wide, dpr 1.0, with [theme] built on the
/// FlutterTest font (spec T20 section 7.2).
Future<void> pumpGoldenSection(
  WidgetTester tester,
  Widget section, {
  required NapThemeKind theme,
  double textScale = 1.0,
  Locale locale = const Locale('vi'),
  double viewHeight = 2400,
}) async {
  tester.view
    ..physicalSize = Size(kGoldenWidth, viewHeight)
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final themeData = NapThemes.of(theme, fontFamily: kGoldenFontFamily);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themeData,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kAppSupportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.topCenter,
            child: RepaintBoundary(
              key: kGoldenBoundaryKey,
              // Material (not ColoredBox): InkWell needs a Material ancestor.
              child: Material(
                color: themeData.extension<NapColors>()!.background,
                child: SizedBox(width: kGoldenWidth, child: section),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
