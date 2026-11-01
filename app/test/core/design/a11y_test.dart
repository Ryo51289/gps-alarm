// TC36-TC38: Flutter accessibility guidelines on every catalog section.
// TC39: no layout overflow at text scale 2.0.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/catalog/catalog_sections.dart';
import 'package:napstop/core/design/design.dart';

import '../../helpers/golden_harness.dart';

/// Tall enough for every section at text scale 2.0.
const double _viewHeight = 6000;

void main() {
  for (final section in kCatalogSections) {
    final kinds = [
      NapThemeKind.light,
      NapThemeKind.dark,
      if (section.id == 'buttons' || section.id == 'status') NapThemeKind.alarm,
    ];
    for (final kind in kinds) {
      testWidgets('TC36-38 ${section.id} ${kind.name}', (tester) async {
        await pumpGoldenSection(
          tester,
          section.builder(includeDisabled: false),
          theme: kind,
          viewHeight: _viewHeight,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
      });
    }

    testWidgets('TC39 ${section.id} at text scale 2.0', (tester) async {
      await pumpGoldenSection(
        tester,
        section.builder(includeDisabled: true),
        theme: NapThemeKind.light,
        textScale: 2,
        viewHeight: _viewHeight * 2,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
