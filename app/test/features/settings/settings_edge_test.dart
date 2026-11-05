// Tester (T28): edge and reverse cases of screen 12 beyond S01-S20/SM04-SM07:
// - rapid language changes: the latest choice wins in memory, on disk, on
//   the native side (last setAppLocale) and after a restart;
// - settings changed during a running trip never touch that trip, and the
//   next trip (also after an app restart, also via "Đặt lại") gets them;
// - holding the logo for less than 3 s never opens the simulation, even
//   repeatedly; a drag (scroll) never opens it either.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/preferences_repository.dart';
import 'package:napstop/core/storage/shared_preferences_key_value_store.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/data/alarm_settings_providers.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';
import 'package:napstop/features/simulation/data/sim_providers.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import '../../helpers/fake_key_value_store.dart';
import '../../helpers/trip_fixtures.dart';
import '../alarm_settings/helpers/alarm_settings_fakes.dart';

const Size _tall = Size(390, 3200);

final SimTraceCatalog _catalog = parseSimTraceCatalog(
  File('assets/sim/catalog.json').readAsStringSync(),
);

const TripDraft _draft = TripDraft(
  destination: kGaDongHoi,
  source: DestinationSource.station,
);

Future<AppHarness> _pump(
  WidgetTester tester, {
  FakeCoreBridge? bridge,
  FakeKeyValueStore? kv,
  bool useApp = false,
  String initialLocation = AppRoutes.settings,
  Future<void> Function(ProviderContainer c)? seed,
  List<Override> overrides = const [],
}) => pumpAppHarness(
  tester,
  bridge: bridge,
  keyValueStore: kv,
  size: _tall,
  initialLocation: initialLocation,
  useApp: useApp,
  seed: seed,
  overrides: [
    appVersionProvider.overrideWith(
      (ref) => Future.value((version: '0.1.0', build: '1')),
    ),
    simTraceCatalogProvider.overrideWith((ref) => Future.value(_catalog)),
    engineParamsReaderProvider.overrideWithValue(FakeEngineParamsReader()),
    tripStartReporterProvider.overrideWithValue(RecordingReporter()),
    tripIdGeneratorProvider.overrideWithValue(() => 'trip-new'),
    ...overrides,
  ],
);

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Finder _switchOf(String title) => find.descendant(
  of: find.ancestor(of: find.text(title), matching: find.byType(NapSwitchRow)),
  matching: find.byType(Switch),
);

Future<void> _flush(AppHarness h) =>
    h.read(appSettingsProvider.notifier).flush();

const String _simTitle = 'Chế độ giả lập (demo)';

/// Calls that would change a running trip.
const Set<String> _tripMutations = {
  'startTrip',
  'stopTrip',
  'setBatteryChoice',
  'dismiss',
  'snooze',
};

