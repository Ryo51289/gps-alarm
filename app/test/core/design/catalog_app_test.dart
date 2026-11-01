// Tester (T20): automatable part of TC43/TC45 on the real catalog app
// (lib/main_catalog.dart): every section opens and closes in every theme,
// at text scale 2.0 and in English; the modal sheet clears a 3-button
// navigation bar (review #2); the license page lists Be Vietnam Pro.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/catalog/catalog_app.dart';
import 'package:napstop/core/design/catalog/catalog_home.dart';
import 'package:napstop/core/design/catalog/catalog_sections.dart';
import 'package:napstop/core/design/design.dart';

/// A 1080x2400 phone at 420 dpi (dpr 2.625), like the test AVD.
void _phone(WidgetTester tester, {double navBarDp = 0}) {
  const dpr = 2.625;
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = dpr
    ..padding = FakeViewPadding(top: 24 * dpr, bottom: navBarDp * dpr)
    ..viewPadding = FakeViewPadding(top: 24 * dpr, bottom: navBarDp * dpr);
  addTearDown(tester.view.reset);
}

/// Scrolls the page (lazy ListView) until [finder] is built and on screen.
Future<void> _reveal(
  WidgetTester tester,
  Finder finder, {
  double step = -300,
}) async {
  for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, Offset(0, step));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openSection(WidgetTester tester, CatalogSection section) async {
  await _tapText(tester, section.title);
  expect(find.byType(CatalogSectionPage), findsOneWidget);
  expect(tester.takeException(), isNull, reason: section.id);
}

Future<void> _back(WidgetTester tester, String label) async {
  // The page header comes first; sections may show more back buttons.
  await tester.tap(find.byTooltip(label).first);
  await tester.pumpAndSettle();
  expect(find.byType(CatalogSectionPage), findsNothing);
}

void main() {
  testWidgets('catalog: every section in every theme, x2.0, vi and en', (
    tester,
  ) async {
    _phone(tester, navBarDp: 48);
    await tester.pumpWidget(const CatalogApp());
    await tester.pumpAndSettle();
    expect(find.text('NapStop design catalog'), findsOneWidget);

    for (final (kind, scale, lang, back) in const [
      ('light', '1.0', 'vi', 'Quay lại'),
      ('dark', '1.0', 'vi', 'Quay lại'),
      ('alarm', '1.0', 'vi', 'Quay lại'),
      ('light', '2.0', 'en', 'Back'),
      ('dark', '2.0', 'vi', 'Quay lại'),
    ]) {
      await _reveal(tester, find.text(kind), step: 300);
      await tester.tap(find.text(kind));
      await tester.pumpAndSettle();
      await tester.tap(find.text(scale));
      await tester.pumpAndSettle();
      await tester.tap(find.text(lang));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(CatalogHome));
      expect(
        Theme.of(context).extension<NapColors>(),
        NapThemes.colorsOf(NapThemeKind.values.byName(kind)),
      );
      expect(
        MediaQuery.textScalerOf(context).scale(10),
        scale == '2.0' ? 20 : 10,
      );
      expect(Localizations.localeOf(context).languageCode, lang);

      for (final section in kCatalogSections) {
        await _openSection(tester, section);
        await _back(tester, back);
      }
    }
  });

  // Review #2 on the real catalog route: Android 15+ edge-to-edge with a
  // 48 dp 3-button navigation bar. Primary action and footnote stay above
  // the bar, also at text scale 2.0 where the sheet scrolls.
  for (final scale in ['1.0', '2.0']) {
    testWidgets('catalog modal sheet clears a 48 dp nav bar at x$scale', (
      tester,
    ) async {
      _phone(tester, navBarDp: 48);
      await tester.pumpWidget(const CatalogApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text(scale));
      await tester.pumpAndSettle();
      await _openSection(
        tester,
        kCatalogSections.singleWhere((s) => s.id == 'sheet'),
      );
      await _tapText(tester, 'Mở sheet');
      expect(find.byType(BottomSheet), findsOneWidget);

      const screenBottom = 2400 / 2.625;
      const navBar = 48.0;
      final sheet = find.byType(BottomSheet);
      final body = find.descendant(
        of: sheet,
        matching: find.byType(NapSheetBody),
      );
      final scrollable = find.descendant(
        of: body,
        matching: find.byType(Scrollable),
      );
      // Scroll to the end of the sheet (it scrolls at x2.0).
      await tester.drag(scrollable, const Offset(0, -2000));
      await tester.pumpAndSettle();

      final footnote = tester.getRect(
        find.descendant(
          of: body,
          matching: find.text('Có thể đổi trong Cài đặt'),
        ),
      );
      final primary = tester.getRect(
        find.descendant(
          of: body,
          matching: find.widgetWithText(NapButton, 'Áp dụng'),
        ),
      );
      expect(footnote.bottom, lessThanOrEqualTo(screenBottom - navBar + 0.01));
      expect(primary.bottom, lessThan(screenBottom - navBar));
      // The primary action is tappable above the bar.
      await tester.tap(
        find.descendant(of: body, matching: find.text('Áp dụng')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byType(BottomSheet),
        findsNothing,
        reason: 'tapping the primary action closes the sheet',
      );
    });
  }

  testWidgets('TC45 (automated part) license page lists Be Vietnam Pro', (
    tester,
  ) async {
    LicenseRegistry.reset();
    resetFontLicenseRegistration();
    addTearDown(LicenseRegistry.reset);
    registerFontLicenses();
    _phone(tester);
    await tester.pumpWidget(const CatalogApp());
    await tester.pumpAndSettle();
    await _tapText(tester, 'Licenses');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text(kBeVietnamProLicensePackage), findsOneWidget);
    await tester.tap(find.text(kBeVietnamProLicensePackage));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('SIL Open Font License', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining(
        'Copyright 2021 The Be Vietnam Pro Project Authors',
        findRichText: true,
      ),
      findsOneWidget,
    );
  });
}
