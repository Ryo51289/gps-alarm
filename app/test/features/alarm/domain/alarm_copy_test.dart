// T27 U03 (reason line, same keys as RingCopy), U04 (minutes), U05 (snooze
// label), U06 (ringingNow / alarmVariant), U05 (snoozeAllowed).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm/domain/alarm_copy.dart';
import 'package:napstop/features/alarm/domain/ring_ui_rules.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../../helpers/fake_core_bridge.dart';

void main() {
  final vi = lookupAppLocalizations(const Locale('vi'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('U04 alarmMinutes = max(1, ceil(etaS / 60))', () {
    expect([-5, 0, 59, 60, 61, 3599, 3600].map(alarmMinutes).toList(), [
      1,
      1,
      1,
      1,
      2,
      60,
      60,
    ]);
  });

  group('U03 alarmReasonText', () {
    String reason(
      AppLocalizations l,
      AlarmReasonMsg? r, {
      String destination = 'Ga Huế',
      int? distanceM,
      int? etaS,
      int? batteryPct,
    }) => alarmReasonText(
      l,
      reason: r,
      destination: destination,
      distanceM: distanceM,
      etaS: etaS,
      batteryPct: batteryPct,
    );

    test('vi literals', () {
      expect(reason(vi, null), 'Sắp tới Ga Huế');
      expect(
        reason(vi, AlarmReasonMsg.distance, distanceM: 1250),
        'Còn khoảng 1,3 km tới Ga Huế',
      );
      expect(
        reason(vi, AlarmReasonMsg.smartTime, etaS: 61),
        'Còn khoảng 2 phút tới Ga Huế',
      );
      expect(
        reason(vi, AlarmReasonMsg.lowBattery, batteryPct: 5),
        'Pin còn 5% — báo sớm để bạn không lỡ trạm',
      );
      expect(
        reason(vi, AlarmReasonMsg.gpsLost, destination: ''),
        startsWith('Mất tín hiệu vị trí — có thể sắp tới nơi đến'),
      );
    });

    for (final l in [vi, en]) {
      test('every reason maps to its key (${l.localeName})', () {
        const d = 'Ga Huế';
        final dist = alarmDistance(l, 850);
        final expected = <AlarmReasonMsg?, (String, String)>{
          null: (l.notifAlarmTitle(d), l.notifAlarmTitle(d)),
          AlarmReasonMsg.distance: (
            l.alarmReasonDistance(dist, d),
            l.notifAlarmTitle(d),
          ),
          AlarmReasonMsg.smartDistance: (
            l.alarmReasonDistance(dist, d),
            l.notifAlarmTitle(d),
          ),
          AlarmReasonMsg.smartSlowDistance: (
            l.alarmReasonDistance(dist, d),
            l.notifAlarmTitle(d),
          ),
          AlarmReasonMsg.time: (
            l.alarmReasonTime('3', d),
            l.notifAlarmTitle(d),
          ),
          AlarmReasonMsg.smartTime: (
            l.alarmReasonTime('3', d),
            l.notifAlarmTitle(d),
          ),
          AlarmReasonMsg.gpsLost: (
            l.alarmReasonGpsLost(d),
            l.alarmReasonGpsLost(d),
          ),
          AlarmReasonMsg.lowBattery: (
            l.alarmReasonLowBattery('4'),
            l.notifAlarmTitle(d),
          ),
          AlarmReasonMsg.passedClosest: (
            l.alarmReasonPassedClosest(d),
            l.alarmReasonPassedClosest(d),
          ),
          AlarmReasonMsg.overshoot: (
            l.alarmReasonOvershoot(d),
            l.alarmReasonOvershoot(d),
          ),
          AlarmReasonMsg.snoozeEnd: (
            l.alarmReasonSnoozeEnd(d),
            l.alarmReasonSnoozeEnd(d),
          ),
          AlarmReasonMsg.timeout: (
            l.alarmReasonTimeout(d),
            l.alarmReasonTimeout(d),
          ),
          AlarmReasonMsg.fallback: (
            l.alarmReasonFallback(d),
            l.alarmReasonFallback(d),
          ),
          AlarmReasonMsg.fallbackMissed: (
            l.alarmReasonFallbackMissed(d),
            l.alarmReasonFallbackMissed(d),
          ),
        };
        expect(expected.length, AlarmReasonMsg.values.length + 1);
        for (final MapEntry(key: r, value: (withData, without))
            in expected.entries) {
          expect(
            reason(l, r, distanceM: 850, etaS: 150, batteryPct: 4),
            withData,
            reason: '$r with data',
          );
          expect(reason(l, r), without, reason: '$r without data');
        }
        // Empty name → "nơi đến" / its English text.
        expect(
          reason(l, AlarmReasonMsg.timeout, destination: ''),
          l.alarmReasonTimeout(l.notifDestinationUnknown),
        );
      });
    }
  });

  test('U05 snoozeLabel', () {
    expect(snoozeLabel(vi, 60), 'Báo lại sau 1 phút');
    expect(snoozeLabel(vi, 120), 'Báo lại sau 2 phút');
    expect(snoozeLabel(vi, 90), 'Báo lại sau 90 giây');
    expect(snoozeLabel(vi, 0), 'Báo lại sau 0 giây');
    expect(snoozeLabel(en, 60), en.alarmSnoozeMinutes('1'));
  });

  test('overshoot line', () {
    expect(alarmPastText(vi, 1234), 'Đã qua 1,2 km');
    expect(alarmPastText(vi, 1300), 'Đã qua 1,3 km');
    expect(alarmPastText(vi, 850), 'Đã qua 850 m');
  });

  TripStateMsg state({
    TripPhaseMsg phase = TripPhaseMsg.alarming,
    bool ringing = true,
    int snoozeCount = 0,
    int? overshootPastM,
    AlarmReasonMsg? reason,
  }) => tripState(phase: phase)
    ..alarmRinging = ringing
    ..snoozeCount = snoozeCount
    ..overshootPastM = overshootPastM
    ..alarmReason = reason;

  test('U06 ringingNow, alarmVariant', () {
    expect(ringingNow(null), isFalse);
    expect(ringingNow(state()), isTrue);
    expect(ringingNow(state(phase: TripPhaseMsg.overshot)), isTrue);
    expect(ringingNow(state(ringing: false)), isFalse);
    for (final p in [
      TripPhaseMsg.acquiring,
      TripPhaseMsg.tracking,
      TripPhaseMsg.snoozed,
      TripPhaseMsg.ended,
    ]) {
      expect(ringingNow(state(phase: p)), isFalse, reason: '$p');
    }

    expect(alarmVariant(state()), AlarmVariant.arriving);
    expect(
      alarmVariant(state(phase: TripPhaseMsg.overshot)),
      AlarmVariant.overshoot,
    );
    expect(alarmVariant(state(overshootPastM: 0)), AlarmVariant.overshoot);
    expect(
      alarmVariant(state(reason: AlarmReasonMsg.overshoot)),
      AlarmVariant.overshoot,
    );
    expect(
      alarmVariant(state(reason: AlarmReasonMsg.passedClosest)),
      AlarmVariant.arriving,
    );
  });

  test('U05 snoozeAllowed', () {
    final defaults = AlarmSettingsParams.fromOverrideJson(null);
    final none = AlarmSettingsParams.fromOverrideJson('{"maxSnoozes":0}');
    final two = AlarmSettingsParams.fromOverrideJson('{"maxSnoozes":2}');
    expect(defaults.maxSnoozes, 1);
    expect(snoozeAllowed(state(), defaults), isTrue);
    expect(snoozeAllowed(state(snoozeCount: 1), defaults), isFalse);
    expect(snoozeAllowed(state(), none), isFalse);
    expect(snoozeAllowed(state(snoozeCount: 1), two), isTrue);
    expect(snoozeAllowed(state(snoozeCount: 2), two), isFalse);
    expect(snoozeAllowed(state(phase: TripPhaseMsg.overshot), two), isFalse);
    expect(snoozeAllowed(state(phase: TripPhaseMsg.snoozed), two), isFalse);
    expect(snoozeAllowed(state(overshootPastM: 10), two), isFalse);
    expect(
      snoozeAllowed(state(reason: AlarmReasonMsg.overshoot), two),
      isFalse,
    );
    expect(AlarmSettingsParams.fromOverrideJson('{"snoozeS":90}').snoozeS, 90);
  });
}
