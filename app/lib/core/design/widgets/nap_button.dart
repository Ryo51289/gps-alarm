import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_colors.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_motion.dart';

enum NapButtonVariant { primary, secondary, tonal, danger, text, link }

enum NapButtonSize { large, medium, small, compact }

/// Text button of the design system (spec T20 section 5.1).
///
/// Heights are minimums: the button grows with a 2-line label or a large
/// text scale. Small and compact sizes keep a 48 px touch target.
final class NapButton extends StatelessWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.variant = NapButtonVariant.primary,
    this.size = NapButtonSize.large,
    this.icon,
    this.expand,
    this.pill = false,
    super.key,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final NapButtonVariant variant;
  final NapButtonSize size;

  /// Decorative icon before the label.
  final IconData? icon;

  /// Full width. Null: true for large/medium, false for small/compact.
  final bool? expand;

  /// Pill shape for large/medium (small/compact are always pills).
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final style = napButtonStyle(
      variant: variant,
      size: size,
      colors: context.napColors,
      textTheme: context.napText,
      pill: pill,
    ).copyWith(animationDuration: NapMotion.of(context, NapMotion.fast));
    final text = Text(
      label,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    );
    final iconWidget = icon == null ? null : Icon(icon);
    final Widget button = switch (variant) {
      NapButtonVariant.primary || NapButtonVariant.tonal =>
        iconWidget == null
            ? FilledButton(onPressed: onPressed, style: style, child: text)
            : FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: iconWidget,
                label: text,
              ),
      NapButtonVariant.secondary =>
        iconWidget == null
            ? OutlinedButton(onPressed: onPressed, style: style, child: text)
            : OutlinedButton.icon(
                onPressed: onPressed,
                style: style,
                icon: iconWidget,
                label: text,
              ),
      NapButtonVariant.danger ||
      NapButtonVariant.text ||
      NapButtonVariant.link =>
        iconWidget == null
            ? TextButton(onPressed: onPressed, style: style, child: text)
            : TextButton.icon(
                onPressed: onPressed,
                style: style,
                icon: iconWidget,
                label: text,
              ),
    };
    final full =
        expand ?? (size == NapButtonSize.large || size == NapButtonSize.medium);
    return full ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Visible minimum height of a button [size].
double napButtonHeight(NapButtonSize size) => switch (size) {
  NapButtonSize.large => NapSizes.buttonLarge,
  NapButtonSize.medium => NapSizes.buttonMedium,
  NapButtonSize.small => NapSizes.buttonSmall,
  NapButtonSize.compact => NapSizes.buttonCompact,
};

/// [ButtonStyle] of a [NapButton]; also used by the Material button themes.
ButtonStyle napButtonStyle({
  required NapButtonVariant variant,
  required NapButtonSize size,
  required NapColors colors,
  required TextTheme textTheme,
  bool pill = false,
}) {
  final height = napButtonHeight(size);
  final (radius, textStyle, iconSize, hPad, vPad) = switch (size) {
    NapButtonSize.large => (
      pill ? NapRadii.pill : NapRadii.r16,
      textTheme.labelLarge,
      NapSizes.icon,
      NapSpace.s20,
      NapSpace.s8,
    ),
    NapButtonSize.medium => (
      pill ? NapRadii.pill : NapRadii.r14,
      textTheme.titleSmall,
      NapSizes.icon,
      NapSpace.s16,
      NapSpace.s8,
    ),
    NapButtonSize.small => (
      NapRadii.pill,
      textTheme.labelMedium,
      NapSizes.iconSmall,
      NapSpace.s16,
      NapSpace.s6,
    ),
    NapButtonSize.compact => (
      NapRadii.pill,
      textTheme.labelSmall,
      14.0,
      NapSpace.s12,
      NapSpace.s4,
    ),
  };
  final foreground = switch (variant) {
    NapButtonVariant.primary => colors.onAccent,
    NapButtonVariant.secondary || NapButtonVariant.tonal => colors.textPrimary,
    NapButtonVariant.danger => colors.danger,
    NapButtonVariant.text => colors.textSecondary,
    NapButtonVariant.link => colors.accent,
  };
  final background = switch (variant) {
    NapButtonVariant.primary => colors.accent,
    NapButtonVariant.tonal => colors.fill,
    _ => Colors.transparent,
  };
  final filled =
      variant == NapButtonVariant.primary || variant == NapButtonVariant.tonal;
  // Material 3 disabled colors: onSurface (= textPrimary) at 38% / 12%.
  final disabledForeground = colors.textPrimary.withValues(alpha: 0.38);
  final disabledBackground = filled
      ? colors.textPrimary.withValues(alpha: 0.12)
      : Colors.transparent;
  bool disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);

  return ButtonStyle(
    textStyle: WidgetStatePropertyAll(textStyle),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => disabled(s) ? disabledForeground : foreground,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => disabled(s) ? disabledForeground : foreground,
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => disabled(s) ? disabledBackground : background,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (s) =>
          s.contains(WidgetState.pressed) ||
              s.contains(WidgetState.hovered) ||
              s.contains(WidgetState.focused)
          ? foreground.withValues(alpha: 0.10)
          : null,
    ),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    side: variant == NapButtonVariant.secondary
        ? WidgetStateProperty.resolveWith(
            (s) => BorderSide(
              color: disabled(s)
                  ? colors.textPrimary.withValues(alpha: 0.12)
                  : colors.border,
            ),
          )
        : const WidgetStatePropertyAll(BorderSide.none),
    padding: WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
    ),
    minimumSize: WidgetStatePropertyAll(Size(height, height)),
    iconSize: WidgetStatePropertyAll(iconSize),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    tapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    alignment: Alignment.center,
  );
}
