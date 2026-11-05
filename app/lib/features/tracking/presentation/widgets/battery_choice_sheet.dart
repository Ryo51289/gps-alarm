import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/features/tracking/presentation/tracking_strings.dart';
import 'package:napstop/features/tracking/presentation/widgets/battery_level_bar.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Applies a screen 7 choice; true when it went through (the sheet closes).
typedef BatteryChoiceApply = Future<bool> Function(BatteryChoiceMsg choice);

/// Opens screen 7 (T26 §4.6) for [tripId].
Future<void> showBatteryChoiceSheet(
  BuildContext context, {
  required String tripId,
  required int? levelPct,
  required AlarmSettingsParams params,
  required LowBatteryRiskMsg? estimate,
  required BatteryChoiceApply onApply,
}) => showNapSheet<void>(
  context: context,
  builder: (context) => BatteryChoiceSheet(
    tripId: tripId,
    levelPct: levelPct,
    params: params,
    estimate: estimate,
    onApply: onApply,
  ),
);

/// Screen 7: how to handle a battery that may not last (T10 §4.9).
/// "Tiết kiệm tối đa" is preselected (Q2). Closes by itself once the trip
/// no longer needs a choice (chosen elsewhere, phase changed, ended).
class BatteryChoiceSheet extends ConsumerStatefulWidget {
  const new({
    required this.tripId,
    required this.levelPct,
    required this.params,
    required this.estimate,
    required this.onApply,
    super.key,
  });

  final String tripId;
  final int? levelPct;
  final AlarmSettingsParams params;

  /// The latest `LowBatteryRiskMsg` of the session, if any.
  final LowBatteryRiskMsg? estimate;
  final BatteryChoiceApply onApply;

  @override
  ConsumerState<BatteryChoiceSheet> createState() => _BatteryChoiceSheetState();
}

class _BatteryChoiceSheetState extends ConsumerState<BatteryChoiceSheet> {
  BatteryChoiceMsg _choice = BatteryChoiceMsg.maxSaving;
  bool _applying = false;
  bool _closed = false;

  /// The last apply failed: shown inside the sheet, a snack bar would sit
  /// under it (review T26 #1).
  bool _failed = false;

  void _close() {
    if (_closed || !mounted) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) {
      return;
    }
    _closed = true;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _apply() async {
    if (_applying) {
      return;
    }
    setState(() {
      _applying = true;
      _failed = false;
    });
    final ok = await widget.onApply(_choice);
    if (!mounted) {
      return;
    }
    if (ok) {
      _close();
    } else {
      setState(() {
        _applying = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(trackedTripProvider, (_, next) {
      final status = next.value;
      final stillWanted =
          status is TrackingActive &&
          status.trip.tripId == widget.tripId &&
          wantsBatterySheetOf(status.trip);
      if (!stillWanted && !next.isLoading) {
        _close();
      }
    });
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final p = widget.params;
    // The event follows the view that raised the risk (T10 §2.3): read it
    // live, the sheet may already be open.
    final live = ref.watch(trackedTripProvider).value;
    final trip = live is TrackingActive && live.trip.tripId == widget.tripId
        ? live.trip
        : null;
    final estimate = trip?.lowBattery ?? widget.estimate;
    // The level the engine reads at Apply (BatteryRule: level − 1), so the
    // promised "khi pin còn N%" follows the battery while the sheet is open
    // (test report T26 #2).
    final pct = trip?.state.batteryPct ?? widget.levelPct;
    NapOptionCard option(BatteryChoiceMsg choice, String title, String body) =>
        NapOptionCard(
          title: title,
          description: body,
          selected: _choice == choice,
          onTap: _applying ? null : () => setState(() => _choice = choice),
        );
    return NapSheetBody(
      leading: const NapIconTile(
        icon: NapIcons.batteryLow,
        tone: NapTone.danger,
        size: NapSizes.iconTileLarge,
      ),
      title: l.batterySheetTitle,
      subtitle: pct == null
          ? l.batterySheetSubtitleNoPct
          : l.batterySheetSubtitle(pct),
      primaryAction: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s10,
        children: [
          if (_failed)
            Semantics(
              liveRegion: true,
              child: Text(
                l.trackingActionFailed,
                textAlign: TextAlign.center,
                style: context.napText.bodyMedium!.copyWith(color: c.danger),
              ),
            ),
          NapButton(
            label: l.batterySheetApply,
            onPressed: _applying ? null : () => unawaited(_apply()),
          ),
          NapButton(
            label: l.commonLater,
            variant: NapButtonVariant.text,
            onPressed: _applying ? null : _close,
          ),
        ],
      ),
      children: [
        if (pct != null)
          BatteryLevelBar(levelPct: pct, alarmPct: p.lowBatteryAlarmPct),
        if (estimate != null)
          Text(
            l.batterySheetEstimate(
              _duration(l, estimate.availableMin),
              _duration(l, estimate.neededMin),
            ),
            style: context.napText.bodyMedium!.copyWith(color: c.textSecondary),
          ),
        option(
          BatteryChoiceMsg.maxSaving,
          l.batteryMaxSavingTitle,
          l.batteryMaxSavingBody,
        ),
        option(
          BatteryChoiceMsg.alarmAt5,
          l.batteryAt5Title(p.lowBatteryAlarmPct),
          l.batteryAt5Body(p.lowBatteryAlarmPct),
        ),
        option(
          BatteryChoiceMsg.alarmEarlier,
          l.batteryEarlierTitle(earlierAlarmPct(pct, p)),
          l.batteryEarlierBody,
        ),
      ],
    );
  }

  static String _duration(AppLocalizations l, int minutes) =>
      l.durationOf(minutes < 0 ? 0 : minutes);
}
