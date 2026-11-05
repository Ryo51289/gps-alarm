import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/features/tracking/presentation/tracking_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// The large block of screen 4 by phase (T26 §4.1, §5 block 2).
class TrackingHeadline extends StatelessWidget {
  const new({required this.view, required this.destination, super.key});

  final TrackingView view;

  /// `config.destinationName`.
  final String destination;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final text = context.napText;
    final eta = view.etaMinutes;
    return switch (view.headline) {
      // A static icon, not a spinner: the screen may stay on for minutes
      // and an endless animation redraws every frame (PRD §5).
      HeadlineAcquiring() => Row(
        spacing: NapSpace.s10,
        children: [
          Icon(NapIcons.gps, size: NapSizes.icon, color: c.accent),
          Expanded(child: Text(l.trackingAcquiring, style: text.titleLarge)),
        ],
      ),
      HeadlineDistance(:final distance, :final estimated) => NapBigValue(
        leading: l.trackingDistanceLeading,
        value: l.maybeApprox(l.distanceOf(distance), estimated: estimated),
        trailing: eta == null ? null : l.trackingApprox(l.durationOf(eta)),
        estimated: estimated,
      ),
      HeadlineAlarm(
        :final copy,
        :final ringing,
        :final remaining,
        :final estimated,
      ) =>
        _StateCard(
          icon: NapIcons.alarm,
          tone: NapTone.warning,
          title: ringing ? l.trackingAlarmRinging : l.trackingAlarmSilenced,
          hint: ringing ? l.trackingAlarmRingingHint : null,
          body: l.alarmCopyText(copy, destination),
          extra: remaining == null
              ? null
              : NapBigValue(
                  size: NapBigValueSize.l,
                  leading: l.trackingDistanceLeading,
                  value: l.maybeApprox(
                    l.distanceOf(remaining),
                    estimated: estimated,
                  ),
                  estimated: estimated,
                ),
        ),
      HeadlineSnoozed(:final remainingMs) => _StateCard(
        icon: NapIcons.snooze,
        tone: NapTone.warning,
        title: l.trackingSnoozedTitle,
        extra: remainingMs == null
            ? null
            : Semantics(
                liveRegion: false,
                label: l.trackingSnoozeInA11y(countdownSeconds(remainingMs)),
                child: ExcludeSemantics(
                  child: Text(
                    l.trackingSnoozeIn(formatCountdown(remainingMs)),
                    style: text.headlineSmall!.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
      ),
      HeadlineOvershoot(:final past, :final ringing) => _StateCard(
        icon: NapIcons.warning,
        tone: NapTone.danger,
        overline: l.alarmOverlineOvershoot,
        title: past == null
            ? l.alarmOverlineOvershoot
            : l.alarmOvershootPast(l.distanceOf(past)),
        hint: ringing ? l.trackingAlarmRingingHint : null,
        body: ringing ? l.trackingAlarmRinging : l.trackingAlarmSilenced,
      ),
    };
  }
}

/// Filled card with a 56 icon tile: ALARMING, SNOOZED, OVERSHOT.
class _StateCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.tone,
    required this.title,
    this.overline,
    this.hint,
    this.body,
    this.extra,
  });

  final IconData icon;
  final NapTone tone;
  final String? overline;
  final String title;
  final String? hint;
  final String? body;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final overline = this.overline;
    final hint = this.hint;
    final body = this.body;
    return NapCard(
      variant: NapCardVariant.filled,
      radius: NapRadii.r16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NapSpace.s14,
        children: [
          NapIconTile(icon: icon, tone: tone, size: NapSizes.iconTileLarge),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: NapSpace.s4,
              children: [
                if (overline != null && overline != title)
                  Text(
                    overline,
                    style: context
                        .napStyle(NapTypography.overline)
                        .copyWith(color: c.textSecondary),
                  ),
                Text(title, style: text.titleLarge),
                if (hint != null)
                  Text(
                    hint,
                    style: text.bodyMedium!.copyWith(color: c.textSecondary),
                  ),
                if (body != null) Text(body, style: text.bodyMedium),
                ?extra,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lines under the headline (§5 block 3).
class TrackingInfoLines extends StatelessWidget {
  const new({
    required this.view,
    required this.config,
    required this.formatTime,
    super.key,
  });

  final TrackingView view;
  final TripConfigMsg config;

  /// Wall clock of an epoch ms ("05:40").
  final String Function(int ms) formatTime;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final style = context.napText.bodyMedium!.copyWith(color: c.textSecondary);
    final v = view;
    final arrival = v.arrivalAtMs;
    final speed = v.speedKmh;
    final alarmAt = v.alarmAtMs;
    final alarmIn = v.alarmInMinutes;
    final error = v.errorDistance;
    final stale = v.staleMinutes;
    final first = [
      if (arrival != null) l.trackingArrivalAt(formatTime(arrival)),
      if (speed != null) l.trackingSpeed(speed),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: NapSpace.s4,
      children: [
        if (first.isNotEmpty)
          Wrap(
            spacing: NapSpace.s6,
            children: [
              for (final (i, part) in first.indexed) ...[
                if (i > 0) ExcludeSemantics(child: Text('·', style: style)),
                Text(part, style: style),
              ],
            ],
          ),
        if (error != null)
          Text(l.trackingEstimating(l.distanceOf(error)), style: style),
        if (alarmAt != null)
          Text(l.trackingAlarmAt(formatTime(alarmAt)), style: style),
        if (alarmIn != null)
          Text(
            l.trackingAlarmIn(l.trackingApprox(l.durationOf(alarmIn))),
            style: style,
          ),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${l.alarmSettingsSummaryPrefix} '),
              TextSpan(
                text: l.ruleValue(config, v.params),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          style: style,
        ),
        if (stale != null)
          Text(
            l.trackingUpdatedAgo(stale),
            style: context.napText.bodyMedium!.copyWith(color: c.warning),
          ),
      ],
    );
  }
}
