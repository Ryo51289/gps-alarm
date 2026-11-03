// T29 TC05, TC06: AppAnalytics drops bad events, honours consent, never
// throws outside strict mode.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/telemetry/analytics/analytics_event.dart';
import 'package:napstop/core/telemetry/analytics/app_analytics.dart';
import 'package:napstop/core/telemetry/crash/crash_reporter.dart';

import '../telemetry_fakes.dart';

const _start = TripStartEvent(
  mode: AlarmModeTag.distance,
  threshold: ThresholdTag.d1000,
  vehicleHint: VehicleTag.train,
  destSource: DestSourceTag.station,
  preAlert: true,
  shortDistanceWarning: false,
  battery: BatteryBucket.le50,
  charging: false,
  simulated: false,
  paramsId: 'default',
);

/// A sample with a wrong value (as a buggy future change could produce).
const _bad = TripStartEvent(
  mode: AlarmModeTag.distance,
  threshold: ThresholdTag.d1000,
  vehicleHint: VehicleTag.train,
  destSource: DestSourceTag.station,
  preAlert: true,
  shortDistanceWarning: false,
  battery: BatteryBucket.le50,
  charging: false,
  simulated: false,
  paramsId: 'Ga Huế 16.4637',
);

void main() {
  late RecordingAnalyticsSink sink;
  late RecordingCrashSink crashSink;
  var enabled = true;

  AppAnalytics analytics({bool strict = false}) {
    final (crash, cs) = recordingCrash();
    crashSink = cs;
    return AppAnalytics(
      sink: sink,
      crash: crash,
      isEnabled: () => enabled,
      strict: strict,
    );
  }

  setUp(() {
    sink = RecordingAnalyticsSink();
    enabled = true;
  });

  test('TC05 a guard violation: dropped, one non-fatal, names only', () async {
    analytics().log(_bad);
    await pumpEventQueue();
    expect(sink.events, isEmpty);
    expect(crashSink.errors, hasLength(1));
    final e = crashSink.errors.single;
    expect(e.reason, NonFatalReason.analyticsGuardViolation.name);
    expect(e.fatal, isFalse);
    final text = e.error.toString();
    expect(text, contains('trip_start'));
    expect(text, contains('params_id'));
    expect(text, isNot(contains('Huế')));
    expect(text, isNot(contains('16.4637')));
  });

  test('TC05 strict: the violation throws, nothing is sent', () {
    expect(() => analytics(strict: true).log(_bad), throwsStateError);
    expect(sink.events, isEmpty);
  });

  test('TC05 strict still checks with collection off', () {
    enabled = false;
    expect(() => analytics(strict: true).log(_bad), throwsStateError);
  });

  test('TC06 collection off: the sink is not called', () async {
    enabled = false;
    analytics().log(_start);
    await pumpEventQueue();
    expect(sink.calls, isEmpty);
  });

  test('TC06 collection on: name and parameters as built', () async {
    analytics().log(_start);
    await pumpEventQueue();
    expect(sink.events.single.$1, 'trip_start');
    expect(sink.events.single.$2, _start.toParameters());
  });

  test('a failing sink or isEnabled never throws', () async {
    sink.logError = StateError('offline');
    analytics().log(_start);
    await pumpEventQueue();
    final (crash, _) = recordingCrash();
    AppAnalytics(
      sink: sink,
      crash: crash,
      isEnabled: () => throw StateError('x'),
      strict: false,
    ).log(_start);
    await pumpEventQueue();
  });

  test('unknown battery: the parameter is left out', () {
    const e = TripStartEvent(
      mode: AlarmModeTag.smart,
      threshold: ThresholdTag.smart,
      vehicleHint: VehicleTag.unknown,
      destSource: DestSourceTag.mapPin,
      preAlert: false,
      shortDistanceWarning: false,
      battery: null,
      charging: false,
      simulated: true,
      paramsId: 'invalid',
    );
    expect(e.toParameters().containsKey('battery'), isFalse);
    expect(e.toParameters()['simulated'], 1);
  });
}
