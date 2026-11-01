import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/widgets/nap_tone.dart';

/// Decorative rounded square with an icon (spec T20 section 5.12).
final class NapIconTile extends StatelessWidget {
  const new({
    required this.icon,
    this.tone = NapTone.neutral,
    this.onFill = false,
    this.size = NapSizes.iconTile,
    super.key,
  });

  final IconData icon;
  final NapTone tone;

  /// Neutral tile placed on a gray or tinted card: uses `surface`.
  final bool onFill;

  /// 40 (default) or 56 (sheet header).
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final large = size >= NapSizes.iconTileLarge;
    final background = tone == NapTone.neutral && onFill
        ? c.surface
        : tone.containerOf(c);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(
            large ? NapRadii.r16 : NapRadii.r10,
          ),
        ),
        child: Icon(
          icon,
          size: large ? 28 : NapSizes.icon,
          color: tone.foregroundOf(c),
        ),
      ),
    );
  }
}
