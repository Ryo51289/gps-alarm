// T25 §3.2/§3.3 decisions: style hint, short distance, battery, muted alarm,
// initial settings; U18 permission-missing details.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_params.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

import '../../../helpers/fake_core_bridge.dart';

void main() {
  const d = AlarmSettingsParams.defaults;

  test('ringsInSilent: unknown, Android, iOS 25/26 with AlarmKit', () {
    expect(ringsInSilent(null, null), isTrue);
    expect(ringsInSilent(androidPermissions(), androidDevice()), isTrue);
    expect(ringsInSilent(iosPermissions(), iosDevice(major: 25)), isFalse);
    expect(ringsInSilent(iosPermissions(), iosDevice()), isTrue);
    expect(
      ringsInSilent(
        iosPermissions(alarmKit: PermissionStateMsg.denied),
        iosDevice(),
      ),
      isFalse,
    );
  });

  test('alarmStyleHint', () {
    expect(
      alarmStyleHint(
        AlarmStyle.ringAndVibrate,
        ringsInSilent: true,
        rampUp: true,
      ),
      AlarmStyleHint.ring,
    );
    expect(
      alarmStyleHint(
        AlarmStyle.ringAndVibrate,
        ringsInSilent: true,
        rampUp: false,
      ),
      AlarmStyleHint.ringNoRamp,
    );
    expect(
      alarmStyleHint(
        AlarmStyle.ringAndVibrate,
        ringsInSilent: false,
        rampUp: true,
      ),
      AlarmStyleHint.ringNoSilent,
    );
    expect(
      alarmStyleHint(
        AlarmStyle.vibrateOnly,
        ringsInSilent: false,
        rampUp: true,
      ),
      AlarmStyleHint.vibrate,
    );
    expect(
      alarmStyleHint(
        AlarmStyle.headphonesOnly,
        ringsInSilent: false,
        rampUp: true,
      ),
      AlarmStyleHint.headphones,
    );
  });

  test('shortDistanceInfo: distance mode only, examples of T25 §3.3', () {
    final dist = TripSettings.defaults.copyWith(mode: AlarmModeMsg.distance);
    expect(
      shortDistanceInfo(dist, VehicleKindMsg.train, d),
      const ShortDistanceInfo(
        vehicle: VehicleKindMsg.train,
        speedKmh: 55,
        thresholdM: 1000,
        leadS: 65,
      ),
    );
    expect(
      shortDistanceInfo(
        dist.copyWith(distanceThresholdM: 3900),
        VehicleKindMsg.coach,
        d,
      )!.leadS,
      234,
    );
    expect(
      shortDistanceInfo(
        dist.copyWith(distanceThresholdM: 1300),
        VehicleKindMsg.bus,
        d,
      )!.leadS,
      234,
    );
    expect(
      shortDistanceInfo(TripSettings.defaults, VehicleKindMsg.train, d),
      isNull,
    );
    expect(
      shortDistanceInfo(
        dist.copyWith(distanceThresholdM: 5000),
        VehicleKindMsg.train,
        d,
      ),
      isNull,
    );
  });

  test('lowBatteryWarningPct (T10 §4.9)', () {
    expect(lowBatteryWarningPct(deviceStatusMsg(batteryPct: 5), d), 5);
    expect(
      lowBatteryWarningPct(deviceStatusMsg(batteryPct: 5, charging: true), d),
      isNull,
    );
    expect(
      lowBatteryWarningPct(deviceStatusMsg(batteryPct: 5, charging: null), d),
      5,
    );
    expect(lowBatteryWarningPct(deviceStatusMsg(batteryPct: 6), d), isNull);
    expect(lowBatteryWarningPct(deviceStatusMsg(batteryPct: null), d), isNull);
    expect(lowBatteryWarningPct(null, d), isNull);
    final ten = AlarmSettingsParams.fromOverrideJson(
      '{"lowBatteryAlarmPct":10}',
    );
    expect(lowBatteryWarningPct(deviceStatusMsg(batteryPct: 8), ten), 8);
  });

  test('alarmMayBeSilenced: muted, volume 0, DND none / priority', () {
    expect(alarmMayBeSilenced(null), isFalse);
    expect(alarmMayBeSilenced(deviceStatusMsg()), isFalse);
    // T14.1 O1: "Tắt hoàn toàn" mutes the alarm stream.
    expect(
      alarmMayBeSilenced(
        deviceStatusMsg(alarmMuted: true, alarmVolumePct: null),
      ),
      isTrue,
    );
    expect(alarmMayBeSilenced(deviceStatusMsg(alarmVolumePct: 0)), isTrue);
    expect(
      alarmMayBeSilenced(
        deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.none),
      ),
      isTrue,
    );
    expect(
      alarmMayBeSilenced(
        deviceStatusMsg(
          interruptionFilter: InterruptionFilterMsg.priority,
          priorityAllowsAlarms: false,
        ),
      ),
      isTrue,
    );
    expect(
      alarmMayBeSilenced(
        deviceStatusMsg(
          interruptionFilter: InterruptionFilterMsg.priority,
          priorityAllowsAlarms: true,
        ),
      ),
      isFalse,
    );
    expect(
      alarmMayBeSilenced(
        deviceStatusMsg(interruptionFilter: InterruptionFilterMsg.alarms),
      ),
      isFalse,
    );
    // iOS: nothing known.
    expect(
      alarmMayBeSilenced(
        DeviceStatusMsg(
          batteryPct: 50,
          interruptionFilter: InterruptionFilterMsg.unknown,
        ),
      ),
      isFalse,
    );
  });

  test('initialTripSettings: preset > draft choice > defaults', () {
    const stored = TripSettings(
      mode: AlarmModeMsg.distance,
      distanceThresholdM: 2000,
      timeThresholdMin: 10,
      preAlertEnabled: false,
      alarmStyle: AlarmStyle.vibrateOnly,
      dismissMethod: DismissMethodMsg.math,
    );
    expect(initialTripSettings(defaults: stored), stored);
    final fromChoice = initialTripSettings(
      defaults: stored,
      choice: const TripAlarmChoice(
        mode: AlarmModeMsg.time,
        timeThresholdMin: 25,
        preAlertEnabled: true,
      ),
    );
    expect(fromChoice.mode, AlarmModeMsg.time);
    expect(fromChoice.timeThresholdMin, 30);
    expect(fromChoice.distanceThresholdM, 2000);
    expect(fromChoice.preAlertEnabled, isTrue);
    expect(fromChoice.alarmStyle, AlarmStyle.vibrateOnly);
    final preset = TripSettings.defaults.copyWith(distanceThresholdM: 1234);
    expect(
      initialTripSettings(
        defaults: stored,
        preset: preset,
        choice: const TripAlarmChoice(
          mode: AlarmModeMsg.time,
          timeThresholdMin: 5,
          preAlertEnabled: true,
        ),
      ),
      preset.normalized(),
    );
  });

  test('U18 requirementsFromDetails', () {
    expect(requirementsFromDetails(['precise', 'alarmChannel']), [
      StartRequirement.precise,
      StartRequirement.alarmChannel,
    ]);
    expect(requirementsFromDetails(['location', 'locationServices']), [
      StartRequirement.location,
      StartRequirement.locationServices,
    ]);
    expect(requirementsFromDetails(['x']), isNull);
    expect(requirementsFromDetails(['precise', 'x']), isNull);
    expect(requirementsFromDetails(<Object?>[]), isNull);
    expect(requirementsFromDetails(null), isNull);
    expect(requirementsFromDetails('precise'), isNull);
  });
}
