// T29 carry-overs of T25: the telemetry reporter of the start flow (events,
// custom keys, privacy of the payload) and review R2-2 (the reporter never
// rebuilds TripStarter).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/analytics/analytics_guard.dart';
import 'package:napstop/core/telemetry/consent/telemetry_consent_store.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/alarm_settings/data/alarm_settings_providers.dart';
import 'package:napstop/features/alarm_settings/data/trip_start_reporter.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';

import '../../../core/telemetry/telemetry_fakes.dart';
import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/fake_key_value_store.dart';
import '../../../helpers/trip_fixtures.dart';
import '../helpers/alarm_settings_fakes.dart';

const _id = '0b9f4f6e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';

/// Telemetry on recording sinks, collection forced on (dev + `on`), strict.
Telemetry _telemetry(RecordingAnalyticsSink a, RecordingCrashSink c) {
  final crash = CrashReporter(c);
  final controller = TelemetryConsentController(
    store: TelemetryConsentStore(FakeKeyValueStore()),
    consent: TelemetryConsent.initial,
    crashSink: c,
    analyticsSink: a,
    flavor: AppFlavor.dev,
    isDebugBuild: false,
    override: TelemetryOverride.on,
  );
  return Telemetry(
    analytics: AppAnalytics(
      sink: a,
      crash: crash,
      isEnabled: () => controller.effective.analytics,
    ),
    crash: crash,
    engineParams: EngineParamsSource(
      FakeRemoteConfigClient(),
      flavor: AppFlavor.dev,
    ),
    consent: controller,
  );
}

TripStartFacts _facts({
  AlarmModeMsg mode = AlarmModeMsg.distance,
  int? distance = 1000,
  int? time,
  int? battery = 42,
}) => TripStartFacts(
  mode: mode,
  distanceThresholdM: distance,
  timeThresholdMin: time,
  vehicleHint: VehicleKindMsg.coach,
  destSource: DestinationSource.savedPlace,
  preAlert: true,
  shortDistanceWarning: false,
  batteryPct: battery,
  charging: true,
  simulated: true,
  paramsId: '0a1b2c3d',
);

void main() {
  late RecordingAnalyticsSink analytics;
  late RecordingCrashSink crash;
  late Telemetry telemetry;

  setUp(() {
    analytics = RecordingAnalyticsSink();
    crash = RecordingCrashSink();
    telemetry = _telemetry(analytics, crash);
  });

  group('mapping', () {
    test('trip_start of the facts', () {
      expect(tripStartEventOf(_facts()).toParameters(), {
        'mode': 'distance',
        'threshold': 'd1000',
        'vehicle_hint': 'coach',
        'dest_source': 'saved_place',
        'pre_alert': 1,
        'short_distance_warning': 0,
        'battery': 'le50',
        'charging': 1,
        'simulated': 1,
        'params_id': '0a1b2c3d',
      });
      final time = tripStartEventOf(
        _facts(
          mode: AlarmModeMsg.time,
          distance: null,
          time: 45,
          battery: null,
        ),
      ).toParameters();
      expect(time['threshold'], 't_other');
      expect(time.containsKey('battery'), isFalse);
      expect(
        tripStartEventOf(_facts(mode: AlarmModeMsg.smart)).threshold,
        ThresholdTag.smart,
      );
    });

    test('every enum maps', () {
      for (final m in AlarmModeMsg.values) {
        expect(alarmModeTagOf(m).name, m.name);
      }
      for (final v in VehicleKindMsg.values) {
        expect(vehicleTagOf(v).name, v.name);
      }
      for (final s in DestinationSource.values) {
        expect(destSourceTagOf(s).name, s.name);
      }
      for (final r in TripStartBlockReason.values) {
        expect(startBlockedReasonOf(r).name, r.name);
      }
    });
  });

  group('TelemetryTripStartReporter', () {
    late TelemetryTripStartReporter reporter;

    setUp(() => reporter = TelemetryTripStartReporter(() => telemetry));

    test('started: event and the four custom keys', () async {
      reporter.started(_facts());
      await pumpEventQueue();
      expect(analytics.events.single.$1, 'trip_start');
      expect(crash.keys, {
        'trip_active': true,
        'alarm_mode': 'distance',
        'simulated': true,
        'engine_params_id': '0a1b2c3d',
      });
    });

    test('blocked: trip_start_blocked with the wire reason', () async {
      reporter.blocked(TripStartBlockReason.noAlarmChannel, simulated: false);
      await pumpEventQueue();
      final (name, params) = analytics.events.single;
      expect(name, 'trip_start_blocked');
      expect(params, {'reason': 'no_alarm_channel', 'simulated': 0});
    });

    test('history write failure: non-fatal, error type only', () async {
      reporter.historyWriteFailed(
        StateError('INSERT ... parameters: [Ga Đồng Hới, 17.4783]'),
        StackTrace.current,
      );
      await pumpEventQueue();
      final e = crash.errors.single;
      expect(e.reason, 'historyWriteFailed');
      expect(e.fatal, isFalse);
      expect(e.error.toString(), 'StateError');
    });

    test('config rejected: the rule (no value) as a non-fatal', () async {
      reporter.configRejected('destLat: out of range');
      await pumpEventQueue();
      expect(
        crash.errors.single.error.toString(),
        'TripConfigRejected: TripConfigRejected(destLat: out of range)',
      );
    });
  });

  group('through the providers', () {
    late FakeCoreBridge bridge;
    late ProviderContainer container;

    setUp(() {
      bridge = FakeCoreBridge();
      container = ProviderContainer(
        overrides: [
          coreBridgeProvider.overrideWithValue(bridge),
          tripsRepositoryProvider.overrideWithValue(
            FakeTripsRepository(bridge.calls),
          ),
          tripIdGeneratorProvider.overrideWithValue(() => _id),
          telemetryProvider.overrideWithValue(telemetry),
        ],
      );
      addTearDown(container.dispose);
    });

    test('R2-2: consent changes never rebuild TripStarter', () async {
      final starter = container.read(tripStarterProvider);
      final reporter = container.read(tripStartReporterProvider);
      await telemetry.consent.update(
        crash: ConsentChoice.denied,
        analytics: ConsentChoice.denied,
      );
      await telemetry.engineParams.refresh();
      expect(container.read(tripStarterProvider), same(starter));
      expect(container.read(tripStartReporterProvider), same(reporter));
    });

    test('a real start: payload has no name, coordinates or trip id', () async {
      final outcome = await container
          .read(tripStarterProvider)
          .start(
            const StartRequest(
              draft: TripDraft(
                destination: kGaDongHoi,
                source: DestinationSource.station,
              ),
              settings: TripSettings.defaults,
              alarmPrefs: AlarmPreferences.defaults,
              engineParams: EngineParamsOverride.defaults,
              shortDistanceWarning: false,
            ),
          );
      expect(outcome, isA<StartSucceeded>());
      await pumpEventQueue();
      final (name, params) = analytics.events.single;
      expect(name, 'trip_start');
      expect(checkAnalyticsEvent(name, params), isNull);
      for (final v in params.values) {
        expect(looksLikeCoordinate(v), isFalse, reason: '$v');
      }
      final all = [
        ...params.values.map((v) => '$v'),
        ...crash.allText,
      ].join(' ');
      expect(all, isNot(contains('Đồng Hới')));
      expect(all, isNot(contains('17.47')));
      expect(all, isNot(contains('106.6')));
      expect(all, isNot(contains(_id)));
    });
  });
}
