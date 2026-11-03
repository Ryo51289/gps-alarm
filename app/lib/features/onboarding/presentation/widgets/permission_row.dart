import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/features/onboarding/presentation/onboarding_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Text scale from which the row button moves under the texts (T21 §7.1).
const double kOnboardingStackedTextScale = 1.5;

/// One permission row of screen 0 (T21 §7.1, §7.2).
class PermissionRow extends StatelessWidget {
  const new({required this.item, required this.onAction, super.key});

  final OnboardingItem item;

  /// Null disables the button (another action is running).
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    final texts = l.onboardingRow(item);
    final stacked =
        MediaQuery.textScalerOf(context).scale(16) >
        16 * (kOnboardingStackedTextScale - 0.01);
    final subtitleColor = item.blocking && !item.isDone
        ? c.danger
        : c.textSecondary;
    final labels = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: NapSpace.s2,
      children: [
        Text(texts.title, style: text.titleSmall),
        Text(
          texts.subtitle,
          style: text.bodySmall!.copyWith(color: subtitleColor),
        ),
      ],
    );
    final action = texts.action;
    final Widget trailing;
    if (item.isDone || action == null) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: NapSpace.s4,
        children: [
          Icon(NapIcons.check, color: c.success, size: NapSizes.icon),
          Text(
            l.onboardingStatusOn,
            style: text.labelMedium!.copyWith(color: c.success),
          ),
        ],
      );
    } else {
      final primary = item.request != null && item.settings == null;
      trailing = Semantics(
        label: l.onboardingActionFor(action, texts.title),
        excludeSemantics: true,
        button: true,
        enabled: onAction != null,
        onTap: onAction,
        child: NapButton(
          label: action,
          onPressed: onAction,
          size: NapButtonSize.small,
          variant: primary
              ? NapButtonVariant.primary
              : NapButtonVariant.secondary,
        ),
      );
    }

    final Widget body;
    if (stacked) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NapSpace.s12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: NapSpace.s12,
            children: [
              NapIconTile(icon: texts.icon),
              Expanded(child: labels),
            ],
          ),
          trailing,
        ],
      );
    } else {
      body = Row(
        spacing: NapSpace.s12,
        children: [
          NapIconTile(icon: texts.icon),
          Expanded(child: labels),
          trailing,
        ],
      );
    }
    final card = NapCard(
      padding: const EdgeInsets.all(NapSpace.s14),
      child: body,
    );
    return item.isDone ? MergeSemantics(child: card) : card;
  }
}
