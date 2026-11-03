import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/features/alarm_settings/presentation/widgets/equal_chip_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Parameters of the selected mode (T25 §3.1).
class ModePanel extends StatelessWidget {
  const new({
    required this.settings,
    required this.params,
    required this.shortDistance,
    required this.onDistanceChanged,
    required this.onTimeChanged,
    super.key,
  });

  final TripSettings settings;
  final AlarmSettingsParams params;

  /// The "khoảng cách quá ngắn" warning, distance mode only.
  final ShortDistanceInfo? shortDistance;
  final ValueChanged<int> onDistanceChanged;
  final ValueChanged<int> onTimeChanged;

  @override
  Widget build(BuildContext context) {
    return NapCard(
      radius: NapRadii.r16,
      padding: const EdgeInsets.symmetric(
        horizontal: NapSpace.s16,
        vertical: NapSpace.s20,
      ),
      child: switch (settings.mode) {
        AlarmModeMsg.distance => _DistancePanel(
          thresholdM: settings.distanceThresholdM,
          shortDistance: shortDistance,
          onChanged: onDistanceChanged,
        ),
        AlarmModeMsg.time => _TimePanel(
          thresholdMin: settings.timeThresholdMin,
          onChanged: onTimeChanged,
        ),
        AlarmModeMsg.smart => _SmartPanel(
          minutes: minutesOf(params.smartTargetS),
        ),
      },
    );
  }
}

class _DistancePanel extends StatelessWidget {
  const new({
    required this.thresholdM,
    required this.shortDistance,
    required this.onChanged,
  });

  final int thresholdM;
  final ShortDistanceInfo? shortDistance;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final warning = shortDistance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NapBigValue(
          value: l.distance(thresholdM),
          leading: l.alarmSettingsDistanceLeading,
          size: NapBigValueSize.l,
          alignment: WrapAlignment.center,
        ),
        const SizedBox(height: NapSpace.s12),
        NapLabeledSlider(
          value: thresholdM.toDouble(),
          min: kMinDistanceThresholdM.toDouble(),
          max: kMaxDistanceThresholdM.toDouble(),
          divisions:
              (kMaxDistanceThresholdM - kMinDistanceThresholdM) ~/
              kDistanceStepM,
          onChanged: (v) {
            final m = normalizeDistanceM(v.round());
            if (m != thresholdM) {
              onChanged(m);
            }
          },
          semanticLabel: l.alarmSettingsDistanceSliderLabel,
          semanticFormatter: (v) => l.distance(normalizeDistanceM(v.round())),
          minLabel: l.distance(kMinDistanceThresholdM),
          maxLabel: l.distance(kMaxDistanceThresholdM),
        ),
        const SizedBox(height: NapSpace.s12),
        EqualChipRow(
          labels: [for (final m in kDistanceChipsM) l.distance(m)],
          chipBuilder: (i) => NapChip(
            label: l.distance(kDistanceChipsM[i]),
            selected: kDistanceChipsM[i] == thresholdM,
            onTap: () => onChanged(kDistanceChipsM[i]),
          ),
        ),
        if (warning != null) ...[
          const SizedBox(height: NapSpace.s16),
          NapBanner(
            tone: NapTone.warning,
            announce: true,
            message: l.shortDistanceWarning(warning),
          ),
        ],
      ],
    );
  }
}

class _TimePanel extends StatelessWidget {
  const new({required this.thresholdMin, required this.onChanged});

  final int thresholdMin;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NapBigValue(
          value: l.commonMinutes(thresholdMin),
          leading: l.alarmSettingsTimeLeading,
          size: NapBigValueSize.l,
          alignment: WrapAlignment.center,
        ),
        const SizedBox(height: NapSpace.s16),
        EqualChipRow(
          // The number is data, not a string (T25 §6).
          labels: [for (final t in kTimeChipsMin) '$t'],
          chipBuilder: (i) => NapChip(
            label: '${kTimeChipsMin[i]}',
            semanticLabel: l.commonMinutes(kTimeChipsMin[i]),
            selected: kTimeChipsMin[i] == thresholdMin,
            onTap: () => onChanged(kTimeChipsMin[i]),
          ),
        ),
        const SizedBox(height: NapSpace.s12),
        Text(
          l.alarmSettingsTimeHint,
          textAlign: TextAlign.center,
          style: context.napText.bodySmall!.copyWith(
            color: context.napColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SmartPanel extends StatelessWidget {
  const new({required this.minutes});

  final int minutes;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = context.napText;
    return Column(
      spacing: NapSpace.s10,
      children: [
        const NapIconTile(
          icon: NapIcons.smart,
          tone: NapTone.accent,
          size: NapSizes.iconTileLarge,
        ),
        Text(
          l.alarmSettingsSmartTitle,
          textAlign: TextAlign.center,
          style: text.titleMedium,
        ),
        Text(
          l.alarmSettingsSmartBody(minutes),
          textAlign: TextAlign.center,
          style: text.bodyMedium!.copyWith(
            color: context.napColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
