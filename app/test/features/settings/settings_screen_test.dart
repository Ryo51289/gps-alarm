// T28 S05-S20, SM04-SM07, N04: screen 12, its sub screen and sheets over the
// app harness (fake bridge, in-memory store).
import 'dart:async';
import 'dart:io';
import 'dart:ui' show CheckedState;

import 'package:flutter/foundation.dart' show LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/data/alarm_settings_providers.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/destination/data/station_license.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';
import 'package:napstop/features/simulation/data/sim_providers.dart';
import 'package:napstop/features/simulation/data/sim_trace_catalog.dart';
import 'package:napstop/features/simulation/domain/sim_launch.dart';

import '../../core/telemetry/telemetry_fakes.dart';
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
  KeyValueStoreLike? kv,
  Size size = _tall,
  Locale locale = const Locale('vi'),
  double textScale = 1,
  NapThemeKind theme = NapThemeKind.light,
  EngineParamsOverride params = EngineParamsOverride.defaults,
  List<Override> overrides = const [],
  String initialLocation = AppRoutes.settings,
  bool useApp = false,
  bool settle = true,
  Future<SimTraceCatalog> Function()? catalog,
  Future<AppVersion> Function()? version,
}) => pumpAppHarness(
  tester,
  bridge: bridge,
  keyValueStore: kv,
  size: size,
  locale: locale,
  textScale: textScale,
  theme: theme,
  initialLocation: initialLocation,
  useApp: useApp,
  settle: settle,
  overrides: [
    appVersionProvider.overrideWith(
      (ref) => version?.call() ?? Future.value((version: '0.1.0', build: '1')),
    ),
    simTraceCatalogProvider.overrideWith(
      (ref) => catalog?.call() ?? Future.value(_catalog),
    ),
    engineParamsReaderProvider.overrideWithValue(
      FakeEngineParamsReader(params),
    ),
    tripStartReporterProvider.overrideWithValue(RecordingReporter()),
    tripIdGeneratorProvider.overrideWithValue(() => 'trip-new'),
    ...overrides,
  ],
);

/// A store type the harness accepts (keeps the helper signature short).
typedef KeyValueStoreLike = FakeKeyValueStore;

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

