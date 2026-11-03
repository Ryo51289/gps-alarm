/// Crashlytics custom keys (T29 §4.2): a closed allowlist, each with the
/// values it may hold. No `double`, nothing that can carry a place.
library;

import 'package:napstop/core/telemetry/analytics/analytics_catalog.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';

const EnumParam _triState = EnumParam({'granted', 'denied', 'na'});

/// Not const (a RegExp), hence the null spec of [CrashKey.engineParamsId].
final PatternParam _paramsId = PatternParam(kParamsIdPattern);

enum CrashKey {
  flavor('flavor', EnumParam({'dev', 'prod'})),
  buildMode('build_mode', EnumParam({'debug', 'profile', 'release'})),
  locale('locale', EnumParam({'vi', 'en', 'other'})),
  tripActive('trip_active', BoolParam()),
  tripPhase(
    'trip_phase',
    EnumParam({
      'none',
      'acquiring',
      'tracking',
      'alarming',
      'snoozed',
      'overshot',
      'ended',
    }),
  ),
  samplingTier(
    'sampling_tier',
    EnumParam({'none', 'sparse', 'medium', 'dense'}),
  ),
  alarmMode('alarm_mode', EnumParam({'none', 'distance', 'time', 'smart'})),
  simulated('simulated', BoolParam()),
  engineParamsId('engine_params_id', null),
  permLocation(
    'perm_location',
    EnumParam({'not_determined', 'denied', 'while_in_use', 'always'}),
  ),
  permPrecise('perm_precise', BoolParam()),
  permNotifications('perm_notifications', _triState),
  permFullScreenIntent('perm_full_screen_intent', _triState),
  permExactAlarm('perm_exact_alarm', _triState);

  new(this.wire, this._spec);

  final String wire;
  final ParamSpec? _spec;

  /// Whether [value] may be stored under this key.
  bool accepts(Object value) => (_spec ?? _paramsId).accepts(value);
}

/// Crashlytics limit (T29 §4.2, F11).
const int kMaxCrashKeys = 64;

/// `locale` key of a language code.
String crashLocaleOf(String languageCode) => switch (languageCode) {
  'vi' || 'en' => languageCode,
  _ => 'other',
};

/// `alarm_mode` key of a trip mode.
String crashAlarmModeOf(AlarmModeTag? mode) => mode?.wire ?? 'none';
