// Pumps screen 3 on top of screen 1 through the real router (T25). Not a
// test file.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/data/alarm_settings_providers.dart';

import '../../../helpers/app_harness.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/fake_key_value_store.dart';
import '../../../helpers/trip_fixtures.dart';
import 'alarm_settings_fakes.dart';

const String kTestTripId = 'trip-new';

const TripDraft kDraftTrain = TripDraft(
  destination: kGaDongHoi,
  source: DestinationSource.station,
);

const TripDraft kDraftCoach = TripDraft(
  destination: kBenXeMyDinh,
  source: DestinationSource.station,
);

const TripDraft kDraftBus = TripDraft(
  destination: TripDestination(
    name: 'Bến xe buýt Kim Mã',
    lat: 21.0313,
    lng: 105.8255,
    kind: DestinationKind.bus,
  ),
  source: DestinationSource.station,
);

const TripDraft kDraftPlaces = TripDraft(
  destination: TripDestination(
    name: '12 Láng Hạ',
    lat: 21.017,
    lng: 105.815,
    kind: DestinationKind.address,
    detail: 'Đống Đa, Hà Nội',
  ),
  source: DestinationSource.places,
);

class AlarmSettingsHarness {
  const new({
    required this.app,
    required this.reader,
    required this.reporter,
    required this.kv,
  });

  final AppHarness app;
  final FakeEngineParamsReader reader;
  final RecordingReporter reporter;
  final FakeKeyValueStore kv;

  FakeCoreBridge get bridge => app.bridge;

  String get location => app.location;
}

/// Screen 1, then screen 3 pushed with [extra] (a [TripDraft] by default).
Future<AlarmSettingsHarness> pumpAlarmSettings(
  WidgetTester tester, {
  Object? extra = kDraftTrain,
  FakeCoreBridge? bridge,
  Map<String, Object>? prefs,
  EngineParamsOverride params = EngineParamsOverride.defaults,
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1.0,
  Locale locale = const Locale('vi'),
  Size size = kHarnessSize,
  String? fontFamily,
  List<Override> overrides = const [],
}) async {
  final reader = FakeEngineParamsReader(params);
  final reporter = RecordingReporter();
  final kv = FakeKeyValueStore(prefs);
  final app = await pumpAppHarness(
    tester,
    bridge: bridge,
    theme: theme,
    textScale: textScale,
    locale: locale,
    size: size,
    fontFamily: fontFamily,
    keyValueStore: kv,
    overrides: [
      engineParamsReaderProvider.overrideWithValue(reader),
      tripStartReporterProvider.overrideWithValue(reporter),
      tripIdGeneratorProvider.overrideWithValue(() => kTestTripId),
      ...overrides,
    ],
  );
  // Not awaited: the push completes only when screen 3 is popped.
  unawaited(app.router.push<void>(AppRoutes.alarmSettings, extra: extra));
  await tester.pumpAndSettle();
  return AlarmSettingsHarness(
    app: app,
    reader: reader,
    reporter: reporter,
    kv: kv,
  );
}

/// Scrolls [finder] into view, taps it, settles.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Moves the distance slider to [meters] (as a drag would report it).
Future<void> slideTo(WidgetTester tester, int meters) async {
  final slider = tester.widget<Slider>(find.byType(Slider));
  slider.onChanged!(meters.toDouble());
  await tester.pumpAndSettle();
}

/// The bold summary line above the start button.
Finder summaryText(String value) =>
    find.text('Sẽ báo khi $value', findRichText: true);

/// [text] inside the big value of the mode panel.
Finder bigValue(String text) =>
    find.descendant(of: find.byType(NapBigValue), matching: find.text(text));

Finder chip(String label) => find.widgetWithText(NapChip, label);
