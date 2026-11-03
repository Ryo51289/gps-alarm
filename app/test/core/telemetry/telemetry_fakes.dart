// Fakes for the T29 telemetry tests. Not a test file.
import 'dart:async';

import 'package:napstop/core/telemetry/analytics/analytics_event.dart';
import 'package:napstop/core/telemetry/analytics/analytics_sink.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';
import 'package:napstop/core/telemetry/remote_config/remote_config_client.dart';

/// One `recordError` call.
typedef RecordedError = ({
  Object error,
  StackTrace? stack,
  String reason,
  bool fatal,
});

/// Records every call; [calls] keeps the order.
class RecordingCrashSink implements CrashSink {
  final List<RecordedError> errors = [];
  final List<String> logs = [];
  final Map<String, Object> keys = {};
  final List<String> calls = [];

  /// Set to make every call throw it (synchronously).
  Object? throwOnCall;

  void _call(String name) {
    calls.add(name);
    final e = throwOnCall;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
  }

  /// Every string the sink received (messages, reasons, logs, keys).
  Iterable<String> get allText => [
    for (final e in errors) ...[e.error.toString(), e.reason],
    ...logs,
    for (final MapEntry(:key, :value) in keys.entries) '$key=$value',
  ];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    required String reason,
    required bool fatal,
  }) async {
    _call('recordError');
    errors.add((error: error, stack: stack, reason: reason, fatal: fatal));
  }

  @override
  Future<void> log(String message) async {
    _call('log');
    logs.add(message);
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    _call('setCustomKey');
    keys[key] = value;
  }

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async =>
      _call('setCollectionEnabled($enabled)');

  @override
  Future<void> sendUnsentReports() async => _call('sendUnsentReports');

  @override
  Future<void> deleteUnsentReports() async => _call('deleteUnsentReports');
}

/// Records every event, in order.
class RecordingAnalyticsSink implements AnalyticsSink {
  final List<(String, Map<String, Object>)> events = [];
  final List<String> calls = [];

  /// Set to make [logEvent] fail asynchronously.
  Object? logError;

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) {
    calls.add('logEvent');
    final e = logError;
    if (e != null) {
      return Future.error(e);
    }
    events.add((name, parameters));
    return Future.value();
  }

  @override
  Future<void> setCollectionEnabled({required bool enabled}) async =>
      calls.add('setCollectionEnabled($enabled)');

  @override
  Future<void> resetData() async => calls.add('resetData');
}

/// In-memory Remote Config: [value] is the active `trip_engine_params`.
class FakeRemoteConfigClient implements RemoteConfigClient {
  new([this.value = '']);

  String value;
  int configureCalls = 0;
  int fetchCalls = 0;
  Duration? fetchTimeout;
  Duration? minimumFetchInterval;
  Map<String, Object>? defaults;

  /// When set, [fetchAndActivate] waits for it.
  Completer<void>? fetchGate;
  Object? fetchError;
  Object? configureError;
  Object? getError;

  /// Value activated by the next successful fetch.
  String? next;

  @override
  Future<void> configure({
    required Duration fetchTimeout,
    required Duration minimumFetchInterval,
    required Map<String, Object> defaults,
  }) async {
    configureCalls++;
    this.fetchTimeout = fetchTimeout;
    this.minimumFetchInterval = minimumFetchInterval;
    this.defaults = defaults;
    final e = configureError;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
  }

  @override
  Future<bool> fetchAndActivate() async {
    fetchCalls++;
    final gate = fetchGate;
    if (gate != null) {
      await gate.future;
    }
    final e = fetchError;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    final n = next;
    if (n != null) {
      value = n;
      next = null;
      return true;
    }
    return false;
  }

  @override
  String getString(String key) {
    final e = getError;
    if (e != null) {
      Error.throwWithStackTrace(e, StackTrace.current);
    }
    return value;
  }
}

/// A crash reporter on a recording sink (not strict unless asked).
(CrashReporter, RecordingCrashSink) recordingCrash({bool strict = false}) {
  final sink = RecordingCrashSink();
  return (CrashReporter(sink, strict: strict), sink);
}

T _at<T>(List<T> values, int i) => values[i % values.length];

int _maxLen(List<List<Object>> lists) =>
    lists.map((l) => l.length).reduce((a, b) => a > b ? a : b);

