// TC32: NapLabeledSlider. TC33: NapBigValue. NapSearchField basics.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';
import '../../../helpers/pixel_probe.dart';

void main() {
  testWidgets('TC32 slider snaps to 100 m steps; semantics', (tester) async {
    var value = 1500.0;
    final seen = <double>[];
    String fmt(double v) => '${(v / 1000).toStringAsFixed(1)} km';
    await pumpNap(
      tester,
      StatefulBuilder(
        builder: (context, setState) => NapLabeledSlider(
          value: value,
          min: 200,
          max: 10000,
          divisions: 98,
          semanticLabel: 'Khoảng cách báo',
          semanticFormatter: fmt,
          minLabel: '200 m',
          maxLabel: '10 km',
          onChanged: (v) => setState(() {
            seen.add(v);
            value = v;
          }),
        ),
      ),
    );
    expect(find.text('200 m'), findsOneWidget);
    expect(find.text('10 km'), findsOneWidget);

    await tester.drag(find.byType(Slider), const Offset(120, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-1000, 0));
    await tester.pumpAndSettle();
    expect(seen, isNotEmpty);
    for (final v in seen) {
      expect(v, inInclusiveRange(200, 10000));
      expect((v - 200) % 100, closeTo(0, 1e-6));
    }
    expect(value, 200);

    final node = tester.getSemantics(find.byType(Slider)).getSemanticsData();
    expect(node.label, contains('Khoảng cách báo'));
    expect(node.value, fmt(value));
  });

  testWidgets('TC33 big value: clamped scale, no overflow, estimated', (
    tester,
  ) async {
    await pumpNap(
      tester,
      const NapBigValue(value: '1.234 km', trailing: '~12 giờ 30 phút'),
      textScale: 2,
      width: 350,
    );
    expect(tester.takeException(), isNull);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('1.234 km'),
    );
    expect(paragraph.textScaler.scale(52), lessThanOrEqualTo(52 * 1.3));
    expect(paragraph.text.style!.color, NapColors.light.textPrimary);

    await pumpNap(tester, const NapBigValue(value: '~148 km', estimated: true));
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('~148 km'))
          .text
          .style!
          .color,
      NapColors.light.textSecondary,
    );
  });

  testWidgets('search field: read-only button and editable field', (
    tester,
  ) async {
    var taps = 0;
    await pumpNap(
      tester,
      NapSearchField(
        hint: 'Bạn muốn đến đâu?',
        readOnly: true,
        onTap: () => taps++,
      ),
    );
    expect(find.byType(TextField), findsNothing);
    expect(
      tester.getSemantics(find.byType(NapSearchField)),
      isSemantics(
        label: 'Bạn muốn đến đâu?',
        isButton: true,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.byType(NapSearchField));
    expect(taps, 1);
    expect(
      tester.getSize(find.byType(NapSearchField)).height,
      greaterThanOrEqualTo(56),
    );

    final typed = <String>[];
    await pumpNap(
      tester,
      NapSearchField(
        hint: 'Tìm ga',
        variant: NapSearchFieldVariant.floating,
        onChanged: typed.add,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Huế');
    expect(typed, ['Huế']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).textInputAction,
      TextInputAction.search,
    );
    expect(
      tester.getSize(find.byType(NapSearchField)).height,
      greaterThanOrEqualTo(48),
    );
  });

  // Review T20 #1: the background must be painted by the field itself, not
  // on the ancestor Material below an opaque sibling (the map of screen 2).
  const mapColor = Color(0xFF00FF00);
  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    for (final variant in NapSearchFieldVariant.values) {
      for (final asButton in [false, true]) {
        testWidgets('search field ${variant.name} button=$asButton paints its '
            'background over an opaque sibling (${theme.name})', (
          tester,
        ) async {
          await pumpNap(
            tester,
            RepaintBoundary(
              key: kPixelProbeKey,
              child: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: mapColor)),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: NapSearchField(
                      hint: 'x',
                      variant: variant,
                      readOnly: asButton,
                      onTap: asButton ? () {} : null,
                    ),
                  ),
                ],
              ),
            ),
            theme: theme,
          );
          final c = napColorsOf(theme);
          final rect = tester.getRect(find.byType(NapSearchField));
          final inside = Offset(rect.right - 30, rect.center.dy);
          expect(
            (await pixelAt(tester, inside)).toARGB32(),
            (variant == NapSearchFieldVariant.filled
                    ? c.fill
                    : c.surfaceFloating)
                .toARGB32(),
          );
          final outside = Offset(rect.right - 30, rect.top - 15);
          expect((await pixelAt(tester, outside)).toARGB32(), 0xFF00FF00);
        });
      }
    }
  }
}
