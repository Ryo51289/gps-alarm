import 'package:flutter/material.dart';

/// Font family of the bundled Be Vietnam Pro (pubspec `fonts:`).
const String kNapFontFamily = 'BeVietnamPro';

/// Type scale (spec T20 section 3.2).
///
/// Styles set no color and no font family: both come from the theme. Every
/// style sets size, height, weight and letter spacing explicitly (overriding
/// `Typography.material2021`) and spreads the leading evenly so stacked
/// Vietnamese diacritics keep room above the line.
abstract final class NapTypography {
  static const TextStyle displayLarge = TextStyle(
    fontSize: 52,
    height: 1.10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle displayMedium = TextStyle(
    fontSize: 44,
    height: 1.10,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle displaySmall = TextStyle(
    fontSize: 40,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 30,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle headlineMedium = TextStyle(
    fontSize: 26,
    height: 1.30,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle headlineSmall = TextStyle(
    fontSize: 22,
    height: 1.30,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    height: 1.30,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle titleMedium = TextStyle(
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle titleSmall = TextStyle(
    fontSize: 15,
    height: 1.40,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    height: 1.50,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 15,
    height: 1.50,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle bodySmall = TextStyle(
    fontSize: 13,
    height: 1.45,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle labelLarge = TextStyle(
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle labelMedium = TextStyle(
    fontSize: 14,
    height: 1.30,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle labelSmall = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  // Additional styles outside the Material 3 slots. Read them through
  // `context.napStyle(...)` so they pick up the theme font family.

  static const TextStyle body14 = TextStyle(
    fontSize: 14,
    height: 1.50,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.40,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle captionStrong = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Upper-case section label; render with `toUpperCase()`.
  static const TextStyle overline = TextStyle(
    fontSize: 13,
    height: 1.30,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.52,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Upper-case label of the alarm screens; render with `toUpperCase()`.
  static const TextStyle alarmOverline = TextStyle(
    fontSize: 14,
    height: 1.30,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.68,
    leadingDistribution: TextLeadingDistribution.even,
  );
  static const TextStyle etaSecondary = TextStyle(
    fontSize: 18,
    height: 1.30,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// Labels on the map overlay only.
  static const TextStyle mapLabel = TextStyle(
    fontSize: 11,
    height: 1.30,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    leadingDistribution: TextLeadingDistribution.even,
  );

  /// The 7 styles outside the Material 3 slots, by name (catalog, tests).
  static const Map<String, TextStyle> extras = {
    'body14': body14,
    'caption': caption,
    'captionStrong': captionStrong,
    'overline': overline,
    'alarmOverline': alarmOverline,
    'etaSecondary': etaSecondary,
    'mapLabel': mapLabel,
  };

  /// The 15 Material 3 styles as a [TextTheme].
  static TextTheme textTheme() => const TextTheme(
    displayLarge: displayLarge,
    displayMedium: displayMedium,
    displaySmall: displaySmall,
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    headlineSmall: headlineSmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    titleSmall: titleSmall,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelMedium: labelMedium,
    labelSmall: labelSmall,
  );
}
