// Tester T25: start flow under adversarial timing (T25 §2.7 + round 2
// timeout). Runs inside testWidgets only for the fake clock: the real
// kStartTripTimeout (15 s) is used, never a shortened one.
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

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/trip_fixtures.dart';
import '../helpers/alarm_settings_fakes.dart';

const _draft = TripDraft(
  destination: kGaDongHoi,
  source: DestinationSource.station,
);

const _otherDraft = TripDraft(
  destination: kBenXeMyDinh,
  source: DestinationSource.station,
);

final class _Rig {
  new({FakeCoreBridge? bridge}) : bridge = bridge ?? FakeCoreBridge() {
    trips = FakeTripsRepository(this.bridge.calls);
    starter = TripStarter(
      bridge: this.bridge,
      trips: trips,
      reporter: reporter,
      newTripId: () => 'id-${++_n}',
      nowMs: () => 1700000000000,
    );
  }

  final FakeCoreBridge bridge;
  final RecordingReporter reporter = RecordingReporter();
  late final FakeTripsRepository trips;
  late final TripStarter starter;
  var _n = 0;

  Future<StartOutcome> start({TripDraft draft = _draft}) => starter.start(
    StartRequest(
      draft: draft,
      settings: TripSettings.defaults,
      alarmPrefs: AlarmPreferences.defaults,
      engineParams: EngineParamsOverride.defaults,
      shortDistanceWarning: false,
    ),
  );
}

/// Starts [future] and lets [elapsed] of fake time pass; returns the outcome
/// when it is done, null otherwise.
Future<StartOutcome?> _runFor(
  WidgetTester tester,
  Future<StartOutcome> future,
  Duration elapsed,
) async {
  StartOutcome? outcome;
  unawaited(future.then((o) => outcome = o));
  await tester.pump(elapsed);
  return outcome;
}

StartError? _error(StartOutcome? o) => o is StartFailed ? o.error : null;

BridgeException _err(BridgeErrorCode c, {Object? details}) =>
    BridgeException(c, rawCode: c.wire, details: details);

