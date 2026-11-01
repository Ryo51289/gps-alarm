// TC19: NapChip. TC20: NapBadge.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

Material _material(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(of: find.byType(NapChip), matching: find.byType(Material))
      .first,
);

void main() {
  const c = NapColors.light;

  for (final style in NapChipStyle.values) {
    for (final selected in [true, false]) {
      testWidgets('TC19 ${style.name} selected=$selected', (tester) async {
        var taps = 0;
        await pumpNap(
          tester,
          Center(
            child: NapChip(
              label: '1 km',
              selected: selected,
              style: style,
              onTap: () => taps++,
            ),
          ),
        );
        final filter = style == NapChipStyle.filter;
        final (bg, fg, border) = selected
            ? filter
                  ? (c.inverseSurface, c.onInverseSurface, c.inverseSurface)
                  : (c.accent, c.onAccent, c.accent)
            : (c.surface, c.textPrimary, c.border);
        final material = _material(tester);
        expect(material.color, bg);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, border);
        expect(
          shape.borderRadius,
          BorderRadius.circular(
            style == NapChipStyle.choice ? NapRadii.r12 : NapRadii.pill,
          ),
        );
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('1 km'))
              .text
              .style!
              .color,
          fg,
        );
        expect(
          tester.getSemantics(find.byType(NapChip)),
          isSemantics(
            label: '1 km',
            isButton: true,
            hasSelectedState: true,
            isSelected: selected,
            isEnabled: true,
          ),
        );
        await tester.tap(find.byType(NapChip));
        expect(taps, 1);
      });
    }
  }

  testWidgets('TC19 compact: visible 40, target 48', (tester) async {
    await pumpNap(
      tester,
      Center(
        child: NapChip(
          label: '5 km',
          selected: false,
          compact: true,
          onTap: () {},
        ),
      ),
    );
    expect(
      tester
          .getSize(
            find
                .descendant(
                  of: find.byType(NapChip),
                  matching: find.byType(Material),
                )
                .first,
          )
          .height,
      40,
    );
    expect(tester.getSize(find.byType(NapChip)).height, 48);
  });

  testWidgets('TC19 disabled chip is not enabled', (tester) async {
    await pumpNap(
      tester,
      const Center(
        child: NapChip(label: '10 km', selected: false, onTap: null),
      ),
    );
    expect(
      tester.getSemantics(find.byType(NapChip)),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
  });

  for (final size in NapBadgeSize.values) {
    for (final tone in NapTone.values) {
      testWidgets('TC20 badge ${size.name} ${tone.name}', (tester) async {
        await pumpNap(
          tester,
          Center(
            child: NapBadge(label: 'Báo lại', tone: tone, size: size),
          ),
        );
        final (bg, fg) = switch ((size, tone)) {
          (NapBadgeSize.medium, NapTone.neutral) => (c.surface, c.textPrimary),
          (NapBadgeSize.medium, NapTone.accent) => (c.accent, c.onAccent),
          _ => (tone.containerOf(c), tone.foregroundOf(c)),
        };
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byType(NapBadge),
            matching: find.byType(DecoratedBox),
          ),
        );
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.color, bg);
        if (size == NapBadgeSize.medium && tone == NapTone.neutral) {
          expect(decoration.border, Border.all(color: c.border));
        }
        expect(
          tester
              .renderObject<RenderParagraph>(find.text('Báo lại'))
              .text
              .style!
              .color,
          fg,
        );
        expect(
          tester.getSemantics(find.text('Báo lại')),
          isSemantics(isButton: false, isFocusable: false),
        );
      });
    }
  }
}
