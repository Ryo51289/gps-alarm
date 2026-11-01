// TC40: 30 golden images of the catalog sections (spec T20 section 7.2).
// Update with: flutter test --update-goldens --tags golden
@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/catalog/catalog_sections.dart';
import 'package:napstop/core/design/design.dart';

import '../../helpers/golden_harness.dart';

/// (section id, theme, text scale): 11 x {light, dark} + 4 alarm + 4 x2.
final List<(String, NapThemeKind, double)> kGoldenCases = [
  for (final s in kCatalogSections) ...[
    (s.id, NapThemeKind.light, 1.0),
    (s.id, NapThemeKind.dark, 1.0),
  ],
  for (final id in ['typography', 'colors', 'buttons', 'status'])
    (id, NapThemeKind.alarm, 1.0),
  for (final id in ['buttons', 'chips', 'cards', 'selection'])
    (id, NapThemeKind.light, 2.0),
];

void main() {
  test('30 golden cases', () {
    expect(kGoldenCases, hasLength(30));
    expect(kGoldenCases.toSet(), hasLength(30));
  });

  for (final (id, kind, scale) in kGoldenCases) {
    final name = '${id}_${kind.name}${scale == 1.0 ? '' : '_x2'}';
    testWidgets('golden $name', (tester) async {
      final section = kCatalogSections.singleWhere((s) => s.id == id);
      await pumpGoldenSection(
        tester,
        section.builder(includeDisabled: true),
        theme: kind,
        textScale: scale,
        viewHeight: scale == 1.0 ? 4000 : 8000,
      );
      await expectLater(
        find.byKey(kGoldenBoundaryKey),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
