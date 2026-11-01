import 'package:flutter/material.dart';

/// Color tokens of the NapStop design system (spec T20 section 2).
///
/// Single source of truth: the [ColorScheme] of each theme is derived from
/// these values. Widgets read them through `context.napColors`.
@immutable
final class NapColors extends ThemeExtension<NapColors> {
  const new({
    required this.background,
    required this.backgroundGrouped,
    required this.surface,
    required this.surfaceFloating,
    required this.fill,
    required this.track,
    required this.segmentThumb,
    required this.border,
    required this.divider,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.warningBorder,
    required this.warningIndicator,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.alarmAccent,
    required this.onAlarmAccent,
    required this.overshootAccent,
    required this.overshootLabel,
    required this.scrim,
  });

  /// Screen background.
  final Color background;

  /// Background of grouped lists (settings screen).
  final Color backgroundGrouped;

  /// Cards on a grouped background, sheets, dialogs.
  final Color surface;

  /// Buttons and labels floating on the map.
  final Color surfaceFloating;

  /// Search field, segmented track, icon tiles, tonal buttons.
  final Color fill;

  /// Progress track.
  final Color track;

  /// Selected segment of a segmented control.
  final Color segmentThumb;

  /// Decorative borders of cards, chips, outlined buttons.
  final Color border;

  /// Row dividers inside a group.
  final Color divider;

  /// Outline of controls that must reach 3:1 (switch off, radio).
  final Color outline;

  final Color textPrimary;
  final Color textSecondary;
  final Color inverseSurface;
  final Color onInverseSurface;
  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color warningBorder;

  /// Non-text indicator (3:1). Use on `surface`/`surfaceFloating`: on the
  /// light `fill` it reaches only 2.87:1.
  final Color warningIndicator;
  final Color danger;
  final Color onDanger;
  final Color dangerContainer;

  /// Alarm theme only (screens 5/6): light and dark keep the alarm value,
  /// which fails contrast on light backgrounds (2.04:1 on white).
  final Color alarmAccent;

  /// Text on [alarmAccent] or [overshootAccent]; alarm theme only.
  final Color onAlarmAccent;

  /// Alarm theme only (overshoot screen); low contrast on light backgrounds.
  final Color overshootAccent;

  /// Alarm theme only (overshoot screen): 2.27:1 on white, do not use as
  /// text on light themes.
  final Color overshootLabel;

  /// Base color of the barrier behind sheets; apply [scrimOpacity].
  final Color scrim;

  /// Opacity of the barrier behind sheets and dialogs.
  static const double scrimOpacity = 0.55;

