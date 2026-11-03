/// Builds and checks the `TripConfigMsg` of screen 3 (T25 §2.5).
///
/// PRIVACY: never log a TripConfigMsg (its toString prints the name).
library;

import 'dart:math';

import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/text/kotlin_blank.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

/// Contract with T16/T17 (T25 §2.5): `volume == 0.0` means vibrate only;
/// `preferHeadphones` means "Chỉ tai nghe".
AlarmSettingsMsg buildAlarmSettings(
  AlarmStyle style,
  DismissMethodMsg dismiss,
  AlarmPreferences g,
) => AlarmSettingsMsg(
  soundId: g.soundId,
  volume: style == AlarmStyle.vibrateOnly ? 0.0 : g.volumePct / 100,
  rampUp: g.rampUp,
  vibration: style == AlarmStyle.vibrateOnly
      ? VibrationMsg.strong
      : g.vibration,
  flash: g.flash,
  preferHeadphones: style == AlarmStyle.headphonesOnly,
  dismissMethod: dismiss,
);

/// Only the threshold of the chosen mode is sent; [engineParamsJson] goes
/// verbatim (T29 §6). Coordinates are not part of it (T14 D5).
TripConfigMsg buildTripConfig({
  required String tripId,
  required TripDraft draft,
  required TripSettings settings,
  required AlarmPreferences prefs,
  required String? engineParamsJson,
}) => TripConfigMsg(
  tripId: tripId,
  destinationName: truncateDestinationName(draft.destination.name),
  mode: settings.mode,
  distanceThresholdM: settings.mode == AlarmModeMsg.distance
      ? settings.distanceThresholdM
      : null,
  timeThresholdMin: settings.mode == AlarmModeMsg.time
      ? settings.timeThresholdMin
      : null,
  preAlertEnabled: settings.preAlertEnabled,
  vehicleHint: draft.vehicleHint,
  alarm: buildAlarmSettings(settings.alarmStyle, settings.dismissMethod, prefs),
  engineParamsJson: engineParamsJson,
);

final RegExp _tripIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// T14 §6 V1–V11 in the same order and with the same messages as the native
/// `TripConfigValidator` (no values in them); null when valid. "Blank" uses
/// Kotlin's definition, like the native check.
String? validateTripConfig(
  TripConfigMsg c,
  double destLat,
  double destLng,
  SimulationMsg? sim,
) {
  if (!_tripIdPattern.hasMatch(c.tripId)) {
    return 'tripId: format';
  }
  if (isBlankLikeKotlin(c.destinationName)) {
    return 'destinationName: empty';
  }
  if (c.destinationName.length > kMaxDestinationNameLength) {
    return 'destinationName: too long';
  }
  if (!destLat.isFinite || destLat < -90 || destLat > 90) {
    return 'destLat: out of range';
  }
  if (!destLng.isFinite || destLng < -180 || destLng >= 180) {
    return 'destLng: out of range';
  }
  final distance = c.distanceThresholdM;
  final time = c.timeThresholdMin;
  if (c.mode == AlarmModeMsg.distance && distance == null) {
    return 'distanceThresholdM: required';
  }
  if (c.mode == AlarmModeMsg.time && time == null) {
    return 'timeThresholdMin: required';
  }
  if (distance != null &&
      (distance < kMinDistanceThresholdM ||
          distance > kMaxDistanceThresholdM)) {
    return 'distanceThresholdM: out of range';
  }
  if (time != null &&
      (time < kMinTimeThresholdMin || time > kMaxTimeThresholdMin)) {
    return 'timeThresholdMin: out of range';
  }
  if (c.alarm.soundId.isEmpty) {
    return 'alarm.soundId: empty';
  }
  final volume = c.alarm.volume;
  if (!volume.isFinite || volume < 0 || volume > 1) {
    return 'alarm.volume: out of range';
  }
  if (sim != null) {
    if (sim.traceAsset.isEmpty) {
      return 'simulation.traceAsset: empty';
    }
    final speed = sim.speedFactor;
    if (!speed.isFinite || speed < 1 || speed > 600) {
      return 'simulation.speedFactor: out of range';
    }
  }
  final params = c.engineParamsJson;
  if (params != null && params.length > kEngineParamsMaxChars) {
    return 'engineParamsJson: too long';
  }
  return null;
}

/// Random UUID v4, lower case, 36 characters (matches T14 V1).
String newTripId([Random? rnd]) {
  final r = rnd ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Trimmed; longer than 200 code units → the first 200, or 199 when the
/// 200th unit would split a surrogate pair.
String truncateDestinationName(String s) {
  final t = s.trim();
  if (t.length <= kMaxDestinationNameLength) {
    return t;
  }
  final last = t.codeUnitAt(kMaxDestinationNameLength - 1);
  final cut = last >= 0xD800 && last <= 0xDBFF
      ? kMaxDestinationNameLength - 1
      : kMaxDestinationNameLength;
  return t.substring(0, cut);
}
