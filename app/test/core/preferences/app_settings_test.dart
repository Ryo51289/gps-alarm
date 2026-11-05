// T28 S01-S04: display preferences in the store, and the in-memory settings
// controller (sync state, serial latest-wins writes, late load).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/storage/key_value_store.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';

import '../../helpers/fake_key_value_store.dart';

ProviderContainer _container(KeyValueStore kv, {DisplayPreferences? initial}) {
  final c = ProviderContainer.test(
    overrides: [
      keyValueStoreProvider.overrideWithValue(kv),
      if (initial != null)
        initialDisplayPreferencesProvider.overrideWithValue(initial),
    ],
  );
  return c;
}

const AlarmPreferences _a1 = AlarmPreferences(
  soundId: 'bell',
  volumePct: 60,
  rampUp: false,
  vibration: VibrationMsg.medium,
  flash: true,
);

void main() {
  group('S01 loadDisplayPreferences', () {
    test('empty store: defaults (system / system)', () async {
      final p = await PreferencesRepository(FakeKeyValueStore())
          .loadDisplayPreferences();
      expect(p, DisplayPreferences.defaults);
      expect(p.locale, isNull);
      expect(p.themeMode, ThemeMode.system);
      expect(p.nativeTag, isNull);
    });

    test('invalid language falls back alone; theme dark is read', () async {
      final p = await PreferencesRepository(
        FakeKeyValueStore({'display.language': 'xx', 'display.theme': 'dark'}),
      ).loadDisplayPreferences();
      expect(p.language, AppLanguage.system);
      expect(p.theme, AppThemeChoice.dark);
      expect(p.themeMode, ThemeMode.dark);
    });

    test('wrong type or IO error: defaults, never throws', () async {
      final wrong = await PreferencesRepository(
        FakeKeyValueStore({'display.language': 3, 'display.theme': 'light'}),
      ).loadDisplayPreferences();
      expect(wrong.language, AppLanguage.system);
      expect(wrong.theme, AppThemeChoice.light);
      final broken = FakeKeyValueStore()..error = StateError('io');
      expect(
        await PreferencesRepository(broken).loadDisplayPreferences(),
        DisplayPreferences.defaults,
      );
    });

    test('save then load; wire names never change', () async {
      final kv = FakeKeyValueStore();
      final repo = PreferencesRepository(kv);
      await repo.saveDisplayPreferences(
        const DisplayPreferences(
          language: AppLanguage.en,
          theme: AppThemeChoice.light,
        ),
      );
      expect(kv.values, {'display.language': 'en', 'display.theme': 'light'});
      final p = await repo.loadDisplayPreferences();
      expect(p.locale, const Locale('en'));
      expect(p.nativeTag, 'en');
      expect(p.themeMode, ThemeMode.light);
      expect(
        const DisplayPreferences(
          language: AppLanguage.vi,
          theme: AppThemeChoice.system,
        ).nativeTag,
        'vi',
      );
    });
  });

  test('S02 sync state; serial writes, latest wins', () async {
    final kv = SlowKeyValueStore(writeDelay: const Duration(milliseconds: 200));
    final c = _container(kv);
    addTearDown(c.dispose);
    final ctrl = c.read(appSettingsProvider.notifier);
    final a2 = _a1.copyWith(soundId: 'beep', volumePct: 90);

    ctrl
      ..setAlarm(_a1)
      ..setAlarm(a2);
    expect(c.read(appSettingsProvider).alarm, a2);

    await ctrl.flush();
    expect(kv.values['alarm.soundId'], 'beep');
    expect(kv.values['alarm.volumePct'], 90);
    expect(kv.values['alarm.rampUp'], 0);
    expect(kv.values['alarm.vibration'], 'medium');
    expect(kv.values['alarm.flash'], 1);
    // Never two writes at once.
    var open = 0;
    for (final e in kv.log) {
      open += e.startsWith('start') ? 1 : -1;
      expect(open, inInclusiveRange(0, 1), reason: kv.log.join(', '));
    }
    // Both changes arrived before the first write started: one write only.
    expect(kv.log.where((e) => e == 'start alarm.soundId'), hasLength(1));
  });

  test('S02 a change during a write is written after it', () async {
    final kv = SlowKeyValueStore(writeDelay: const Duration(milliseconds: 50));
    final c = _container(kv);
    addTearDown(c.dispose);
    final ctrl = c.read(appSettingsProvider.notifier)..setAlarm(_a1);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    ctrl.setAlarm(_a1.copyWith(volumePct: 35));
    await ctrl.flush();
    expect(kv.values['alarm.volumePct'], 35);
  });

  test('S03 late load keeps what the user changed meanwhile', () async {
    final kv = SlowKeyValueStore()
      ..readGate = Completer<void>()
      ..values.addAll({
        'display.language': 'vi',
        'display.theme': 'dark',
        'alarm.soundId': 'beep',
      });
    final c = _container(kv);
    addTearDown(c.dispose);
    final initial = c.read(appSettingsProvider);
    expect(initial.loaded, isFalse);
    expect(initial.display, DisplayPreferences.defaults);

    c
        .read(appSettingsProvider.notifier)
        .setDisplay(
          const DisplayPreferences(
            language: AppLanguage.en,
            theme: AppThemeChoice.system,
          ),
        );
    kv.readGate!.complete();
    await pumpEventQueue();

    final s = c.read(appSettingsProvider);
    expect(s.loaded, isTrue);
    expect(s.display.language, AppLanguage.en);
    expect(s.display.theme, AppThemeChoice.system);
    // Groups the user did not touch take the stored values.
    expect(s.alarm.soundId, 'beep');
  });

  test('the initial display (main) is used until the load', () async {
    final kv = SlowKeyValueStore()..readGate = Completer<void>();
    const en = DisplayPreferences(
      language: AppLanguage.en,
      theme: AppThemeChoice.dark,
    );
    final c = _container(kv, initial: en);
    addTearDown(c.dispose);
    expect(c.read(appSettingsProvider).display, en);
  });

  test('S04 a failing write: state kept, warning with the type only', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    final kv = FakeKeyValueStore();
    final c = _container(kv);
    addTearDown(c.dispose);
    final ctrl = c.read(appSettingsProvider.notifier);
    await pumpEventQueue();
    kv.error = StateError('disk full /data/user/0 Ga Đồng Hới');
    const s = TripSettings(
      mode: AlarmModeMsg.time,
      distanceThresholdM: 1234,
      timeThresholdMin: 20,
      preAlertEnabled: false,
      alarmStyle: AlarmStyle.headphonesOnly,
      dismissMethod: DismissMethodMsg.math,
    );

    ctrl.setTripDefaults(s);
    await ctrl.flush();

    expect(c.read(appSettingsProvider).tripDefaults, s.normalized());
    final warnings = records.where((r) => r.level == Level.WARNING).toList();
    expect(warnings, hasLength(1));
    expect(warnings.single.message, 'save trip failed: StateError');
    expect(warnings.single.error, isNull);
  });
}