  static const NapColors light = NapColors(
    background: Color(0xFFFFFFFF),
    backgroundGrouped: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    surfaceFloating: Color(0xFFFFFFFF),
    fill: Color(0xFFF2F3F5),
    track: Color(0xFFE9EAED),
    segmentThumb: Color(0xFFFFFFFF),
    border: Color(0xFFDCDDE1),
    divider: Color(0xFFECEDEF),
    outline: Color(0xFF80858F),
    textPrimary: Color(0xFF16181D),
    textSecondary: Color(0xFF5B606B),
    inverseSurface: Color(0xFF16181D),
    onInverseSurface: Color(0xFFFFFFFF),
    accent: Color(0xFF2348D1),
    onAccent: Color(0xFFFFFFFF),
    accentContainer: Color(0xFFEEF2FF),
    onAccentContainer: Color(0xFF16181D),
    success: Color(0xFF1F7A4D),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFE7F5EE),
    warning: Color(0xFF8A4B08),
    warningContainer: Color(0xFFFEF6EC),
    warningBorder: Color(0xFFF0C48A),
    warningIndicator: Color(0xFFD97706),
    danger: Color(0xFFB42318),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFDECEC),
    alarmAccent: Color(0xFFFF9F43),
    onAlarmAccent: Color(0xFF0F1115),
    overshootAccent: Color(0xFFFF6B6B),
    overshootLabel: Color(0xFFFF8A8A),
    scrim: Color(0xFF0F1115),
  );

  static const NapColors dark = NapColors(
    background: Color(0xFF0F1115),
    backgroundGrouped: Color(0xFF0F1115),
    surface: Color(0xFF1B1E25),
    surfaceFloating: Color(0xFF262A33),
    fill: Color(0xFF262A33),
    track: Color(0xFF2E323C),
    segmentThumb: Color(0xFF3A3F4B),
    border: Color(0xFF3A3F4B),
    divider: Color(0xFF2A2E38),
    outline: Color(0xFF7A808C),
    textPrimary: Color(0xFFF2F3F5),
    textSecondary: Color(0xFF9EA3AD),
    inverseSurface: Color(0xFFF2F3F5),
    onInverseSurface: Color(0xFF0F1115),
    accent: Color(0xFF8CA2FF),
    onAccent: Color(0xFF0F1115),
    accentContainer: Color(0xFF1E2A52),
    onAccentContainer: Color(0xFFF2F3F5),
    success: Color(0xFF7DD3A8),
    onSuccess: Color(0xFF0F1115),
    successContainer: Color(0xFF173A2A),
    warning: Color(0xFFFFB869),
    warningContainer: Color(0xFF3A2A14),
    warningBorder: Color(0xFF6B4A1F),
    warningIndicator: Color(0xFFFFB869),
    danger: Color(0xFFFF8A8A),
    onDanger: Color(0xFF0F1115),
    dangerContainer: Color(0xFF3D1A1A),
    alarmAccent: Color(0xFFFF9F43),
    onAlarmAccent: Color(0xFF0F1115),
    overshootAccent: Color(0xFFFF6B6B),
    overshootLabel: Color(0xFFFF8A8A),
    scrim: Color(0xFF0F1115),
  );

  /// Always-dark theme of the alarm screens (5, 8).
  static const NapColors alarm = NapColors(
    background: Color(0xFF0F1115),
    backgroundGrouped: Color(0xFF0F1115),
    surface: Color(0xFF1B1E25),
    surfaceFloating: Color(0xFF262A33),
    fill: Color(0xFF262A33),
    track: Color(0xFF262A33),
    segmentThumb: Color(0xFF3A3F4B),
    border: Color(0xFF3A3F4B),
    divider: Color(0xFF2A2E38),
    outline: Color(0xFF7A808C),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFC9CCD3),
    inverseSurface: Color(0xFFFFFFFF),
    onInverseSurface: Color(0xFF0F1115),
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF0F1115),
    accentContainer: Color(0xFF1E2A52),
    onAccentContainer: Color(0xFFFFFFFF),
    success: Color(0xFF7DD3A8),
    onSuccess: Color(0xFF0F1115),
    successContainer: Color(0xFF173A2A),
    warning: Color(0xFFFFB869),
    warningContainer: Color(0xFF3A2A14),
    warningBorder: Color(0xFF6B4A1F),
    warningIndicator: Color(0xFFFFB869),
    danger: Color(0xFFFF8A8A),
    onDanger: Color(0xFF0F1115),
    dangerContainer: Color(0xFF3D1A1A),
    alarmAccent: Color(0xFFFF9F43),
    onAlarmAccent: Color(0xFF0F1115),
    overshootAccent: Color(0xFFFF6B6B),
    overshootLabel: Color(0xFFFF8A8A),
    scrim: Color(0xFF0F1115),
  );

  /// Every token by name, in declaration order (catalog, tests, equality).
  Map<String, Color> get tokens => {
    'background': background,
    'backgroundGrouped': backgroundGrouped,
    'surface': surface,
    'surfaceFloating': surfaceFloating,
    'fill': fill,
    'track': track,
    'segmentThumb': segmentThumb,
    'border': border,
    'divider': divider,
    'outline': outline,
    'textPrimary': textPrimary,
    'textSecondary': textSecondary,
    'inverseSurface': inverseSurface,
    'onInverseSurface': onInverseSurface,
    'accent': accent,
    'onAccent': onAccent,
    'accentContainer': accentContainer,
    'onAccentContainer': onAccentContainer,
    'success': success,
    'onSuccess': onSuccess,
    'successContainer': successContainer,
    'warning': warning,
    'warningContainer': warningContainer,
    'warningBorder': warningBorder,
    'warningIndicator': warningIndicator,
    'danger': danger,
    'onDanger': onDanger,
    'dangerContainer': dangerContainer,
    'alarmAccent': alarmAccent,
    'onAlarmAccent': onAlarmAccent,
    'overshootAccent': overshootAccent,
    'overshootLabel': overshootLabel,
    'scrim': scrim,
  };

  @override
  NapColors copyWith({
    Color? background,
    Color? backgroundGrouped,
    Color? surface,
    Color? surfaceFloating,
    Color? fill,
    Color? track,
    Color? segmentThumb,
    Color? border,
    Color? divider,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? inverseSurface,
    Color? onInverseSurface,
    Color? accent,
    Color? onAccent,
    Color? accentContainer,
    Color? onAccentContainer,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? warningBorder,
    Color? warningIndicator,
    Color? danger,
    Color? onDanger,
    Color? dangerContainer,
    Color? alarmAccent,
    Color? onAlarmAccent,
    Color? overshootAccent,
    Color? overshootLabel,
    Color? scrim,
  }) {
    return NapColors(
      background: background ?? this.background,
      backgroundGrouped: backgroundGrouped ?? this.backgroundGrouped,
      surface: surface ?? this.surface,
      surfaceFloating: surfaceFloating ?? this.surfaceFloating,
      fill: fill ?? this.fill,
      track: track ?? this.track,
      segmentThumb: segmentThumb ?? this.segmentThumb,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      outline: outline ?? this.outline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      inverseSurface: inverseSurface ?? this.inverseSurface,
      onInverseSurface: onInverseSurface ?? this.onInverseSurface,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentContainer: accentContainer ?? this.accentContainer,
      onAccentContainer: onAccentContainer ?? this.onAccentContainer,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      warningBorder: warningBorder ?? this.warningBorder,
      warningIndicator: warningIndicator ?? this.warningIndicator,
      danger: danger ?? this.danger,
      onDanger: onDanger ?? this.onDanger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      alarmAccent: alarmAccent ?? this.alarmAccent,
      onAlarmAccent: onAlarmAccent ?? this.onAlarmAccent,
      overshootAccent: overshootAccent ?? this.overshootAccent,
      overshootLabel: overshootLabel ?? this.overshootLabel,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  NapColors lerp(covariant NapColors? other, double t) {
    if (other == null || t == 0) {
      return this;
    }
    if (t == 1) {
      return other;
    }
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return NapColors(
      background: l(background, other.background),
      backgroundGrouped: l(backgroundGrouped, other.backgroundGrouped),
      surface: l(surface, other.surface),
      surfaceFloating: l(surfaceFloating, other.surfaceFloating),
      fill: l(fill, other.fill),
      track: l(track, other.track),
      segmentThumb: l(segmentThumb, other.segmentThumb),
      border: l(border, other.border),
      divider: l(divider, other.divider),
      outline: l(outline, other.outline),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      inverseSurface: l(inverseSurface, other.inverseSurface),
      onInverseSurface: l(onInverseSurface, other.onInverseSurface),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentContainer: l(accentContainer, other.accentContainer),
      onAccentContainer: l(onAccentContainer, other.onAccentContainer),
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      warningBorder: l(warningBorder, other.warningBorder),
      warningIndicator: l(warningIndicator, other.warningIndicator),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      alarmAccent: l(alarmAccent, other.alarmAccent),
      onAlarmAccent: l(onAlarmAccent, other.onAlarmAccent),
      overshootAccent: l(overshootAccent, other.overshootAccent),
      overshootLabel: l(overshootLabel, other.overshootLabel),
      scrim: l(scrim, other.scrim),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! NapColors) {
      return false;
    }
    final a = tokens;
    final b = other.tokens;
    return a.keys.every((k) => a[k] == b[k]);
  }

  @override
  int get hashCode => Object.hashAll(tokens.values);
}
