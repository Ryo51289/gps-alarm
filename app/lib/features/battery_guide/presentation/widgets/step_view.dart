import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// One bar per step: done in `success`, current in `accent`, others `fill`.
/// [current] == steps means every step is done. Decorative: the step label
/// carries the semantics.
class StepProgress extends StatelessWidget {
  const new({required this.steps, required this.current, super.key});

  final int steps;
  final int current;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return ExcludeSemantics(
      child: Row(
        spacing: NapSpace.s6,
        children: [
          for (var i = 0; i < steps; i++)
            Expanded(
              child: Container(
                key: ValueKey('step-bar-$i'),
                height: 6,
                decoration: BoxDecoration(
                  color: i < current
                      ? c.success
                      : i == current
                      ? c.accent
                      : c.fill,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Texts of step [index] of [guide] (T21 §8.1 phase "step").
class StepContent extends StatelessWidget {
  const new({required this.guide, required this.index, super.key});

  final BatteryGuide guide;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    final step = guide.steps[index];
    final n = guide.steps.length;
    String t(String key) => batteryGuideText(l, key) ?? '';
    final highlight = t(step.highlightKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NapSpace.s12,
      children: [
        Semantics(
          label: l.batteryGuideStepSemantics(index + 1, n),
          excludeSemantics: true,
          child: Text(
            l.batteryGuideStepLabel(index + 1, n),
            style: text.labelMedium!.copyWith(color: c.accent),
          ),
        ),
        Semantics(
          header: true,
          child: Text(t(step.titleKey), style: text.titleLarge),
        ),
        Text(
          t(step.pathKey),
          style: text.bodyMedium!.copyWith(color: c.textSecondary),
        ),
        _HighlightMock(highlight: highlight),
        Text(
          l.batteryGuideNamesMayDiffer,
          style: context
              .napStyle(NapTypography.caption)
              .copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// Stands in for a settings screenshot (none yet, S1): two faded rows and
/// the row to choose, outlined in `accent`.
class _HighlightMock extends StatelessWidget {
  const new({required this.highlight});

  final String highlight;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    Widget faded(double widthFactor) => ExcludeSemantics(
      child: FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: widthFactor,
        child: Container(
          height: 12,
          decoration: BoxDecoration(
            color: c.border,
            borderRadius: BorderRadius.circular(NapRadii.r6),
          ),
        ),
      ),
    );
    return NapCard(
      variant: NapCardVariant.filled,
      radius: NapRadii.r16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s12,
        children: [
          faded(0.7),
          faded(0.5),
          Semantics(
            label: l.batteryGuideHighlightSemantics(highlight),
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: NapSpace.s12,
                vertical: NapSpace.s10,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.accent, width: 2),
                borderRadius: BorderRadius.circular(NapRadii.r10),
              ),
              child: Row(
                spacing: NapSpace.s8,
                children: [
                  Expanded(child: Text(highlight, style: text.titleSmall)),
                  Icon(NapIcons.check, color: c.accent, size: NapSizes.icon),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
