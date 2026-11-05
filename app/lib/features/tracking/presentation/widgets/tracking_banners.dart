import 'package:flutter/material.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/features/tracking/presentation/tracking_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// The warning banners of screen 4 (T26 §4.4), in [TrackingView.banners]
/// order.
class TrackingBanners extends StatelessWidget {
  const new({
    required this.view,
    required this.onOpenSettings,
    required this.onChooseBattery,
    super.key,
  });

  final TrackingView view;
  final ValueChanged<SettingsTargetMsg> onOpenSettings;
  final VoidCallback onChooseBattery;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = view;
    Widget button(String label, VoidCallback onPressed) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: NapButton(
        label: label,
        onPressed: onPressed,
        variant: NapButtonVariant.secondary,
        size: NapButtonSize.small,
      ),
    );
    NapBanner banner(TrackingBanner b) {
      final pct = v.batteryPct;
      final error = v.errorDistance;
      final minutes = v.params.gpsLostAlarmEtaS ~/ 60;
      return switch (b) {
        TrackingBanner.locationPermission => NapBanner(
          tone: NapTone.danger,
          announce: true,
          title: l.gpsPermissionRevoked,
          message: l.trackingBackupStillRings,
          action: button(
            l.trackingOpenSettings,
            () => onOpenSettings(SettingsTargetMsg.appDetails),
          ),
        ),
        TrackingBanner.locationServices => NapBanner(
          tone: NapTone.danger,
          announce: true,
          title: l.gpsServicesOff,
          message: l.trackingBackupStillRings,
          action: button(
            l.trackingTurnOnLocation,
            () => onOpenSettings(SettingsTargetMsg.locationServices),
          ),
        ),
        TrackingBanner.fallbackFailed => NapBanner(
          tone: NapTone.danger,
          announce: true,
          message: l.fallbackScheduleFailed,
          action: button(
            l.trackingOpenSettings,
            () => onOpenSettings(SettingsTargetMsg.exactAlarm),
          ),
        ),
        TrackingBanner.noGps => NapBanner(
          tone: NapTone.warning,
          announce: true,
          title: l.gpsNotAcquired,
          message: l.trackingNoGpsBody,
        ),
        TrackingBanner.gpsLost => NapBanner(
          tone: NapTone.warning,
          announce: true,
          title: l.trackingGpsLostTitle,
          message: error == null
              ? l.trackingGpsLostBodyNoError(minutes)
              : l.trackingGpsLostBody(l.distanceOf(error), minutes),
        ),
        TrackingBanner.batteryRisk => NapBanner(
          tone: NapTone.warning,
          title: l.batterySheetTitle,
          message: pct == null
              ? l.batterySheetSubtitleNoPct
              : l.batterySheetSubtitle(pct),
          action: button(l.trackingBatteryChoose, onChooseBattery),
        ),
        TrackingBanner.batteryLow => NapBanner(
          tone: NapTone.warning,
          title: l.alarmSettingsBatteryLowTitle(pct ?? 0),
          message: l.alarmSettingsBatteryLowBody,
        ),
      };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NapSpace.s12,
      children: [for (final b in v.banners) banner(b)],
    );
  }
}
