import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';
import 'package:napstop/core/design/widgets/nap_tone.dart';

/// Small status cell, e.g. "GPS good / +-8 m" (spec T20 section 5.15).
/// Place three in a `Row` with `Expanded`.
final class NapStatusTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    this.subtitle,
    this.tone = NapTone.neutral,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Icon color only.
  final NapTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final subtitle = this.subtitle;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(NapSpace.s12),
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(NapRadii.r12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: NapSpace.s6,
          children: [
            Icon(icon, size: NapSizes.iconSmall, color: tone.foregroundOf(c)),
            Text(title, style: context.napText.labelSmall),
            if (subtitle != null)
              Text(
                subtitle,
                style: context
                    .napStyle(NapTypography.caption)
                    .copyWith(color: c.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
