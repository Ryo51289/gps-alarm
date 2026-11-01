// TC24: NapSwitchRow. TC25: NapOptionCard (+ NapRadioIndicator).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';
import '../../../helpers/pixel_probe.dart';

void main() {
  testWidgets('TC24 tapping the title toggles; merged semantics', (
    tester,
  ) async {
    final calls = <bool>[];
    await pumpNap(
      tester,
      NapSwitchRow(
        title: 'Rung khi báo',
        subtitle: 'Rung mạnh kèm âm thanh',
        value: false,
        onChanged: calls.add,
      ),
    );
    await tester.tap(find.text('Rung khi báo'));
    expect(calls, [true]);

    final node = tester.getSemantics(find.byType(Switch));
    expect(node.label, contains('Rung khi báo'));
    expect(node.label, contains('Rung mạnh kèm âm thanh'));
    expect(node, isSemantics(hasToggledState: true, isToggled: false));

    await pumpNap(
      tester,
      const NapSwitchRow(title: 'Đèn flash', value: false, onChanged: null),
    );
    await tester.tap(find.text('Đèn flash'));
    expect(calls, [true]);
    expect(
      tester.getSemantics(find.byType(Switch)),
      isSemantics(hasEnabledState: true, isEnabled: false),
    );
  });

  // Review T20 #7: the press highlight must show over a colored container,
  // not on the ancestor Material below it.
  testWidgets('TC24 press highlight visible over a colored container', (
    tester,
  ) async {
    const container = Color(0xFF00FF00);
    await pumpNap(
      tester,
      RepaintBoundary(
        key: kPixelProbeKey,
        child: ColoredBox(
          color: container,
          child: NapSwitchRow(title: 'A', value: true, onChanged: (_) {}),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(NapSwitchRow));
    final point = Offset(rect.center.dx, rect.top + 4);
    expect((await pixelAt(tester, point)).toARGB32(), 0xFF00FF00);
    final gesture = await tester.startGesture(
      rect.centerLeft + const Offset(40, 0),
    );
    // Tap down fires after kPressTimeout; then let the highlight fade in.
    await tester.pump(kPressTimeout);
    await tester.pump(const Duration(milliseconds: 300));
    expect((await pixelAt(tester, point)).toARGB32(), isNot(0xFF00FF00));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('TC24 row is at least 60 px high', (tester) async {
    await pumpNap(
      tester,
      NapSwitchRow(title: 'A', value: true, onChanged: (_) {}),
    );
    expect(
      tester.getSize(find.byType(NapSwitchRow)).height,
      greaterThanOrEqualTo(60),
    );
  });

  for (final layout in NapOptionLayout.values) {
    for (final selected in [true, false]) {
      testWidgets('TC25 ${layout.name} selected=$selected', (tester) async {
        var taps = 0;
        await pumpNap(
          tester,
          NapOptionCard(
            title: 'Tiết kiệm pin',
            description: layout == NapOptionLayout.row ? 'Mô tả' : null,
            icon: NapIcons.vibrate,
            layout: layout,
            selected: selected,
            onTap: () => taps++,
          ),
        );
        expect(
          tester.getSemantics(find.byType(NapOptionCard)),
          isSemantics(
            label: 'Tiết kiệm pin',
            hasCheckedState: true,
            isChecked: selected,
            isInMutuallyExclusiveGroup: true,
            isEnabled: true,
          ),
        );
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(NapOptionCard),
                matching: find.byType(Material),
              )
              .first,
        );
        const c = NapColors.light;
        expect(material.color, selected ? c.accentContainer : c.surface);
        final side = (material.shape! as RoundedRectangleBorder).side;
        expect(side.width, 1.5);
        expect(side.color, selected ? c.accent : c.border);
        await tester.tap(find.byType(NapOptionCard));
        expect(taps, 1);
      });
    }
  }

  test('TC25 tile without icon asserts', () {
    expect(
      () => NapOptionCard(
        title: 'Rung',
        selected: false,
        onTap: null,
        layout: NapOptionLayout.tile,
      ),
      throwsAssertionError,
    );
  });

  testWidgets('radio indicator: ring widths and no semantics', (tester) async {
    await pumpNap(
      tester,
      const Row(
        children: [
          NapRadioIndicator(selected: true),
          NapRadioIndicator(selected: false),
        ],
      ),
    );
    final boxes = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((b) => (b.decoration! as BoxDecoration).border! as Border)
        .toList();
    expect(boxes[0].top.width, 7);
    expect(boxes[0].top.color, NapColors.light.accent);
    expect(boxes[1].top.width, 2);
    expect(boxes[1].top.color, NapColors.light.outline);
    expect(
      tester.getSize(find.byType(NapRadioIndicator).first),
      const Size(22, 22),
    );
  });
}
