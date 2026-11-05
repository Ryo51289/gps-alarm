// Tester (T20, review N1-N3): NapListRow uses a hand-written render object
// (_RenderRowLayout). Dry layout, intrinsic sizes and baselines must agree
// with the real layout, or rows inside AlertDialog/SimpleDialog
// (IntrinsicWidth) and IntrinsicHeight drift silently.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import '../../../helpers/nap_test_app.dart';

/// The private `_RowLayout` render box inside the only NapListRow.
RenderBox _rowBox(WidgetTester tester) => tester.renderObject<RenderBox>(
  find.byWidgetPredicate((w) => w.runtimeType.toString() == '_RowLayout'),
);

/// Row configurations used by the screens (1, 2, 9, 11, 12).
final Map<String, NapListRow> _configs = {
  'title only': const NapListRow(title: 'Ga Đồng Hới'),
  'title + subtitle': const NapListRow(
    title: 'Ga Đồng Hới',
    subtitle: 'Quảng Bình, tuyến Bắc - Nam',
  ),
  'leading + trailing + chevron': const NapListRow(
    title: 'Âm báo khi tới nơi',
    leading: NapIconTile(icon: NapIcons.alarm),
    trailing: Text('Chuông 1'),
    chevron: true,
  ),
  'long trailing': const NapListRow(
    title: 'Âm báo',
    trailing: Text('Chuông báo thức số 1 rất dài'),
  ),
  'radio': const NapListRow(
    title: 'Tiếng Việt',
    semanticsChecked: true,
    trailing: NapRadioIndicator(selected: true),
  ),
  'all slots + badge': const NapListRow(
    title: 'Chuyến Hà Nội - Đồng Hới ngày 12/10',
    subtitle: 'Báo trước 5 km',
    leading: NapIconTile(icon: NapIcons.train),
    trailing: NapBadge(label: 'Tỉnh đúng lúc', tone: NapTone.success),
    chevron: true,
  ),
};

