import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_strings.dart';
import 'package:napstop/features/settings/domain/settings_logic.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Display strings of screen 12 (T28 §4, §9).
extension SettingsStrings on AppLocalizations {
  /// `default` and unknown ids read as the train horn (T16).
  String soundLabel(String id) => switch (resolveSoundId(id)) {
    'bell' => settingsSoundBell,
    'beep' => settingsSoundBeep,
    'system' => settingsSoundSystem,
    _ => settingsSoundHorn,
  };

  String vibrationLabel(VibrationMsg v) => switch (v) {
    VibrationMsg.light => settingsVibrationLight,
    VibrationMsg.medium => settingsVibrationMedium,
    VibrationMsg.strong || VibrationMsg.off => settingsVibrationStrong,
  };

  String themeLabel(AppThemeChoice t) => switch (t) {
    AppThemeChoice.light => settingsThemeLight,
    AppThemeChoice.dark => settingsThemeDark,
    AppThemeChoice.system => settingsThemeSystem,
  };

  String languageLabel(AppLanguage language) => switch (language) {
    AppLanguage.vi => settingsLanguageVi,
    AppLanguage.en => settingsLanguageEn,
    AppLanguage.system => settingsLanguageSystem,
  };

  /// "Thông minh", "Khoảng cách · 1 km", "Thời gian · 15 phút".
  String tripDefaultsSummary(TripSettings s) => switch (s.mode) {
    AlarmModeMsg.smart => settingsTripModeSmart,
    AlarmModeMsg.distance => settingsTripModeDistance(
      distance(s.distanceThresholdM),
    ),
    AlarmModeMsg.time => settingsTripModeTime(s.timeThresholdMin),
  };

  /// "1 lần · sau 1 phút", or "Không có báo lại" (engine values, T10 §5).
  String snoozeValue(AlarmSettingsParams p) {
    if (p.maxSnoozes == 0) {
      return alarmSettingsSnoozeNone;
    }
    final interval = p.snoozeS % 60 == 0
        ? commonMinutes(p.snoozeS ~/ 60)
        : commonSeconds(p.snoozeS);
    return settingsSnoozeValue(p.maxSnoozes, interval);
  }
}
