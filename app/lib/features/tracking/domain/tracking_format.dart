/// Pure formatting of screen 4 (T26 §3.3). Numbers only: the widgets add the
/// units through ARB.
library;

import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';

/// A distance number and its unit (metres or kilometres).
@immutable
final class FormattedDistance {
  const new(this.value, {required this.isKm});

  /// Already formatted for the locale, without the unit.
  final String value;
  final bool isKm;

  @override
  bool operator ==(Object other) =>
      other is FormattedDistance && other.value == value && other.isKm == isKm;

  @override
  int get hashCode => Object.hash(value, isKm);

  @override
  String toString() => 'FormattedDistance(<value>, km: $isKm)';
}

/// Below 1000 m: rounded to 10 m ("850"; 995 → 1000 → "1" km).
/// 1000-99 999 m: km with one decimal, ",0" dropped ("12,3" / "12.3"; "12").
/// From 100 000 m: whole km with the locale grouping ("152", "1.726" /
/// "1,726"). Every step rounds half up, in integers. Negative counts as 0.
FormattedDistance formatTripDistance(int meters, String locale) {
  final m = math.max(0, meters);
  final tens = (m + 5) ~/ 10;
  if (tens < 100) {
    return FormattedDistance('${tens * 10}', isKm: false);
  }
  final tenths = (m + 50) ~/ 100;
  if (tenths < 1000) {
    final whole = tenths ~/ 10;
    final decimal = tenths % 10;
    if (decimal == 0) {
      return FormattedDistance('$whole', isKm: true);
    }
    final separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
    return FormattedDistance('$whole$separator$decimal', isKm: true);
  }
  final km = (m + 500) ~/ 1000;
  return FormattedDistance(
    NumberFormat('#,##0', locale).format(km),
    isKm: true,
  );
}

/// Minutes left, like the tracking notification (T15 §5.10): ceil(etaS/60),
/// at least 1.
int etaMinutesOf(int etaS) => math.max(1, (etaS + 59) ~/ 60);

/// Hours and minutes of [minutes]: 130 → (2, 10); 45 → (0, 45).
({int hours, int minutes}) splitHm(int minutes) =>
    (hours: minutes ~/ 60, minutes: minutes % 60);

/// "m:ss", minutes not padded: 45 000 → "0:45"; 61 000 → "1:01";
/// negative → "0:00". Rounded up to the second.
String formatCountdown(int remainingMs) {
  final seconds = remainingMs <= 0 ? 0 : (remainingMs + 999) ~/ 1000;
  final ss = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$ss';
}

/// Seconds of [remainingMs], rounded up like [formatCountdown].
int countdownSeconds(int remainingMs) =>
    remainingMs <= 0 ? 0 : (remainingMs + 999) ~/ 1000;

/// Threshold of "Báo sớm hơn" (T10 §4.9, review #16b).
int earlierAlarmPct(int? levelPct, AlarmSettingsParams p) => levelPct == null
    ? p.lowBatteryEarlierPct
    : math.max(
        p.lowBatteryAlarmPct,
        math.min(p.lowBatteryEarlierPct, levelPct - 1),
      );

enum AlarmStyleKind { ring, vibrateOnly, headphonesOnly }

/// Contract of T25 §2.5: volume 0.0 → vibrateOnly; preferHeadphones →
/// headphonesOnly; otherwise ring.
AlarmStyleKind alarmStyleOf(AlarmSettingsMsg a) {
  if (a.volume == 0.0) {
    return AlarmStyleKind.vibrateOnly;
  }
  if (a.preferHeadphones) {
    return AlarmStyleKind.headphonesOnly;
  }
  return AlarmStyleKind.ring;
}

/// Time left until the snooze ends. Real trip: snoozeUntil − now.
/// Simulated (virtual time, T18 D14; the clock runs at 1× after the alarm,
/// T18 D3): (snoozeUntil − state.atMs) − (now − receivedAt). Null when
/// there is no snoozeUntilMs. Never below 0.
int? snoozeRemainingMs(TrackedTrip t, int nowMs) {
  final until = t.state.snoozeUntilMs;
  if (until == null) {
    return null;
  }
  final remaining = t.simulated
      ? (until - t.state.atMs) - (nowMs - t.receivedAtMs)
      : until - nowMs;
  return math.max(0, remaining);
}
