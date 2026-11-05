/// Texts of the Flutter alarm screen (T27 §4.2), the same keys and rules as
/// the native `RingCopy` / `SnoozeLabel` (T16 §9, T10 §10). Pure.
library;

import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/format/distance_format.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Minutes shown for an ETA (= `RingCopy.minutes`):
/// max(1, ceil(max(0, etaS) / 60)).
int alarmMinutes(int etaS) {
  final minutes = ((etaS < 0 ? 0 : etaS) / 60).ceil();
  return minutes < 1 ? 1 : minutes;
}

/// Reason line of screen 5 (= `RingCopy.reasonLine`). An empty
/// [destination] reads as `notifDestinationUnknown`.
String alarmReasonText(
  AppLocalizations l, {
  required AlarmReasonMsg? reason,
  required String destination,
  int? distanceM,
  int? etaS,
  int? batteryPct,
}) {
  final dest = destination.isEmpty ? l.notifDestinationUnknown : destination;
  final generic = l.notifAlarmTitle(dest);
  return switch (reason) {
    null => generic,
    AlarmReasonMsg.distance ||
    AlarmReasonMsg.smartDistance ||
    AlarmReasonMsg.smartSlowDistance =>
      distanceM == null
          ? generic
          : l.alarmReasonDistance(alarmDistance(l, distanceM), dest),
    AlarmReasonMsg.time || AlarmReasonMsg.smartTime =>
      etaS == null ? generic : l.alarmReasonTime('${alarmMinutes(etaS)}', dest),
    AlarmReasonMsg.gpsLost => l.alarmReasonGpsLost(dest),
    AlarmReasonMsg.lowBattery =>
      batteryPct == null ? generic : l.alarmReasonLowBattery('$batteryPct'),
    AlarmReasonMsg.passedClosest => l.alarmReasonPassedClosest(dest),
    AlarmReasonMsg.overshoot => l.alarmReasonOvershoot(dest),
    AlarmReasonMsg.snoozeEnd => l.alarmReasonSnoozeEnd(dest),
    AlarmReasonMsg.timeout => l.alarmReasonTimeout(dest),
    AlarmReasonMsg.fallback => l.alarmReasonFallback(dest),
    AlarmReasonMsg.fallbackMissed => l.alarmReasonFallbackMissed(dest),
  };
}

/// Overshoot line "Đã qua {distance}".
String alarmPastText(AppLocalizations l, int pastM) =>
    l.alarmOvershootPast(alarmDistance(l, pastM));

/// Distance of the alarm texts ("850 m", "1,2 km").
String alarmDistance(AppLocalizations l, int meters) =>
    formatDistanceShort(meters, l.localeName);

/// Snooze button (= `SnoozeLabel`): whole minutes → minutes, else seconds.
String snoozeLabel(AppLocalizations l, int snoozeS) =>
    snoozeS > 0 && snoozeS % 60 == 0
    ? l.alarmSnoozeMinutes('${snoozeS ~/ 60}')
    : l.alarmSnoozeSeconds('$snoozeS');
