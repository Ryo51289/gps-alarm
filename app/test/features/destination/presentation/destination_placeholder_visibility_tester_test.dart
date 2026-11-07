// Tester T23.2 (beyond spec, review note): with no map builder, the
// placeholder message "Bản đồ chưa có trong bản này." must be readable, not
// only present in the tree. X3 of the text-scale test finds the Text; this
// checks where it is painted: inside the map area left above the panel and
// inside the clip of the placeholder's scroll view, not ellipsized.
// Sizes: 320×568 (smallest phone of the spec) and 360×640; text scale 1.0,
// 1.3, 2.0; vi and en. States: panel expanded (screen just opened) and panel
// collapsed (a station chosen). Gate is on the collapsed panel only: with the
// panel expanded the placeholder area is fully covered (behaviour since T23,
// recorded with NAPSTOP_TESTER_TRACE=true, not asserted).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/presentation/widgets/map_unavailable_placeholder.dart';

import 'destination_harness.dart';

const _vi = 'Bản đồ chưa có trong bản này.';
const _en = "The map isn't available in this build.";

/// Result of one placement check, for the recorded table.
typedef _Placement = ({
  bool inTree,
  bool fullyVisible,
  bool ellipsized,
  double visibleHeight,
  String box,
});

_Placement _placement(WidgetTester tester, String message) {
  final text = find.text(message);
  if (text.evaluate().isEmpty) {
    return (
      inTree: false,
      fullyVisible: false,
      ellipsized: false,
      visibleHeight: 0,
      box: '',
    );
  }
  final placeholder = find.byType(MapUnavailablePlaceholder);
  final widget = tester.widget<MapUnavailablePlaceholder>(placeholder);
  final area = tester.getRect(placeholder);
  // Map area not covered by the panel.
  final visibleBottom = area.bottom - widget.bottomPadding;
  final scroll = find.descendant(
    of: placeholder,
    matching: find.byType(SingleChildScrollView),
  );
  final clip = tester.getRect(scroll);
  final rect = tester.getRect(text);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final fully =
      rect.top >= clip.top - 0.5 &&
      rect.bottom <= clip.bottom + 0.5 &&
      rect.top >= area.top - 0.5 &&
      rect.bottom <= visibleBottom + 0.5;
  return (
    inTree: true,
    fullyVisible: fully,
    ellipsized: paragraph.didExceedMaxLines,
    visibleHeight: visibleBottom - area.top,
    box:
        'text ${rect.size} scaler ${paragraph.textScaler} '
        'font ${paragraph.text.style?.fontSize} clip ${clip.size}',
  );
}

void main() {
  for (final (locale, message) in [
    (const Locale('vi'), _vi),
    (const Locale('en'), _en),
  ]) {
    for (final size in [const Size(320, 568), const Size(360, 640)]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        final tag =
            '${locale.languageCode} '
            '${size.width.toInt()}x${size.height.toInt()} x$scale';

        testWidgets('PV [$tag] placeholder message readable', (tester) async {
          await pumpDestination(
            tester,
            withMap: false,
            textScale: scale,
            locale: locale,
          );
          // The harness pumps at its own size; resize like X3 does.
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          final expanded = _placement(tester, message);
          await typeQuery(tester, 'dong hoi');
          await tapVisible(tester, find.text('Ga Đồng Hới').first);
          final collapsed = _placement(tester, message);
          expect(tester.takeException(), isNull);
          // Unmount before asserting so a failure here does not leak the
          // screen into the next test (teardown order of the harness).
          await tester.pumpWidget(const SizedBox());
          // Recorded for the test report (expanded panel may cover it).
          final detail = 'expanded=$expanded collapsed=$collapsed';
          printOnFailure(detail);
          if (const bool.fromEnvironment('NAPSTOP_TESTER_TRACE')) {
            // ignore: avoid_print, recorded for the test report only.
            print('PV [$tag] $detail');
          }
          // Gate: once a station is chosen the panel is at its smallest; the
          // user must then be able to read the whole message.
          expect(collapsed.inTree, isTrue, reason: 'collapsed $tag');
          expect(collapsed.fullyVisible, isTrue, reason: 'collapsed $tag');
          // The FlutterTest font draws every glyph 1 em wide, about twice a
          // real font, so at 2.0 the 3-line limit is hit here only. Scale 2.0
          // with the real font is checked on the emulator (test report).
          if (scale <= 1.3) {
            expect(collapsed.ellipsized, isFalse, reason: 'collapsed $tag');
          }
        });
      }
    }
  }
}
