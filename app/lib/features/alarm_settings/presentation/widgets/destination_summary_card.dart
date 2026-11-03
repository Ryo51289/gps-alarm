import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

IconData _iconOf(DestinationKind kind) => switch (kind) {
  DestinationKind.train => NapIcons.train,
  DestinationKind.coach => NapIcons.coach,
  DestinationKind.bus => NapIcons.bus,
  DestinationKind.address || DestinationKind.pin => NapIcons.place,
};

/// Destination at the top of screen 3, with "Đổi" (T25 §3 block 2).
class DestinationSummaryCard extends StatelessWidget {
  const new({required this.destination, required this.onChange, super.key});

  final TripDestination destination;

  /// Null while starting.
  final VoidCallback? onChange;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = context.napText;
    final subtitle = destinationSubtitle(
      l,
      destination.kind,
      destination.detail,
    );
    return NapCard(
      variant: NapCardVariant.filled,
      padding: const EdgeInsets.fromLTRB(
        NapSpace.s14,
        NapSpace.s12,
        NapSpace.s4,
        NapSpace.s12,
      ),
      child: Row(
        children: [
          NapIconTile(icon: _iconOf(destination.kind), onFill: true),
          const SizedBox(width: NapSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: NapSpace.s2,
              children: [
                Text(
                  destination.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: text.bodySmall!.copyWith(
                      color: context.napColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Semantics(
            button: true,
            enabled: onChange != null,
            label: l.alarmSettingsChangeDestinationLabel,
            onTap: onChange,
            excludeSemantics: true,
            child: NapButton(
              label: l.alarmSettingsChangeDestination,
              onPressed: onChange,
              variant: NapButtonVariant.link,
              size: NapButtonSize.compact,
            ),
          ),
        ],
      ),
    );
  }
}
