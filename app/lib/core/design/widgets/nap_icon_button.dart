import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';

enum NapIconButtonVariant { plain, outlined, floating }

/// Icon-only button (spec T20 section 5.2). [semanticLabel] is required and
/// doubles as the tooltip.
final class NapIconButton extends StatelessWidget {
  const new({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.variant = NapIconButtonVariant.outlined,
    this.size = NapSizes.iconButton,
    this.square = false,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final NapIconButtonVariant variant;

  /// Visible size: 44 (default), 48 (map buttons), 56 (save place).
  final double size;

  /// Rounded square (r16) instead of a circle.
  final bool square;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final shadows = context.napShadows;
    final shape = square
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NapRadii.r16),
          )
        : const CircleBorder();
    final background = switch (variant) {
      NapIconButtonVariant.plain => Colors.transparent,
      NapIconButtonVariant.outlined => c.surface,
      NapIconButtonVariant.floating => c.surfaceFloating,
    };
    final bordered =
        variant == NapIconButtonVariant.outlined ||
        (variant == NapIconButtonVariant.floating &&
            shadows.borderInsteadOfShadow);
    final button = IconButton(
      onPressed: onPressed,
      tooltip: semanticLabel,
      icon: Icon(
        icon,
        size: size >= NapSizes.iconTileLarge
            ? NapSizes.iconLarge
            : NapSizes.icon,
      ),
      style: IconButton.styleFrom(
        foregroundColor: c.textPrimary,
        backgroundColor: background,
        disabledForegroundColor: c.textPrimary.withValues(alpha: 0.38),
        disabledBackgroundColor: background,
        fixedSize: Size.square(size),
        minimumSize: Size.square(size),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
        shape: shape,
        side: bordered ? BorderSide(color: c.border) : BorderSide.none,
      ),
    );
    final hasShadow =
        variant == NapIconButtonVariant.floating &&
        !shadows.borderInsteadOfShadow;
    if (!hasShadow) {
      return button;
    }
    // The shadow sits behind the visible shape only, not the padded target.
    return Stack(
      alignment: Alignment.center,
      children: [
        IgnorePointer(
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: shape,
              color: background,
              shadows: shadows.floating,
            ),
            child: SizedBox.square(dimension: size),
          ),
        ),
        button,
      ],
    );
  }
}
