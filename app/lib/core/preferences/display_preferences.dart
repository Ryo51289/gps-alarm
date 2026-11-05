/// Language and theme of the app (screen 12, T28 §4.1).
library;

import 'package:flutter/material.dart';

/// App language. Wire names (stored, never renamed): `system`, `vi`, `en`.
enum AppLanguage { system, vi, en }

/// App theme. Wire names (stored, never renamed): `system`, `light`, `dark`.
enum AppThemeChoice { system, light, dark }

@immutable
final class DisplayPreferences {
  const new({required this.language, required this.theme});

  final AppLanguage language;
  final AppThemeChoice theme;

  /// New users follow the phone for both (T28 Q2 = A). A phone in another
  /// language shows Vietnamese (T20 Q3).
  static const DisplayPreferences defaults = DisplayPreferences(
    language: AppLanguage.system,
    theme: AppThemeChoice.system,
  );

  /// `MaterialApp.locale`; null follows the phone.
  Locale? get locale => switch (language) {
    AppLanguage.system => null,
    AppLanguage.vi => const Locale('vi'),
    AppLanguage.en => const Locale('en'),
  };

  ThemeMode get themeMode => switch (theme) {
    AppThemeChoice.system => ThemeMode.system,
    AppThemeChoice.light => ThemeMode.light,
    AppThemeChoice.dark => ThemeMode.dark,
  };

  /// Tag sent to `setAppLocale` (native strings); null follows the phone.
  String? get nativeTag => switch (language) {
    AppLanguage.system => null,
    AppLanguage.vi => 'vi',
    AppLanguage.en => 'en',
  };

  DisplayPreferences copyWith({AppLanguage? language, AppThemeChoice? theme}) =>
      DisplayPreferences(
        language: language ?? this.language,
        theme: theme ?? this.theme,
      );

  @override
  bool operator ==(Object other) =>
      other is DisplayPreferences &&
      other.language == language &&
      other.theme == theme;

  @override
  int get hashCode => Object.hash(language, theme);

  @override
  String toString() => 'DisplayPreferences(${language.name}, ${theme.name})';
}
