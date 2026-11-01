import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';
import 'package:napstop/core/design/widgets/nap_tone.dart';

enum NapBadgeSize { small, medium }

/// Non-interactive label (spec T20 section 5.4).
final class NapBadge extends StatelessWidget {
  const new({
    required this.label,
    this.tone = NapTone.neutral,
    this.size = NapBadgeSize.small,
    super.key,
  });

  final String label;
  final NapTone tone;
  final NapBadgeSize size;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final medium = size == NapBadgeSize.medium;
    final (background, foreground, border) = switch ((size, tone)) {
      (NapBadgeSize.medium, NapTone.neutral) => (
        c.surface,
        c.textPrimary,
        c.border,
      ),
      (NapBadgeSize.medium, NapTone.accent) => (c.accent, c.onAccent, null),
      _ => (tone.containerOf(c), tone.foregroundOf(c), null),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          medium ? NapRadii.pill : NapRadii.r6,
        ),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Padding(
        padding: medium
            ? const EdgeInsets.symmetric(
                vertical: NapSpace.s6,
                horizontal: NapSpace.s10,
              )
            : const EdgeInsets.symmetric(vertical: 3, horizontal: NapSpace.s8),
        child: Text(
          label,
          style: medium
              ? context.napText.bodySmall!.copyWith(color: foreground)
              : context
                    .napStyle(NapTypography.captionStrong)
                    .copyWith(color: foreground),
        ),
      ),
    );
  }
}
