// T28 N1/N2/N04 (coder): intrinsic width with the half-width trailing cap,
// and the debug overflow report. The tester's repro of N1 (in
// nap_list_row_layout_test.dart) stays skipped: see T28 Implementation
// notes "Câu hỏi cho designer".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

RenderBox _rowBox(WidgetTester tester) => tester.renderObject<RenderBox>(
  find.byWidgetPredicate((w) => w.runtimeType.toString() == '_RowLayout'),
);

void main() {
  testWidgets('N1 max intrinsic width >= 2 x trailing; one line inside '
      'IntrinsicWidth when that fits the screen', (tester) async {
    const value = 'Chuông 1';
    await pumpNap(
      tester,
      const Center(
        child: IntrinsicWidth(
          child: NapListRow(title: 'A', trailing: Text(value)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final box = _rowBox(tester);
    final trailing = tester.renderObject<RenderBox>(find.text(value));
    final t = trailing.getMaxIntrinsicWidth(double.infinity);
    expect(
      box.getMaxIntrinsicWidth(double.infinity),
      greaterThanOrEqualTo(2 * t),
    );
    expect(
      box.getMinIntrinsicWidth(double.infinity),
      lessThanOrEqualTo(box.getMaxIntrinsicWidth(double.infinity)),
    );
    // One line: as tall as the text laid out without a width limit.
    expect(
      trailing.size.height,
      moreOrLessEquals(trailing.getMinIntrinsicHeight(double.infinity)),
    );
    // RenderBox contract at the max intrinsic width.
    final w = box.getMaxIntrinsicWidth(double.infinity);
    expect(
      box.getMinIntrinsicHeight(w),
      moreOrLessEquals(box.getMinIntrinsicHeight(double.infinity)),
    );
  });

  testWidgets('N1 without trailing the width is the plain sum', (tester) async {
    await pumpNap(
      tester,
      const Center(
        child: IntrinsicWidth(child: NapListRow(title: 'Ga Huế')),
      ),
    );
    final box = _rowBox(tester);
    final title = tester.renderObject<RenderBox>(find.text('Ga Huế'));
    expect(
      box.getMaxIntrinsicWidth(double.infinity),
      moreOrLessEquals(title.getMaxIntrinsicWidth(double.infinity)),
    );
  });

  testWidgets('N2 a row that fits reports nothing', (tester) async {
    await pumpNap(
      tester,
      const NapListRow(
        title: 'Ga Đồng Hới',
        leading: NapIconTile(icon: NapIcons.train),
        trailing: NapBadge(label: 'OK', tone: NapTone.success),
        chevron: true,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('N2 overflow in RTL is reported too', (tester) async {
    await pumpNap(
      tester,
      const Directionality(
        textDirection: TextDirection.rtl,
        child: NapListRow(
          title: 'Chuyến Hà Nội - Đồng Hới',
          leading: NapIconTile(icon: NapIcons.train),
          trailing: NapBadge(label: 'Tỉnh đúng lúc', tone: NapTone.success),
          chevron: true,
        ),
      ),
      textScale: 2,
      width: 200,
    );
    expect(tester.takeException(), isNotNull);
  });
}
