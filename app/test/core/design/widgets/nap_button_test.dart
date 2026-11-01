// TC16, TC17: NapButton.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

/// Background, foreground and border of [variant] per spec section 5.1.
(Color, Color, Color?) _expected(NapButtonVariant variant, NapColors c) =>
    switch (variant) {
      NapButtonVariant.primary => (c.accent, c.onAccent, null),
      NapButtonVariant.secondary => (
        Colors.transparent,
        c.textPrimary,
        c.border,
      ),
      NapButtonVariant.tonal => (c.fill, c.textPrimary, null),
      NapButtonVariant.danger => (Colors.transparent, c.danger, null),
      NapButtonVariant.text => (Colors.transparent, c.textSecondary, null),
      NapButtonVariant.link => (Colors.transparent, c.accent, null),
    };

Material _buttonMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(of: _buttonStyleButton, matching: find.byType(Material))
      .first,
);

void main() {
  for (final kind in NapThemeKind.values) {
    for (final variant in NapButtonVariant.values) {
      testWidgets('TC16 ${variant.name} on ${kind.name}', (tester) async {
        var taps = 0;
        await pumpNap(
          tester,
          NapButton(
            label: 'Tiếp tục',
            variant: variant,
            onPressed: () => taps++,
          ),
          theme: kind,
        );
        final c = napColorsOf(kind);
        final (bg, fg, border) = _expected(variant, c);
        final material = _buttonMaterial(tester);
        expect(material.color!.toARGB32(), bg.toARGB32());
        final side = (material.shape! as OutlinedBorder).side;
        if (border == null) {
          expect(side.style, BorderStyle.none);
        } else {
          expect(side.color, border);
          expect(side.width, 1);
        }
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text('Tiếp tục'),
        );
        expect(paragraph.text.style!.color, fg);

        await tester.tap(find.byType(NapButton));
        expect(taps, 1);
      });
    }
  }

  for (final size in NapButtonSize.values) {
    testWidgets('TC16 ${size.name}: min height and 48 px target', (
      tester,
    ) async {
      await pumpNap(
        tester,
        NapButton(label: 'Nghe thử', size: size, onPressed: () {}),
      );
      final visible = tester.getSize(
        find
            .descendant(of: _buttonStyleButton, matching: find.byType(Material))
            .first,
      );
      expect(visible.height, greaterThanOrEqualTo(napButtonHeight(size)));
      final target = tester.getSize(_buttonStyleButton);
      expect(target.height, greaterThanOrEqualTo(48));
      expect(target.width, greaterThanOrEqualTo(48));
    });
  }

  testWidgets('TC16 disabled: not enabled, taps ignored', (tester) async {
    await pumpNap(tester, const NapButton(label: 'Áp dụng', onPressed: null));
    expect(
      tester.getSemantics(find.text('Áp dụng')),
      isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
    );
    await tester.tap(find.byType(NapButton), warnIfMissed: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC16 expand defaults by size', (tester) async {
    await pumpNap(
      tester,
      Column(
        children: [
          NapButton(label: 'A', onPressed: () {}),
          NapButton(label: 'B', size: NapButtonSize.small, onPressed: () {}),
        ],
      ),
    );
    expect(tester.getSize(find.byType(NapButton).first).width, 390);
    expect(tester.getSize(find.byType(NapButton).last).width, lessThan(390));
  });

  testWidgets('TC17 long label at text scale 2.0 grows, no overflow', (
    tester,
  ) async {
    await pumpNap(
      tester,
      NapButton(
        label: 'Mở Cài đặt của máy để cho phép vị trí chạy nền',
        onPressed: () {},
      ),
      textScale: 2,
      width: 350,
    );
    expect(tester.takeException(), isNull);
    expect(tester.getSize(_buttonStyleButton).height, greaterThan(56));
  });
}

final Finder _buttonStyleButton = find.byWidgetPredicate(
  (w) => w is ButtonStyleButton,
);