void main() {
  group('15 s timeout boundary (real constant)', () {
    testWidgets('answer at 14.999 s: success, no timeout', (tester) async {
      final r = _Rig(bridge: FakeCoreBridge()..startTripGate = Completer());
      final f = r.start();
      expect(
        await _runFor(tester, f, const Duration(milliseconds: 14999)),
        null,
      );
      r.bridge.startTripGate!.complete();
      await tester.pump();
      expect(await f, isA<StartSucceeded>());
      expect(r.reporter.startedFacts, hasLength(1));
      expect(r.reporter.blockedEvents, isEmpty);
    });

    testWidgets('no answer at 15 s: timeout, row kept', (tester) async {
      final r = _Rig(bridge: FakeCoreBridge()..startTripGate = Completer());
      final f = r.start();
      expect(
        await _runFor(tester, f, const Duration(milliseconds: 14999)),
        null,
      );
      await tester.pump(const Duration(milliseconds: 1));
      expect(_error(await f), StartError.timeout);
      expect(r.trips.rows.keys, ['id-1']);
      expect(r.reporter.blockedEvents, [
        (TripStartBlockReason.startFailed, false),
      ]);
      r.bridge.startTripGate!.complete();
      await tester.pump();
    });
  });

  group('late answers', () {
    testWidgets('late success, retries for another destination: tripActive', (
      tester,
    ) async {
      final r = _Rig(bridge: FakeCoreBridge()..startTripGate = Completer());
      expect(
        _error(await _runFor(tester, r.start(), kStartTripTimeout)),
        StartError.timeout,
      );
      // Native finally answers success; the trip runs.
      r.bridge
        ..active = activeTrip(tripId: 'id-1')
        ..startTripGate!.complete();
      await tester.pump();
      // The user went back, picked another destination and starts again.
      final o = await _runFor(
        tester,
        r.start(draft: _otherDraft),
        Duration.zero,
      );
      expect(_error(o), StartError.tripActive);
      expect(r.bridge.callCount('startTrip'), 1, reason: 'no second trip');
      expect(r.trips.rows.keys, ['id-1'], reason: 'running trip row kept');
    });

    testWidgets('late failure (each code): row removed, next start works', (
      tester,
    ) async {
      for (final code in BridgeErrorCode.values) {
        final r = _Rig(bridge: FakeCoreBridge()..startTripGate = Completer());
        expect(
          _error(await _runFor(tester, r.start(), kStartTripTimeout)),
          StartError.timeout,
        );
        r.bridge
          ..startTripError = _err(code, details: const ['location'])
          ..startTripGate!.complete();
        await tester.pump();
        expect(r.trips.rows, isEmpty, reason: code.name);
        // Next start: a normal one with a fresh id.
        r.bridge
          ..startTripGate = null
          ..startTripError = null;
        final o = await _runFor(tester, r.start(), Duration.zero);
        expect(o, isA<StartSucceeded>(), reason: code.name);
        expect((o! as StartSucceeded).tripId, 'id-2');
        expect(r.trips.rows.keys, ['id-2']);
        expect(r.bridge.callCount('startTrip'), 2);
      }
    });

    testWidgets('three retries while still hung: startTrip called once', (
      tester,
    ) async {
      final r = _Rig(bridge: FakeCoreBridge()..startTripGate = Completer());
      expect(
        _error(await _runFor(tester, r.start(), kStartTripTimeout)),
        StartError.timeout,
      );
      for (var i = 0; i < 3; i++) {
        // Each retry waits up to 15 s for the pending call, then gives up.
        final f = r.start();
        expect(
          await _runFor(
            tester,
            f,
            kStartTripTimeout - const Duration(milliseconds: 1),
          ),
          isNull,
          reason: 'retry $i still waiting',
        );
        await tester.pump(const Duration(milliseconds: 1));
        expect(_error(await f), StartError.timeout);
      }
      expect(r.bridge.callCount('startTrip'), 1);
      expect(r.bridge.callCount('insertStarted'), 1);
      expect(r.bridge.callCount('currentTrip'), 1, reason: 'first start only');
      expect(r.trips.rows.keys, ['id-1']);
      // Each attempt was counted as a blocked start (review R2-1).
      expect(r.reporter.blockedEvents, hasLength(4));
      r.bridge.startTripGate!.complete();
      await tester.pump();
    });

    testWidgets(
      'late success but currentTrip unreadable: native trip-active is the '
      'only guard (2nd startTrip call, its row removed)',
      (tester) async {
        final r = _Rig(bridge: FakeCoreBridge()..startTripGate = Completer());
        await _runFor(tester, r.start(), kStartTripTimeout);
        r.bridge.startTripGate!.complete();
        await tester.pump();
        // The real native side would refuse a second trip.
        r.bridge
          ..startTripGate = null
          ..currentTripError = StateError('channel')
          ..startTripError = _err(BridgeErrorCode.tripActive);
        final o = await _runFor(tester, r.start(), Duration.zero);
        expect(_error(o), StartError.tripActive);
        expect(r.bridge.callCount('startTrip'), 2);
        expect(r.trips.rows.keys, ['id-1'], reason: 'id-2 row removed');
      },
    );
  });

  group('error mapping = T25 §3.4 (derived from the spec table)', () {
    // Spec: tripActive / notForeground / simulationUnavailable keep their own
    // copy; invalid-config, start-failed, internal, channel-error,
    // request-in-progress, unknown → generic; permission-missing with
    // readable details → blocked sheet, otherwise generic.
    const expected = {
      BridgeErrorCode.invalidConfig: StartError.generic,
      BridgeErrorCode.tripActive: StartError.tripActive,
      BridgeErrorCode.simulationUnavailable: StartError.simulationUnavailable,
      BridgeErrorCode.permissionMissing: StartError.generic,
      BridgeErrorCode.notForeground: StartError.notForeground,
      BridgeErrorCode.startFailed: StartError.generic,
      BridgeErrorCode.requestInProgress: StartError.generic,
      BridgeErrorCode.internal: StartError.generic,
      BridgeErrorCode.channelError: StartError.generic,
      BridgeErrorCode.unknown: StartError.generic,
    };

    test('every BridgeErrorCode is in the table', () {
      expect(expected.keys.toSet(), BridgeErrorCode.values.toSet());
    });

    for (final MapEntry(key: code, value: error) in expected.entries) {
      test('${code.name} → ${error.name}; row removed', () async {
        final r = _Rig()..bridge.startTripError = _err(code);
        expect(_error(await r.start()), error);
        expect(r.trips.rows, isEmpty);
        expect(r.reporter.startedFacts, isEmpty);
        expect(
          r.reporter.blockedEvents.single.$1,
          TripStartBlockReason.startFailed,
        );
      });
    }

    for (final (details, missing) in <(Object?, List<StartRequirement>?)>[
      (const ['location'], [StartRequirement.location]),
      (
        const ['precise', 'alarmChannel'],
        [StartRequirement.precise, StartRequirement.alarmChannel],
      ),
      (const ['locationServices'], [StartRequirement.locationServices]),
      (const ['bogus'], null),
      (const <String>[], null),
      ('precise', null),
      (null, null),
      (const [1, 2], null),
    ]) {
      test('permission-missing details $details', () async {
        final r = _Rig()
          ..bridge.startTripError = _err(
            BridgeErrorCode.permissionMissing,
            details: details,
          );
        final o = await r.start();
        if (missing == null) {
          expect(_error(o), StartError.generic);
        } else {
          expect((o as StartBlocked).missing, missing);
        }
        expect(r.trips.rows, isEmpty);
      });
    }
  });

  test('blocked before startTrip: nothing written, nothing started', () async {
    for (final (status, device) in [
      (androidPermissions(location: LocationAccessMsg.denied), androidDevice()),
      (androidPermissions(precise: PermissionStateMsg.denied), androidDevice()),
      (androidPermissions(locationServicesEnabled: false), androidDevice()),
      (
        iosPermissions(
          notifications: PermissionStateMsg.denied,
          alarmKit: PermissionStateMsg.denied,
        ),
        iosDevice(),
      ),
    ]) {
      final r = _Rig(
        bridge: FakeCoreBridge(permissions: status, deviceInfoValue: device),
      );
      final o = await r.start();
      expect(o, isA<StartBlocked>());
      expect(r.bridge.callCount('startTrip'), 0);
      expect(r.bridge.callCount('insertStarted'), 0);
      expect(r.bridge.callCount('currentTrip'), 0);
    }
  });
}
