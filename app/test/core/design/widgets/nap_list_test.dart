// TC26: NapListGroup + NapListRow. TC27: NapSectionHeader.
// TC28: NapScreenHeader. Plus NapCard and NapIconTile basics.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

void main() {
  const c = NapColors.light;

  testWidgets('TC26 group of 3 rows', (tester) async {
    var taps = 0;
    await pumpNap(
      tester,
      NapListGroup(
        children: [
          NapListRow(title: 'Ga Đồng Hới', chevron: true, onTap: () => taps++),
          const NapListRow(title: 'Bến xe Mỹ Đình', selected: true),
          const NapListRow(
            title: 'Tiếng Việt',
            semanticsChecked: true,
            trailing: NapRadioIndicator(selected: true),
          ),
        ],
      ),
    );
    expect(find.byType(Divider), findsNWidgets(2));
    await tester.tap(find.text('Ga Đồng Hới'));
    expect(taps, 1);

    final selectedMaterial = tester.widget<Material>(
      find
          .descendant(
            of: find.widgetWithText(NapListRow, 'Bến xe Mỹ Đình'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(selectedMaterial.color, c.accentContainer);

    expect(
      tester.getSemantics(find.text('Tiếng Việt')),
      isSemantics(
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Ga Đồng Hới')),
      isSemantics(label: 'Ga Đồng Hới', isButton: true),
    );
    expect(
      tester.widget<Icon>(find.byIcon(NapIcons.chevron)).semanticLabel,
      isNull,
    );
  });

  // Review T20 #4: AlertDialog and SimpleDialog wrap their content in
  // IntrinsicWidth; the row must report intrinsic sizes.
  for (final dialog in ['AlertDialog', 'SimpleDialog']) {
    testWidgets('TC26 rows inside $dialog', (tester) async {
      var picked = '';
      final rows = [
        for (final (label, on) in const [
          ('Tiếng Việt', true),
          ('English', false),
        ])
          NapListRow(
            title: label,
            semanticsChecked: on,
            trailing: NapRadioIndicator(selected: on),
            onTap: () => picked = label,
          ),
        const NapListRow(
          title: 'Âm báo',
          leading: NapIconTile(icon: NapIcons.alarm),
          trailing: Text('Chuông 1'),
          chevron: true,
        ),
      ];
      await pumpNap(
        tester,
        dialog == 'AlertDialog'
            ? AlertDialog(
                title: const Text('Ngôn ngữ'),
                content: Column(mainAxisSize: MainAxisSize.min, children: rows),
              )
            : SimpleDialog(title: const Text('Ngôn ngữ'), children: rows),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(NapRadioIndicator), findsNWidgets(2));
      // Every row gets the same (dialog) width; trailing sits at the end.
      final row = tester.getRect(find.widgetWithText(NapListRow, 'English'));
      expect(
        tester.getRect(find.widgetWithText(NapListRow, 'Âm báo')).width,
        row.width,
      );
      expect(
        tester.getRect(find.byType(NapRadioIndicator).last).right,
        closeTo(row.right - 16, 0.01),
      );
      await tester.tap(find.text('English'));
      expect(picked, 'English');
    });
  }

  testWidgets('TC26 trailing capped at half the row at text scale 2.0', (
    tester,
  ) async {
    const longValue = 'Chuông báo thức số 1 rất dài';
    await pumpNap(
      tester,
      const NapListGroup(
        children: [
          NapListRow(
            title: 'Âm báo khi tới nơi',
            leading: NapIconTile(icon: NapIcons.alarm),
            trailing: Text(longValue),
            chevron: true,
          ),
          NapListRow(
            title: 'Chuyến 12/10',
            trailing: NapBadge(label: 'Tỉnh đúng lúc', tone: NapTone.success),
          ),
        ],
      ),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final row = tester.getRect(
      find.widgetWithText(NapListRow, 'Âm báo khi tới nơi'),
    );
    final inner = row.width - 2 * 16;
    final value = tester.getRect(find.text(longValue));
    expect(value.width, lessThanOrEqualTo(inner / 2 + 0.01));
    // Wrapped, not cut: taller than one line.
    expect(
      value.height,
      greaterThan(tester.getSize(find.text('Âm báo khi tới nơi')).height / 2),
    );
    expect(
      tester.getRect(find.byType(NapBadge)).width,
      lessThanOrEqualTo(inner / 2 + 0.01),
    );

    // A short trailing does not take space from the title.
    await pumpNap(
      tester,
      const NapListRow(title: 'Âm báo', trailing: Text('1')),
    );
    final title = tester.getRect(
      find
          .ancestor(of: find.text('Âm báo'), matching: find.byType(Column))
          .first,
    );
    final short = tester.getRect(find.text('1'));
    final shortRow = tester.getRect(find.byType(NapListRow));
    expect(short.right, closeTo(shortRow.right - 16, 0.01));
    // Title column fills the row up to the trailing gap.
    expect(title.right, closeTo(short.left - 12, 0.01));
  });

  testWidgets('TC26 row layout mirrors in RTL', (tester) async {
    await pumpNap(
      tester,
      const Directionality(
        textDirection: TextDirection.rtl,
        child: NapListRow(
          title: 'Ga',
          leading: NapIconTile(icon: NapIcons.train),
          trailing: Text('12 km'),
          chevron: true,
        ),
      ),
    );
    final row = tester.getRect(find.byType(NapListRow));
    final leading = tester.getRect(find.byType(NapIconTile));
    final trailing = tester.getRect(find.text('12 km'));
    final chevron = tester.getRect(find.byIcon(NapIcons.chevron));
    expect(leading.right, closeTo(row.right - 16, 0.01));
    expect(chevron.left, closeTo(row.left + 16, 0.01));
    expect(trailing.left, closeTo(chevron.right + 12, 0.01));
    expect(
      tester.getRect(find.text('Ga')).right,
      closeTo(leading.left - 12, 0.01),
    );
  });

  testWidgets('TC27 section header: upper case, plain label, header', (
    tester,
  ) async {
    await pumpNap(tester, const NapSectionHeader('Đã lưu'));
    expect(find.text('ĐÃ LƯU'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(NapSectionHeader)),
      isSemantics(label: 'Đã lưu', isHeader: true),
    );
  });

  for (final (locale, label) in const [
    (Locale('vi'), 'Quay lại'),
    (Locale('en'), 'Back'),
  ]) {
    testWidgets('TC28 screen header back button (${locale.languageCode})', (
      tester,
    ) async {
      var backs = 0;
      await pumpNap(
        tester,
        NapScreenHeader(title: 'Cài đặt chung', onBack: () => backs++),
        locale: locale,
      );
      expect(find.byTooltip(label), findsOneWidget);
      await tester.tap(find.byTooltip(label));
      expect(backs, 1);
      expect(
        tester.getSemantics(find.text('Cài đặt chung')),
        isSemantics(isHeader: true),
      );
    });
  }

  testWidgets('TC28 no back button without onBack', (tester) async {
    await pumpNap(tester, const NapScreenHeader(title: 'Lịch sử'));
    expect(find.byType(NapIconButton), findsNothing);
  });

  testWidgets('card variants and tappable card', (tester) async {
    var taps = 0;
    await pumpNap(
      tester,
      Column(
        children: [
          for (final v in NapCardVariant.values)
            NapCard(variant: v, child: Text(v.name)),
          NapCard(
            onTap: () => taps++,
            semanticLabel: 'Chuyến gần nhất',
            child: const Text('tap'),
          ),
        ],
      ),
    );
    Color? colorOf(String text) => tester
        .widget<Material>(
          find
              .ancestor(of: find.text(text), matching: find.byType(Material))
              .first,
        )
        .color;
    expect(colorOf('outlined'), c.surface);
    expect(colorOf('filled'), c.fill);
    expect(colorOf('accent'), c.accentContainer);
    expect(colorOf('warning'), c.warningContainer);
    await tester.tap(find.text('tap'));
    expect(taps, 1);
    expect(tester.getSemantics(find.text('tap')), isSemantics(isButton: true));
  });

  testWidgets('icon tile colors by tone; decorative', (tester) async {
    await pumpNap(
      tester,
      const Row(
        children: [
          NapIconTile(icon: NapIcons.place),
          NapIconTile(icon: NapIcons.battery, tone: NapTone.danger),
          NapIconTile(icon: NapIcons.home, onFill: true),
        ],
      ),
    );
    expect(tester.widget<Icon>(find.byIcon(NapIcons.battery)).color, c.danger);
    expect(
      tester.widget<Icon>(find.byIcon(NapIcons.place)).color,
      c.textPrimary,
    );
    final decorations = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(NapIconTile),
            matching: find.byType(Container),
          ),
        )
        .map((w) => (w.decoration! as BoxDecoration).color)
        .toList();
    expect(decorations, [c.fill, c.dangerContainer, c.surface]);
  });
}
