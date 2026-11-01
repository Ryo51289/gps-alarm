// TC18: NapIconButton.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

void main() {
  for (final variant in NapIconButtonVariant.values) {
    testWidgets('TC18 ${variant.name}: label, tooltip, sizes', (tester) async {
      var taps = 0;
      await pumpNap(
        tester,
        Center(
          child: NapIconButton(
            icon: NapIcons.settings,
            semanticLabel: 'Cài đặt',
            variant: variant,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(IconButton)),
        isSemantics(tooltip: 'Cài đặt', isButton: true),
      );
      final visible = tester.getSize(
        find
            .descendant(
              of: find.byType(IconButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(visible, const Size(44, 44));
      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));

      await tester.tap(find.byType(IconButton));
      expect(taps, 1);

      await tester.longPress(find.byType(IconButton));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Cài đặt'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  }

  testWidgets('TC18 floating: shadow on light, border on dark', (tester) async {
    const button = Center(
      child: NapIconButton(
        icon: NapIcons.gps,
        semanticLabel: 'Vị trí',
        variant: NapIconButtonVariant.floating,
        onPressed: null,
      ),
    );
    await pumpNap(tester, button);
    final decorated = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(NapIconButton),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(
      (decorated.decoration as ShapeDecoration).shadows,
      NapShadows.light.floating,
    );

    await pumpNap(tester, button, theme: NapThemeKind.dark);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(IconButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(
      (material.shape! as OutlinedBorder).side.color,
      NapColors.dark.border,
    );
  });

  testWidgets('TC18 size 56 square uses r16 and icon 22', (tester) async {
    await pumpNap(
      tester,
      Center(
        child: NapIconButton(
          icon: NapIcons.bookmark,
          semanticLabel: 'Lưu điểm',
          size: 56,
          square: true,
          onPressed: () {},
        ),
      ),
    );
    expect(tester.widget<Icon>(find.byIcon(NapIcons.bookmark)).size, 22);
    expect(
      tester.getSize(
        find
            .descendant(
              of: find.byType(IconButton),
              matching: find.byType(Material),
            )
            .first,
      ),
      const Size(56, 56),
    );
  });
}
