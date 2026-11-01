// Tester (T20): contrast recomputed with an independent WCAG 2.x formula
// (not Color.computeLuminance), on every text/background pair that the
// components actually paint, in all 3 themes. Complements TC01-TC05, which
// check the list returned by napContrastPairs.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

double _channel(int v) {
  final c = v / 255;
  return c <= 0.04045
      ? c / 12.92
      : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final argb = color.toARGB32();
  return 0.2126 * _channel((argb >> 16) & 0xFF) +
      0.7152 * _channel((argb >> 8) & 0xFF) +
      0.0722 * _channel(argb & 0xFF);
}

double _ratio(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// Text pairs painted by the components (foreground token, background
/// token, where).
const List<(String, String, String)> _textPairs = [
  // NapButton on the page / sheet / grouped background.
  ('onAccent', 'accent', 'button primary'),
  ('textPrimary', 'fill', 'button tonal'),
  ('textPrimary', 'surface', 'button secondary'),
  ('textPrimary', 'background', 'button secondary'),
  ('danger', 'background', 'button danger'),
  ('danger', 'surface', 'button danger in a sheet'),
  ('textSecondary', 'background', 'button text'),
  ('textSecondary', 'surface', 'button text in a sheet'),
  ('accent', 'background', 'button link'),
  ('accent', 'surface', 'button link in a card'),
  // NapChip.
  ('textPrimary', 'surface', 'chip outline'),
  ('onAccent', 'accent', 'chip accent'),
  ('onInverseSurface', 'inverseSurface', 'chip inverse'),
  // NapBadge small (tone on container) and medium.
  ('textPrimary', 'fill', 'badge neutral'),
  ('accent', 'accentContainer', 'badge accent'),
  ('success', 'successContainer', 'badge success'),
  ('warning', 'warningContainer', 'badge warning'),
  ('danger', 'dangerContainer', 'badge danger'),
  ('textPrimary', 'surface', 'badge medium neutral'),
  // NapSegmentedControl.
  ('textPrimary', 'segmentThumb', 'segment selected'),
  ('textSecondary', 'fill', 'segment unselected'),
  // NapOptionCard, NapCard, NapListRow, NapSwitchRow.
  ('textPrimary', 'accentContainer', 'option selected title'),
  ('textSecondary', 'accentContainer', 'option selected description'),
  ('textSecondary', 'surface', 'option description'),
  ('textPrimary', 'warningContainer', 'warning card'),
  ('textSecondary', 'warningContainer', 'warning card secondary'),
  ('textPrimary', 'backgroundGrouped', 'grouped list header'),
  ('textSecondary', 'backgroundGrouped', 'section header'),
  // NapBanner.
  ('textSecondary', 'background', 'banner neutral'),
  ('success', 'successContainer', 'banner success'),
  ('warning', 'warningContainer', 'banner warning'),
  ('danger', 'dangerContainer', 'banner danger'),
  // NapStatusTile, NapSearchField, NapBigValue.
  ('textPrimary', 'fill', 'status tile title'),
  ('textSecondary', 'fill', 'status tile caption / search hint'),
  ('textSecondary', 'surfaceFloating', 'floating search hint'),
  ('textPrimary', 'background', 'big value'),
  ('textSecondary', 'background', 'big value estimated'),
];

/// Non-text state indicators (3:1): switch/radio outline, selected option
/// border, status icons on the status tile.
const List<(String, String, String)> _nonTextPairs = [
  ('outline', 'surface', 'radio / switch off'),
  ('outline', 'background', 'radio / switch off'),
  ('accent', 'surface', 'radio selected'),
  ('accent', 'accentContainer', 'selected option border'),
  ('success', 'fill', 'status tile icon'),
  ('danger', 'fill', 'status tile icon'),
];

void main() {
  test('independent formula agrees with contrastRatio on all token pairs', () {
    for (final kind in NapThemeKind.values) {
      final tokens = NapThemes.colorsOf(kind).tokens;
      for (final a in tokens.entries) {
        for (final b in tokens.entries) {
          expect(
            contrastRatio(a.value, b.value),
            closeTo(_ratio(a.value, b.value), 0.005),
            reason: '${kind.name} ${a.key}/${b.key}',
          );
        }
      }
    }
  });

  for (final kind in NapThemeKind.values) {
    test('component text pairs reach 4.5:1 (${kind.name})', () {
      final t = NapThemes.colorsOf(kind).tokens;
      final failures = [
        for (final (fg, bg, where) in _textPairs)
          if (_ratio(t[fg]!, t[bg]!) < 4.5)
            '$fg/$bg ($where) = ${_ratio(t[fg]!, t[bg]!).toStringAsFixed(2)}',
      ];
      expect(failures, isEmpty);
    });

    test('component non-text pairs reach 3:1 (${kind.name})', () {
      final t = NapThemes.colorsOf(kind).tokens;
      final failures = [
        for (final (fg, bg, where) in _nonTextPairs)
          if (_ratio(t[fg]!, t[bg]!) < 3)
            '$fg/$bg ($where) = ${_ratio(t[fg]!, t[bg]!).toStringAsFixed(2)}',
      ];
      expect(failures, isEmpty);
    });
  }

  // The alarm screens (5, 6, 8) are the ones read half-asleep, often in the
  // dark: their key pairs must stay well above the minimum.
  test('alarm theme key pairs (screens 5/6/8)', () {
    final t = NapColors.alarm.tokens;
    for (final (fg, bg) in const [
      ('alarmAccent', 'background'),
      ('onAlarmAccent', 'alarmAccent'),
      ('overshootLabel', 'background'),
      ('onAlarmAccent', 'overshootAccent'),
      ('textPrimary', 'background'),
      ('onAccent', 'accent'),
    ]) {
      expect(
        _ratio(t[fg]!, t[bg]!),
        greaterThanOrEqualTo(4.5),
        reason: '$fg/$bg',
      );
    }
  });
}
