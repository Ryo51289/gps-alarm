// T26 U01-U06: pure formatting of screen 4.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/tracking/domain/tracking_format.dart';

import '../tracking_fixtures.dart';

void main() {
  test('U01 formatTripDistance vi / en', () {
    const m = FormattedDistance.new;
    final cases = <int, (FormattedDistance, FormattedDistance)>{
      0: (m('0', isKm: false), m('0', isKm: false)),
      4: (m('0', isKm: false), m('0', isKm: false)),
      5: (m('10', isKm: false), m('10', isKm: false)),
      849: (m('850', isKm: false), m('850', isKm: false)),
      994: (m('990', isKm: false), m('990', isKm: false)),
      995: (m('1', isKm: true), m('1', isKm: true)),
      1000: (m('1', isKm: true), m('1', isKm: true)),
      1049: (m('1', isKm: true), m('1', isKm: true)),
      1050: (m('1,1', isKm: true), m('1.1', isKm: true)),
      12340: (m('12,3', isKm: true), m('12.3', isKm: true)),
      99949: (m('99,9', isKm: true), m('99.9', isKm: true)),
      99950: (m('100', isKm: true), m('100', isKm: true)),
      152400: (m('152', isKm: true), m('152', isKm: true)),
      1726000: (m('1.726', isKm: true), m('1,726', isKm: true)),
      -20: (m('0', isKm: false), m('0', isKm: false)),
    };
    for (final MapEntry(key: meters, value: (vi, en)) in cases.entries) {
      expect(formatTripDistance(meters, 'vi'), vi, reason: 'vi $meters');
      expect(formatTripDistance(meters, 'en'), en, reason: 'en $meters');
    }
  });

  test('U02 etaMinutesOf, splitHm', () {
    expect([0, 1, 59, 60, 61, 7800].map(etaMinutesOf), [1, 1, 1, 1, 2, 130]);
    expect(splitHm(45), (hours: 0, minutes: 45));
    expect(splitHm(60), (hours: 1, minutes: 0));
    expect(splitHm(130), (hours: 2, minutes: 10));
  });

  test('U03 formatCountdown', () {
    expect([-5, 0, 1, 44001, 45000, 61000, 600000].map(formatCountdown), [
      '0:00',
      '0:00',
      '0:01',
      '0:45',
      '0:45',
      '1:01',
      '10:00',
    ]);
    expect(countdownSeconds(44001), 45);
    expect(countdownSeconds(-1), 0);
  });

  test('U04 earlierAlarmPct', () {
    const d = AlarmSettingsParams.defaults;
    expect([null, 40, 15, 13, 6, 5, 3].map((p) => earlierAlarmPct(p, d)), [
      15,
      15,
      14,
      12,
      5,
      5,
      5,
    ]);
    final o = AlarmSettingsParams.fromOverrideJson(
      '{"lowBatteryAlarmPct":8,"lowBatteryEarlierPct":20}',
    );
    expect(earlierAlarmPct(12, o), 11);
  });

  test('U05 alarmStyleOf', () {
    expect(alarmStyleOf(alarmMsg(volume: 0)), AlarmStyleKind.vibrateOnly);
    expect(
      alarmStyleOf(alarmMsg(volume: 0, preferHeadphones: true)),
      AlarmStyleKind.vibrateOnly,
    );
    expect(
      alarmStyleOf(alarmMsg(preferHeadphones: true)),
      AlarmStyleKind.headphonesOnly,
    );
    expect(alarmStyleOf(alarmMsg()), AlarmStyleKind.ring);
  });

  group('U06 snoozeRemainingMs', () {
    const now = kAtMs + 500000;
    test('real: until − now', () {
      final t = tracked(
        state: stateMsg(
          phase: TripPhaseMsg.snoozed,
          snoozeUntilMs: now + 45000,
        ),
      );
      expect(snoozeRemainingMs(t, now), 45000);
      expect(snoozeRemainingMs(t, now + 50000), 0, reason: 'past: 0');
    });

    test('simulated: virtual clock, real time since received', () {
      final t = tracked(
        simulation: SimulationMsg(traceAsset: 'x', speedFactor: 60),
        state: stateMsg(
          atMs: 10000000,
          phase: TripPhaseMsg.snoozed,
          snoozeUntilMs: 10060000,
        ),
        receivedAtMs: now - 15000,
      );
      expect(snoozeRemainingMs(t, now), 45000);
      expect(snoozeRemainingMs(t, now + 60000), 0);
    });

    test('no snoozeUntilMs: null', () {
      final t = tracked(state: stateMsg(phase: TripPhaseMsg.snoozed));
      expect(snoozeRemainingMs(t, now), isNull);
    });
  });
}
