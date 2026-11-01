import 'package:flutter/material.dart';
import 'package:napstop/core/design/tokens/nap_colors.dart';
import 'package:napstop/core/design/tokens/nap_shadows.dart';

/// Shortcuts to the design system tokens of the current theme.
extension NapThemeContext on BuildContext {
  NapColors get napColors => Theme.of(this).extension<NapColors>()!;

  NapShadows get napShadows => Theme.of(this).extension<NapShadows>()!;

  /// The 15 Material 3 styles, with the theme font and `textPrimary`.
  TextTheme get napText => Theme.of(this).textTheme;

  /// Resolves one of the additional `NapTypography` styles (caption,
  /// overline...) against the theme, so it gets the theme font family and
  /// `textPrimary` color.
  TextStyle napStyle(TextStyle style) => napText.bodyMedium!.merge(style);
}
