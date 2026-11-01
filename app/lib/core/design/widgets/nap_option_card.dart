import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/widgets/nap_radio_indicator.dart';

enum NapOptionLayout { row, tile }

/// One choice of a single-choice group shown as a card
/// (spec T20 section 5.8).
final class NapOptionCard extends StatelessWidget {
  const new({
    required this.title,
    required this.selected,
    required this.onTap,
    this.description,
    this.icon,
    this.layout = NapOptionLayout.row,
    super.key,
  }) : assert(
         layout != NapOptionLayout.tile || icon != null,
         'A tile option needs an icon',
       );

  final String title;
  final String? description;

  /// Required for [NapOptionLayout.tile].
  final IconData? icon;
  final bool selected;

  /// Null disables the card.
  final VoidCallback? onTap;
  final NapOptionLayout layout;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(NapRadii.r14),
      side: BorderSide(color: selected ? c.accent : c.border, width: 1.5),
    );
    final Widget content = switch (layout) {
      NapOptionLayout.row => Padding(
        padding: const EdgeInsets.all(NapSpace.s14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NapRadioIndicator(selected: selected),
            const SizedBox(width: NapSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: NapSpace.s2,
                children: [
                  Text(title, style: text.titleSmall),
                  if (description case final description?)
                    Text(
                      description,
                      style: text.bodySmall!.copyWith(
                        color: c.textSecondary,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      NapOptionLayout.tile => Padding(
        padding: const EdgeInsets.symmetric(
          vertical: NapSpace.s14,
          horizontal: NapSpace.s6,
        ),
        child: Column(
          spacing: NapSpace.s6,
          children: [
            Icon(icon, size: NapSizes.iconXLarge, color: c.textPrimary),
            Text(title, textAlign: TextAlign.center, style: text.labelSmall),
          ],
        ),
      ),
    };
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: onTap != null,
      label: title,
      hint: description,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.accentContainer : c.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
