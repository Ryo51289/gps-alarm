// Tester T25.1: adversarial sweep of the two layout fixes (test report T25
// bugs #1 and #2): chip labels never cut at any width / text scale / bold
// text, and the bottom bar never pushes Start (or Retry) out of reach.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/equal_chip_row.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/start_bar.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../helpers/alarm_settings_harness.dart';

const _distanceLabels = ['500 m', '1 km', '2 km', '5 km'];
const _timeLabels = ['5', '10', '15', '20', '30'];

/// No ellipsis and no word spread over two lines.
void _expectWhole(WidgetTester tester, String label, String where) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.widgetWithText(NapChip, label),
      matching: find.text(label),
    ),
  );
  expect(paragraph.didExceedMaxLines, isFalse, reason: '$label $where');
  var start = 0;
  for (final word in label.split(' ')) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    );
    expect(
      {for (final b in boxes) b.top.round()},
      hasLength(1),
      reason: '"$word" of "$label" split at $where',
    );
    start += word.length + 1;
  }
}

void _bold(WidgetTester tester, {required bool on}) {
  if (!on) {
    return;
  }
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(boldText: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Collects layout errors; [check] fails only on errors raised by the
/// widgets under test (chips, bottom bar). Others (e.g. the T20 slider label
/// row at 320 px x2.0, the destination card at x3.0) are only counted and
/// printed: they are reported separately in docs/test-reports/T25.1.md.
final class _Guard {
  new() {
    _previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.toString());
  }

  late final void Function(FlutterErrorDetails)? _previous;

  /// Described at once, while the element tree is still active.
  final List<String> errors = [];
  final Set<String> others = {};

  static const _ours = [
    'equal_chip_row.dart',
    'nap_chip.dart',
    'start_bar.dart',
    'mode_panel.dart',
    'alarm_settings_screen.dart',
  ];

  void check(String where) {
    for (final e in errors) {
      final lines = e.split('\n');
      final loc = lines.firstWhere(
        (l) => l.contains('/app/lib/'),
        orElse: () => lines.first,
      );
      final ours = _ours.any(loc.contains);
      if (ours) {
        fail('$where: ${lines.first} @ ${loc.trim()}');
      }
      final over = lines.firstWhere(
        (l) => l.contains('overflowed'),
        orElse: () => lines.first,
      );
      others.add('${over.trim()} @ ${loc.trim().split('/').last}');
    }
    errors.clear();
  }

  void restore() => FlutterError.onError = _previous;
}

Future<void> _resize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  group('chips: width sweep 296-480 px', () {
    for (final scale in const [1.0, 1.3, 1.5, 1.75, 2.0, 3.0]) {
      for (final bold in const [false, true]) {
        testWidgets('x$scale bold=$bold', (tester) async {
          _bold(tester, on: bold);
          final guard = _Guard();
          try {
            await pumpAlarmSettings(
              tester,
              textScale: scale,
              size: const Size(480, 1400),
            );
            var rows = 0;
            var wraps = 0;
            for (final (mode, labels) in const [
              ('Khoảng cách', _distanceLabels),
              ('Thời gian', _timeLabels),
            ]) {
              await tapVisible(tester, find.text(mode));
              for (var w = 296; w <= 480; w += 2) {
                await _resize(tester, Size(w.toDouble(), 1400));
                guard.check('$mode w=$w x$scale bold=$bold');
                final tops = {
                  for (final l in labels)
                    tester.getRect(find.widgetWithText(NapChip, l)).top,
                };
                tops.length == 1 ? rows++ : wraps++;
                for (final l in labels) {
                  _expectWhole(tester, l, '$mode w=$w x$scale bold=$bold');
                  final r = tester.getRect(find.widgetWithText(NapChip, l));
                  expect(r.height, greaterThanOrEqualTo(44), reason: l);
                  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$l $w');
                  expect(r.right, lessThanOrEqualTo(w + 0.5), reason: '$l $w');
                }
              }
            }
            debugPrint(
              'SWEEP x$scale bold=$bold rows=$rows wraps=$wraps '
              'others=${guard.others}',
            );
          } finally {
            guard.restore();
          }
        });
      }
    }
  });

  testWidgets('wrapped chips still select (320x568 x2.0 bold)', (tester) async {
    _bold(tester, on: true);
    final guard = _Guard();
    try {
      final h = await pumpAlarmSettings(
        tester,
        textScale: 2,
        size: const Size(320, 568),
      );
      await tapVisible(tester, find.text('Khoảng cách'));
      await tapVisible(tester, find.widgetWithText(NapChip, '500 m'));
      expect(
        tester.getSemantics(find.widgetWithText(NapChip, '500 m')),
        isSemantics(isSelected: true),
      );
      await tapVisible(tester, find.text('Thời gian'));
      await tapVisible(tester, find.widgetWithText(NapChip, '30'));
      expect(
        tester.getSemantics(find.widgetWithText(NapChip, '30')),
        isSemantics(label: '30 phút', isSelected: true),
      );
      await tapVisible(tester, find.text('Bắt đầu theo dõi'));
      expect(h.bridge.startTripCalls.single.config.timeThresholdMin, 30);
      guard.check('select');
      debugPrint('SELECT others=${guard.others}');
    } finally {
      guard.restore();
    }
  });

  group('bottom bar: timeout banner, Start and Retry reachable (bold)', () {
    for (final (locale, start, retry) in const [
      ('vi', 'Bắt đầu theo dõi', 'Thử lại'),
      ('en', 'Start tracking', 'Retry'),
    ]) {
      for (final size in const [
        Size(320, 568),
        Size(360, 640),
        Size(568, 320),
        Size(640, 360),
      ]) {
        for (final scale in const [1.75, 2.0, 3.0]) {
          final name =
              '$locale ${size.width.toInt()}x${size.height.toInt()} x$scale';
          testWidgets(name, (tester) async {
            _bold(tester, on: true);
            final guard = _Guard();
            try {
              final bridge = FakeCoreBridge(
                deviceStatusValue: deviceStatusMsg(
                  batteryPct: 3,
                  alarmMuted: true,
                ),
              )..startTripGate = Completer<void>();
              await pumpAlarmSettings(
                tester,
                textScale: scale,
                size: size,
                locale: Locale(locale),
                bridge: bridge,
              );
              await tester.ensureVisible(find.text(start));
              await tester.pumpAndSettle();
              await tester.tap(find.text(start));
              await tester.pump();
              await tester.pump(kStartTripTimeout);
              await tester.pumpAndSettle();
              guard.check(name);

              // Start: whole, on screen, tappable, >= 44 px.
              expect(find.text(start).hitTestable(), findsOneWidget);
              final button = tester.getRect(
                find.ancestor(
                  of: find.text(start),
                  matching: find.byType(NapButton),
                ),
              );
              expect(button.top, greaterThanOrEqualTo(0), reason: name);
              expect(
                button.bottom,
                lessThanOrEqualTo(size.height),
                reason: name,
              );
              expect(button.height, greaterThanOrEqualTo(44), reason: name);

              final bar = tester.getRect(find.byType(StartBar));
              final content = tester.getRect(
                find.byType(SingleChildScrollView).first,
              );
              debugPrint(
                'BAR $name bar=${bar.height.toInt()} '
                'content=${content.height.toInt()} others=${guard.others}',
              );
              expect(content.height, greaterThan(0), reason: name);

              // Retry: reachable by scrolling inside the bar, then works.
              await tester.ensureVisible(find.text(retry));
              await tester.pumpAndSettle();
              expect(find.text(retry).hitTestable(), findsOneWidget);
              final calls = bridge.calls.length;
              await tester.tap(find.text(retry));
              await tester.pump();
              expect(
                bridge.calls.sublist(calls),
                containsAllInOrder(['permissionStatus', 'deviceInfo']),
                reason: 'Retry ran the start flow',
              );
              bridge.startTripGate!.complete();
              await tester.pumpAndSettle();
              guard.check('$name after retry');
            } finally {
              guard.restore();
            }
          });
        }
      }
    }
  });

  testWidgets('no error: the bar has nothing to scroll (no thumb)', (
    tester,
  ) async {
    await pumpAlarmSettings(tester, textScale: 2, size: const Size(320, 568));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(StartBar),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);
  });

  testWidgets('equal-width rule at x1.0 on 360/390/411 (recorded)', (
    tester,
  ) async {
    await pumpAlarmSettings(tester, size: const Size(360, 800));
    await tapVisible(tester, find.text('Khoảng cách'));
    for (final w in const [360.0, 390.0, 411.0]) {
      await _resize(tester, Size(w, 800));
      final tops = {
        for (final l in _distanceLabels)
          tester.getRect(find.widgetWithText(NapChip, l)).top,
      };
      // FlutterTest glyphs are wider than Be Vietnam Pro; the real font is
      // checked on the emulator.
      debugPrint('ROW x1.0 w=$w one row=${tops.length == 1}');
      expect(find.byType(EqualChipRow), findsOneWidget);
      for (final l in _distanceLabels) {
        _expectWhole(tester, l, 'x1.0 w=$w');
      }
    }
  });
}
