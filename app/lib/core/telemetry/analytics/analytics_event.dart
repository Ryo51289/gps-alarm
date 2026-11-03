/// Typed Analytics events (T29 §2). Pure Dart: no Flutter, no Firebase.
///
/// Parameter values are only wire strings of the enums below and small
/// ints; there is no `double` anywhere, so no coordinate fits. Never add a
/// name, a station id, a search text, an exact distance or a trip id.
library;

import 'package:meta/meta.dart';

/// An enum value with its fixed Analytics name.
abstract interface class WireEnum {
  String get wire;
}

enum AlarmModeTag implements WireEnum {
  distance('distance'),
  time('time'),
  smart('smart');

  new(this.wire);

  @override
  final String wire;
}

enum ThresholdTag implements WireEnum {
  d500('d500'),
  d1000('d1000'),
  d2000('d2000'),
  d5000('d5000'),
  dOther('d_other'),
  t5('t5'),
  t10('t10'),
  t15('t15'),
  t20('t20'),
  t30('t30'),
  tOther('t_other'),
  smart('smart');

  new(this.wire);

  @override
  final String wire;
}

enum VehicleTag implements WireEnum {
  train('train'),
  coach('coach'),
  bus('bus'),
  unknown('unknown');

  new(this.wire);

  @override
  final String wire;
}

enum DestSourceTag implements WireEnum {
  station('station'),
  places('places'),
  mapPin('map_pin'),
  savedPlace('saved_place'),
  recentTrip('recent_trip');

  new(this.wire);

  @override
  final String wire;
}

enum BatteryBucket implements WireEnum {
  le5('le5'),
  le15('le15'),
  le50('le50'),
  gt50('gt50');

  new(this.wire);

  @override
  final String wire;
}

enum DurationBucket implements WireEnum {
  lt30m('lt30m'),
  lt2h('lt2h'),
  lt6h('lt6h'),
  lt12h('lt12h'),
  ge12h('ge12h');

  new(this.wire);

  @override
  final String wire;
}

enum DistanceBucket implements WireEnum {
  lt10km('lt10km'),
  lt50km('lt50km'),
  lt200km('lt200km'),
  lt500km('lt500km'),
  ge500km('ge500km');

  new(this.wire);

  @override
  final String wire;
}

enum StartBlockedReason implements WireEnum {
  locationDenied('location_denied'),
  locationApproximate('location_approximate'),
  locationServicesOff('location_services_off'),
  noAlarmChannel('no_alarm_channel'),
  startFailed('start_failed');

  new(this.wire);

  @override
  final String wire;
}

enum TripOutcomeTag implements WireEnum {
  onTime('on_time'),
  snoozed('snoozed'),
  missed('missed'),
  cancelled('cancelled');

  new(this.wire);

  @override
  final String wire;
}

enum EndReasonTag implements WireEnum {
  dismissed('dismissed'),
  userStop('user_stop'),
  alarmUnanswered('alarm_unanswered');

  new(this.wire);

  @override
  final String wire;
}

/// T10 `AlarmReason` in snake case, plus [none] (no alarm rang).
enum AlarmReasonTag implements WireEnum {
  distance('distance'),
  time('time'),
  smartTime('smart_time'),
  smartDistance('smart_distance'),
  smartSlowDistance('smart_slow_distance'),
  gpsLost('gps_lost'),
  lowBattery('low_battery'),
  passedClosest('passed_closest'),
  overshoot('overshoot'),
  snoozeEnd('snooze_end'),
  timeout('timeout'),
  fallback('fallback'),
  fallbackMissed('fallback_missed'),
  none('none');

  new(this.wire);

  @override
  final String wire;
}

enum BatteryChoiceTag implements WireEnum {
  maxSaving('max_saving'),
  alarmAt5('alarm_at_5'),
  alarmEarlier('alarm_earlier');

  new(this.wire);

  @override
  final String wire;
}

enum OvershootActionTag implements WireEnum {
  openMaps('open_maps'),
  dismiss('dismiss');

