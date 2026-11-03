import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/battery_guide/domain/background_check.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// After the last step: invitation to the 30 second check (T21 §8.1).
class CheckIntro extends StatelessWidget {
  const new({required this.steps, super.key});

  final int steps;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NapSpace.s16,
      children: [
        ExcludeSemantics(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: c.successContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(NapIcons.check, size: 36, color: c.success),
            ),
          ),
        ),
        Semantics(
          header: true,
          child: Text(l.batteryGuideAllDone(steps), style: text.titleLarge),
        ),
        Text(
          l.batteryGuideTestIntro,
          style: text.bodyMedium!.copyWith(color: c.textSecondary),
        ),
        NapCard(
          variant: NapCardVariant.filled,
          child: Row(
            spacing: NapSpace.s12,
            children: [
              const NapIconTile(icon: NapIcons.timer, onFill: true),
              Expanded(
                child: Text(l.batteryGuideTestRow, style: text.titleSmall),
              ),
              Text(
                formatCountdown(kBackgroundCheckDelay),
                style: text.titleSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// While the check runs: countdown (display only, not a live region).
class CheckRunning extends StatelessWidget {
  const new({required this.remaining, super.key});

  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NapSpace.s16,
      children: [
        ExcludeSemantics(child: NapBigValue(value: formatCountdown(remaining))),
        Text(
          l.batteryGuideTestRunning,
          style: context.napText.bodyMedium!.copyWith(color: c.textSecondary),
        ),
      ],
    );
  }
}

/// Result banner, read out when it appears.
class CheckResultBanner extends StatelessWidget {
  const new({required this.result, super.key});

  final BackgroundCheckResult result;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (tone, title, message) = switch (result.verdict) {
      BackgroundCheckVerdict.passed => (
        NapTone.success,
        l.batteryGuideTestPassed,
        l.batteryGuideTestPassedNote,
      ),
      BackgroundCheckVerdict.passedScreenOn => (
        NapTone.neutral,
        null,
        l.batteryGuideTestScreenOn,
      ),
      BackgroundCheckVerdict.late => (
        NapTone.warning,
        null,
        l.batteryGuideTestLate(result.lateBy?.inSeconds ?? 0),
      ),
      BackgroundCheckVerdict.missed || BackgroundCheckVerdict.running => (
        NapTone.danger,
        null,
        l.batteryGuideTestFailed,
      ),
    };
    return NapBanner(
      tone: tone,
      title: title,
      message: message,
      announce: true,
    );
  }
}
