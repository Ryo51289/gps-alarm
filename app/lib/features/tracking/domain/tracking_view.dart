/// TripState → what screen 4 shows (T26 §3.3, §4). Pure: no Flutter.
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/features/tracking/data/tracked_trip_provider.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';

/// D8 (b): 3 × AWAKE_TICK_MAX_MS of the runtime.
const int kStaleViewMs = 180000;

/// = default acquireTimeoutS (T10 §5); only for the hint, not the engine.
const int kNoGpsHintAfterMs = 120000;

/// D16: device status poll while screen 4 is visible.
const int kDeviceStatusPollMs = 30000;

/// = PREVIEW_MAX_MS of T16.
const int kPreviewMs = 10000;

/// What the screen knows besides the trip.
@immutable
final class TrackingEnv {
  const new({
    required this.nowMs,
    required this.locale,
    this.missing = const [],
    this.device,
  });

  /// Real time.
  final int nowMs;

  /// `checkStart(permissionStatus, deviceInfo).missing`; empty when not read
  /// yet or unreadable.
  final List<StartRequirement> missing;
  final DeviceStatusMsg? device;
  final String locale;
}

/// The large block, by phase (§4.1).
@immutable
sealed class Headline {
  const new();
}

/// ACQUIRING (or TRACKING without a distance).
final class HeadlineAcquiring extends Headline {
  const new();

  @override
  bool operator ==(Object other) => other is HeadlineAcquiring;

  @override
  int get hashCode => 0;
}

/// TRACKING: "152 km" / "~148 km".
final class HeadlineDistance extends Headline {
  const new(this.distance, {required this.estimated});

  final FormattedDistance distance;
  final bool estimated;

  @override
  bool operator ==(Object other) =>
      other is HeadlineDistance &&
      other.distance == distance &&
      other.estimated == estimated;

  @override
  int get hashCode => Object.hash(distance, estimated);
}

/// ALARMING: why it rang; [remaining] = "Còn …" under it when known.
final class HeadlineAlarm extends Headline {
  const new(
    this.copy, {
    required this.ringing,
    this.remaining,
    this.estimated = false,
  });

  final AlarmCopy copy;
  final bool ringing;
  final FormattedDistance? remaining;
  final bool estimated;

  @override
  bool operator ==(Object other) =>
      other is HeadlineAlarm &&
      other.copy == copy &&
      other.ringing == ringing &&
      other.remaining == remaining &&
      other.estimated == estimated;

  @override
  int get hashCode => Object.hash(copy, ringing, remaining, estimated);
}

/// SNOOZED: countdown to the next ring.
final class HeadlineSnoozed extends Headline {
  const new(this.remainingMs);

  final int? remainingMs;

  @override
  bool operator ==(Object other) =>
      other is HeadlineSnoozed && other.remainingMs == remainingMs;

  @override
  int get hashCode => remainingMs.hashCode;
}

/// OVERSHOT: "Đã qua 1,4 km".
final class HeadlineOvershoot extends Headline {
  const new({required this.ringing, this.past});

  final FormattedDistance? past;
  final bool ringing;

  @override
  bool operator ==(Object other) =>
      other is HeadlineOvershoot &&
      other.past == past &&
      other.ringing == ringing;

  @override
  int get hashCode => Object.hash(past, ringing);
}

/// Alarm reason → ARB key (T10 §10). The destination is always
/// `config.destinationName`.
enum AlarmCopyKind {
  distance,
  time,
  gpsLost,
  lowBattery,
  passedClosest,
  overshoot,
  snoozeEnd,
  timeout,
  fallback,
  fallbackMissed,
  generic,
}

@immutable
final class AlarmCopy {
  const new(this.kind, {this.distance, this.minutes, this.percent});

  final AlarmCopyKind kind;
  final FormattedDistance? distance;
  final int? minutes;
  final int? percent;

  @override
  bool operator ==(Object other) =>
      other is AlarmCopy &&
      other.kind == kind &&
      other.distance == distance &&
      other.minutes == minutes &&
      other.percent == percent;

  @override
  int get hashCode => Object.hash(kind, distance, minutes, percent);

  @override
  String toString() => 'AlarmCopy(${kind.name})';
}