void main() {
  group('rapid language changes: the latest wins', () {
    test('controller: 6 changes in a row with a slow store', () async {
      final kv = SlowKeyValueStore(
        writeDelay: const Duration(milliseconds: 30),
      );
      final c = ProviderContainer.test(
        overrides: [keyValueStoreProvider.overrideWithValue(kv)],
      );
      final ctl = c.read(appSettingsProvider.notifier);
      await ctl.flush();
      const seq = [
        AppLanguage.en,
        AppLanguage.vi,
        AppLanguage.system,
        AppLanguage.en,
        AppLanguage.system,
        AppLanguage.vi,
      ];
      for (final l in seq) {
        ctl.setDisplay(
          DisplayPreferences(language: l, theme: AppThemeChoice.system),
        );
        expect(c.read(appSettingsProvider).display.language, l);
        // Some changes land while a write is running.
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await ctl.flush();
      expect(kv.values['display.language'], 'vi');
      // Writes never interleave: start/end pairs alternate.
      final lang = kv.log.where((e) => e.endsWith('display.language'));
      var open = false;
      for (final e in lang) {
        expect(e.startsWith('start'), !open, reason: '$lang');
        open = !open;
      }
      // The next app start reads the last choice.
      final again = await PreferencesRepository(kv).loadDisplayPreferences();
      expect(again.language, AppLanguage.vi);
    });

    testWidgets('app: English, Tiếng Việt, system, English tapped quickly → '
        'English everywhere; last native call en; stored en', (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('vi');
      tester.platformDispatcher.localesTestValue = const [Locale('vi')];
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final kv = FakeKeyValueStore();
      final h = await _pump(tester, kv: kv, useApp: true);
      Future<void> quick(String label) async {
        final f = find.text(label);
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pump(); // one frame, no settle
      }

      await quick('English');
      await quick('Tiếng Việt');
      await quick('Theo ngôn ngữ máy');
      await quick('English');
      await tester.pumpAndSettle();
      await _flush(h);
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Cài đặt chung'), findsNothing);
      expect(h.bridge.setAppLocaleCalls.last, 'en');
      expect(kv.values['display.language'], 'en');
      // The tag sequence follows the choices (no stale value after en).
      expect(h.bridge.setAppLocaleCalls.skip(1).toList(), [
        'en',
        'vi',
        null,
        'en',
      ]);
    });
  });

  group('settings apply to new trips only', () {
    testWidgets('changes during a running trip: no call touches that trip; '
        'after an app restart screen 3 starts the next trip with them', (
      tester,
    ) async {
      final kv = FakeKeyValueStore();
      final running = FakeCoreBridge(active: activeTrip(tripId: 'run'));
      final h1 = await _pump(tester, bridge: running, kv: kv);
      expect(
        find.text(
          'Chuyến đang chạy giữ cài đặt cũ. Thay đổi áp dụng từ chuyến sau.',
        ),
        findsOneWidget,
      );
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(40);
      slider.onChangeEnd!(40);
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Nhẹ'));
      await _tap(tester, _switchOf('Tăng dần âm lượng'));
      await _tap(tester, find.text('Chế độ báo'));
      await _tap(tester, find.text('Khoảng cách'));
      await _tap(tester, find.byTooltip('Quay lại'));
      await _flush(h1);
      expect(running.calls.toSet().intersection(_tripMutations), isEmpty);
      expect(running.startTripCalls, isEmpty);

      // Restart: a new app over the same store, no trip running anymore.
      final h2 = await _pump(tester, kv: kv);
      unawaited(h2.router.push<void>(AppRoutes.alarmSettings, extra: _draft));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Bắt đầu theo dõi'));
      final config = h2.bridge.startTripCalls.single.config;
      expect(config.alarm.volume, closeTo(0.4, 1e-9));
      expect(config.alarm.vibration, VibrationMsg.light);
      expect(config.alarm.rampUp, isFalse);
      expect(config.mode, AlarmModeMsg.distance);
    });

    testWidgets('screen 3 opened twice picks the newest defaults each time', (
      tester,
    ) async {
      final h = await _pump(tester);
      unawaited(h.router.push<void>(AppRoutes.alarmSettings, extra: _draft));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NapChip>(find.widgetWithText(NapChip, 'Vuốt hết thanh'))
            .selected,
        isTrue,
      );
      h.router.pop();
      await tester.pumpAndSettle();
      final ctl = h.read(appSettingsProvider.notifier)
        ..setTripDefaults(
          h
              .read(appSettingsProvider)
              .tripDefaults
              .copyWith(dismissMethod: DismissMethodMsg.math),
        );
      await ctl.flush();
      unawaited(h.router.push<void>(AppRoutes.alarmSettings, extra: _draft));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NapChip>(find.widgetWithText(NapChip, 'Giải phép tính'))
            .selected,
        isTrue,
      );
      await _tap(tester, find.text('Bắt đầu theo dõi'));
      expect(
        h.bridge.startTripCalls.single.config.alarm.dismissMethod,
        DismissMethodMsg.math,
      );
    });

    testWidgets('"Đặt lại" from history keeps the trip mode but takes the '
        'new sound/dismiss defaults of screen 12', (tester) async {
      const d2 = TripAlarmChoice(
        mode: AlarmModeMsg.distance,
        distanceThresholdM: 2000,
        preAlertEnabled: false,
      );
      final h = await _pump(
        tester,
        seed: (c) async {
          final repo = c.read(tripsRepositoryProvider);
          await repo.insertStarted(
            sampleRecord(
              id: 'old',
              alarm: d2,
              startedAtMs: DateTime(2026, 11, 1, 8).millisecondsSinceEpoch,
            ),
          );
          await repo.applyFinished(finishedTrip('old'));
        },
      );
      final ctl = h.read(appSettingsProvider.notifier)
        ..setAlarm(h.read(appSettingsProvider).alarm.copyWith(soundId: 'beep'))
        ..setTripDefaults(
          h
              .read(appSettingsProvider)
              .tripDefaults
              .copyWith(dismissMethod: DismissMethodMsg.math),
        );
      await ctl.flush();
      h.router.go(AppRoutes.history);
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Đặt lại chuyến này'));
      expect(h.location, AppRoutes.alarmSettings);
      await _tap(tester, find.text('Bắt đầu theo dõi'));
      final config = h.bridge.startTripCalls.single.config;
      expect(config.mode, AlarmModeMsg.distance);
      expect(config.distanceThresholdM, 2000);
      expect(config.preAlertEnabled, isFalse);
      expect(config.alarm.soundId, 'beep');
      expect(config.alarm.dismissMethod, DismissMethodMsg.math);
    });
  });

  group('logo hold shorter than 3 s never opens the simulation', () {
    late List<MethodCall> platform;

    Future<void> hold(WidgetTester tester, Duration d, {Offset? move}) async {
      final logo = find.text('NapStop');
      await tester.ensureVisible(logo);
      await tester.pumpAndSettle();
      final g = await tester.startGesture(tester.getCenter(logo));
      if (move != null) {
        await tester.pump(const Duration(milliseconds: 100));
        await g.moveBy(move);
        await tester.pump(d - const Duration(milliseconds: 100));
      } else {
        await tester.pump(d);
      }
      await g.up();
      await tester.pumpAndSettle();
    }

    setUp(() => platform = []);

    Future<void> mockPlatform(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          platform.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    int haptics() => platform
        .where(
          (c) =>
              c.method == 'HapticFeedback.vibrate' &&
              c.arguments == 'HapticFeedbackType.heavyImpact',
        )
        .length;

    testWidgets('tap, 0.5 s, 1 s, 2 s, 2.5 s, 2.99 s: no sheet, no haptic', (
      tester,
    ) async {
      await mockPlatform(tester);
      await _pump(tester);
      for (final ms in [50, 500, 1000, 2000, 2500, 2990]) {
        await hold(tester, Duration(milliseconds: ms));
        expect(find.text(_simTitle), findsNothing, reason: '$ms ms');
      }
      expect(haptics(), 0);
    });

    testWidgets('three 1.5 s holds in a row do not add up', (tester) async {
      await mockPlatform(tester);
      await _pump(tester);
      for (var i = 0; i < 3; i++) {
        await hold(tester, const Duration(milliseconds: 1500));
      }
      expect(find.text(_simTitle), findsNothing);
      expect(haptics(), 0);
    });

    testWidgets('a 3 s hold that drags (scroll) does not open it', (
      tester,
    ) async {
      await mockPlatform(tester);
      await _pump(tester);
      await hold(
        tester,
        const Duration(milliseconds: 3200),
        move: const Offset(0, -60),
      );
      expect(find.text(_simTitle), findsNothing);
    });

    testWidgets('a 3 s hold opens exactly one sheet, one haptic; a 2.9 s '
        'hold after closing it opens nothing', (tester) async {
      await mockPlatform(tester);
      await _pump(tester);
      await hold(tester, const Duration(seconds: 3));
      expect(find.text(_simTitle), findsOneWidget);
      expect(haptics(), 1);
      // Close the sheet (barrier).
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();
      expect(find.text(_simTitle), findsNothing);
      await hold(tester, const Duration(milliseconds: 2900));
      expect(find.text(_simTitle), findsNothing);
      expect(haptics(), 1);
    });
  });
}
