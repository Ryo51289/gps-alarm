import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';

/// Weight of a row title: semibold (default) or regular (settings screen).
enum NapRowTitle { semibold, regular }

/// Row with a title, optional subtitle and a Material 3 [Switch]
/// (spec T20 section 5.6). Tapping anywhere on the row toggles it; screen
/// readers get one merged node.
final class NapSwitchRow extends StatelessWidget {
  const new({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.titleWeight = NapRowTitle.semibold,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// Null disables the row.
  final ValueChanged<bool>? onChanged;
  final NapRowTitle titleWeight;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final onChanged = this.onChanged;
    final enabled = onChanged != null;
    final disabledColor = c.textPrimary.withValues(alpha: 0.38);
    final titleStyle = titleWeight == NapRowTitle.semibold
        ? text.titleSmall!
        : text.bodyMedium!;
    // Own transparent Material: the ripple stays visible when the row sits on
    // a colored container instead of a NapCard/NapListGroup.
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: NapSizes.switchRowMin),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: NapSpace.s16,
                vertical: NapSpace.s12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: NapSpace.s2,
                      children: [
                        Text(
                          title,
                          style: enabled
                              ? titleStyle
                              : titleStyle.copyWith(color: disabledColor),
                        ),
                        if (subtitle case final subtitle?)
                          Text(
                            subtitle,
                            style: text.bodySmall!.copyWith(
                              color: enabled ? c.textSecondary : disabledColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: NapSpace.s12),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
