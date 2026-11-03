/// Allowlist of every Analytics event and parameter (T29 §2, §3). Pure Dart.
/// Built from the `wire` names of analytics_event.dart, so the events and
/// the guard cannot drift apart.
library;

import 'package:napstop/core/telemetry/analytics/analytics_event.dart';

/// What a value may be. There is deliberately no spec that accepts a
/// `double`.
sealed class ParamSpec {
  const new();

  bool accepts(Object value);
}

/// One of a fixed set of strings.
final class EnumParam extends ParamSpec {
  const new(this.values);

  /// The wire names of [tags].
  new of(Iterable<WireEnum> tags) : values = {for (final t in tags) t.wire};

  final Set<String> values;

  @override
  bool accepts(Object value) => value is String && values.contains(value);
}

/// An int in a narrow range. Never a `double`.
final class IntParam extends ParamSpec {
  const new(this.min, this.max);

  final int min;
  final int max;

  @override
  bool accepts(Object value) => value is int && value >= min && value <= max;
}

/// A short string matching [pattern]; only for `params_id`.
final class PatternParam extends ParamSpec {
  new(this.pattern);

  final RegExp pattern;

  @override
  bool accepts(Object value) =>
      value is String && value.length <= 40 && pattern.hasMatch(value);
}

/// A `bool`. Crashlytics custom keys only: Analytics takes no bool (0/1 is
/// an [IntParam]), and the catalog test checks it is not used there.
final class BoolParam extends ParamSpec {
  const new();

  @override
  bool accepts(Object value) => value is bool;
}

/// `EngineParamsOverride.id`: 8 lower-case hex digits, `default` or
/// `invalid`.
final RegExp kParamsIdPattern = RegExp(r'^([0-9a-f]{8}|default|invalid)$');

const IntParam _bit = IntParam(0, 1);

final Map<String, ParamSpec> _modeOnly = {
  'mode': EnumParam.of(AlarmModeTag.values),
};

/// Event name → (parameter name → spec). The only source of the allowlist.
final Map<String, Map<String, ParamSpec>> kAnalyticsCatalog = {
  'trip_start': {
    ..._modeOnly,
    'threshold': EnumParam.of(ThresholdTag.values),
    'vehicle_hint': EnumParam.of(VehicleTag.values),
    'dest_source': EnumParam.of(DestSourceTag.values),
    'pre_alert': _bit,
    'short_distance_warning': _bit,
    'battery': EnumParam.of(BatteryBucket.values),
    'charging': _bit,
    'simulated': _bit,
    'params_id': PatternParam(kParamsIdPattern),
  },
  'trip_start_blocked': {
    'reason': EnumParam.of(StartBlockedReason.values),
    'simulated': _bit,
  },
  'trip_end': {
    'outcome': EnumParam.of(TripOutcomeTag.values),
    'end_reason': EnumParam.of(EndReasonTag.values),
    'alarm_reason': EnumParam.of(AlarmReasonTag.values),
    'snooze_count': const IntParam(0, 3),
    ..._modeOnly,
    'vehicle_guess': EnumParam.of(VehicleTag.values),
    'duration': EnumParam.of(DurationBucket.values),
    'distance': EnumParam.of(DistanceBucket.values),
    'simulated': _bit,
  },
  'low_battery_choice': {
    'choice': EnumParam.of(BatteryChoiceTag.values),
    'simulated': _bit,
  },
  'overshoot_action': {
    'action': EnumParam.of(OvershootActionTag.values),
    'simulated': _bit,
  },
  'destination_selected': {
    'source': EnumParam.of(DestSourceTag.values),
    'kind': EnumParam.of(DestKindTag.values),
  },
  'permission_snapshot': {
    'location': EnumParam.of(LocationPermTag.values),
    'precise': _bit,
    'location_services': _bit,
    'notifications': EnumParam.of(TriStateTag.values),
    'full_screen_intent': EnumParam.of(TriStateTag.values),
    'exact_alarm': EnumParam.of(TriStateTag.values),
    'battery_opt_ignored': EnumParam.of(YesNoNaTag.values),
    'alarm_kit': EnumParam.of(AlarmKitTag.values),
  },
  'battery_guide_test': {
    'oem': EnumParam.of(OemTag.values),
    'result': EnumParam.of(GuideTestResult.values),
  },
};