void main() {
  for (final MapEntry(key: name, value: row) in _configs.entries) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      for (final dir in TextDirection.values) {
        for (final width in const [390.0, 360.0]) {
          testWidgets('N3 dry/intrinsic/baseline == layout: $name, x$scale, '
              '${dir.name}, w$width', (tester) async {
            debugCheckIntrinsicSizes = true;
            try {
              await pumpNap(
                tester,
                Directionality(textDirection: dir, child: row),
                textScale: scale,
                width: width,
              );
              expect(tester.takeException(), isNull);
              final box = _rowBox(tester);
              final c = box.constraints;
              final size = box.size;

              expect(box.getDryLayout(c), size, reason: 'dry layout');
              // The parent's min height (56/64 minus padding) may lift
              // the row above its intrinsic height.
              expect(
                c.constrainHeight(box.getMinIntrinsicHeight(size.width)),
                moreOrLessEquals(size.height),
                reason: 'min intrinsic height',
              );
              expect(
                c.constrainHeight(box.getMaxIntrinsicHeight(size.width)),
                moreOrLessEquals(size.height),
                reason: 'max intrinsic height',
              );
              // Reading the actual baseline outside the parent's layout or
              // paint needs the flag the framework sets for its own checks.
              RenderObject.debugCheckingIntrinsics = true;
              final double actualBaseline;
              try {
                actualBaseline = box.getDistanceToBaseline(
                  TextBaseline.alphabetic,
                )!;
              } finally {
                RenderObject.debugCheckingIntrinsics = false;
              }
              expect(
                box.getDryBaseline(c, TextBaseline.alphabetic),
                moreOrLessEquals(actualBaseline),
                reason: 'dry baseline',
              );
              // Children stay inside the row.
              final rowRect = Offset.zero & size;
              var childCount = 0;
              box.visitChildren((child) {
                childCount++;
                final b = child as RenderBox;
                final offset = (b.parentData! as BoxParentData).offset;
                final rect = offset & b.size;
                expect(
                  rect.left >= rowRect.left - 0.01 &&
                      rect.right <= rowRect.right + 0.01,
                  isTrue,
                  reason: 'child $rect outside row $rowRect',
                );
              });
              expect(childCount, greaterThanOrEqualTo(1));
            } finally {
              debugCheckIntrinsicSizes = false;
            }
          });
        }
      }
    }
  }

  // Intrinsic height drives IntrinsicHeight siblings (e.g. a color bar next
  // to the row) at the largest text scale.
  testWidgets('N3 IntrinsicHeight sibling matches the row at x2.0', (
    tester,
  ) async {
    await pumpNap(
      tester,
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(width: 4, child: ColoredBox(color: Colors.red)),
            Expanded(child: _configs['all slots + badge']!),
          ],
        ),
      ),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(ColoredBox).last).height,
      moreOrLessEquals(tester.getSize(find.byType(NapListRow)).height),
    );
  });

  // N1 (review T20 vong 2; T28 §7, orchestrator N1 = A): the max intrinsic
  // width is max(gaps + children, 2 x trailing), because layout caps the
  // trailing at half the inner width (T20 rule, unchanged). RenderBox
  // contract: at maxIntrinsicWidth the height must already be minimal.
  // Inside IntrinsicWidth the row gets min(2T + padding, screen): where 2T
  // does not fit (390 px), the trailing keeps the W/2 cap and wraps to 2
  // lines without overflow; where it fits (600 px) it stays on one line.
  testWidgets('N1 max intrinsic width honours the half-width trailing cap', (
    tester,
  ) async {
    await pumpNap(tester, _configs['long trailing']!);
    final box = _rowBox(tester);
    final w = box.getMaxIntrinsicWidth(double.infinity);
    expect(
      box.getMinIntrinsicHeight(w),
      moreOrLessEquals(box.getMinIntrinsicHeight(double.infinity)),
    );

    // Same thing through IntrinsicWidth (AlertDialog/SimpleDialog).
    const value = 'Chuông số 1 dài';
    const padding = 2 * NapSpace.s16;
    Future<({double row, double inner, RenderBox trailing})> pumpAt(
      double width,
    ) async {
      await pumpNap(
        tester,
        const Center(
          child: IntrinsicWidth(
            child: NapListRow(title: 'A', trailing: Text(value)),
          ),
        ),
        width: width,
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
      final row = tester.getSize(find.byType(NapListRow)).width;
      return (
        row: row,
        inner: _rowBox(tester).size.width,
        trailing: tester.renderObject<RenderBox>(find.text(value)),
      );
    }

    // 390 px: 2T + padding does not fit, the row takes the screen width.
    final narrow = await pumpAt(390);
    final t = narrow.trailing.getMaxIntrinsicWidth(double.infinity);
    final line = narrow.trailing.getMinIntrinsicHeight(double.infinity);
    expect(2 * t + padding, greaterThan(390));
    expect(narrow.row, moreOrLessEquals(390));
    expect(narrow.inner, moreOrLessEquals(390 - padding));
    expect(narrow.trailing.size.width, lessThanOrEqualTo(narrow.inner / 2));
    expect(narrow.trailing.size.height, moreOrLessEquals(2 * line));
    // The title still has its one line.
    expect(
      tester.getSize(find.text('A')).height,
      moreOrLessEquals(
        tester
            .renderObject<RenderBox>(find.text('A'))
            .getMinIntrinsicHeight(double.infinity),
      ),
    );

    // 600 px: 2T + padding fits, so IntrinsicWidth gives exactly that and
    // the trailing is on one line.
    final wide = await pumpAt(600);
    expect(wide.row, moreOrLessEquals(2 * t + padding));
    expect(wide.trailing.size.height, moreOrLessEquals(line));
  });

  // N2 (review T20 vong 2): when leading + gaps + chevron + half-width
  // trailing exceed the row, children paint outside it and nothing is
  // reported (a Row would throw "RenderFlex overflowed").
  testWidgets('N2 overflowing row is reported in debug', (tester) async {
    await pumpNap(
      tester,
      _configs['all slots + badge']!,
      textScale: 2,
      width: 200,
    );
    final reported = tester.takeException() != null;
    final box = _rowBox(tester);
    var outside = false;
    box.visitChildren((child) {
      final b = child as RenderBox;
      final rect = (b.parentData! as BoxParentData).offset & b.size;
      if (rect.left < -0.01 || rect.right > box.size.width + 0.01) {
        outside = true;
      }
    });
    expect(
      !outside || reported,
      isTrue,
      reason: 'children overflow the row but no error was reported',
    );
  });
}
