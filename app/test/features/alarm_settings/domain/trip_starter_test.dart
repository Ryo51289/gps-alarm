// T25 U19, U20: start flow (T25 §2.7, adapted to T22 §7.2: the history row
// is written before startTrip and removed again when it fails).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_override.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm_settings/domain/trip_starter.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/trip_fixtures.dart';
import '../helpers/alarm_settings_fakes.dart';

const _id = '0b9f4f6e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
const _draft = TripDraft(
  destination: kGaDongHoi,
  source: DestinationSource.station,
);

final class _Setup {
  new({FakeCoreBridge? bridge, Duration timeout = kStartTripTimeout})
    : bridge = bridge ?? FakeCoreBridge() {
    trips = FakeTripsRepository(this.bridge.calls);
    starter = TripStarter(
      bridge: this.bridge,
      trips: trips,
      reporter: reporter,
      newTripId: () => _id,
      nowMs: () => 1700000000000,
      startTimeout: timeout,
    );
  }

  final FakeCoreBridge bridge;
  final RecordingReporter reporter = RecordingReporter();
  late final FakeTripsRepository trips;
  late final TripStarter starter;

  Future<StartOutcome> start({
    TripDraft draft = _draft,
    TripSettings settings = TripSettings.defaults,
    SimulationMsg? simulation,
    EngineParamsOverride params = EngineParamsOverride.defaults,
    bool warning = false,
  }) => starter.start(
    StartRequest(
      draft: draft,
      settings: settings,
      alarmPrefs: AlarmPreferences.defaults,
      engineParams: params,
      shortDistanceWarning: warning,
      simulation: simulation,
    ),
  );
}

BridgeException _bridgeError(BridgeErrorCode code, {Object? details}) =>
    BridgeException(code, rawCode: code.wire, details: details);

