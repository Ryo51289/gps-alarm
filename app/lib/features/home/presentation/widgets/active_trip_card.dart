import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Shown on screen 1 while a trip runs; "Mở" opens screen 4.
class ActiveTripCard extends StatelessWidget {
  const new({required this.destinationName, required this.onOpen, super.key});

  final String destinationName;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NapCard(
      variant: NapCardVariant.accent,
      child: Row(
        spacing: NapSpace.s12,
        children: [
          const NapIconTile(
            icon: NapIcons.gps,
            tone: NapTone.accent,
            onFill: true,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: NapSpace.s2,
              children: [
                Text(l.homeActiveTripTitle, style: context.napText.titleSmall),
                Text(
                  destinationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.napText.bodyMedium,
                ),
              ],
            ),
          ),
          NapButton(
            label: l.homeActiveTripOpen,
            onPressed: onOpen,
            size: NapButtonSize.small,
          ),
        ],
      ),
    );
  }
}