/// The reason text of the latest alarm (§4.2). A missing parameter falls
/// back to [AlarmCopyKind.generic].
AlarmCopy alarmCopyOf(TripStateMsg s, String locale) {
  const generic = AlarmCopy(AlarmCopyKind.generic);
  final distanceM = s.distanceM;
  final etaS = s.etaS;
  final pct = s.batteryPct;
  return switch (s.alarmReason) {
    AlarmReasonMsg.distance ||
    AlarmReasonMsg.smartDistance ||
    AlarmReasonMsg.smartSlowDistance =>
      distanceM == null
          ? generic
          : AlarmCopy(
              AlarmCopyKind.distance,
              distance: formatTripDistance(distanceM, locale),
            ),
    AlarmReasonMsg.time || AlarmReasonMsg.smartTime =>
      etaS == null
          ? generic
          : AlarmCopy(AlarmCopyKind.time, minutes: etaMinutesOf(etaS)),
    AlarmReasonMsg.gpsLost => const AlarmCopy(AlarmCopyKind.gpsLost),
    AlarmReasonMsg.lowBattery =>
      pct == null ? generic : AlarmCopy(AlarmCopyKind.lowBattery, percent: pct),
    AlarmReasonMsg.passedClosest => const AlarmCopy(
      AlarmCopyKind.passedClosest,
    ),
    AlarmReasonMsg.overshoot => const AlarmCopy(AlarmCopyKind.overshoot),
    AlarmReasonMsg.snoozeEnd => const AlarmCopy(AlarmCopyKind.snoozeEnd),
    AlarmReasonMsg.timeout => const AlarmCopy(AlarmCopyKind.timeout),
    AlarmReasonMsg.fallback => const AlarmCopy(AlarmCopyKind.fallback),
    AlarmReasonMsg.fallbackMissed => const AlarmCopy(
      AlarmCopyKind.fallbackMissed,
    ),
    null => generic,
  };
}

/// = the matching `NapTone`.
enum TileTone { neutral, success, warning, danger }

enum GpsTile { noPermission, servicesOff, good, lost, searching }

enum BatteryTileNote {
  none,
  charging,
  risk,
  enough,
  maxSaving,
  alarmAt5,
  alarmEarlier,
  low,
}

enum HeadphonesTile {
  connected,
  connectedPreferred,
  notConnected,
  notConnectedSpeaker,
  unknownShowStyle,
}

/// In display order (§4.4).
enum TrackingBanner {
  locationPermission,
  locationServices,
  fallbackFailed,
  noGps,
  gpsLost,
  batteryRisk,
  batteryLow,
}

/// Everything screen 4 shows for one trip view.
@immutable
final class TrackingView {
  const new({
    required this.headline,
    required this.gps,
    required this.gpsTone,
    required this.batteryNote,
    required this.batteryTone,
    required this.headphones,
    required this.headphonesTone,
    required this.style,
    required this.banners,
    required this.canPreview,
    required this.canDismiss,
    required this.canStop,
    required this.wantsBatterySheet,
    required this.params,
    this.etaMinutes,
    this.arrivalAtMs,
    this.alarmAtMs,
    this.alarmInMinutes,
    this.speedKmh,
    this.errorDistance,
    this.progress,
    this.markerProgress,
    this.progressEstimated = false,
    this.gpsAccuracy,
    this.batteryPct,
    this.batteryNotePct,
    this.staleMinutes,
  });

  final Headline headline;

  /// Null: hidden.
  final int? etaMinutes;

  /// Real time; real trips only.
  final int? arrivalAtMs;

  /// "Dự kiến báo lúc"; real trips only.
  final int? alarmAtMs;

  /// "Dự kiến báo sau"; simulated trips only.
  final int? alarmInMinutes;

  /// Null when estimated, unknown or not TRACKING.
  final int? speedKmh;

  /// "±" while estimated.
  final FormattedDistance? errorDistance;
  final double? progress;
  final double? markerProgress;
  final bool progressEstimated;
  final GpsTile gps;
  final FormattedDistance? gpsAccuracy;
  final TileTone gpsTone;
  final int? batteryPct;
  final BatteryTileNote batteryNote;
  final TileTone batteryTone;
  final int? batteryNotePct;
  final HeadphonesTile headphones;
  final TileTone headphonesTone;
  final AlarmStyleKind style;
  final List<TrackingBanner> banners;

  /// D8 (b).
  final int? staleMinutes;
  final bool canPreview;
  final bool canDismiss;
  final bool canStop;

  /// D10 condition (the screen decides whether it was shown already).
  final bool wantsBatterySheet;

  /// D11: the engine parameters of this trip.
  final AlarmSettingsParams params;
}