Future<void> _longPressLogo(WidgetTester tester, Duration hold) async {
  final logo = find.text('NapStop');
  await tester.ensureVisible(logo);
  await tester.pumpAndSettle();
  final g = await tester.startGesture(tester.getCenter(logo));
  await tester.pump(hold);
  await g.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('S05 alarm settings reach the next trip (TripConfigMsg)', (
    tester,
  ) async {
    final h = await _pump(tester);
    // Sound: sheet → "Chuông" (heard at once), then close.
    await _tap(tester, find.text('Âm báo thức'));
    await _tap(tester, find.text('Chuông'));
    expect(h.bridge.previewCalls.last, (soundId: 'bell', volume: 1.0));
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(find.text('Chọn âm báo'), findsNothing);
    expect(h.bridge.calls.last, 'stopPreview');
    // Volume 60 % (as a drag reports it).
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(60);
    slider.onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(find.text('60%'), findsOneWidget);
    await _tap(tester, _switchOf('Tăng dần âm lượng'));
    await _tap(tester, find.text('Vừa'));
    await _tap(tester, _switchOf('Nhấp nháy đèn flash'));
    await _tap(tester, _switchOf('Ưu tiên phát qua tai nghe'));
    await _flush(h);

    unawaited(h.router.push<void>(AppRoutes.alarmSettings, extra: _draft));
    await tester.pumpAndSettle();
    final headphones = tester.widget<NapOptionCard>(
      find.ancestor(
        of: find.text('Chỉ tai nghe'),
        matching: find.byType(NapOptionCard),
      ),
    );
    expect(headphones.selected, isTrue);
    await _tap(tester, find.text('Bắt đầu theo dõi'));
    final a = h.bridge.startTripCalls.single.config.alarm;
    expect(a.soundId, 'bell');
    expect(a.volume, 0.6);
    expect(a.rampUp, isFalse);
    expect(a.vibration, VibrationMsg.medium);
    expect(a.flash, isTrue);
    expect(a.preferHeadphones, isTrue);
  });

  testWidgets('S06 trip defaults sub screen → store, screen 3, summary', (
    tester,
  ) async {
    final kv = FakeKeyValueStore();
    final h = await _pump(tester, kv: kv);
    await _tap(tester, find.text('Chế độ báo'));
    expect(h.location, AppRoutes.tripDefaults);
    expect(find.text('Mặc định cho chuyến mới'), findsOneWidget);
    await _tap(tester, find.text('Thời gian'));
    await _tap(tester, find.widgetWithText(NapChip, '20'));
    await _tap(tester, find.byType(Switch));
    await _tap(tester, find.widgetWithText(NapChip, 'Giải phép tính'));
    await _flush(h);
    expect(kv.values['tripDefaults.mode'], 'time');
    expect(kv.values['tripDefaults.timeMin'], 20);
    expect(kv.values['tripDefaults.preAlert'], 0);
    expect(kv.values['tripDefaults.dismiss'], 'math');

    await _tap(tester, find.byTooltip('Quay lại'));
    expect(h.location, AppRoutes.settings);
    expect(find.text('Thời gian · 20 phút'), findsOneWidget);
    expect(find.text('Giải phép tính'), findsOneWidget);

    unawaited(h.router.push<void>(AppRoutes.alarmSettings, extra: _draft));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NapChip>(find.widgetWithText(NapChip, '20')).selected,
      isTrue,
    );
    expect(
      tester
          .widget<NapChip>(find.widgetWithText(NapChip, 'Giải phép tính'))
          .selected,
      isTrue,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('S07 headphones off → ringAndVibrate (D11)', (tester) async {
    final kv = FakeKeyValueStore({'tripDefaults.alarmStyle': 'headphonesOnly'});
    final h = await _pump(tester, kv: kv);
    final sw = _switchOf('Ưu tiên phát qua tai nghe');
    expect(tester.widget<Switch>(sw).value, isTrue);
    await _tap(tester, sw);
    await _flush(h);
    expect(
      h.read(appSettingsProvider).tripDefaults.alarmStyle,
      AlarmStyle.ringAndVibrate,
    );
    expect(kv.values['tripDefaults.alarmStyle'], 'ringAndVibrate');
  });

  testWidgets('S08 language: English at once, native + crash key; system', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('fr', 'FR');
    tester.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final crash = RecordingCrashSink();
    final telemetry = Telemetry(
      analytics: AppAnalytics(
        sink: RecordingAnalyticsSink(),
        crash: CrashReporter(crash),
        isEnabled: () => false,
      ),
      crash: CrashReporter(crash),
      engineParams: Telemetry.noop().engineParams,
      consent: Telemetry.noop().consent,
    );
    final h = await _pump(
      tester,
      useApp: true,
      overrides: [telemetryProvider.overrideWithValue(telemetry)],
    );
    // fr device, "Theo ngôn ngữ máy" → Vietnamese (T20 Q3).
    expect(find.text('Cài đặt chung'), findsOneWidget);
    expect(h.bridge.setAppLocaleCalls, [null]);
    expect(crash.keys['locale'], 'other');

    await _tap(tester, find.text('English'));
    expect(find.text('Settings'), findsWidgets); // title + tab
    expect(find.text('Trips'), findsOneWidget);
    expect(h.bridge.setAppLocaleCalls, [null, 'en']);
    expect(crash.keys['locale'], 'en');
    expect(h.location, AppRoutes.settings);

    await _tap(tester, find.text('Use phone language'));
    expect(find.text('Cài đặt chung'), findsOneWidget);
    expect(h.bridge.setAppLocaleCalls, [null, 'en', null]);
    expect(crash.keys['locale'], 'other');
    await _flush(h);
  });

  testWidgets('S09 theme dark / light', (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('vi');
    tester.platformDispatcher.localesTestValue = const [Locale('vi')];
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    final kv = FakeKeyValueStore();
    final h = await _pump(tester, kv: kv, useApp: true);
    Brightness brightness() =>
        Theme.of(tester.element(find.text('Giao diện'))).brightness;
    await _tap(tester, find.text('Tối'));
    expect(brightness(), Brightness.dark);
    await _tap(tester, find.text('Sáng'));
    expect(brightness(), Brightness.light);
    await _flush(h);
    expect(kv.values['display.theme'], 'light');
  });

  testWidgets('S10 the first frame already uses the stored en + dark', (
    tester,
  ) async {
    final kv = FakeKeyValueStore({
      'display.language': 'en',
      'display.theme': 'dark',
    });
    const initial = DisplayPreferences(
      language: AppLanguage.en,
      theme: AppThemeChoice.dark,
    );
    await _pump(
      tester,
      kv: kv,
      useApp: true,
      settle: false,
      overrides: [initialDisplayPreferencesProvider.overrideWithValue(initial)],
    );
    // First frame, before the store was read again.
    expect(find.text('Settings'), findsWidgets);
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
  });

  testWidgets('S11 a failing setAppLocale changes nothing visible', (
    tester,
  ) async {
    final bridge = FakeCoreBridge()..setAppLocaleError = channelError();
    await _pump(tester, bridge: bridge, useApp: true);
    await _tap(tester, find.text('English'));
    expect(tester.takeException(), isNull);
    expect(find.text('Appearance'), findsOneWidget);
    expect(bridge.setAppLocaleCalls.last, 'en');
  });

  testWidgets('S12 consent switches answer at once (slow store)', (
    tester,
  ) async {
    final store = SlowKeyValueStore(writeDelay: const Duration(seconds: 2));
    final telemetry = Telemetry.noop(store: TelemetryConsentStore(store));
    await _pump(
      tester,
      overrides: [telemetryProvider.overrideWithValue(telemetry)],
    );
    final crash = _switchOf('Gửi báo cáo lỗi');
    final usage = _switchOf('Gửi thống kê sử dụng');
    expect(tester.widget<Switch>(crash).value, isFalse);
    await tester.ensureVisible(crash);
    await tester.pumpAndSettle();
    await tester.tap(crash);
    await tester.pump();
    expect(tester.widget<Switch>(crash).value, isTrue);
    expect(telemetry.consent.current.crash, ConsentChoice.granted);
    await tester.tap(crash);
    await tester.pump();
    expect(tester.widget<Switch>(crash).value, isFalse);
    expect(telemetry.consent.current.crash, ConsentChoice.denied);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(usage).value, isFalse);
  });

  testWidgets('S12 a late read of the stored consent (adoptLoaded)', (
    tester,
  ) async {
    final late = Telemetry.noop(consentLoaded: false);
    await _pump(tester, overrides: [telemetryProvider.overrideWithValue(late)]);
    final usage = _switchOf('Gửi thống kê sử dụng');
    expect(tester.widget<Switch>(usage).value, isFalse);
    await late.consent.adoptLoaded(
      TelemetryConsent.initial.copyWith(
        analytics: ConsentChoice.granted,
        version: kConsentTextVersion,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(usage).value, isTrue);
  });

  testWidgets('S13 preview: play, stop, new volume, leave the tab', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _tap(tester, find.text('Nghe thử'));
    expect(h.bridge.previewCalls.single, (soundId: 'horn', volume: 1.0));
    expect(find.text('Dừng'), findsOneWidget);
    await _tap(tester, find.text('Dừng'));
    expect(h.bridge.calls.last, 'stopPreview');
    expect(find.text('Nghe thử'), findsOneWidget);

    await _tap(tester, find.text('Nghe thử'));
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(60);
    slider.onChangeEnd!(60);
    await tester.pumpAndSettle();
    expect(h.bridge.previewCalls.last, (soundId: 'horn', volume: 0.6));

    final stops = h.bridge.callCount('stopPreview');
    await tester.tap(find.text('Trang chủ'));
    await tester.pumpAndSettle();
    expect(h.bridge.callCount('stopPreview'), stops + 1);
  });

  testWidgets('S13 the UI goes back to "Nghe thử" after 10 s', (tester) async {
    await _pump(tester);
    await _tap(tester, find.text('Nghe thử'));
    expect(find.text('Dừng'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Nghe thử'), findsOneWidget);
  });

  testWidgets('S13 a failing preview shows a snack bar', (tester) async {
    final bridge = FakeCoreBridge()..previewError = channelError();
    await _pump(tester, bridge: bridge);
    await _tap(tester, find.text('Nghe thử'));
    expect(find.text('Không phát thử được âm báo.'), findsOneWidget);
    expect(find.text('Nghe thử'), findsOneWidget);
  });

  testWidgets('S14 sound sheet: radio rows, pick, preview, stop on close', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final h = await _pump(tester);
    await _tap(tester, find.text('Âm báo thức'));
    final horn = tester.getSemantics(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Còi tàu (mặc định)'),
      ),
    );
    expect(horn.flagsCollection.isChecked, CheckedState.isTrue);
    expect(horn.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    await _tap(tester, find.text('Bíp'));
    expect(h.bridge.previewCalls.last, (soundId: 'beep', volume: 1.0));
    expect(h.read(appSettingsProvider).alarm.soundId, 'beep');
    final beep = tester.getSemantics(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('Bíp')),
    );
    expect(beep.flagsCollection.isChecked, CheckedState.isTrue);
    await tester.tapAt(const Offset(195, 20));
    await tester.pumpAndSettle();
    expect(h.bridge.calls.last, 'stopPreview');
    expect(find.text('Bíp'), findsOneWidget); // subtitle of the row
    handle.dispose();
  });

  for (final (name, permissions, label) in [
    ('ready', androidPermissions(), 'Đủ quyền'),
    (
      'blocked',
      androidPermissions(location: LocationAccessMsg.denied),
      'Cần kiểm tra',
    ),
  ]) {
    testWidgets('S15 permissions badge: $name', (tester) async {
      final h = await _pump(
        tester,
        bridge: FakeCoreBridge(permissions: permissions),
      );
      expect(find.text(label), findsOneWidget);
      await _tap(tester, find.text('Quyền & tối ưu pin'));
      expect(h.location, AppRoutes.onboarding);
    });
  }

  testWidgets('S15 permissions unreadable: no badge', (tester) async {
    final bridge = FakeCoreBridge()..permissionStatusError = channelError();
    await _pump(tester, bridge: bridge);
    expect(find.text('Đủ quyền'), findsNothing);
    expect(find.text('Cần kiểm tra'), findsNothing);
    expect(find.text('Quyền & tối ưu pin'), findsOneWidget);
  });

  testWidgets('S16 a running trip shows the note', (tester) async {
    await _pump(tester, bridge: FakeCoreBridge(active: activeTrip()));
    expect(
      find.text(
        'Chuyến đang chạy giữ cài đặt cũ. Thay đổi áp dụng từ chuyến sau.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('S17 snooze row from the engine params, not tappable', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      params: const EngineParamsOverride(
        json: '{"snoozeS":120,"maxSnoozes":2}',
        id: 'abcd1234',
      ),
    );
    expect(find.text('Báo lại tối đa'), findsOneWidget);
    expect(find.text('2 lần · sau 2 phút'), findsOneWidget);
    final row = tester.widget<NapListRow>(
      find.ancestor(
        of: find.text('Báo lại tối đa'),
        matching: find.byType(NapListRow),
      ),
    );
    expect(row.onTap, isNull);
    expect(row.chevron, isFalse);
    await _tap(tester, find.text('Báo lại tối đa'));
    expect(h.location, AppRoutes.settings);
  });

  for (final locale in const [Locale('vi'), Locale('en')]) {
    for (final theme in const [NapThemeKind.light, NapThemeKind.dark]) {
      testWidgets('S18 320x568, x2, ${locale.languageCode}, ${theme.name}: '
          'no overflow, 44 px controls', (tester) async {
        final h = await _pump(
          tester,
          size: const Size(320, 568),
          textScale: 2,
          locale: locale,
          theme: theme,
        );
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 40; i++) {
          expect(tester.takeException(), isNull, reason: 'scroll step $i');
          for (final e in find.byType(Switch).evaluate()) {
            final size = (e.renderObject! as RenderBox).size;
            expect(size.height, greaterThanOrEqualTo(44));
          }
          await tester.drag(scrollable, const Offset(0, -300));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        unawaited(h.router.push<void>(AppRoutes.tripDefaults));
        await tester.pumpAndSettle();
        for (var i = 0; i < 10; i++) {
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -300),
          );
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('S19 controls disabled until the store was read', (tester) async {
    final kv = SlowKeyValueStore()
      ..readGate = Completer<void>()
      ..values['alarm.flash'] = 1;
    await _pump(tester, kv: kv, settle: false);
    await tester.pump();
    final flash = _switchOf('Nhấp nháy đèn flash');
    expect(tester.widget<Switch>(flash).onChanged, isNull);
    expect(tester.widget<Switch>(flash).value, isFalse);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    kv.readGate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(flash).onChanged, isNotNull);
    expect(tester.widget<Switch>(flash).value, isTrue);
  });

  testWidgets('S20 licenses page: Be Vietnam Pro and the ODbL notice', (
    tester,
  ) async {
    LicenseRegistry.reset();
    resetFontLicenseRegistration();
    resetStationDataLicenseRegistration();
    addTearDown(LicenseRegistry.reset);
    registerFontLicenses();
    registerStationDataLicense();
    await _pump(tester);
    await _tap(tester, find.text('Giấy phép & ghi công'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text(kBeVietnamProLicensePackage), findsOneWidget);
    expect(find.text(kStationDataLicensePackage), findsOneWidget);
  });

  testWidgets('SM04 hold 2.9 s: nothing; 3.0 s: the sheet, 6 traces, 60×', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pump(tester);
    await _longPressLogo(tester, const Duration(milliseconds: 2900));
    expect(find.text('Chế độ giả lập (demo)'), findsNothing);
    await _longPressLogo(tester, const Duration(seconds: 3));
    expect(find.text('Chế độ giả lập (demo)'), findsOneWidget);
    expect(
      calls.where((c) => c.method == 'HapticFeedback.vibrate'),
      isNotEmpty,
    );
    final titles = [
      'Tàu Hà Nội → Đồng Hới',
      'Xe khách Mỹ Đình → Thái Bình',
      'Buýt nhanh BRT01 (Hà Nội)',
      'Xe khách qua hầm Hải Vân → Lăng Cô',
      'Xe khách Giáp Bát → Phủ Lý (đi quá trạm)',
      'Buýt BRT01, GPS nhiễu',
    ];
    final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    expect([...ys]..sort(), ys);
    expect(
      tester
          .widget<NapSegmentedControl<SimSpeed>>(
            find.byType(NapSegmentedControl<SimSpeed>),
          )
          .selected,
      SimSpeed.x60,
    );
    expect(
      find.text('Tàu · tới nơi sau khoảng 9 phút 24 giây'),
      findsOneWidget,
    );
    // Nothing chosen yet: "Tiếp tục" is off.
    expect(
      tester
          .widget<NapButton>(find.widgetWithText(NapButton, 'Tiếp tục'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('SM05 trace + 10× → screen 3 with the simulation', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _longPressLogo(tester, const Duration(seconds: 3));
    await _tap(tester, find.text('Xe khách Mỹ Đình → Thái Bình'));
    await _tap(tester, find.text('10×'));
    expect(
      find.text('Xe khách · tới nơi sau khoảng 12 phút 11 giây'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Tiếp tục'));
    expect(h.location, AppRoutes.alarmSettings);
    final args = h.extra! as AlarmSettingsArgs;
    expect(args.simulation!.traceAsset, 'coach_md_tb');
    expect(args.simulation!.speedFactor, 10.0);
    expect(args.draft.destination.name, 'Bến xe khách Trung tâm Thái Bình');
    expect(args.draft.vehicleHint, VehicleKindMsg.coach);
    expect(find.text('Chuyến giả lập · tốc độ 10×'), findsOneWidget);
  });

  testWidgets('SM06 catalog error: message, "Tiếp tục" off', (tester) async {
    await _pump(
      tester,
      catalog: () => Future<SimTraceCatalog>.error(
        const FormatException('sim catalog: traces'),
      ),
    );
    await _longPressLogo(tester, const Duration(seconds: 3));
    expect(
      find.text('Không đọc được danh sách chuyến giả lập.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<NapButton>(find.widgetWithText(NapButton, 'Tiếp tục'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('SM07 a running trip: snack bar instead of the sheet', (
    tester,
  ) async {
    await _pump(tester, bridge: FakeCoreBridge(active: activeTrip()));
    await _longPressLogo(tester, const Duration(seconds: 3));
    expect(find.text('Chế độ giả lập (demo)'), findsNothing);
    expect(
      find.text('Đang có chuyến đi. Dừng chuyến đó trước khi đặt chuyến mới.'),
      findsOneWidget,
    );
  });

  testWidgets('version line; the logo stays without it', (tester) async {
    await _pump(tester);
    await tester.ensureVisible(find.text('phiên bản 0.1.0 (1)'));
    expect(find.text('phiên bản 0.1.0 (1)'), findsOneWidget);
  });

  testWidgets('version unreadable: line hidden', (tester) async {
    await _pump(
      tester,
      version: () => Future<AppVersion>.error(StateError('no plugin')),
    );
    expect(find.textContaining('phiên bản'), findsNothing);
    expect(find.text('NapStop'), findsOneWidget);
  });

  testWidgets('N04 SimpleDialog with radio rows and long trailing', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: NapThemes.light(),
        home: const Scaffold(
          body: SimpleDialog(
            title: Text('Ngôn ngữ'),
            children: [
              NapListRow(
                title: 'Tiếng Việt',
                trailing: Text('Đang bật'),
                semanticsChecked: true,
              ),
              NapListRow(
                title: 'English',
                trailing: Text('Theo máy'),
                semanticsChecked: false,
              ),
              NapListRow(
                title: 'Theo ngôn ngữ máy',
                trailing: Text('Mặc định'),
                semanticsChecked: false,
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Each trailing on one line (as tall as without a width limit).
    for (final t in ['Đang bật', 'Theo máy', 'Mặc định']) {
      final box = tester.renderObject<RenderBox>(find.text(t));
      expect(
        box.size.height,
        moreOrLessEquals(box.getMinIntrinsicHeight(double.infinity)),
        reason: t,
      );
    }
  });
}
