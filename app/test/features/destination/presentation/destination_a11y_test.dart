// T23 TW25–TW27: screen 2 accessibility (touch targets, labels, contrast,
// text scale 2.0, semantics).
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

import 'destination_harness.dart';

Future<void> selectDongHoi(WidgetTester tester) async {
  await typeQuery(tester, 'dong hoi');
  await tapVisible(tester, find.text('Ga Đồng Hới').first);
}

Future<void> expectGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    testWidgets('TW25 guidelines with a selection (${theme.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpDestination(tester, theme: theme);
      await selectDongHoi(tester);
      await expectGuidelines(tester);
      handle.dispose();
    });
  }

  testWidgets('TW25 guidelines with a Places error banner', (tester) async {
    final handle = tester.ensureSemantics();
    final h = await pumpDestination(tester);
    h.places.autocompleteError = const SocketException('offline');
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    await expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('TW26 text scale 2.0: no overflow, label on 2 lines', (
    tester,
  ) async {
    await pumpDestination(tester, textScale: 2);
    await selectDongHoi(tester);
    expect(tester.takeException(), isNull);
    final label = find.text('Chọn Ga Đồng Hới');
    expect(label, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(label);
    expect(
      paragraph.size.height,
      greaterThan(paragraph.text.style!.fontSize! * 2 * 1.5),
    );
  });

  testWidgets('TW27 semantics: labels, selected row, link, live region', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    // Icon-only buttons: the label is read out (tooltip semantics).
    for (final label in ['Quay lại', 'Xoá nội dung tìm', 'Lưu điểm này']) {
      final node = tester.getSemantics(find.byTooltip(label));
      expect('${node.label} ${node.tooltip}', contains(label), reason: label);
    }
    final osm = tester.getSemantics(
      find.text('Dữ liệu ga/bến © OpenStreetMap contributors'),
    );
    expect(osm.flagsCollection.isLink, isTrue);
    expect(osm.hint, 'Mở trang bản quyền OpenStreetMap');

    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    final row = tester.getSemantics(find.text('Ga Đồng Hới').first);
    expect(row.flagsCollection.isSelected, Tristate.isTrue);

    h.places.autocompleteStatus = 403;
    await typeQuery(tester, 'duc long');
    await tapVisible(tester, find.text('Tìm "duc long" bằng Google Maps'));
    final banner = tester.getSemantics(
      find.text('Tìm địa chỉ tạm thời không dùng được.'),
    );
    expect(banner.flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
