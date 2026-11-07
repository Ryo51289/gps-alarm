// D02-D08 (spec T14): CoreBridge over the generated API, with mock handlers
// on the test binary messenger.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/features/simulation/domain/sim_trace.dart';

import 'bridge_samples.dart';

const _prefix = 'dev.flutter.pigeon.napstop';
const _eventChannel = '$_prefix.TripEventChannelApi.tripUpdates';

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Registers [reply] on `<prefix>.<api>.<method>`; records the decoded args.
List<List<Object?>> _handle(
  String api,
  String method,
  List<Object?> Function(List<Object?> args) reply, [
  List<List<Object?>>? calls,
]) {
  final channel = BasicMessageChannel<Object?>(
    '$_prefix.$api.$method',
    TripHostApi.pigeonChannelCodec,
  );
  final seen = calls ?? <List<Object?>>[];
  _messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
    final args = (message as List<Object?>?) ?? const <Object?>[];
    seen.add(args);
    return reply(args);
  });
  return seen;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CoreBridge bridge;
  setUp(() => bridge = CoreBridge());

  tearDown(() {
    // Drop every mock handler between tests.
    for (final name in [
      'TripHostApi.startTrip',
      'TripHostApi.stopTrip',
      'TripHostApi.currentTrip',
      'TripHostApi.setBatteryChoice',
      'TripHostApi.dismiss',
      'TripHostApi.snooze',
      'TripHostApi.pendingFinishedTrips',
      'TripHostApi.ackFinishedTrips',
      'PermissionHostApi.status',
      'PermissionHostApi.request',
      'PermissionHostApi.openSettings',
      'PermissionHostApi.deviceInfo',
      'PermissionHostApi.deviceStatus',
      'PermissionHostApi.distancesFromLastKnownM',
      'AlarmHostApi.previewSound',
      'AlarmHostApi.stopPreview',
    ]) {
      _messenger.setMockMessageHandler('$_prefix.$name', null);
    }
    _messenger.setMockStreamHandler(
      const EventChannel(_eventChannel, pigeonMethodCodec),
      null,
    );
  });

  test('D02 startTrip sends config, coordinates and simulation', () async {
    final calls = _handle('TripHostApi', 'startTrip', (_) => [null]);
    await bridge.startTrip(sampleConfig(), destLat: 17.47, destLng: 106.6);
    expect(calls, [
      [sampleConfig(), 17.47, 106.6, null],
    ]);

    await bridge.startTrip(
      sampleConfig(),
      destLat: 17.47,
      destLng: 106.6,
      simulation: SimulationMsg(
        traceAsset: SimTraces.trainHnDh,
        speedFactor: 60,
      ),
    );
    expect(
      calls.last.last,
      SimulationMsg(traceAsset: 'train_hn_dh', speedFactor: 60),
    );
  });

  test('D03 native error becomes BridgeException without leaking', () async {
    _handle(
      'TripHostApi',
      'startTrip',
      (_) => ['invalid-config', 'destLat: out of range', null],
    );
    final error = await bridge
        .startTrip(sampleConfig(), destLat: 99, destLng: 106.6)
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(error, isA<BridgeException>());
    final e = error! as BridgeException;
    expect(e.code, BridgeErrorCode.invalidConfig);
    expect(e.rawCode, 'invalid-config');
    expect(e.message, 'destLat: out of range');
    expect(e.details, isNull);
    expect(e.toString(), 'BridgeException(invalid-config)');
    expect(e.toString(), isNot(contains('destLat')));
  });

  test('D03 every wire code maps to its enum value', () {
    for (final code in BridgeErrorCode.values) {
      if (code == BridgeErrorCode.unknown) {
        continue;
      }
      expect(BridgeErrorCode.fromWire(code.wire), code);
    }
    expect(BridgeErrorCode.fromWire(''), BridgeErrorCode.unknown);
  });

  test('D04 unknown code', () async {
    _handle('TripHostApi', 'stopTrip', (_) => ['weird', null, null]);
    await expectLater(
      bridge.stopTrip('t1'),
      throwsA(
        isA<BridgeException>()
            .having((e) => e.code, 'code', BridgeErrorCode.unknown)
            .having((e) => e.rawCode, 'rawCode', 'weird'),
      ),
    );
  });

  test('D05 no native handler is channelError', () async {
    await expectLater(
      bridge.currentTrip(),
      throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          BridgeErrorCode.channelError,
        ),
      ),
    );
  });

  test('D06 currentTrip null, then a trip', () async {
    var call = 0;
    _handle(
      'TripHostApi',
      'currentTrip',
      (_) => [if (call++ == 0) null else sampleActive()],
    );
    expect(await bridge.currentTrip(), isNull);
    expect(await bridge.currentTrip(), sampleActive());
  });

  test('D07 one shared update stream, items in order', () async {
    _messenger.setMockStreamHandler(
      const EventChannel(_eventChannel, pigeonMethodCodec),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(TripStateUpdateMsg(state: sampleState()))
            ..success(
              AlarmMsg(
                tripId: 't1',
                atMs: 2,
                reason: AlarmReasonMsg.smartTime,
                ringNow: true,
                snoozeAllowed: true,
              ),
            );
        },
      ),
    );
    expect(identical(bridge.updates, bridge.updates), isTrue);
    expect(bridge.updates.isBroadcast, isTrue);

    final items = await bridge.updates.take(2).toList();
    expect(items.first, isA<TripStateUpdateMsg>());
    expect((items.first as TripStateUpdateMsg).state, sampleState());
    expect(items.last, isA<AlarmMsg>());
    expect((items.last as AlarmMsg).reason, AlarmReasonMsg.smartTime);
  });

  test('D07 custom single-subscription factory is made broadcast', () async {
    final controller = StreamController<TripUpdateMsg>();
    final custom = CoreBridge(updatesFactory: () => controller.stream);
    expect(custom.updates.isBroadcast, isTrue);
    final first = custom.updates.first;
    controller.add(SnoozedMsg(tripId: 't1', atMs: 1, untilMs: 2));
    expect(await first, isA<SnoozedMsg>());
    await controller.close();
  });

  group('M5 replay of the latest state per subscriber', () {
    const channel = EventChannel(_eventChannel, pigeonMethodCodec);
    final replayed = TripStateUpdateMsg(state: sampleState());
    final newer = TripStateUpdateMsg(state: sampleState()..atMs = 99);
    final alarm = AlarmMsg(
      tripId: 't1',
      atMs: 2,
      reason: AlarmReasonMsg.smartTime,
      ringNow: true,
      snoozeAllowed: true,
    );

    late int listens;
    late MockStreamHandlerEventSink native;
    late List<StreamSubscription<TripUpdateMsg>> subscriptions;
    setUp(() {
      listens = 0;
      subscriptions = [];
      _messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            // Native replays the latest view on onListen (T14 §2 rule 2).
            listens++;
            native = events..success(replayed);
          },
        ),
      );
    });

    tearDown(() async {
      for (final s in subscriptions) {
        await s.cancel();
      }
    });

    /// A new subscriber to `bridge.updates`; returns what it receives.
    Future<List<TripUpdateMsg>> subscribe() async {
      final items = <TripUpdateMsg>[];
      subscriptions.add(bridge.updates.listen(items.add));
      await pumpEventQueue();
      return items;
    }

    test(
      'a later subscriber gets the latest state, never old events',
      () async {
        final first = await subscribe();
        expect(first, [replayed]);

        native.success(alarm);
        await pumpEventQueue();
        final second = await subscribe();
        expect(listens, 1, reason: 'one native listen for the broadcast');
        expect(second, [replayed]);

        native.success(newer);
        await pumpEventQueue();
        final third = await subscribe();
        expect(third, [newer]);
        expect(first, [replayed, alarm, newer]);
        expect(second, [replayed, newer]);

        // After the trip's TripEndedMsg nothing is replayed (T14 §2 rule 5).
        native.success(TripEndedMsg(atMs: 100, trip: sampleFinished()));
        await pumpEventQueue();
        final fourth = await subscribe();
        expect(fourth, isEmpty);
        expect(third.last, isA<TripEndedMsg>());
      },
    );

    test('nothing stale once every subscriber has left', () async {
      final first = await subscribe();
      native.success(newer);
      await pumpEventQueue();
      expect(first, [replayed, newer]);
      await subscriptions.removeLast().cancel();

      // A new first subscriber: only the fresh native replay, not `newer`.
      final second = await subscribe();
      expect(listens, 2);
      expect(second, [replayed]);
    });
  });

  group('D08 every other call', () {
    test('TripHostApi', () async {
      final calls = <String, List<List<Object?>>>{};
      List<Object?> Function(List<Object?>) ok(Object? result) =>
          (_) => [result];
      for (final (method, result) in <(String, Object?)>[
        ('stopTrip', null),
        ('setBatteryChoice', null),
        ('dismiss', null),
        ('snooze', null),
        ('pendingFinishedTrips', [sampleFinished()]),
        ('ackFinishedTrips', null),
      ]) {
        calls[method] = _handle('TripHostApi', method, ok(result));
      }

      await bridge.stopTrip('t1');
      await bridge.setBatteryChoice('t1', BatteryChoiceMsg.alarmEarlier);
      await bridge.dismiss('t1');
      await bridge.snooze('t1');
      expect(await bridge.pendingFinishedTrips(), [sampleFinished()]);
      await bridge.ackFinishedTrips(['t1', 't2']);

      expect(calls['stopTrip'], [
        ['t1'],
      ]);
      expect(calls['setBatteryChoice'], [
        ['t1', BatteryChoiceMsg.alarmEarlier],
      ]);
      expect(calls['dismiss'], [
        ['t1'],
      ]);
      expect(calls['snooze'], [
        ['t1'],
      ]);
      expect(calls['pendingFinishedTrips'], [<Object?>[]]);
      expect(calls['ackFinishedTrips'], [
        [
          ['t1', 't2'],
        ],
      ]);
    });

    test('PermissionHostApi', () async {
      final status = _handle(
        'PermissionHostApi',
        'status',
        (_) => [samplePermissions()],
      );
      final request = _handle(
        'PermissionHostApi',
        'request',
        (_) => [samplePermissions()],
      );
      final open = _handle('PermissionHostApi', 'openSettings', (_) => [true]);
      _handle('PermissionHostApi', 'deviceInfo', (_) => [sampleDevice()]);

      expect(await bridge.permissionStatus(), samplePermissions());
      expect(
        await bridge.requestPermission(PermissionKindMsg.notifications),
        samplePermissions(),
      );
      expect(
        await bridge.openSettings(SettingsTargetMsg.batteryOptimization),
        isTrue,
      );
      expect(await bridge.deviceInfo(), sampleDevice());
      expect(status, [<Object?>[]]);
      expect(request, [
        [PermissionKindMsg.notifications],
      ]);
      expect(open, [
        [SettingsTargetMsg.batteryOptimization],
      ]);
    });

    test('PermissionHostApi.deviceStatus (T14.1)', () async {
      final calls = <List<Object?>>[];
      var reply = sampleDeviceStatus();
      _handle('PermissionHostApi', 'deviceStatus', (_) => [reply], calls);

      expect(await bridge.deviceStatus(), sampleDeviceStatus());
      reply = sampleDeviceStatus(nulls: true);
      final unknown = await bridge.deviceStatus();
      expect(unknown, sampleDeviceStatus(nulls: true));
      expect(unknown.batteryPct, isNull);
      expect(unknown.charging, isNull);
      expect(unknown.interruptionFilter, InterruptionFilterMsg.unknown);
      expect(calls, [<Object?>[], <Object?>[]]);
    });

    test('deviceStatus errors become BridgeException (T14.1)', () async {
      _handle(
        'PermissionHostApi',
        'deviceStatus',
        (_) => ['internal', 'SecurityException', null],
      );
      await expectLater(
        bridge.deviceStatus(),
        throwsA(
          isA<BridgeException>()
              .having((e) => e.code, 'code', BridgeErrorCode.internal)
              .having((e) => e.message, 'message', 'SecurityException'),
        ),
      );
      _messenger.setMockMessageHandler(
        '$_prefix.PermissionHostApi.deviceStatus',
        null,
      );
      await expectLater(
        bridge.deviceStatus(),
        throwsA(
          isA<BridgeException>().having(
            (e) => e.code,
            'code',
            BridgeErrorCode.channelError,
          ),
        ),
      );
    });

    test('TB01 distancesFromLastKnownM (T23)', () async {
      final calls = <List<Object?>>[];
      List<Object?>? reply = <Object?>[402000.0, 12.5];
      _handle(
        'PermissionHostApi',
        'distancesFromLastKnownM',
        (_) => [reply],
        calls,
      );
      expect(
        await bridge.distancesFromLastKnownM([
          17.47,
          106.6,
          16.0,
          108.2,
        ], 1800000),
        [402000.0, 12.5],
      );
      expect(calls, [
        [
          [17.47, 106.6, 16.0, 108.2],
          1800000,
        ],
      ]);
      reply = null;
      expect(await bridge.distancesFromLastKnownM([17.47, 106.6], 1), isNull);
    });

    test('TB01 T23 method maps errors to BridgeException', () async {
      _handle(
        'PermissionHostApi',
        'distancesFromLastKnownM',
        (_) => ['internal', null, null],
      );
      final internal = throwsA(
        isA<BridgeException>().having(
          (e) => e.code,
          'code',
          BridgeErrorCode.internal,
        ),
      );
      await expectLater(bridge.distancesFromLastKnownM([1, 2], 1), internal);
    });

    test('startTrip sends engineParamsJson verbatim (T14.1)', () async {
      final calls = _handle('TripHostApi', 'startTrip', (_) => [null]);
      const json = '{"smartTargetS": 300, "smartSlowSpeedKmh": 5}';
      final config = sampleConfig()..engineParamsJson = json;
      await bridge.startTrip(config, destLat: 16.8, destLng: 107.1);
      final sent = calls.single.first! as TripConfigMsg;
      expect(sent.engineParamsJson, json);
      expect(sent, config);
    });

    test('native V11 rejection maps to invalidConfig (T14.1)', () async {
      _handle(
        'TripHostApi',
        'startTrip',
        (_) => ['invalid-config', 'engineParamsJson: too long', null],
      );
      final config = sampleConfig()..engineParamsJson = 'x' * 16385;
      await expectLater(
        bridge.startTrip(config, destLat: 16.8, destLng: 107.1),
        throwsA(
          isA<BridgeException>()
              .having((e) => e.code, 'code', BridgeErrorCode.invalidConfig)
              .having((e) => e.message, 'message', 'engineParamsJson: too long')
              .having((e) => e.toString(), 'toString', isNot(contains('xx'))),
        ),
      );
    });

    test('AlarmHostApi', () async {
      final preview = _handle('AlarmHostApi', 'previewSound', (_) => [null]);
      final stop = _handle('AlarmHostApi', 'stopPreview', (_) => [null]);
      await bridge.previewSound('chime', 0.5);
      await bridge.stopPreview();
      expect(preview, [
        ['chime', 0.5],
      ]);
      expect(stop, [<Object?>[]]);
    });

    test('errors are mapped on every API', () async {
      _handle(
        'PermissionHostApi',
        'request',
        (_) => ['request-in-progress', null, null],
      );
      await expectLater(
        bridge.requestPermission(PermissionKindMsg.location),
        throwsA(
          isA<BridgeException>().having(
            (e) => e.code,
            'code',
            BridgeErrorCode.requestInProgress,
          ),
        ),
      );
      await expectLater(
        bridge.stopPreview(),
        throwsA(
          isA<BridgeException>().having(
            (e) => e.code,
            'code',
            BridgeErrorCode.channelError,
          ),
        ),
      );
    });
  });
}
