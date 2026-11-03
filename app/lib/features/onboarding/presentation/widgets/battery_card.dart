import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Battery optimization card of screen 0 (Android, T21 §7.1).
class BatteryCard extends StatelessWidget {
  const new({required this.model, required this.onOpenGuide, super.key});

  final BatteryCardModel model;

  /// Null disables the button.
  final VoidCallback? onOpenGuide;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    final warning = model.tone == BatteryCardTone.warning;
    final key = model.brandKey;
    final brand = key == null ? null : batteryGuideText(l, key);
    return NapCard(
      variant: warning ? NapCardVariant.warning : NapCardVariant.outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s12,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: NapSpace.s12,
            children: [
              NapIconTile(icon: NapIcons.battery, onFill: warning),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: NapSpace.s2,
                  children: [
                    Text(l.permBatteryTitle, style: text.titleSmall),
                    Text(
                      brand == null
                          ? l.permBatteryBody
                          : l.permBatteryOemSubtitle(brand),
                      style: text.bodySmall!.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          NapButton(
            label: brand == null
                ? l.permBatteryGuideButtonGeneric
                : l.permBatteryGuideButton(brand, model.stepCount),
            onPressed: onOpenGuide,
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.medium,
            expand: true,
          ),
        ],
      ),
    );
  }
}
