// TC06: token values match spec T20 section 2. TC08: lerp / copyWith.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

// Columns light / dark / alarm of the table in spec T20 section 2.
const Map<String, List<int>> _spec = {
  'background': [0xFFFFFFFF, 0xFF0F1115, 0xFF0F1115],
  'backgroundGrouped': [0xFFF7F7F8, 0xFF0F1115, 0xFF0F1115],
  'surface': [0xFFFFFFFF, 0xFF1B1E25, 0xFF1B1E25],
  'surfaceFloating': [0xFFFFFFFF, 0xFF262A33, 0xFF262A33],
  'fill': [0xFFF2F3F5, 0xFF262A33, 0xFF262A33],
  'track': [0xFFE9EAED, 0xFF2E323C, 0xFF262A33],
  'segmentThumb': [0xFFFFFFFF, 0xFF3A3F4B, 0xFF3A3F4B],
  'border': [0xFFDCDDE1, 0xFF3A3F4B, 0xFF3A3F4B],
  'divider': [0xFFECEDEF, 0xFF2A2E38, 0xFF2A2E38],
  'outline': [0xFF80858F, 0xFF7A808C, 0xFF7A808C],
  'textPrimary': [0xFF16181D, 0xFFF2F3F5, 0xFFFFFFFF],
  'textSecondary': [0xFF5B606B, 0xFF9EA3AD, 0xFFC9CCD3],
  'inverseSurface': [0xFF16181D, 0xFFF2F3F5, 0xFFFFFFFF],
  'onInverseSurface': [0xFFFFFFFF, 0xFF0F1115, 0xFF0F1115],
  'accent': [0xFF2348D1, 0xFF8CA2FF, 0xFFFFFFFF],
  'onAccent': [0xFFFFFFFF, 0xFF0F1115, 0xFF0F1115],
  'accentContainer': [0xFFEEF2FF, 0xFF1E2A52, 0xFF1E2A52],
  'onAccentContainer': [0xFF16181D, 0xFFF2F3F5, 0xFFFFFFFF],
  'success': [0xFF1F7A4D, 0xFF7DD3A8, 0xFF7DD3A8],
  'onSuccess': [0xFFFFFFFF, 0xFF0F1115, 0xFF0F1115],
  'successContainer': [0xFFE7F5EE, 0xFF173A2A, 0xFF173A2A],
  'warning': [0xFF8A4B08, 0xFFFFB869, 0xFFFFB869],
  'warningContainer': [0xFFFEF6EC, 0xFF3A2A14, 0xFF3A2A14],
  'warningBorder': [0xFFF0C48A, 0xFF6B4A1F, 0xFF6B4A1F],
  'warningIndicator': [0xFFD97706, 0xFFFFB869, 0xFFFFB869],
  'danger': [0xFFB42318, 0xFFFF8A8A, 0xFFFF8A8A],
  'onDanger': [0xFFFFFFFF, 0xFF0F1115, 0xFF0F1115],
  'dangerContainer': [0xFFFDECEC, 0xFF3D1A1A, 0xFF3D1A1A],
  'alarmAccent': [0xFFFF9F43, 0xFFFF9F43, 0xFFFF9F43],
  'onAlarmAccent': [0xFF0F1115, 0xFF0F1115, 0xFF0F1115],
  'overshootAccent': [0xFFFF6B6B, 0xFFFF6B6B, 0xFFFF6B6B],
  'overshootLabel': [0xFFFF8A8A, 0xFFFF8A8A, 0xFFFF8A8A],
  'scrim': [0xFF0F1115, 0xFF0F1115, 0xFF0F1115],
};

void main() {
  const themes = [NapColors.light, NapColors.dark, NapColors.alarm];

  test('TC06 every token matches the spec table', () {
    expect(_spec, hasLength(33));
    for (var i = 0; i < themes.length; i++) {
      final tokens = themes[i].tokens;
      expect(tokens.keys.toSet(), _spec.keys.toSet());
      for (final MapEntry(key: name, value: hex) in _spec.entries) {
        expect(
          tokens[name]!.toARGB32(),
          hex[i],
          reason: '$name in ${['light', 'dark', 'alarm'][i]}',
        );
      }
    }
    expect(NapColors.scrimOpacity, 0.55);
  });

  group('TC08 NapColors', () {
    test('lerp ends and null', () {
      expect(NapColors.light.lerp(NapColors.dark, 0), NapColors.light);
      expect(NapColors.light.lerp(NapColors.dark, 1), NapColors.dark);
      expect(NapColors.light.lerp(null, 0.5), NapColors.light);
      final mid = NapColors.light.lerp(NapColors.dark, 0.5);
      expect(mid, isNot(NapColors.light));
      expect(mid, isNot(NapColors.dark));
    });

    test('copyWith changes only the given field', () {
      const x = Color(0xFF123456);
      final copy = NapColors.light.copyWith(accent: x);
      final before = NapColors.light.tokens;
      final after = copy.tokens;
      for (final name in before.keys) {
        expect(after[name], name == 'accent' ? x : before[name], reason: name);
      }
      expect(NapColors.light.copyWith(), NapColors.light);
    });
  });

  group('TC08 NapShadows', () {
    test('lerp ends and null', () {
      expect(NapShadows.light.lerp(NapShadows.dark, 0), NapShadows.light);
      expect(NapShadows.light.lerp(NapShadows.dark, 1), NapShadows.dark);
      expect(NapShadows.light.lerp(null, 0.5), NapShadows.light);
      expect(
        NapShadows.light.lerp(NapShadows.dark, 0.4).borderInsteadOfShadow,
        isFalse,
      );
      expect(
        NapShadows.light.lerp(NapShadows.dark, 0.6).borderInsteadOfShadow,
        isTrue,
      );
    });

    test('copyWith changes only the given field', () {
      final copy = NapShadows.light.copyWith(borderInsteadOfShadow: true);
      expect(copy.borderInsteadOfShadow, isTrue);
      expect(copy.floating, NapShadows.light.floating);
      expect(copy.thumb, NapShadows.light.thumb);
      expect(copy.sheet, NapShadows.light.sheet);
    });

    test('values match spec section 3.1', () {
      expect(NapShadows.light.floating.single.color.toARGB32(), 0x1F000000);
      expect(NapShadows.light.floating.single.offset, const Offset(0, 2));
      expect(NapShadows.light.floating.single.blurRadius, 8);
      expect(NapShadows.light.thumb.single.offset, const Offset(0, 1));
      expect(NapShadows.light.thumb.single.blurRadius, 3);
      expect(NapShadows.light.sheet.single.color.toARGB32(), 0x14000000);
      expect(NapShadows.light.sheet.single.offset, const Offset(0, -4));
      expect(NapShadows.light.sheet.single.blurRadius, 16);
      expect(NapShadows.light.borderInsteadOfShadow, isFalse);
      expect(NapShadows.dark.floating, isEmpty);
      expect(NapShadows.dark.borderInsteadOfShadow, isTrue);
    });
  });
}
