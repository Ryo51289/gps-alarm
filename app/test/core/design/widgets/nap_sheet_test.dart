// TC31: showNapSheet + NapSheetBody; NapSheetContainer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

void main() {
  testWidgets('TC31 modal sheet: handle, surface, r24, header, dismiss', (
    tester,
  ) async {
    await pumpNap(
      tester,
      Builder(
        builder: (context) => NapButton(
          label: 'Mở',
          onPressed: () => showNapSheet<void>(
            context: context,
            builder: (_) => const NapSheetBody(
              title: 'Pin còn 15%',
              subtitle: 'Còn khoảng 40 km',
              footnote: 'Ghi chú',
              children: [Text('Nội dung')],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();

    expect(find.byType(NapSheetBody), findsOneWidget);
    final context = tester.element(find.byType(NapSheetBody));
    expect(
      find.bySemanticsLabel(
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
      findsWidgets,
    );
    final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
    final theme = Theme.of(context);
    expect(sheet.showDragHandle ?? theme.bottomSheetTheme.showDragHandle, true);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, NapColors.light.surface);
    expect(
      (material.shape! as RoundedRectangleBorder).borderRadius,
      const BorderRadius.vertical(top: Radius.circular(24)),
    );
    expect(
      tester.getSemantics(find.text('Pin còn 15%')),
      isSemantics(isHeader: true),
    );

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(NapSheetBody), findsNothing);
  });

  // Review T20 #2: a Material bottom sheet extends under the bottom system
  // bar (Android 15+ edge-to-edge, 48 dp 3-button navigation).
  for (final navBar in [0.0, 48.0]) {
    testWidgets('sheet body clears a ${navBar.toInt()} px bottom bar', (
      tester,
    ) async {
      final dpr = tester.view.devicePixelRatio;
      tester.view
        ..viewPadding = FakeViewPadding(bottom: navBar * dpr)
        ..padding = FakeViewPadding(bottom: navBar * dpr);
      addTearDown(tester.view.reset);
      await pumpNap(
        tester,
        Builder(
          builder: (context) => NapButton(
            label: 'Mở',
            onPressed: () => showNapSheet<void>(
              context: context,
              builder: (_) => NapSheetBody(
                title: 'Pin còn 15%',
                primaryAction: NapButton(label: 'Tiếp tục', onPressed: () {}),
                footnote: 'Ghi chú',
                children: const [Text('Nội dung')],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở'));
      await tester.pumpAndSettle();

      final screenBottom = tester.view.physicalSize.height / dpr;
      final footnote = tester.getRect(find.text('Ghi chú'));
      expect(footnote.bottom, closeTo(screenBottom - navBar - 28, 0.01));
      expect(
        tester.getRect(find.widgetWithText(NapButton, 'Tiếp tục')).bottom,
        lessThan(screenBottom - navBar),
      );
    });
  }

  testWidgets('sheet container: shadow on light, top border on dark', (
    tester,
  ) async {
    const widget = NapSheetContainer(child: SizedBox(height: 40));
    BoxDecoration decoration() =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(NapSheetContainer),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    await pumpNap(tester, widget);
    expect(decoration().boxShadow, NapShadows.light.sheet);
    expect(decoration().border, isNull);
    await pumpNap(tester, widget, theme: NapThemeKind.dark);
    expect(decoration().boxShadow, isEmpty);
    expect(decoration().border, isNotNull);
  });
}
