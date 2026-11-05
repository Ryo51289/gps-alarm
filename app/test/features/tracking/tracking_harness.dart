// Pumps screen 4 inside the whole app (T26). Not a test file.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/storage/memory_key_value_store.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';

import '../../core/telemetry/telemetry_fakes.dart';
import '../../helpers/app_harness.dart';
import '../../helpers/fake_core_bridge.dart';
import 'tracking_fixtures.dart';

/// Real time of the harness clock; tests move it.
int trackingNowMs = kAtMs + 1000;

/// Recording sinks of the last [pumpTracking].
late RecordingAnalyticsSink trackingAnalytics;
late RecordingCrashSink trackingCrash;

Telemetry _telemetry() {
  trackingAnalytics = RecordingAnalyticsSink();
  trackingCrash = RecordingCrashSink();
  final crash = CrashReporter(trackingCrash);
  final consent = TelemetryConsentController(
    store: TelemetryConsentStore(MemoryKeyValueStore()),
    consent: TelemetryConsent.initial,
    crashSink: trackingCrash,
    analyticsSink: trackingAnalytics,
    flavor: AppFlavor.dev,
    isDebugBuild: false,
    override: TelemetryOverride.on,
  );
  return Telemetry(
    analytics: AppAnalytics(
      sink: trackingAnalytics,
      crash: crash,
      isEnabled: () => consent.effective.analytics,
    ),
    crash: crash,
    engineParams: EngineParamsSource(
      FakeRemoteConfigClient(),
      flavor: AppFlavor.dev,
    ),
    consent: consent,
  );
}

/// A bridge whose snapshot is [state] (default: W01) of [config].
FakeCoreBridge trackingBridge({
  TripStateMsg? state,
  TripConfigMsg? config,
  SimulationMsg? simulation,
  bool? headphones = true,
}) => FakeCoreBridge(
  active: activeMsg(
    state: state ?? w01State(),
    config: config,
    simulation: simulation,
  ),
  deviceStatusValue: deviceStatusMsg(
    batteryPct: 80,
    headphonesConnected: headphones,
  ),
);

/// Opens `/tracking` with `go` (as screen 3 does).
Future<AppHarness> pumpTracking(
  WidgetTester tester, {
  FakeCoreBridge? bridge,
  NapThemeKind theme = NapThemeKind.light,
  double textScale = 1.0,
  Locale locale = const Locale('vi'),
  Size size = kHarnessSize,
  String? fontFamily,
  bool settle = true,
  String initialLocation = AppRoutes.tracking,
  List<Override> overrides = const [],
  int nowMs = kAtMs + 1000,
}) {
  trackingNowMs = nowMs;
  return pumpAppHarness(
    tester,
    bridge: bridge ?? trackingBridge(),
    initialLocation: initialLocation,
    theme: theme,
    textScale: textScale,
    locale: locale,
    size: size,
    fontFamily: fontFamily,
    settle: settle,
    clock: () => DateTime.fromMillisecondsSinceEpoch(trackingNowMs),
    overrides: [
      telemetryProvider.overrideWithValue(_telemetry()),
      ...overrides,
    ],
  );
}

/// Sends [state] as the next view.
Future<void> emitState(
  WidgetTester tester,
  FakeCoreBridge b,
  TripStateMsg state,
) async {
  b.emit(TripStateUpdateMsg(state: state));
  await tester.pump();
  await tester.pump();
}
