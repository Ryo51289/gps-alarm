import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/features/history/domain/history_logic.dart';
import 'package:napstop/features/history/presentation/history_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// One trip of screen 11 (T28 §3.4 block 3): icon, destination name, "Tàu ·
/// 26/10 · 498 km", result and "Giả lập" badges, and "Đặt lại" when
/// [onRestart] is set. No time of day is shown (D5: simulated trips store
/// virtual times). Screen readers get the info as one node and the restart
/// button on its own.
class HistoryTripTile extends StatelessWidget {
  const new({
    required this.record,
    required this.status,
    required this.now,
    this.onTap,
    this.onRestart,
    super.key,
  });

  final TripRecord record;

  /// Null: no result badge (running trip not known yet).
  final HistoryStatus? status;

  /// For the date format (current year or not).
  final DateTime now;

  /// The running trip opens screen 4; other rows are not tappable.
  final VoidCallback? onTap;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    final status = this.status;
    final onRestart = this.onRestart;
    final info = MergeSemantics(
      child: Semantics(
        button: onTap != null ? true : null,
        child: Row(
          spacing: NapSpace.s12,
          children: [
            NapIconTile(icon: historyIcon(record)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: NapSpace.s4,
                children: [
                  Text(
                    record.destination.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                  Text(
                    l.historyMetaLine(record, now),
                    style: text.bodySmall!.copyWith(color: c.textSecondary),
                  ),
                  if (status != null || record.simulated)
                    Wrap(
                      spacing: NapSpace.s6,
                      runSpacing: NapSpace.s4,
                      children: [
                        if (status != null)
                          NapBadge(
                            label: l.statusLabel(status, record.snoozeCount),
                            tone: historyTone(status),
                          ),
                        if (record.simulated)
                          NapBadge(label: l.historySimulatedBadge),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: NapSizes.listRowWithSubtitleMin,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: NapSpace.s16,
              vertical: NapSpace.s12,
            ),
            child: Row(
              spacing: NapSpace.s8,
              children: [
                Expanded(child: info),
                if (onRestart != null)
                  NapIconButton(
                    icon: NapIcons.redo,
                    semanticLabel: l.historyRestart,
                    onPressed: onRestart,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
