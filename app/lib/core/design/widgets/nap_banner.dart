import 'package:flutter/material.dart';
import 'package:napstop/core/design/nap_icons.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/widgets/nap_tone.dart';

/// Inline message box (spec T20 section 5.16). Tones: neutral, warning,
/// danger, success.
final class NapBanner extends StatelessWidget {
  const new({
    required this.message,
    this.title,
    this.tone = NapTone.neutral,
    this.icon,
    this.action,
    this.announce = false,
    super.key,
  }) : assert(tone != NapTone.accent, 'NapBanner has no accent tone');

  final String message;
  final String? title;
  final NapTone tone;

  /// Null: info, warning, error or check, by [tone].
  final IconData? icon;

  /// Widget under the text, e.g. a small secondary NapButton.
  final Widget? action;

  /// Live region: read out when it appears.
  final bool announce;

  /// Default icon of [tone].
  static IconData defaultIcon(NapTone tone) => switch (tone) {
    NapTone.warning => NapIcons.warning,
    NapTone.danger => NapIcons.error,
    NapTone.success => NapIcons.check,
    NapTone.neutral || NapTone.accent => NapIcons.info,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final title = this.title;
    final action = this.action;
    final neutral = tone == NapTone.neutral;
    final (background, border) = switch (tone) {
      NapTone.warning => (c.warningContainer, c.warningBorder),
      NapTone.danger => (c.dangerContainer, null),
      NapTone.success => (c.successContainer, null),
      NapTone.neutral || NapTone.accent => (Colors.transparent, c.border),
    };
    final bodyColor = neutral ? c.textSecondary : tone.foregroundOf(c);
    final titleColor = neutral ? c.textPrimary : tone.foregroundOf(c);
    return Semantics(
      container: true,
      liveRegion: announce ? true : null,
      child: Container(
        padding: EdgeInsets.all(title == null ? NapSpace.s12 : NapSpace.s14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(NapRadii.r12),
          border: border == null ? null : Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon ?? defaultIcon(tone),
              size: title == null ? NapSizes.iconSmall : NapSizes.iconLarge,
              color: bodyColor,
            ),
            const SizedBox(width: NapSpace.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: NapSpace.s4,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: text.titleSmall!.copyWith(color: titleColor),
                    ),
                  Text(
                    message,
                    style: text.bodySmall!.copyWith(
                      color: bodyColor,
                      height: 1.45,
                    ),
                  ),
                  if (action != null)
                    Padding(
                      padding: const EdgeInsets.only(top: NapSpace.s6),
                      child: action,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
