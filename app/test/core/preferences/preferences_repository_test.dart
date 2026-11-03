// T25 U10, U11, U21: trip settings and the preferences repository.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

import '../../helpers/fake_key_value_store.dart';

void main() {
  test('U10 normalizeDistanceM', () {
    final inputs = [0, 149, 150, 1234, 1250, 10049, 99999, -5];
    final expected = [200, 200, 200, 1200, 1300, 10000, 10000, 200];
    expect(inputs.map(normalizeDistanceM).toList(), expected);
  });

  test('U10 normalizeTimeMin: nearest chip, tie to the larger', () {
    final inputs = [1, 7, 8, 12, 13, 25, 26, 60, 15, -3];
    final expected = [5, 5, 10, 10, 15, 30, 30, 30, 15, 5];
    expect(inputs.map(normalizeTimeMin).toList(), expected);
  });

  test('U11 defaults: smart, 1 km, 15 min, pre-alert, ring, swipe', () {
    const d = TripSettings.defaults;
    expect(d.mode, AlarmModeMsg.smart);
    expect(d.distanceThresholdM, 1000);
    expect(d.timeThresholdMin, 15);
    expect(d.preAlertEnabled, isTrue);
    expect(d.alarmStyle, AlarmStyle.ringAndVibrate);
    expect(d.dismissMethod, DismissMethodMsg.swipe);
    expect(d.normalized(), d);
  });

  test('withChoice keeps the other threshold; toAlarmChoice has both', () {
    final s = TripSettings.defaults.withChoice(
      const TripAlarmChoice(
        mode: AlarmModeMsg.time,
        timeThresholdMin: 25,
        preAlertEnabled: false,
      ),
    );
    expect(s.mode, AlarmModeMsg.time);
    expect(s.timeThresholdMin, 30);
    expect(s.distanceThresholdM, 1000);
    expect(s.preAlertEnabled, isFalse);
    final choice = s.toAlarmChoice();
    expect(choice.isValid, isTrue);
    expect(choice.distanceThresholdM, 1000);
    expect(choice.timeThresholdMin, 30);
  });

  group('U21 PreferencesRepository', () {
    test('empty store: defaults', () async {
      final repo = PreferencesRepository(FakeKeyValueStore());
      expect(await repo.loadAlarmPreferences(), AlarmPreferences.defaults);
      expect(await repo.loadTripDefaults(), TripSettings.defaults);
    });

    test('store errors: defaults, never throws', () async {
      final kv = FakeKeyValueStore()..error = StateError('io');
      final repo = PreferencesRepository(kv);
      expect(await repo.loadAlarmPreferences(), AlarmPreferences.defaults);
      expect(await repo.loadTripDefaults(), TripSettings.defaults);
    });

    test('each broken key falls back on its own', () async {
      final kv = FakeKeyValueStore({
        PreferenceKeys.alarmSoundId: '',
        PreferenceKeys.alarmVolumePct: 20,
        PreferenceKeys.alarmRampUp: 0,
        PreferenceKeys.alarmVibration: 'off',
        PreferenceKeys.alarmFlash: 2,
        PreferenceKeys.tripMode: 'xyz',
        PreferenceKeys.tripDistanceM: 1234,
        PreferenceKeys.tripTimeMin: 'twenty',
        PreferenceKeys.tripPreAlert: 0,
        PreferenceKeys.tripAlarmStyle: 'loud',
        PreferenceKeys.tripDismiss: 'math',
      });
      final repo = PreferencesRepository(kv);
      final a = await repo.loadAlarmPreferences();
      expect(a.soundId, kDefaultAlarmSoundId);
      expect(a.volumePct, 100);
      expect(a.rampUp, isFalse);
      expect(a.vibration, VibrationMsg.strong);
      expect(a.flash, isFalse);
      final t = await repo.loadTripDefaults();
      expect(t.mode, AlarmModeMsg.smart);
      expect(t.distanceThresholdM, 1200);
      expect(t.timeThresholdMin, 15);
      expect(t.preAlertEnabled, isFalse);
      expect(t.alarmStyle, AlarmStyle.ringAndVibrate);
      expect(t.dismissMethod, DismissMethodMsg.math);
    });

    test('sound id longer than 64 falls back', () async {
      final repo = PreferencesRepository(
        FakeKeyValueStore({PreferenceKeys.alarmSoundId: 'x' * 65}),
      );
      expect((await repo.loadAlarmPreferences()).soundId, 'default');
    });

    test('round trip', () async {
      final repo = PreferencesRepository(FakeKeyValueStore());
      const alarm = AlarmPreferences(
        soundId: 'bell',
        volumePct: 80,
        rampUp: false,
        vibration: VibrationMsg.medium,
        flash: true,
      );
      const trip = TripSettings(
        mode: AlarmModeMsg.distance,
        distanceThresholdM: 2500,
        timeThresholdMin: 20,
        preAlertEnabled: false,
        alarmStyle: AlarmStyle.headphonesOnly,
        dismissMethod: DismissMethodMsg.shake,
      );
      await repo.saveAlarmPreferences(alarm);
      await repo.saveTripDefaults(trip);
      expect(await repo.loadAlarmPreferences(), alarm);
      expect(await repo.loadTripDefaults(), trip);
    });
  });
}
