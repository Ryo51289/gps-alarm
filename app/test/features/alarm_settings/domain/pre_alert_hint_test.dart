// T25 U08: pre-alert subtitle (mirrors T10 §4.6 zones).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/alarm_settings/domain/pre_alert_hint.dart';

TripSettings _s(AlarmModeMsg mode, {int distance = 1000, int time = 15}) =>
    TripSettings.defaults.copyWith(
      mode: mode,
      distanceThresholdM: distance,
      timeThresholdMin: time,
    );

void main() {
  const d = AlarmSettingsParams.defaults;

  test('minutesOf rounds half up', () {
    expect(minutesOf(0), 0);
    expect(minutesOf(29), 0);
    expect(minutesOf(30), 1);
    expect(minutesOf(600), 10);
    expect(minutesOf(1800), 30);
    expect(minutesOf(2430), 41);
  });

  test('U08', () {
    expect(
      preAlertHint(_s(AlarmModeMsg.distance), d),
      const PreAlertAtDistance(5000),
    );
    expect(
      preAlertHint(_s(AlarmModeMsg.distance, distance: 500), d),
      const PreAlertAtDistance(3000),
    );
    expect(
      preAlertHint(_s(AlarmModeMsg.distance, distance: 10000), d),
      const PreAlertAtDistance(50000),
    );
    expect(preAlertHint(_s(AlarmModeMsg.time), d), const PreAlertAtMinutes(30));
    expect(
      preAlertHint(_s(AlarmModeMsg.time, time: 30), d),
      const PreAlertSkipped(30),
    );
    expect(
      preAlertHint(_s(AlarmModeMsg.smart), d),
      const PreAlertAtMinutes(30),
    );
    final longer = AlarmSettingsParams.fromOverrideJson(
      '{"preAlertLeadS":2400}',
    );
    expect(
      preAlertHint(_s(AlarmModeMsg.time, time: 30), longer),
      const PreAlertAtMinutes(40),
    );
  });

  test('time: gap exactly preAlertMinGapS still pre-alerts', () {
    // 1800 - 25 * 60 = 300 >= 300.
    expect(
      preAlertHint(_s(AlarmModeMsg.time, time: 25), d),
      const PreAlertAtMinutes(30),
    );
  });
}