  new(this.wire);

  @override
  final String wire;
}

enum DestKindTag implements WireEnum {
  train('train'),
  coach('coach'),
  bus('bus'),
  address('address'),
  pin('pin');

  new(this.wire);

  @override
  final String wire;
}

enum LocationPermTag implements WireEnum {
  notDetermined('not_determined'),
  denied('denied'),
  whileInUse('while_in_use'),
  always('always');

  new(this.wire);

  @override
  final String wire;
}

/// granted / denied / not applicable on this platform or OS version.
enum TriStateTag implements WireEnum {
  granted('granted'),
  denied('denied'),
  na('na');

  new(this.wire);

  @override
  final String wire;
}

enum YesNoNaTag implements WireEnum {
  yes('yes'),
  no('no'),
  na('na');

  new(this.wire);

  @override
  final String wire;
}

enum AlarmKitTag implements WireEnum {
  granted('granted'),
  denied('denied'),
  notDetermined('not_determined'),
  na('na');

  new(this.wire);

  @override
  final String wire;
}

/// Screen 9 guide brands (T21 Q1 = A: the PRD four plus the four draft
/// guides), everything else [other]. Never the raw manufacturer or model.
enum OemTag implements WireEnum {
  xiaomi('xiaomi'),
  samsung('samsung'),
  oppo('oppo'),
  vivo('vivo'),
  realme('realme'),
  oneplus('oneplus'),
  huawei('huawei'),
  honor('honor'),
  other('other');

  new(this.wire);

  @override
  final String wire;

  /// The tag of a screen 9 guide id; unknown ids (and `generic`) → [other].
  static OemTag fromGuideId(String guideId) {
    for (final t in values) {
      if (t != other && t.wire == guideId) {
        return t;
      }
    }
    return other;
  }
}

enum GuideTestResult implements WireEnum {
  pass('pass'),
  fail('fail'),
  cancelled('cancelled');

  new(this.wire);

  @override
  final String wire;
}

int _bit(bool b) => b ? 1 : 0;

/// One Analytics event. [toParameters] holds only wire strings and ints.
@immutable
sealed class AnalyticsEvent {
  const new();

  String get name;

  Map<String, Object> toParameters();

  /// Names and parameter keys only, never values.
  @override
  String toString() => 'AnalyticsEvent($name)';
}

/// `startTrip` succeeded (T25).
final class TripStartEvent extends AnalyticsEvent {
  const new({
    required this.mode,
    required this.threshold,
    required this.vehicleHint,
    required this.destSource,
    required this.preAlert,
    required this.shortDistanceWarning,
    required this.battery,
    required this.charging,
    required this.simulated,
    required this.paramsId,
  });

  final AlarmModeTag mode;
  final ThresholdTag threshold;
  final VehicleTag vehicleHint;
  final DestSourceTag destSource;
  final bool preAlert;
  final bool shortDistanceWarning;

  /// Null when the battery level could not be read: the parameter is left
  /// out.
  final BatteryBucket? battery;
  final bool charging;
  final bool simulated;

  /// `default`, `invalid` or 8 hex digits (`EngineParamsOverride.id`).
  final String paramsId;

  @override
  String get name => 'trip_start';

  @override
  Map<String, Object> toParameters() => {
    'mode': mode.wire,
    'threshold': threshold.wire,
    'vehicle_hint': vehicleHint.wire,
    'dest_source': destSource.wire,
    'pre_alert': _bit(preAlert),
    'short_distance_warning': _bit(shortDistanceWarning),
    'battery': ?battery?.wire,
    'charging': _bit(charging),
    'simulated': _bit(simulated),
    'params_id': paramsId,
  };
}

/// "Bắt đầu theo dõi" did not start a trip (T25).
final class TripStartBlockedEvent extends AnalyticsEvent {
  const new({required this.reason, required this.simulated});

  final StartBlockedReason reason;
  final bool simulated;

  @override
  String get name => 'trip_start_blocked';

