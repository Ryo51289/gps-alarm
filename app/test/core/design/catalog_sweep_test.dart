// Tester (T20), beyond TC36-TC39: every catalog section (all 20
// components) in all 3 themes, at text scales 1.3 and 2.0, LTR and RTL, on
// narrow phones; tap targets, labels and contrast where the spec only asks
// for light/dark at 1.0.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/core/design/catalog/catalog_sections.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../helpers/golden_harness.dart';

/// Pumps [section] like the golden harness, with a configurable width,
/// direction and locale.
Future<void> _pumpSection(
  WidgetTester tester,
  Widget section, {
  required NapThemeKind theme,
  double textScale = 1.0,
  double width = kGoldenWidth,
  TextDirection? direction,
  Locale locale = const Locale('vi'),
}) async {
  tester.view
    ..physicalSize = Size(width, 12000)
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
        builder: (context) {
          final body = MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: Align(
              alignment: Alignment.topCenter,
              child: Material(
                color: themeData.extension<NapColors>()!.background,
                child: SizedBox(width: width, child: section),
              ),
            ),
          );
          return direction == null
              ? body
              : Directionality(textDirection: direction, child: body);
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fails when a NapListRow child is laid out outside the row (review N2:
/// the custom row layout does not report overflow itself).
void _expectRowsContainChildren(WidgetTester tester) {
  final rows = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_RowLayout',
  );
  for (final element in rows.evaluate()) {
    final box = element.renderObject! as RenderBox;
    box.visitChildren((child) {
      final b = child as RenderBox;
      final rect = (b.parentData! as BoxParentData).offset & b.size;
      expect(
        rect.left >= -0.01 && rect.right <= box.size.width + 0.01,
        isTrue,
        reason: 'NapListRow child $rect overflows row ${box.size}',
      );
    });
  }
}

/// The 20 components of spec T20 section 5 (bottom sheet = body + container).
const List<String> _components = [
  'NapButton',
  'NapIconButton',
  'NapChip',
  'NapBadge',
  'NapSegmentedControl',
  'NapSwitchRow',
  'NapRadioIndicator',
  'NapOptionCard',
  'NapCard',
  'NapListGroup',
  'NapListRow',
  'NapIconTile',
  'NapSectionHeader',
  'NapScreenHeader',
  'NapStatusTile',
  'NapBanner',
  'NapSheetBody',
  'NapSheetContainer',
  'NapBigValue',
  'NapLabeledSlider',
  'NapSearchField',
];

void main() {
  testWidgets('catalog sections contain all 20 components', (tester) async {
    final seen = <String>{};
    for (final section in kCatalogSections) {
      await _pumpSection(
        tester,
        section.builder(includeDisabled: true),
        theme: NapThemeKind.light,
      );
      for (final e in find.byWidgetPredicate((_) => true).evaluate()) {
        // Generic types print as NapSegmentedControl<int>.
        seen.add(e.widget.runtimeType.toString().split('<').first);
      }
    }
    expect(seen, containsAll(_components));
  });

  for (final section in kCatalogSections) {
    for (final kind in NapThemeKind.values) {
      for (final scale in const [1.3, 2.0]) {
        testWidgets('no overflow: ${section.id} ${kind.name} x$scale', (
          tester,
        ) async {
          await _pumpSection(
            tester,
            section.builder(includeDisabled: true),
            theme: kind,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          _expectRowsContainChildren(tester);
        });
      }

      testWidgets('no overflow: ${section.id} ${kind.name} x2.0 RTL', (
        tester,
      ) async {
        await _pumpSection(
          tester,
          section.builder(includeDisabled: true),
          theme: kind,
          textScale: 2,
          direction: TextDirection.rtl,
        );
        expect(tester.takeException(), isNull);
        _expectRowsContainChildren(tester);
      });

      // Tap targets and labels hold in every theme and at text scale 2.0.
      for (final scale in const [1.0, 2.0]) {
        testWidgets('tap targets + labels: ${section.id} ${kind.name} '
            'x$scale', (tester) async {
          await _pumpSection(
            tester,
            section.builder(includeDisabled: false),
            theme: kind,
            textScale: scale,
          );
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        });
      }
    }

    // Text contrast at text scale 2.0 in every theme, and the alarm theme at
    // 1.0 on every section (TC38 checks light/dark at 1.0, alarm on 2).
    for (final (kind, scale) in [
      for (final k in NapThemeKind.values) (k, 2.0),
      (NapThemeKind.alarm, 1.0),
    ]) {
      testWidgets('text contrast: ${section.id} ${kind.name} x$scale', (
        tester,
      ) async {
        await _pumpSection(
          tester,
          section.builder(includeDisabled: false),
          theme: kind,
          textScale: scale,
        );
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }

    // Common Android widths: 360 dp (most budget phones) and 320 dp.
    for (final width in const [360.0, 320.0]) {
      testWidgets('no overflow: ${section.id} light x2.0 width $width', (
        tester,
      ) async {
        await _pumpSection(
          tester,
          section.builder(includeDisabled: true),
          theme: NapThemeKind.light,
          textScale: 2,
          width: width,
        );
        expect(tester.takeException(), isNull);
        _expectRowsContainChildren(tester);
      });
    }
  }

  // Icon-only buttons must expose a label (TalkBack reads the tooltip) and a
  // tap action, in both languages and every theme. Covers the back button of
  // NapScreenHeader ("Quay lại" / "Back").
  for (final kind in NapThemeKind.values) {
    for (final locale in kAppSupportedLocales) {
      testWidgets('icon-only buttons are labeled: ${kind.name} '
          '${locale.languageCode}', (tester) async {
        final handle = tester.ensureSemantics();
        final labels = <String>[];
        for (final section in kCatalogSections) {
          await _pumpSection(
            tester,
            section.builder(includeDisabled: false),
            theme: kind,
            locale: locale,
          );
          for (final e in find.byType(NapIconButton).evaluate()) {
            final button = e.widget as NapIconButton;
            final data = tester
                .getSemantics(
                  find.descendant(
                    of: find.byWidget(button),
                    matching: find.byIcon(button.icon),
                  ),
                )
                .getSemanticsData();
            final label = '${data.label} ${data.tooltip}'.trim();
            expect(label, isNotEmpty, reason: section.id);
            expect(data.flagsCollection.isButton, isTrue, reason: label);
            expect(
              data.hasAction(SemanticsAction.tap),
              isTrue,
              reason: '${section.id} "$label" has no tap action',
            );
            labels.add(label);
          }
        }
        expect(labels.length, greaterThanOrEqualTo(3));
        expect(
          labels,
          contains(locale.languageCode == 'vi' ? 'Quay lại' : 'Back'),
        );
        handle.dispose();
      });
    }
  }
}
