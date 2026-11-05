import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';

/// Store keys (T25 §2.1). Contract with T28: never rename.
abstract final class PreferenceKeys {
  static const String alarmSoundId = 'alarm.soundId';
  static const String alarmVolumePct = 'alarm.volumePct';
  static const String alarmRampUp = 'alarm.rampUp';
  static const String alarmVibration = 'alarm.vibration';
  static const String alarmFlash = 'alarm.flash';
  static const String tripMode = 'tripDefaults.mode';
  static const String tripDistanceM = 'tripDefaults.distanceM';
  static const String tripTimeMin = 'tripDefaults.timeMin';
  static const String tripPreAlert = 'tripDefaults.preAlert';
  static const String tripAlarmStyle = 'tripDefaults.alarmStyle';
  static const String tripDismiss = 'tripDefaults.dismiss';

  /// T28: `system` | `vi` | `en`.
  static const String displayLanguage = 'display.language';

  /// T28: `system` | `light` | `dark`.
  static const String displayTheme = 'display.theme';
}

/// Global alarm settings and defaults for new trips. Each missing, invalid
/// or unreadable key falls back to its own default; reading never throws.
final class PreferencesRepository {
  new(this._kv);

  final KeyValueStore _kv;

  Future<AlarmPreferences> loadAlarmPreferences() async {
    const d = AlarmPreferences.defaults;
    final soundId = await _string(PreferenceKeys.alarmSoundId);
    final volume = await _int(PreferenceKeys.alarmVolumePct);
    return AlarmPreferences(
      soundId:
          soundId != null &&
              soundId.isNotEmpty &&
              soundId.length <= kMaxAlarmSoundIdLength
          ? soundId
          : d.soundId,
      volumePct:
          volume != null &&
              volume >= kMinAlarmVolumePct &&
              volume <= kMaxAlarmVolumePct
          ? volume
          : d.volumePct,
      rampUp: await _bool(PreferenceKeys.alarmRampUp) ?? d.rampUp,
      vibration:
          _byName(const [
            VibrationMsg.light,
            VibrationMsg.medium,
            VibrationMsg.strong,
          ], await _string(PreferenceKeys.alarmVibration)) ??
          d.vibration,
      flash: await _bool(PreferenceKeys.alarmFlash) ?? d.flash,
    );
  }

  /// Already [TripSettings.normalized].
  Future<TripSettings> loadTripDefaults() async {
    const d = TripSettings.defaults;
    return TripSettings(
      mode:
          _byName(
            AlarmModeMsg.values,
            await _string(PreferenceKeys.tripMode),
          ) ??
          d.mode,
      distanceThresholdM:
          await _int(PreferenceKeys.tripDistanceM) ?? d.distanceThresholdM,
      timeThresholdMin:
          await _int(PreferenceKeys.tripTimeMin) ?? d.timeThresholdMin,
      preAlertEnabled:
          await _bool(PreferenceKeys.tripPreAlert) ?? d.preAlertEnabled,
      alarmStyle:
          _byName(
            AlarmStyle.values,
            await _string(PreferenceKeys.tripAlarmStyle),
          ) ??
          d.alarmStyle,
      dismissMethod:
          _byName(
            DismissMethodMsg.values,
            await _string(PreferenceKeys.tripDismiss),
          ) ??
          d.dismissMethod,
    ).normalized();
  }

  /// Language and theme (T28 §4.1).
  Future<DisplayPreferences> loadDisplayPreferences() async {
    const d = DisplayPreferences.defaults;
    return DisplayPreferences(
      language:
          _byName(
            AppLanguage.values,
            await _string(PreferenceKeys.displayLanguage),
          ) ??
          d.language,
      theme:
          _byName(
            AppThemeChoice.values,
            await _string(PreferenceKeys.displayTheme),
          ) ??
          d.theme,
    );
  }

  Future<void> saveDisplayPreferences(DisplayPreferences p) async {
    await _kv.setString(PreferenceKeys.displayLanguage, p.language.name);
    await _kv.setString(PreferenceKeys.displayTheme, p.theme.name);
  }

  Future<void> saveAlarmPreferences(AlarmPreferences p) async {
    await _kv.setString(PreferenceKeys.alarmSoundId, p.soundId);
    await _kv.setInt(PreferenceKeys.alarmVolumePct, p.volumePct);
    await _kv.setInt(PreferenceKeys.alarmRampUp, p.rampUp ? 1 : 0);
    await _kv.setString(PreferenceKeys.alarmVibration, p.vibration.name);
    await _kv.setInt(PreferenceKeys.alarmFlash, p.flash ? 1 : 0);
  }

  Future<void> saveTripDefaults(TripSettings s) async {
    await _kv.setString(PreferenceKeys.tripMode, s.mode.name);
    await _kv.setInt(PreferenceKeys.tripDistanceM, s.distanceThresholdM);
    await _kv.setInt(PreferenceKeys.tripTimeMin, s.timeThresholdMin);
    await _kv.setInt(PreferenceKeys.tripPreAlert, s.preAlertEnabled ? 1 : 0);
    await _kv.setString(PreferenceKeys.tripAlarmStyle, s.alarmStyle.name);
    await _kv.setString(PreferenceKeys.tripDismiss, s.dismissMethod.name);
  }

  Future<String?> _string(String key) async {
    try {
      return await _kv.getString(key);
    } on Object {
      return null;
    }
  }

  Future<int?> _int(String key) async {
    try {
      return await _kv.getInt(key);
    } on Object {
      return null;
    }
  }

  /// 0/1 only.
  Future<bool?> _bool(String key) async => switch (await _int(key)) {
    0 => false,
    1 => true,
    _ => null,
  };

  static T? _byName<T extends Enum>(List<T> values, String? name) {
    for (final v in values) {
      if (v.name == name) {
        return v;
      }
    }
    return null;
  }
}

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(ref.watch(keyValueStoreProvider)),
);
