// T23 TW25–TW27: screen 2 accessibility (touch targets, labels, contrast,
// text scale 2.0, semantics).
import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/destination/data/stations_codec.dart';

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

  testWidgets('TW25 guidelines with the catalog error banner', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDestination(
      tester,
      stationCatalog: () async => throw const StationDataException('broken'),
    );
    expect(find.text('Không tải được danh sách ga, bến xe.'), findsOneWidget);
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

  testWidgets('TW27 semantics: labels, selected row, link', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDestination(tester);
    await typeQuery(tester, 'dong hoi');
    // Icon-only buttons: the label is read out (tooltip semantics).
    for (final label in ['Quay lại', 'Xoá nội dung tìm', 'Lưu điểm này']) {
      final node = tester.getSemantics(find.byTooltip(label));
      expect('${node.label} ${node.tooltip}', contains(label), reason: label);
    }
    final osm = tester.getSemantics(
      find.text('Dữ liệu ga, bến, trạm buýt © OpenStreetMap contributors'),
    );
    expect(osm.flagsCollection.isLink, isTrue);
    expect(osm.hint, 'Mở trang bản quyền OpenStreetMap');

    await tapVisible(tester, find.text('Ga Đồng Hới').first);
    final row = tester.getSemantics(find.text('Ga Đồng Hới').first);
    expect(row.flagsCollection.isSelected, Tristate.isTrue);

    handle.dispose();
  });

  // T23.7 Y1: the leave dialog of the slot picker.
  for (final theme in [NapThemeKind.light, NapThemeKind.dark]) {
    testWidgets('T23.7 Y1 leave dialog guidelines (${theme.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openLeaveDialog(tester, theme: theme);
      expect(find.text('Lưu vào Công ty?'), findsOneWidget);
      await expectGuidelines(tester);
      final named = find
          .bySemanticsLabel('Lưu vào Công ty?')
          .evaluate()
          .map((e) => e.renderObject!.debugSemantics!)
          .where((n) => n.getSemanticsData().flagsCollection.namesRoute);
      expect(named, isNotEmpty);
      handle.dispose();
    });
  }

  testWidgets('T23.7 Y1 "Lưu vào …" button guidelines', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpDestination(tester, open: false);
    unawaited(homeContext(tester).pickDestination(slot: SavedPlaceSlot.work));
    await tester.pumpAndSettle();
    await selectDongHoi(tester);
    expect(find.text('Lưu vào Công ty'), findsOneWidget);
    await expectGuidelines(tester);
    handle.dispose();
  });

  testWidgets('T23.7 Y2 leave dialog at text scale 2.0', (tester) async {
    await _openLeaveDialog(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('leave-save')).hitTestable(), findsOne);
    expect(find.byKey(const ValueKey('leave-discard')).hitTestable(), findsOne);
  });
}

/// Screen 2 picking for "Công ty" with Ga Đồng Hới chosen, Back pressed.
Future<void> _openLeaveDialog(
  WidgetTester tester, {
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1.0,
}) async {
  await pumpDestination(
    tester,
    open: false,
    theme: theme,
    textScale: textScale,
  );
  unawaited(homeContext(tester).pickDestination(slot: SavedPlaceSlot.work));
  await tester.pumpAndSettle();
  await selectDongHoi(tester);
  await tester.tap(find.byTooltip('Quay lại'));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}
