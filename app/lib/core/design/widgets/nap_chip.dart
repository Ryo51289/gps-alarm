import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_motion.dart';

enum NapChipStyle { choice, choicePill, filter }

/// Selectable chip (spec T20 section 5.3). No check mark; the selected state
/// is the filled color plus the `selected` semantics flag.
///
/// Built on [OutlinedButton] for the padded 48 px touch target, focus and
/// ink; colors animate over [NapMotion.fast].
final class NapChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.style = NapChipStyle.choice,
    this.compact = false,
    super.key,
  });

  final String label;
  final bool selected;

  /// Null disables the chip.
  final VoidCallback? onTap;
  final NapChipStyle style;

  /// 40 px visible height instead of 44.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final (selectedBg, selectedFg) = style == NapChipStyle.filter
        ? (c.inverseSurface, c.onInverseSurface)
        : (c.accent, c.onAccent);
    final background = selected ? selectedBg : c.surface;
    final foreground = selected ? selectedFg : c.textPrimary;
    final border = selected ? selectedBg : c.border;
    final radius = style == NapChipStyle.choice ? NapRadii.r12 : NapRadii.pill;
    final height = compact ? NapSizes.chipCompact : NapSizes.chip;
    final disabledFg = c.textPrimary.withValues(alpha: 0.38);
    final disabledFill = c.textPrimary.withValues(alpha: 0.12);
    bool disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);

    final buttonStyle = ButtonStyle(
      textStyle: WidgetStatePropertyAll(context.napText.labelMedium),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? disabledFg : foreground,
      ),
      // Disabled: Material 3 style (onSurface at 12%), exempt from contrast.
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) && selected ? disabledFill : background,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.pressed)
            ? foreground.withValues(alpha: 0.10)
            : null,
      ),
      side: WidgetStateProperty.resolveWith(
        (s) => BorderSide(color: disabled(s) ? disabledFill : border),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(
          horizontal: compact ? NapSpace.s14 : NapSpace.s16,
          vertical: NapSpace.s4,
        ),
      ),
      minimumSize: WidgetStatePropertyAll(Size(height, height)),
      elevation: const WidgetStatePropertyAll(0),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      animationDuration: NapMotion.of(context, NapMotion.fast),
    );
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          onPressed: onTap,
          style: buttonStyle,
          child: Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