/// Accuracy / error: exact metres below 1 km ("±8 m"), else like
/// [formatTripDistance] ("±1,2 km").
FormattedDistance formatAccuracy(int meters, String locale) => meters < 1000
    ? FormattedDistance('${math.max(0, meters)}', isKm: false)
    : formatTripDistance(meters, locale);

/// D10: screen 7 is wanted (risk, no choice yet, ACQUIRING or TRACKING).
bool wantsBatterySheetOf(TrackedTrip t) {
  final s = t.state;
  return s.batteryRisk &&
      s.batteryChoice == null &&
      (s.phase == TripPhaseMsg.acquiring || s.phase == TripPhaseMsg.tracking);
}

/// §4: the view of [t] in [env].
TrackingView buildTrackingView(TrackedTrip t, TrackingEnv env) {
  final s = t.state;
  final p = AlarmSettingsParams.fromOverrideJson(t.config.engineParamsJson);
  final real = !t.simulated;
  final phase = s.phase;
  final watching =
      phase == TripPhaseMsg.acquiring || phase == TripPhaseMsg.tracking;
  final locale = env.locale;

  // §4.1 headline and secondary lines.
  final distanceM = s.distanceM;
  final Headline headline;
  int? etaMinutes;
  int? arrivalAtMs;
  int? alarmAtMs;
  int? alarmInMinutes;
  int? speedKmh;
  switch (phase) {
    case TripPhaseMsg.tracking when distanceM != null:
      headline = HeadlineDistance(
        formatTripDistance(distanceM, locale),
        estimated: s.isEstimated,
      );
      final etaS = s.etaS;
      if (etaS != null) {
        etaMinutes = etaMinutesOf(etaS);
        arrivalAtMs = real ? s.atMs + etaS * 1000 : null;
      }
      final predicted = s.predictedAlarmAtMs;
      if (predicted != null) {
        if (real) {
          alarmAtMs = predicted;
        } else {
          alarmInMinutes = etaMinutesOf(
            math.max(0, (predicted - s.atMs) ~/ 1000),
          );
        }
      }
      speedKmh = s.isEstimated ? null : s.speedKmh?.round();
    case TripPhaseMsg.alarming:
      headline = HeadlineAlarm(
        alarmCopyOf(s, locale),
        ringing: s.alarmRinging,
        remaining: distanceM == null
            ? null
            : formatTripDistance(distanceM, locale),
        estimated: s.isEstimated,
      );
    case TripPhaseMsg.snoozed:
      headline = HeadlineSnoozed(snoozeRemainingMs(t, env.nowMs));
    case TripPhaseMsg.overshot:
      final past = s.overshootPastM;
      headline = HeadlineOvershoot(
        ringing: s.alarmRinging,
        past: past == null ? null : formatTripDistance(past, locale),
      );
    case TripPhaseMsg.acquiring || TripPhaseMsg.tracking || TripPhaseMsg.ended:
      headline = const HeadlineAcquiring();
  }

  final errorM = s.distanceErrorM;
  final showProgress = s.progress != null && phase != TripPhaseMsg.acquiring;

  // §4.3 GPS tile.
  final noPermission =
      s.locationCause == AvailabilityCauseMsg.permissionRevoked ||
      env.missing.contains(StartRequirement.location) ||
      env.missing.contains(StartRequirement.precise);
  final servicesOff =
      s.locationCause == AvailabilityCauseMsg.servicesOff ||
      env.missing.contains(StartRequirement.locationServices);
  final acquiringSince = t.acquiringSinceMs;
  final noGpsBanner =
      phase == TripPhaseMsg.acquiring &&
      s.gps == GpsStatusMsg.noFixYet &&
      (t.neverAcquired ||
          (acquiringSince != null &&
              env.nowMs - acquiringSince >= kNoGpsHintAfterMs));
  final (GpsTile gps, TileTone gpsTone) = noPermission
      ? (GpsTile.noPermission, TileTone.danger)
      : servicesOff
      ? (GpsTile.servicesOff, TileTone.danger)
      : switch (s.gps) {
          GpsStatusMsg.ok => (GpsTile.good, TileTone.success),
          GpsStatusMsg.lost => (GpsTile.lost, TileTone.warning),
          GpsStatusMsg.noFixYet => (
            GpsTile.searching,
            noGpsBanner ? TileTone.warning : TileTone.neutral,
          ),
        };

  // §4.3 battery tile.
  final device = env.device;
  final charging = device?.charging == true;
  final pct = s.batteryPct ?? device?.batteryPct;
  final risk = s.batteryRisk && s.batteryChoice == null;
  final (BatteryTileNote note, TileTone batteryTone, int? notePct) = charging
      ? (BatteryTileNote.charging, TileTone.success, null)
      : risk
      ? (BatteryTileNote.risk, TileTone.danger, null)
      : switch (s.batteryChoice) {
          BatteryChoiceMsg.maxSaving => (
            BatteryTileNote.maxSaving,
            TileTone.neutral,
            null,
          ),
          BatteryChoiceMsg.alarmAt5 => (
            BatteryTileNote.alarmAt5,
            TileTone.neutral,
            p.lowBatteryAlarmPct,
          ),
          BatteryChoiceMsg.alarmEarlier => (
            BatteryTileNote.alarmEarlier,
            TileTone.neutral,
            null,
          ),
          null when pct != null && pct <= p.lowBatteryAlarmPct => (
            BatteryTileNote.low,
            TileTone.danger,
            null,
          ),
          null when s.batteryPct != null && phase == TripPhaseMsg.tracking => (
            BatteryTileNote.enough,
            TileTone.neutral,
            null,
          ),
          null => (BatteryTileNote.none, TileTone.neutral, null),
        };

  // §4.3 headphones tile.
  final style = alarmStyleOf(t.config.alarm);
  final headphonesOnly = style == AlarmStyleKind.headphonesOnly;
  final (
    HeadphonesTile headphones,
    TileTone headphonesTone,
  ) = switch (device?.headphonesConnected) {
    true when headphonesOnly => (
      HeadphonesTile.connectedPreferred,
      TileTone.success,
    ),
    true => (HeadphonesTile.connected, TileTone.neutral),
    false when headphonesOnly => (
      HeadphonesTile.notConnectedSpeaker,
      TileTone.warning,
    ),
    false => (HeadphonesTile.notConnected, TileTone.neutral),
    null => (HeadphonesTile.unknownShowStyle, TileTone.neutral),
  };

  // §4.4 banners.
  final warningPhase = watching || phase == TripPhaseMsg.snoozed;
  // Simulated trips: the engine has no battery (T18 D7); the phone's level
  // only counts for a real trip.
  final bannerPct = real ? pct : s.batteryPct;
  final banners = <TrackingBanner>[
    if (warningPhase && noPermission) TrackingBanner.locationPermission,
    if (warningPhase && servicesOff) TrackingBanner.locationServices,
    if (warningPhase && real && s.fallbackStatus == FallbackStatusMsg.failed)
      TrackingBanner.fallbackFailed,
    if (noGpsBanner) TrackingBanner.noGps,
    if (phase == TripPhaseMsg.tracking && s.isEstimated) TrackingBanner.gpsLost,
    if (watching && risk) TrackingBanner.batteryRisk,
    if (watching &&
        !risk &&
        bannerPct != null &&
        bannerPct <= p.lowBatteryAlarmPct &&
        !charging)
      TrackingBanner.batteryLow,
  ];

  final age = env.nowMs - s.atMs;
  return TrackingView(
    headline: headline,
    etaMinutes: etaMinutes,
    arrivalAtMs: arrivalAtMs,
    alarmAtMs: alarmAtMs,
    alarmInMinutes: alarmInMinutes,
    speedKmh: speedKmh,
    errorDistance: s.isEstimated && errorM != null
        ? formatAccuracy(errorM, locale)
        : null,
    progress: showProgress ? s.progress : null,
    markerProgress: showProgress && phase == TripPhaseMsg.tracking
        ? s.alarmMarkerProgress
        : null,
    progressEstimated: s.isEstimated,
    gps: gps,
    gpsAccuracy: gps == GpsTile.good && errorM != null
        ? formatAccuracy(errorM, locale)
        : null,
    gpsTone: gpsTone,
    batteryPct: pct,
    batteryNote: note,
    batteryTone: batteryTone,
    batteryNotePct: notePct,
    headphones: headphones,
    headphonesTone: headphonesTone,
    style: style,
    banners: List.unmodifiable(banners),
    staleMinutes: real && watching && age > kStaleViewMs ? age ~/ 60000 : null,
    canPreview: watching && style != AlarmStyleKind.vibrateOnly,
    canDismiss: switch (phase) {
      TripPhaseMsg.alarming || TripPhaseMsg.overshot => !s.alarmRinging,
      TripPhaseMsg.snoozed => true,
      _ => false,
    },
    canStop: phase != TripPhaseMsg.ended,
    wantsBatterySheet: wantsBatterySheetOf(t),
    params: p,
  );
}
