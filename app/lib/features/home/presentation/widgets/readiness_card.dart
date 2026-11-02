import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/home/domain/readiness.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Tone of a chip by severity (T22 §8.3).
NapTone readinessTone(ReadinessSeverity severity) => switch (severity) {
  ReadinessSeverity.ok || ReadinessSeverity.guide => NapTone.neutral,
  ReadinessSeverity.caution => NapTone.warning,
  ReadinessSeverity.warning || ReadinessSeverity.blocking => NapTone.danger,
};

/// The "Sẵn sàng" card (T22 §9.4).
class ReadinessCard extends StatelessWidget {
  const new({
    required this.readiness,
    required this.onRetry,
    required this.onOpenPermissions,
    required this.onOpenBatteryGuide,
    super.key,
  });

  final AsyncValue<Readiness> readiness;
  final VoidCallback onRetry;
  final VoidCallback onOpenPermissions;
  final VoidCallback onOpenBatteryGuide;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    // Refreshes (resume, retry) keep showing the previous result.
    final (variant, content) = readiness.when<(NapCardVariant, Widget)>(
      data: (value) {
        final (cardVariant, icon, color, title) = switch (value.level) {
          ReadinessLevel.ready => (
            NapCardVariant.accent,
            NapIcons.check,
            c.success,
            l.homeReadyTitle,
          ),
          ReadinessLevel.check => (
            NapCardVariant.warning,
            NapIcons.warning,
            c.warning,
            l.homeReadyCheckTitle,
          ),
          ReadinessLevel.blocked => (
            NapCardVariant.warning,
            NapIcons.error,
            c.danger,
            l.homeReadyBlockedTitle,
          ),
        };
        final action = switch (value.action) {
          ReadinessAction.none => null,
          ReadinessAction.openPermissions => NapButton(
            label: l.homeReadyFixPermissions,
            onPressed: onOpenPermissions,
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.small,
          ),
          ReadinessAction.openBatteryGuide => NapButton(
            label: l.homeReadyOpenBatteryGuide,
            onPressed: onOpenBatteryGuide,
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.small,
          ),
        };
        return (
          cardVariant,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: NapSpace.s12,
            children: [
              _Title(icon: icon, color: color, text: title),
              Wrap(
                spacing: NapSpace.s8,
                runSpacing: NapSpace.s8,
                children: [
                  for (final chip in value.chips)
                    // Own node: screen readers read chips one by one (§9.4).
                    Semantics(
                      container: true,
                      child: NapBadge(
                        label: l.readinessChip(chip),
                        tone: readinessTone(chip.severity),
                        size: NapBadgeSize.medium,
                      ),
                    ),
                ],
              ),
              if (value.showSleepModeHint)
                // Own node, so it is read after the chips, not as the label
                // of the card container (which would be read first).
                Semantics(
                  container: true,
                  child: Text(
                    l.homeReadySleepModeHint,
                    style: context.napText.bodySmall!.copyWith(
                      color: c.textSecondary,
                    ),
                  ),
                ),
              ?action,
            ],
          ),
        );
      },
      error: (_, _) => (
        NapCardVariant.filled,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: NapSpace.s12,
          children: [
            _Title(
              icon: NapIcons.info,
              color: c.textSecondary,
              text: l.homeReadyError,
            ),
            NapButton(
              label: l.commonRetry,
              onPressed: onRetry,
              variant: NapButtonVariant.secondary,
              size: NapButtonSize.small,
            ),
          ],
        ),
      ),
      loading: () => (NapCardVariant.accent, _Title(text: l.homeReadyLoading)),
    );
    return Semantics(
      container: true,
      child: NapCard(variant: variant, child: content),
    );
  }
}

class _Title extends StatelessWidget {
  const new({required this.text, this.icon, this.color});

  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Row(
      spacing: NapSpace.s8,
      children: [
        if (icon != null)
          ExcludeSemantics(
            child: Icon(icon, size: NapSizes.iconLarge, color: color),
          ),
        Expanded(
          // container: the header flag stays on the title instead of
          // turning the whole card into one heading (test report T22 B1).
          child: Semantics(
            header: true,
            container: true,
            child: Text(text, style: context.napText.titleSmall),
          ),
        ),
      ],
    );
  }
}
