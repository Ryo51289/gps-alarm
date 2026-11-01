// TC01-TC05: contrast function and token pairs (spec T20 section 2.1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

void main() {
  group('TC01 contrastRatio', () {
    test('known values and symmetry', () {
      const black = Color(0xFF000000);
      const white = Color(0xFFFFFFFF);
      const gray = Color(0xFF777777);
      expect(contrastRatio(black, white), closeTo(21, 1e-9));
      expect(contrastRatio(white, white), closeTo(1, 1e-9));
      expect(contrastRatio(gray, white), closeTo(4.48, 0.01));
      expect(contrastRatio(white, gray), contrastRatio(gray, white));
      expect(contrastRatio(white, black), contrastRatio(black, white));
    });
  });

  // Pairs of the spec table (section 2.1) that must be present per theme.
  const specPairs = <NapThemeKind, List<String>>{
    NapThemeKind.light: [
      'textPrimary / background',
      'textPrimary / surface',
      'textPrimary / fill',
      'textSecondary / background',
      'textSecondary / surface',
      'textSecondary / fill',
      'textSecondary / backgroundGrouped',
      'textSecondary / accentContainer',
      'textSecondary / warningContainer',
      'textSecondary / successContainer',
      'textSecondary / dangerContainer',
      'accent / background',
      'accent / surface',
      'accent / fill',
      'accent / accentContainer',
      'onAccent / accent',
      'onInverseSurface / inverseSurface',
      'success / background',
      'success / successContainer',
      'success / fill',
      'warning / warningContainer',
      'warning / background',
      'warning / surfaceFloating',
      'danger / background',
      'danger / dangerContainer',
      'onDanger / danger',
    ],
    NapThemeKind.dark: [
      'textPrimary / background',
      'textSecondary / fill',
      'accent / background',
      'onAccent / accent',
      'warning / surface',
      'danger / dangerContainer',
    ],
    NapThemeKind.alarm: [
      'textPrimary / background',
      'textSecondary / accentContainer',
      'onAccent / accent',
      'alarmAccent / background',
      'onAlarmAccent / alarmAccent',
      'overshootLabel / background',
      'onAlarmAccent / overshootAccent',
    ],
  };

  for (final (id, kind) in const [
    ('TC02', NapThemeKind.light),
    ('TC03', NapThemeKind.dark),
    ('TC04', NapThemeKind.alarm),
  ]) {
    test('$id every text pair of ${kind.name} reaches 4.5:1', () {
      final pairs = napContrastPairs(NapThemes.colorsOf(kind), kind);
      final text = pairs.where((p) => p.isText).toList();
      expect(text, isNotEmpty);
      for (final p in text) {
        expect(
          p.ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${kind.name} ${p.name} = ${p.ratio.toStringAsFixed(2)}',
        );
      }
      final names = pairs.map((p) => p.name).toSet();
      for (final name in specPairs[kind]!) {
        expect(names, contains(name), reason: kind.name);
      }
    });
  }

  test('TC05 every non-text pair of the 3 themes reaches 3:1', () {
    for (final kind in NapThemeKind.values) {
      final pairs = napContrastPairs(
        NapThemes.colorsOf(kind),
        kind,
      ).where((p) => !p.isText).toList();
      expect(
        pairs.map((p) => p.name),
        containsAll([
          'outline / surface',
          'outline / fill',
          'accent / surface',
        ]),
      );
      for (final p in pairs) {
        expect(
          p.ratio,
          greaterThanOrEqualTo(3.0),
          reason: '${kind.name} ${p.name} = ${p.ratio.toStringAsFixed(2)}',
        );
      }
    }
  });
}
