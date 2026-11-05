import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/history/domain/history_logic.dart';
import 'package:napstop/features/history/presentation/history_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Tháng này" card of screen 11 (T28 §3.4 block 1): trips, km, woke on time.
/// Three equal columns; stacked rows at large text or on narrow screens.
/// Screen readers get one sentence ([AppLocalizations.historyStatsSemantics]).
class HistoryStatsCard extends StatelessWidget {
  const new({required this.stats, required this.month, super.key});

  final HistoryStats stats;

  /// Any time in the current month (only the month name is shown).
  final DateTime month;

  /// Text scale or width at which the columns become rows.
  static const double stackedTextScale = 1.75;
  static const double stackedMaxWidth = 340;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final km = l.statsKm(stats);
    final ratio = l.statsRatio(stats);
    final items = [
      (value: '${stats.tripCount}', label: l.statsTrips(month)),
      (value: km, label: l.historyStatsKm),
      (value: ratio, label: l.historyStatsOnTime),
    ];
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      container: true,
      label: l.statsSemantics(stats, month),
      child: ExcludeSemantics(
        child: NapCard(
          radius: NapRadii.r16,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  scale >= stackedTextScale ||
                  constraints.maxWidth < stackedMaxWidth;
              final cells = [
                for (final i in items)
                  _StatCell(value: i.value, label: i.label, inline: stacked),
              ];
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: NapSpace.s10,
                  children: cells,
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: NapSpace.s12,
                children: [for (final c in cells) Expanded(child: c)],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const new({required this.value, required this.label, required this.inline});

  final String value;
  final String label;

  /// Value and label on one line (stacked layout).
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final valueText = Text(value, style: context.napText.headlineSmall);
    final labelText = Text(
      label,
      style: context.napText.bodySmall!.copyWith(
        color: context.napColors.textSecondary,
      ),
    );
    if (inline) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: NapSpace.s8,
        children: [
          valueText,
          Expanded(child: labelText),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: NapSpace.s2,
      children: [valueText, labelText],
    );
  }
}
