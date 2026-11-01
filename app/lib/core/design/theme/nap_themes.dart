import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_component_themes.dart';
import 'package:napstop/core/design/theme/nap_theme_kind.dart';
import 'package:napstop/core/design/tokens/nap_colors.dart';
import 'package:napstop/core/design/tokens/nap_shadows.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';

export 'package:napstop/core/design/theme/nap_theme_kind.dart';

/// Material 3 [ThemeData] of the three themes (spec T20 section 4).
///
/// Results are cached per (kind, fontFamily). `fontFamily` exists only for
/// golden tests (FlutterTest font); product code uses the default.
abstract final class NapThemes {
  static final Map<(NapThemeKind, String), ThemeData> _cache = {};

  static ThemeData light({String fontFamily = kNapFontFamily}) =>
      of(NapThemeKind.light, fontFamily: fontFamily);

  static ThemeData dark({String fontFamily = kNapFontFamily}) =>
      of(NapThemeKind.dark, fontFamily: fontFamily);

  static ThemeData alarm({String fontFamily = kNapFontFamily}) =>
      of(NapThemeKind.alarm, fontFamily: fontFamily);

  static ThemeData of(
    NapThemeKind kind, {
    String fontFamily = kNapFontFamily,
  }) => _cache.putIfAbsent((kind, fontFamily), () => _build(kind, fontFamily));

  static NapColors colorsOf(NapThemeKind kind) => switch (kind) {
    NapThemeKind.light => NapColors.light,
    NapThemeKind.dark => NapColors.dark,
    NapThemeKind.alarm => NapColors.alarm,
  };

  static ColorScheme colorScheme(NapColors c, Brightness brightness) =>
      ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.onAccent,
        primaryContainer: c.accentContainer,
        onPrimaryContainer: c.onAccentContainer,
        secondary: c.inverseSurface,
        onSecondary: c.onInverseSurface,
        secondaryContainer: c.fill,
        onSecondaryContainer: c.textPrimary,
        tertiary: c.success,
        onTertiary: c.onSuccess,
        tertiaryContainer: c.successContainer,
        onTertiaryContainer: c.success,
        error: c.danger,
        onError: c.onDanger,
        errorContainer: c.dangerContainer,
        onErrorContainer: c.danger,
        surface: c.background,
        onSurface: c.textPrimary,
        onSurfaceVariant: c.textSecondary,
        surfaceContainerLowest: c.surface,
        surfaceContainerLow: c.surface,
        surfaceBright: c.surface,
        surfaceContainer: c.fill,
        surfaceContainerHigh: c.track,
        surfaceContainerHighest: c.track,
        surfaceDim: c.track,
        surfaceTint: Colors.transparent,
        outline: c.outline,
        outlineVariant: c.border,
        inverseSurface: c.inverseSurface,
        onInverseSurface: c.onInverseSurface,
        // The accent of the opposite brightness.
        inversePrimary: brightness == Brightness.light
            ? NapColors.dark.accent
            : NapColors.light.accent,
        shadow: Colors.black,
        scrim: c.scrim,
      );

  static ThemeData _build(NapThemeKind kind, String fontFamily) {
    final c = colorsOf(kind);
    final shadows = kind == NapThemeKind.light
        ? NapShadows.light
        : NapShadows.dark;
    final brightness = kind == NapThemeKind.light
        ? Brightness.light
        : Brightness.dark;
    final textTheme = NapTypography.textTheme().apply(
      fontFamily: fontFamily,
      bodyColor: c.textPrimary,
      displayColor: c.textPrimary,
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme(c, brightness),
      fontFamily: fontFamily,
      textTheme: textTheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      extensions: [c, shadows],
      filledButtonTheme: NapComponentThemes.filledButton(c, textTheme),
      outlinedButtonTheme: NapComponentThemes.outlinedButton(c, textTheme),
      textButtonTheme: NapComponentThemes.textButton(c, textTheme),
      iconButtonTheme: NapComponentThemes.iconButton(c),
      switchTheme: NapComponentThemes.switchTheme(c, brightness),
      sliderTheme: NapComponentThemes.slider(c),
      bottomSheetTheme: NapComponentThemes.bottomSheet(c),
      dividerTheme: NapComponentThemes.divider(c),
      navigationBarTheme: NapComponentThemes.navigationBar(c, fontFamily),
      textSelectionTheme: NapComponentThemes.textSelection(c),
      progressIndicatorTheme: NapComponentThemes.progressIndicator(c),
      dialogTheme: NapComponentThemes.dialog(c),
      snackBarTheme: NapComponentThemes.snackBar(c, textTheme),
    );
  }
}