void main() {
  group('U19 success', () {
    for (final (mode, distance, time) in [
      (AlarmModeMsg.distance, 2000, null),
      (AlarmModeMsg.time, null, 20),
      (AlarmModeMsg.smart, null, null),
    ]) {
      test(mode.name, () async {
        final s = _Setup(
          bridge: FakeCoreBridge(
            deviceStatusValue: deviceStatusMsg(batteryPct: 80),
          ),
        );
        final outcome = await s.start(
          settings: TripSettings.defaults.copyWith(
            mode: mode,
            distanceThresholdM: 2000,
            timeThresholdMin: 20,
          ),
          params: const EngineParamsOverride(json: '{"x":1}', id: 'abcd1234'),
          warning: mode == AlarmModeMsg.distance,
        );
        expect(outcome, isA<StartSucceeded>());
        expect((outcome as StartSucceeded).tripId, _id);
        expect(s.bridge.calls, [
          'permissionStatus',
          'deviceInfo',
          'currentTrip',
          'deviceStatus',
          'insertStarted',
          'startTrip',
        ]);
        final call = s.bridge.startTripCalls.single;
        expect(call.config.tripId, _id);
        expect(call.config.mode, mode);
        expect(call.config.distanceThresholdM, distance);
        expect(call.config.timeThresholdMin, time);
        expect(call.config.engineParamsJson, '{"x":1}');
        expect(call.destLat, kGaDongHoi.lat);
        expect(call.destLng, kGaDongHoi.lng);
        expect(call.simulation, isNull);

        final row = s.trips.rows[_id]!;
        expect(row.destination, kGaDongHoi);
        expect(row.alarm.mode, mode);
        // Both thresholds kept for a restart (T22).
        expect(row.alarm.distanceThresholdM, 2000);
        expect(row.alarm.timeThresholdMin, 20);
        expect(row.startedAtMs, 1700000000000);
        expect(row.simulated, isFalse);
        expect(row.source, DestinationSource.station);

        final facts = s.reporter.startedFacts.single;
        expect(facts.mode, mode);
        expect(facts.distanceThresholdM, distance);
        expect(facts.timeThresholdMin, time);
        expect(facts.vehicleHint, VehicleKindMsg.train);
        expect(facts.destSource, DestinationSource.station);
        expect(facts.batteryPct, 80);
        expect(facts.charging, isFalse);
        expect(facts.paramsId, 'abcd1234');
        expect(facts.shortDistanceWarning, mode == AlarmModeMsg.distance);
        expect(facts.simulated, isFalse);
        expect(s.reporter.blockedEvents, isEmpty);
      });
    }

    test('simulation is passed through and marks the row', () async {
      final s = _Setup();
      final sim = SimulationMsg(
        traceAsset: SimTraces.busHnBrt01,
        speedFactor: 60,
      );
      expect(await s.start(simulation: sim), isA<StartSucceeded>());
      expect(s.bridge.startTripCalls.single.simulation, same(sim));
      expect(s.trips.rows[_id]!.simulated, isTrue);
      expect(s.reporter.startedFacts.single.simulated, isTrue);
    });

    test('a 250-character name is truncated in config and row', () async {
      final s = _Setup();
      final long = TripDraft(
        destination: TripDestination(
          name: 'a' * 250,
          lat: 10,
          lng: 106,
          kind: DestinationKind.address,
        ),
        source: DestinationSource.places,
      );
      expect(await s.start(draft: long), isA<StartSucceeded>());
      expect(s.bridge.startTripCalls.single.config.destinationName, 'a' * 200);
      expect(s.trips.rows[_id]!.destination.name, 'a' * 200);
      expect(s.reporter.historyErrors, isEmpty);
    });

    test('unknown battery: null pct, not charging', () async {
      final s = _Setup()..bridge.deviceStatusError = channelError();
      expect(await s.start(), isA<StartSucceeded>());
      expect(s.reporter.startedFacts.single.batteryPct, isNull);
      expect(s.reporter.startedFacts.single.charging, isFalse);
    });
  });

  group('U20 failures', () {
    for (final (permissions, device, missing, reason) in [
      (
        androidPermissions(location: LocationAccessMsg.denied),
        androidDevice(),
        StartRequirement.location,
        TripStartBlockReason.locationDenied,
      ),
      (
        androidPermissions(precise: PermissionStateMsg.denied),
        androidDevice(),
        StartRequirement.precise,
        TripStartBlockReason.locationApproximate,
      ),
      (
        androidPermissions(locationServicesEnabled: false),
        androidDevice(),
        StartRequirement.locationServices,
        TripStartBlockReason.locationServicesOff,
      ),
      (
        iosPermissions(
          notifications: PermissionStateMsg.denied,
          alarmKit: PermissionStateMsg.denied,
        ),
        iosDevice(),
        StartRequirement.alarmChannel,
        TripStartBlockReason.noAlarmChannel,
      ),
    ]) {
      test('blocked: ${missing.name}', () async {
        final s = _Setup(
          bridge: FakeCoreBridge(
            permissions: permissions,
            deviceInfoValue: device,
          ),
        );
        final outcome = await s.start();
        expect(outcome, isA<StartBlocked>());
        expect((outcome as StartBlocked).missing.first, missing);
        expect(s.bridge.callCount('startTrip'), 0);
        expect(s.trips.rows, isEmpty);
        expect(s.reporter.blockedEvents, [(reason, false)]);
      });
    }

    test('permission read fails: generic, startTrip never called', () async {
      final s = _Setup()..bridge.permissionStatusError = channelError();
      expect((await s.start() as StartFailed).error, StartError.generic);
      expect(s.bridge.callCount('startTrip'), 0);
      expect(s.reporter.blockedEvents, [
        (TripStartBlockReason.startFailed, false),
      ]);
    });

    test('invalid destination: configRejected, no bridge start', () async {
      final s = _Setup();
      final outcome = await s.start(
        draft: const TripDraft(
          destination: TripDestination(
            name: 'X',
            lat: 91,
            lng: 0,
            kind: DestinationKind.pin,
          ),
          source: DestinationSource.mapPin,
        ),
      );
      expect((outcome as StartFailed).error, StartError.invalidDestination);
      expect(s.reporter.rejected, ['destLat: out of range']);
      expect(s.reporter.blockedEvents, [
        (TripStartBlockReason.startFailed, false),
      ]);
      expect(s.bridge.callCount('startTrip'), 0);
      expect(s.trips.rows, isEmpty);
    });

    test('invalid simulation: generic', () async {
      final s = _Setup();
      final outcome = await s.start(
        simulation: SimulationMsg(traceAsset: '', speedFactor: 60),
      );
      expect((outcome as StartFailed).error, StartError.generic);
      expect(s.reporter.rejected, ['simulation.traceAsset: empty']);
      expect(s.reporter.blockedEvents.single.$2, isTrue);
    });

    test('a running trip (currentTrip) stops before startTrip', () async {
      final s = _Setup(bridge: FakeCoreBridge(active: activeTrip()));
      expect((await s.start() as StartFailed).error, StartError.tripActive);
      expect(s.bridge.callCount('startTrip'), 0);
      expect(s.trips.rows, isEmpty);
      expect(s.reporter.blockedEvents, [
        (TripStartBlockReason.startFailed, false),
      ]);
    });

    test('an ended snapshot or an unreadable one does not block', () async {
      final ended = _Setup(
        bridge: FakeCoreBridge(active: activeTrip(phase: TripPhaseMsg.ended)),
      );
      expect(await ended.start(), isA<StartSucceeded>());
      final broken = _Setup()..bridge.currentTripError = channelError();
      expect(await broken.start(), isA<StartSucceeded>());
    });

    for (final (code, error) in [
      (BridgeErrorCode.tripActive, StartError.tripActive),
      (BridgeErrorCode.notForeground, StartError.notForeground),
      (BridgeErrorCode.simulationUnavailable, StartError.simulationUnavailable),
      (BridgeErrorCode.invalidConfig, StartError.generic),
      (BridgeErrorCode.startFailed, StartError.generic),
      (BridgeErrorCode.internal, StartError.generic),
      (BridgeErrorCode.channelError, StartError.generic),
      (BridgeErrorCode.requestInProgress, StartError.generic),
      (BridgeErrorCode.unknown, StartError.generic),
      (BridgeErrorCode.permissionMissing, StartError.generic),
    ]) {
      test('startTrip throws ${code.name} → ${error.name}', () async {
        final s = _Setup()..bridge.startTripError = _bridgeError(code);
        expect((await s.start() as StartFailed).error, error);
        expect(s.bridge.calls.sublist(s.bridge.calls.length - 3), [
          'insertStarted',
          'startTrip',
          'delete',
        ]);
        expect(s.trips.rows, isEmpty);
        expect(s.reporter.startedFacts, isEmpty);
        expect(s.reporter.blockedEvents, [
          (TripStartBlockReason.startFailed, false),
        ]);
      });
    }

    test('permission-missing with details: blocked', () async {
      final s = _Setup()
        ..bridge.startTripError = _bridgeError(
          BridgeErrorCode.permissionMissing,
          details: ['precise'],
        );
      final outcome = await s.start();
      expect((outcome as StartBlocked).missing, [StartRequirement.precise]);
      expect(s.reporter.blockedEvents, [
        (TripStartBlockReason.locationApproximate, false),
      ]);
      expect(s.trips.rows, isEmpty);
    });

    test('unexpected exception: generic', () async {
      final s = _Setup()..bridge.startTripError = StateError('boom');
      expect((await s.start() as StartFailed).error, StartError.generic);
      expect(s.trips.rows, isEmpty);
    });

    test('history write fails: trip still starts, reported', () async {
      final s = _Setup();
      s.trips.insertError = StateError('disk full');
      expect(await s.start(), isA<StartSucceeded>());
      expect(s.bridge.callCount('startTrip'), 1);
      expect(s.reporter.historyErrors, hasLength(1));
      expect(s.reporter.startedFacts, hasLength(1));
    });

    test('row removal fails after a failed start: reported', () async {
      final s = _Setup()
        ..bridge.startTripError = _bridgeError(BridgeErrorCode.startFailed);
      s.trips.deleteError = StateError('locked');
      expect((await s.start() as StartFailed).error, StartError.generic);
      expect(s.reporter.historyErrors, hasLength(1));
    });

    test('no row written: nothing to remove on failure', () async {
      final s = _Setup()
        ..bridge.startTripError = _bridgeError(BridgeErrorCode.startFailed);
      s.trips.insertError = StateError('disk full');
      await s.start();
      expect(s.bridge.calls, isNot(contains('delete')));
    });
  });

  group('round 2: startTrip timeout', () {
    const short = Duration(milliseconds: 50);

    _Setup hung() => _Setup(
      bridge: FakeCoreBridge()..startTripGate = Completer<void>(),
      timeout: short,
    );

    /// Lets the late answer and its row clean-up run.
    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 1));

    test('the default timeout is 15 s', () {
      expect(kStartTripTimeout, const Duration(seconds: 15));
    });

    test('no answer: timeout error, row kept for the late answer', () async {
      final s = hung();
      expect((await s.start() as StartFailed).error, StartError.timeout);
      expect(s.bridge.callCount('startTrip'), 1);
      expect(s.trips.rows.keys, [_id]);
      expect(s.reporter.blockedEvents, [
        (TripStartBlockReason.startFailed, false),
      ]);
      expect(s.reporter.startedFacts, isEmpty);
    });

    test('T29 (review R2-1): a late success is reported as started', () async {
      final s = hung();
      await s.start(warning: true);
      expect(s.reporter.startedFacts, isEmpty);
      s.bridge.startTripGate!.complete();
      await settle();
      final facts = s.reporter.startedFacts.single;
      expect(facts.shortDistanceWarning, isTrue);
      expect(facts.paramsId, 'default');
      // The timeout itself was counted once, as before.
      expect(s.reporter.blockedEvents, [
        (TripStartBlockReason.startFailed, false),
      ]);
    });

    test('T29: a late failure reports no start', () async {
      final s = hung();
      await s.start();
      s.bridge
        ..startTripError = const BridgeException(
          BridgeErrorCode.internal,
          rawCode: 'internal',
        )
        ..startTripGate!.complete();
      await settle();
      expect(s.reporter.startedFacts, isEmpty);
    });

    test('late failure removes the row', () async {
      final s = hung();
      await s.start();
      s.bridge
        ..startTripError = const BridgeException(
          BridgeErrorCode.startFailed,
          rawCode: 'start-failed',
        )
        ..startTripGate!.complete();
      await settle();
      expect(s.trips.rows, isEmpty);
      expect(s.bridge.calls.last, 'delete');
    });

    test(
      'late success, then retry: currentTrip sees it, no 2nd start',
      () async {
        final s = hung();
        await s.start();
        s.bridge.startTripGate!.complete();
        s.bridge.active = activeTrip(tripId: _id);
        await settle();
        expect(s.trips.rows.keys, [_id], reason: 'late success keeps the row');
        expect((await s.start() as StartFailed).error, StartError.tripActive);
        expect(s.bridge.callCount('startTrip'), 1);
        expect(s.bridge.callCount('insertStarted'), 1);
      },
    );

    test(
      'retry while still pending: waits, never calls startTrip again',
      () async {
        final s = hung();
        await s.start();
        final calls = s.bridge.calls.length;
        expect((await s.start() as StartFailed).error, StartError.timeout);
        // Only the permission reads of the retry; no currentTrip, no row,
        // no startTrip.
        expect(s.bridge.calls.sublist(calls), [
          'permissionStatus',
          'deviceInfo',
        ]);
        expect(s.bridge.callCount('startTrip'), 1);
      },
    );

    test('retry while pending, answer arrives during the wait', () async {
      final s = hung();
      await s.start();
      final retry = s.start();
      await settle();
      s.bridge.active = activeTrip(tripId: _id);
      s.bridge.startTripGate!.complete();
      expect((await retry as StartFailed).error, StartError.tripActive);
      expect(s.bridge.callCount('startTrip'), 1);
    });

    test('pending answered as failure: retry starts normally', () async {
      final s = hung();
      await s.start();
      s.bridge.startTripError = const BridgeException(
        BridgeErrorCode.internal,
        rawCode: 'internal',
      );
      s.bridge.startTripGate!.complete();
      await settle();
      s.bridge.startTripError = null;
      expect(await s.start(), isA<StartSucceeded>());
      expect(s.bridge.callCount('startTrip'), 2);
      expect(s.trips.rows.keys, [_id]);
    });
  });

  test('TripStartFacts.toString has no name or coordinates', () async {
    final s = _Setup();
    await s.start();
    final text = s.reporter.startedFacts.single.toString();
    expect(text, isNot(contains('Đồng Hới')));
    expect(text, isNot(contains('17.4')));
    expect(text, isNot(contains(_id)));
  });
}
