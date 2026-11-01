// TC29: NapBanner. TC30: NapStatusTile.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

void main() {
  const c = NapColors.light;

  for (final tone in [
    NapTone.neutral,
    NapTone.warning,
    NapTone.danger,
    NapTone.success,
  ]) {
    testWidgets('TC29 banner ${tone.name}', (tester) async {
      await pumpNap(
        tester,
        NapBanner(tone: tone, title: 'Tiêu đề', message: 'Nội dung'),
      );
      final (bg, border, body, title) = switch (tone) {
        NapTone.warning => (
          c.warningContainer,
          c.warningBorder,
          c.warning,
          c.warning,
        ),
        NapTone.danger => (c.dangerContainer, null, c.danger, c.danger),
        NapTone.success => (c.successContainer, null, c.success, c.success),
        _ => (Colors.transparent, c.border, c.textSecondary, c.textPrimary),
      };
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(NapBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, bg);
      expect(
        decoration.border,
        border == null ? isNull : Border.all(color: border),
      );
      Color? colorOf(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .text
          .style!
          .color;
      expect(colorOf('Nội dung'), body);
      expect(colorOf('Tiêu đề'), title);
      expect(find.byIcon(NapBanner.defaultIcon(tone)), findsOneWidget);
      expect(tester.widget<Icon>(find.byType(Icon)).color, body);
    });
  }

  test('TC29 default icons', () {
    expect(NapBanner.defaultIcon(NapTone.neutral), NapIcons.info);
    expect(NapBanner.defaultIcon(NapTone.warning), NapIcons.warning);
    expect(NapBanner.defaultIcon(NapTone.danger), NapIcons.error);
    expect(NapBanner.defaultIcon(NapTone.success), NapIcons.check);
  });

  testWidgets('TC29 announce sets a live region', (tester) async {
    await pumpNap(
      tester,
      const NapBanner(
        tone: NapTone.warning,
        message: 'Khoảng cách quá gần',
        announce: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Khoảng cách quá gần')),
      isSemantics(isLiveRegion: true),
    );
  });

  test('TC29 accent tone asserts', () {
    expect(
      () => NapBanner(message: 'x', tone: NapTone.accent),
      throwsAssertionError,
    );
  });

  testWidgets('TC30 status tile: icon tone, merged semantics', (tester) async {
    await pumpNap(
      tester,
      const NapStatusTile(
        icon: NapIcons.gps,
        title: 'GPS tốt',
        subtitle: '±8 m',
        tone: NapTone.success,
      ),
    );
    expect(tester.widget<Icon>(find.byIcon(NapIcons.gps)).color, c.success);
    final node = tester.getSemantics(find.text('GPS tốt'));
    expect(node.label, contains('GPS tốt'));
    expect(node.label, contains('±8 m'));
  });
}