  @override
  Map<String, Object> toParameters() => {
    'reason': reason.wire,
    'simulated': _bit(simulated),
  };
}

/// First history write of a finished trip (T28), once per trip.
final class TripEndEvent extends AnalyticsEvent {
  /// [snoozeCount] is clamped to 0..3.
  new({
    required this.outcome,
    required this.endReason,
    required this.alarmReason,
    required int snoozeCount,
    required this.mode,
    required this.vehicleGuess,
    required this.duration,
    required this.distance,
    required this.simulated,
  }) : snoozeCount = snoozeCount.clamp(0, 3);

  final TripOutcomeTag outcome;
  final EndReasonTag endReason;
  final AlarmReasonTag alarmReason;
  final int snoozeCount;
  final AlarmModeTag mode;
  final VehicleTag vehicleGuess;
  final DurationBucket duration;
  final DistanceBucket distance;
  final bool simulated;

  @override
  String get name => 'trip_end';

  @override
  Map<String, Object> toParameters() => {
    'outcome': outcome.wire,
    'end_reason': endReason.wire,
    'alarm_reason': alarmReason.wire,
    'snooze_count': snoozeCount,
    'mode': mode.wire,
    'vehicle_guess': vehicleGuess.wire,
    'duration': duration.wire,
    'distance': distance.wire,
    'simulated': _bit(simulated),
  };
}

/// Choice on screen 7 (T26).
final class LowBatteryChoiceEvent extends AnalyticsEvent {
  const new({required this.choice, required this.simulated});

  final BatteryChoiceTag choice;
  final bool simulated;

  @override
  String get name => 'low_battery_choice';

  @override
  Map<String, Object> toParameters() => {
    'choice': choice.wire,
    'simulated': _bit(simulated),
  };
}

/// Action on screen 8 (T27).
final class OvershootActionEvent extends AnalyticsEvent {
  const new({required this.action, required this.simulated});

  final OvershootActionTag action;
  final bool simulated;

  @override
  String get name => 'overshoot_action';

  @override
  Map<String, Object> toParameters() => {
    'action': action.wire,
    'simulated': _bit(simulated),
  };
}

/// A destination was chosen (T22, T23). Source and kind only.
final class DestinationSelectedEvent extends AnalyticsEvent {
  const new({required this.source, required this.kind});

  final DestSourceTag source;
  final DestKindTag kind;

  @override
  String get name => 'destination_selected';

  @override
  Map<String, Object> toParameters() => {
    'source': source.wire,
    'kind': kind.wire,
  };
}

/// Permission state (T21 leaving screen 0; T22 once a day).
final class PermissionSnapshotEvent extends AnalyticsEvent {
  const new({
    required this.location,
    required this.precise,
    required this.locationServices,
    required this.notifications,
    required this.fullScreenIntent,
    required this.exactAlarm,
    required this.batteryOptIgnored,
    required this.alarmKit,
  });

  final LocationPermTag location;
  final bool precise;
  final bool locationServices;
  final TriStateTag notifications;
  final TriStateTag fullScreenIntent;
  final TriStateTag exactAlarm;
  final YesNoNaTag batteryOptIgnored;
  final AlarmKitTag alarmKit;

  @override
  String get name => 'permission_snapshot';

  @override
  Map<String, Object> toParameters() => {
    'location': location.wire,
    'precise': _bit(precise),
    'location_services': _bit(locationServices),
    'notifications': notifications.wire,
    'full_screen_intent': fullScreenIntent.wire,
    'exact_alarm': exactAlarm.wire,
    'battery_opt_ignored': batteryOptIgnored.wire,
    'alarm_kit': alarmKit.wire,
  };
}

/// Result of the 30 s check on screen 9 (T21).
final class BatteryGuideTestEvent extends AnalyticsEvent {
  const new({required this.oem, required this.result});

  final OemTag oem;
  final GuideTestResult result;

  @override
  String get name => 'battery_guide_test';

  @override
  Map<String, Object> toParameters() => {
    'oem': oem.wire,
    'result': result.wire,
  };
}
