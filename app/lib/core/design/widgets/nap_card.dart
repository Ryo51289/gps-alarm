import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';

enum NapCardVariant { outlined, filled, accent, warning }

/// Container card (spec T20 section 5.9). With [onTap] it becomes a button.
final class NapCard extends StatelessWidget {
  const new({
    required this.child,
    this.variant = NapCardVariant.outlined,
    this.padding = const EdgeInsets.all(NapSpace.s16),
    this.radius = NapRadii.r14,
    this.onTap,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final NapCardVariant variant;
  final EdgeInsetsGeometry padding;

  /// r14 (default) or r16 for large cards.
  final double radius;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final (background, border) = switch (variant) {
      NapCardVariant.outlined => (c.surface, c.border),
      NapCardVariant.filled => (c.fill, null),
      NapCardVariant.accent => (c.accentContainer, null),
      NapCardVariant.warning => (c.warningContainer, c.warningBorder),
    };
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border == null ? BorderSide.none : BorderSide(color: border),
    );
    final padded = Padding(padding: padding, child: child);
    final card = Material(
      color: background,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? padded : InkWell(onTap: onTap, child: padded),
    );
    if (onTap == null && semanticLabel == null) {
      return card;
    }
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: card,
    );
  }
}