/// Every value of every enum of every event, at least once (TC02). The
/// exhaustive switch in [eventKind] stops compiling when an event type is
/// added without being listed there.
List<AnalyticsEvent> sampleEvents() {
  final tripStart = _maxLen([
    AlarmModeTag.values,
    ThresholdTag.values,
    VehicleTag.values,
    DestSourceTag.values,
    BatteryBucket.values,
  ]);
  final tripEnd = _maxLen([
    TripOutcomeTag.values,
    EndReasonTag.values,
    AlarmReasonTag.values,
    AlarmModeTag.values,
    VehicleTag.values,
    DurationBucket.values,
    DistanceBucket.values,
  ]);
  final snapshot = _maxLen([
    LocationPermTag.values,
    TriStateTag.values,
    YesNoNaTag.values,
    AlarmKitTag.values,
  ]);
  const ids = ['default', 'invalid', '811c9dc5', '0a1b2c3d'];
  return [
    for (var i = 0; i < tripStart; i++)
      TripStartEvent(
        mode: _at(AlarmModeTag.values, i),
        threshold: _at(ThresholdTag.values, i),
        vehicleHint: _at(VehicleTag.values, i),
        destSource: _at(DestSourceTag.values, i),
        preAlert: i.isEven,
        shortDistanceWarning: i.isOdd,
        // The last sample has no battery level.
        battery: i == tripStart - 1 ? null : _at(BatteryBucket.values, i),
        charging: i.isEven,
        simulated: i.isOdd,
        paramsId: _at(ids, i),
      ),
    for (final (i, r) in StartBlockedReason.values.indexed)
      TripStartBlockedEvent(reason: r, simulated: i.isEven),
    for (var i = 0; i < tripEnd; i++)
      TripEndEvent(
        outcome: _at(TripOutcomeTag.values, i),
        endReason: _at(EndReasonTag.values, i),
        alarmReason: _at(AlarmReasonTag.values, i),
        // -2 .. 11: clamped to 0..3.
        snoozeCount: i - 2,
        mode: _at(AlarmModeTag.values, i),
        vehicleGuess: _at(VehicleTag.values, i),
        duration: _at(DurationBucket.values, i),
        distance: _at(DistanceBucket.values, i),
        simulated: i.isEven,
      ),
    for (final (i, c) in BatteryChoiceTag.values.indexed)
      LowBatteryChoiceEvent(choice: c, simulated: i.isOdd),
    for (final (i, a) in OvershootActionTag.values.indexed)
      OvershootActionEvent(action: a, simulated: i.isOdd),
    for (var i = 0; i < DestKindTag.values.length; i++)
      DestinationSelectedEvent(
        source: _at(DestSourceTag.values, i),
        kind: _at(DestKindTag.values, i),
      ),
    for (var i = 0; i < snapshot; i++)
      PermissionSnapshotEvent(
        location: _at(LocationPermTag.values, i),
        precise: i.isEven,
        locationServices: i.isOdd,
        notifications: _at(TriStateTag.values, i),
        fullScreenIntent: _at(TriStateTag.values, i + 1),
        exactAlarm: _at(TriStateTag.values, i + 2),
        batteryOptIgnored: _at(YesNoNaTag.values, i),
        alarmKit: _at(AlarmKitTag.values, i),
      ),
    for (var i = 0; i < OemTag.values.length; i++)
      BatteryGuideTestEvent(
        oem: _at(OemTag.values, i),
        result: _at(GuideTestResult.values, i),
      ),
  ];
}

/// Exhaustive over the sealed class (TC02): a new event type does not
/// compile until it is listed here (and sampled above).
String eventKind(AnalyticsEvent e) => switch (e) {
  TripStartEvent() => 'trip_start',
  TripStartBlockedEvent() => 'trip_start_blocked',
  TripEndEvent() => 'trip_end',
  LowBatteryChoiceEvent() => 'low_battery_choice',
  OvershootActionEvent() => 'overshoot_action',
  DestinationSelectedEvent() => 'destination_selected',
  PermissionSnapshotEvent() => 'permission_snapshot',
  BatteryGuideTestEvent() => 'battery_guide_test',
};

/// Every enum whose values must all appear in [sampleEvents].
const List<List<WireEnum>> kAllTagEnums = [
  AlarmModeTag.values,
  ThresholdTag.values,
  VehicleTag.values,
  DestSourceTag.values,
  BatteryBucket.values,
  DurationBucket.values,
  DistanceBucket.values,
  StartBlockedReason.values,
  TripOutcomeTag.values,
  EndReasonTag.values,
  AlarmReasonTag.values,
  BatteryChoiceTag.values,
  OvershootActionTag.values,
  DestKindTag.values,
  LocationPermTag.values,
  TriStateTag.values,
  YesNoNaTag.values,
  AlarmKitTag.values,
  OemTag.values,
  GuideTestResult.values,
];
