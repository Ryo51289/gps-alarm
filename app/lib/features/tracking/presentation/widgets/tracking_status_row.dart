import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';
import 'package:napstop/features/tracking/domain/tracking_view.dart';
import 'package:napstop/features/tracking/presentation/tracking_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// `NapTone` of a [TileTone].
NapTone napToneOf(TileTone tone) => switch (tone) {
  TileTone.neutral => NapTone.neutral,
  TileTone.success => NapTone.success,
  TileTone.warning => NapTone.warning,
  TileTone.danger => NapTone.danger,
};

/// GPS, battery and headphones tiles (T26 §4.3). One row; stacked from a
/// text scale of 1.5 so nothing overflows.
class TrackingStatusRow extends StatelessWidget {
  const new({required this.view, super.key});

  final TrackingView view;

  /// From this text scale the tiles are stacked.
  static const double stackFromScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final v = view;
    final accuracy = v.gpsAccuracy;
    final gps = NapStatusTile(
      icon: switch (v.gps) {
        GpsTile.noPermission ||
        GpsTile.servicesOff ||
        GpsTile.lost => NapIcons.gpsOff,
        GpsTile.good || GpsTile.searching => NapIcons.gps,
      },
      tone: napToneOf(v.gpsTone),
      title: switch (v.gps) {
        GpsTile.noPermission => l.trackingGpsNoPermission,
        GpsTile.servicesOff => l.trackingGpsOff,
        GpsTile.good => l.trackingGpsGood,
        GpsTile.lost => l.trackingGpsLost,
        GpsTile.searching => l.trackingGpsSearching,
      },
      subtitle: switch (v.gps) {
        GpsTile.good when accuracy != null => l.trackingGpsAccuracy(
          l.distanceOf(accuracy),
        ),
        GpsTile.lost => l.trackingGpsEstimatingShort,
        _ => null,
      },
    );
    final pct = v.batteryPct;
    final note = l.batteryNoteOf(v);
    final battery = NapStatusTile(
      icon:
          v.batteryNote == BatteryTileNote.risk ||
              v.batteryNote == BatteryTileNote.low
          ? NapIcons.batteryLow
          : NapIcons.battery,
      tone: napToneOf(v.batteryTone),
      title: pct == null ? l.trackingBattery : l.trackingBatteryPct(pct),
      subtitle: note.isEmpty ? null : note,
    );
    final headphones = v.headphones == HeadphonesTile.unknownShowStyle
        ? NapStatusTile(
            icon: switch (v.style) {
              AlarmStyleKind.ring => NapIcons.alarm,
              AlarmStyleKind.vibrateOnly => NapIcons.vibrate,
              AlarmStyleKind.headphonesOnly => NapIcons.headphones,
            },
            tone: napToneOf(v.headphonesTone),
            title: l.trackingAlarmStyle,
            subtitle: l.styleLabelOf(v.style),
          )
        : NapStatusTile(
            icon: NapIcons.headphones,
            tone: napToneOf(v.headphonesTone),
            title: l.trackingHeadphones,
            subtitle: switch (v.headphones) {
              HeadphonesTile.connected ||
              HeadphonesTile.connectedPreferred => l.trackingHeadphonesOn,
              HeadphonesTile.notConnectedSpeaker => l.trackingHeadphonesSpeaker,
              HeadphonesTile.notConnected ||
              HeadphonesTile.unknownShowStyle => l.trackingHeadphonesOff,
            },
          );
    final tiles = [gps, battery, headphones];
    if (MediaQuery.textScalerOf(context).scale(1) >= stackFromScale) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s8,
        children: tiles,
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s8,
        children: [for (final t in tiles) Expanded(child: t)],
      ),
    );
  }
}
