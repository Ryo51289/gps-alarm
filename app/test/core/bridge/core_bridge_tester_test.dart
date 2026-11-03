// Tester additions for T14 (beyond D02-D08): error mapping on every call and
// code, update-stream subscription sequences (review M5, R2-2), and the
// pendingFinishedTrips/ackFinishedTrips round trip.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_bridge.dart';

import 'bridge_samples.dart';

const _prefix = 'dev.flutter.pigeon.napstop';
const _channel = EventChannel(
  '$_prefix.TripEventChannelApi.tripUpdates',
  pigeonMethodCodec,
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Every host method, with a call through [CoreBridge].
final _calls = <String, Future<Object?> Function(CoreBridge)>{
  'TripHostApi.startTrip': (b) =>
      b.startTrip(sampleConfig(), destLat: 16.8, destLng: 107.1),
  'TripHostApi.stopTrip': (b) => b.stopTrip('t1'),
  'TripHostApi.currentTrip': (b) => b.currentTrip(),
  'TripHostApi.setBatteryChoice': (b) =>
      b.setBatteryChoice('t1', BatteryChoiceMsg.maxSaving),
  'TripHostApi.dismiss': (b) => b.dismiss('t1'),
  'TripHostApi.snooze': (b) => b.snooze('t1'),
  'TripHostApi.pendingFinishedTrips': (b) => b.pendingFinishedTrips(),
  'TripHostApi.ackFinishedTrips': (b) => b.ackFinishedTrips(['t1']),
  'PermissionHostApi.status': (b) => b.permissionStatus(),
  'PermissionHostApi.request': (b) =>
      b.requestPermission(PermissionKindMsg.location),
  'PermissionHostApi.openSettings': (b) =>
      b.openSettings(SettingsTargetMsg.appDetails),
  'PermissionHostApi.deviceInfo': (b) => b.deviceInfo(),
  // T14.1 tester.
  'PermissionHostApi.deviceStatus': (b) => b.deviceStatus(),
  // T23 coder: new host methods join the error-mapping loops.
  'PermissionHostApi.mapsConfig': (b) => b.mapsConfig(),
  'PermissionHostApi.distancesFromLastKnownM': (b) =>
      b.distancesFromLastKnownM([16.8, 107.1], 1800000),
  // T21: screen 9 background check.
  'PermissionHostApi.startBackgroundCheck': (b) =>
      b.startBackgroundCheck(const Duration(seconds: 30)),
  'PermissionHostApi.backgroundCheck': (b) => b.backgroundCheck(),
  'PermissionHostApi.cancelBackgroundCheck': (b) => b.cancelBackgroundCheck(),
  'AlarmHostApi.previewSound': (b) => b.previewSound('chime', 0.5),
  'AlarmHostApi.stopPreview': (b) => b.stopPreview(),
};

void _handle(String name, List<Object?> Function(List<Object?> args) reply) {
  _messenger.setMockDecodedMessageHandler<Object?>(
    BasicMessageChannel<Object?>(
      '$_prefix.$name',
      TripHostApi.pigeonChannelCodec,
    ),
    (message) async => reply((message as List<Object?>?) ?? const []),
  );
}

Future<BridgeException> _failure(Future<Object?> call) async {
  try {
    await call;
  } on BridgeException catch (e) {
    return e;
  }
  fail('expected BridgeException');
}

AlarmMsg _alarm(int atMs) => AlarmMsg(
  tripId: 't1',
  atMs: atMs,
  reason: AlarmReasonMsg.smartTime,
  ringNow: true,
  snoozeAllowed: true,
);

TripStateUpdateMsg _state(String tripId, int atMs) => TripStateUpdateMsg(
  state: sampleState()
    ..tripId = tripId
    ..atMs = atMs,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CoreBridge bridge;
  setUp(() => bridge = CoreBridge());

  tearDown(() {
    for (final name in _calls.keys) {
      _messenger.setMockMessageHandler('$_prefix.$name', null);
    }
    _messenger.setMockStreamHandler(_channel, null);
  });

  group('error mapping', () {
    test('the call table covers every host method of the Pigeon input', () {
      // T14.1 tester: a method added later (like deviceStatus) cannot be left
      // out of the error-mapping loops below.
      final code = File('pigeons/core_api.dart').readAsStringSync();
      final methods = <String>{};
      for (final api in RegExp(
        r'@HostApi\(\)\s*abstract class (\w+) \{([\s\S]*?)\n\}',
      ).allMatches(code)) {
        final body = api[2]!
            .split('\n')
            .map((l) => l.replaceFirst(RegExp('//.*'), ''))
            .join(' ');
        // Signatures may span lines (startTrip): match on the joined body.
        final signature = RegExp(r'[\w<>?]+\s+(\w+)\(([^()]*)\);');
        for (final m in signature.allMatches(body)) {
          methods.add('${api[1]}.${m[1]}');
        }
      }
      expect(methods, hasLength(greaterThanOrEqualTo(15)));
      expect(methods, contains('PermissionHostApi.deviceStatus'));
      expect(_calls.keys.toSet(), methods);
    });

    test('every wire code, message and details survive the bridge', () async {
      for (final code in BridgeErrorCode.values) {
        if (code == BridgeErrorCode.unknown) {
          continue;
        }
        final details = code == BridgeErrorCode.permissionMissing
            ? <Object?>['location', 'precise']
            : null;
        _handle(
          'TripHostApi.startTrip',
          (_) => [code.wire, 'msg ${code.name}', details],
        );
        final e = await _failure(
          bridge.startTrip(sampleConfig(), destLat: 16.8, destLng: 107.1),
        );
        expect(e.code, code, reason: code.wire);
        expect(e.rawCode, code.wire);
        expect(e.message, 'msg ${code.name}');
        expect(e.details, details);
        expect(e.toString(), 'BridgeException(${code.wire})');
        expect(e.toString(), isNot(contains('msg')));
      }
    });

    test('wire codes are matched exactly', () {
      for (final raw in ['INTERNAL', ' internal', 'internal ', 'trip_active']) {
        expect(BridgeErrorCode.fromWire(raw), BridgeErrorCode.unknown);
      }
      expect(
        BridgeErrorCode.values.map((c) => c.wire).toSet().length,
        BridgeErrorCode.values.length,
        reason: 'wire codes are unique',
      );
    });

    test('every CoreBridge method maps a native error', () async {
      for (final name in _calls.keys) {
        _handle(name, (_) => ['internal', 'IllegalStateException', null]);
      }
      for (final MapEntry(key: name, value: call) in _calls.entries) {
        final e = await _failure(call(bridge));
        expect(e.code, BridgeErrorCode.internal, reason: name);
        expect(e.message, 'IllegalStateException', reason: name);
      }
    });

    test('every CoreBridge method without a native handler', () async {
      for (final MapEntry(key: name, value: call) in _calls.entries) {
        final e = await _failure(call(bridge));
        expect(e.code, BridgeErrorCode.channelError, reason: name);
        expect(e.rawCode, 'channel-error', reason: name);
      }
    });
  });

  group('updates subscriptions', () {
    late int listens;
    late int cancels;
    MockStreamHandlerEventSink? native;
    late TripStateUpdateMsg replay;
    final subscriptions = <StreamSubscription<TripUpdateMsg>>[];

    setUp(() {
      listens = 0;
      cancels = 0;
      native = null;
      replay = _state('t1', 1);
      _messenger.setMockStreamHandler(
        _channel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            listens++;
            native = events..success(replay);
          },
          onCancel: (arguments) {
            cancels++;
            native = null;
          },
        ),
      );
    });

    tearDown(() async {
      for (final s in subscriptions) {
        await s.cancel();
      }
      subscriptions.clear();
    });

    Future<List<TripUpdateMsg>> subscribe() async {
      final items = <TripUpdateMsg>[];
      subscriptions.add(bridge.updates.listen(items.add));
      await pumpEventQueue();
      return items;
    }

    Future<void> send(TripUpdateMsg update) async {
      native!.success(update);
      await pumpEventQueue();
    }

    test('native listens once and cancels after the last subscriber', () async {
      final a = await subscribe();
      final b = await subscribe();
      expect((listens, cancels), (1, 0));
      expect(a, [replay]);
      expect(b, [replay]);

      await subscriptions.removeAt(0).cancel();
      await pumpEventQueue();
      expect(cancels, 0, reason: 'B still listens');
      await send(_state('t1', 2));
      expect(b.last, _state('t1', 2));

      await subscriptions.removeAt(0).cancel();
      await pumpEventQueue();
      expect((listens, cancels), (1, 1));
      expect(native, isNull);
    });

    test('cancel / re-listen cycles never replay a stale state', () async {
      for (var round = 0; round < 5; round++) {
        replay = _state('t1', 100 + round);
        final items = await subscribe();
        expect(items, [replay], reason: 'round $round');
        await send(_state('t1', 200 + round));
        await subscriptions.removeLast().cancel();
        await pumpEventQueue();
      }
      expect((listens, cancels), (5, 5));
    });

    test(
      'updates.first takes the replay and leaves no subscriber behind',
      () async {
        final a = await subscribe();
        await send(_state('t1', 2));
        expect(a, [replay, _state('t1', 2)]);

        // A short-lived reader (e.g. a FutureProvider) gets the latest state.
        expect(await bridge.updates.first, _state('t1', 2));
        await pumpEventQueue();

        await subscriptions.removeLast().cancel();
        await pumpEventQueue();
        expect(cancels, 1, reason: 'the count of subscribers went back to 0');

        replay = _state('t1', 3);
        final b = await subscribe();
        expect(b, [_state('t1', 3)], reason: 'fresh native replay only');
      },
    );

    test('events are never replayed, only the latest state', () async {
      final a = await subscribe();
      await send(_state('t1', 2));
      for (final u in sampleUpdates(nulls: false)) {
        if (u is TripStateUpdateMsg || u is TripEndedMsg) {
          continue;
        }
        await send(u);
      }
      expect(a.length, 2 + 8);
      final b = await subscribe();
      expect(b, [_state('t1', 2)]);
    });

    test('TripEndedMsg clears only its own trip', () async {
      await subscribe();
      await send(_state('t2', 5));
      // A late record of another trip (t1) does not drop t2's view.
      await send(TripEndedMsg(atMs: 6, trip: sampleFinished()));
      expect(await subscribe(), [_state('t2', 5)]);

      await send(TripEndedMsg(atMs: 7, trip: sampleFinished(tripId: 't2')));
      expect(await subscribe(), isEmpty);

      // Next trip: its first state is kept again.
      await send(_state('t3', 8));
      expect(await subscribe(), [_state('t3', 8)]);
    });

    test(
      'R2-2 (known limitation, for T26): while every subscription is paused '
      'a new subscriber starts with the state seen before the pause',
      () async {
        final items = <TripUpdateMsg>[];
        final a = bridge.updates.listen(items.add);
        subscriptions.add(a);
        await pumpEventQueue();
        a.pause();
        await send(_state('t1', 2)); // buffered for A, not remembered yet

        final b = await subscribe();
        expect(b, [replay], reason: 'stale until the next Step');
        expect(b.first, isNot(_state('t1', 2)));

        a.resume();
        await pumpEventQueue();
        expect(items, [replay, _state('t1', 2)]);
        // Once A has seen it, later subscribers get the newer state.
        expect(await subscribe(), [_state('t1', 2)]);
      },
    );

    test('a native error event does not close the stream', () async {
      final items = <TripUpdateMsg>[];
      final errors = <Object>[];
      subscriptions.add(bridge.updates.listen(items.add, onError: errors.add));
      await pumpEventQueue();
      native!.error(code: 'internal', message: 'IllegalStateException');
      await pumpEventQueue();
      await send(_alarm(3));
      expect(errors.single, isA<PlatformException>());
      expect(items, [replay, _alarm(3)]);
    });
  });

  group('pendingFinishedTrips / ackFinishedTrips', () {
    test('two-phase history hand-off against a native queue', () async {
      // Native queue, oldest endedAtMs first (D12); ack ignores unknown ids.
      final queue = [
        sampleFinished(),
        sampleFinished(nulls: true, tripId: 't2'),
        sampleFinished(tripId: 't3')..endedAtMs = 1700000030000,
      ];
      final acks = <List<Object?>>[];
      _handle('TripHostApi.pendingFinishedTrips', (_) => [queue.toList()]);
      _handle('TripHostApi.ackFinishedTrips', (args) {
        acks.add(args);
        final ids = (args.single! as List<Object?>).cast<String>().toSet();
        queue.removeWhere((t) => ids.contains(t.tripId));
        return [null];
      });

      final first = await bridge.pendingFinishedTrips();
      expect(first.map((t) => t.tripId), ['t1', 't2', 't3']);
      expect(first[1], sampleFinished(nulls: true, tripId: 't2'));
      // Reading does not consume: the app may die before writing drift.
      expect(await bridge.pendingFinishedTrips(), first);

      await bridge.ackFinishedTrips(['t1', 'unknown']);
      await bridge.ackFinishedTrips(['t1']); // idempotent
      await bridge.ackFinishedTrips([]);
      expect(acks, [
        [
          ['t1', 'unknown'],
        ],
        [
          ['t1'],
        ],
        [<Object?>[]],
      ]);
      expect((await bridge.pendingFinishedTrips()).map((t) => t.tripId), [
        't2',
        't3',
      ]);
    });

    test('empty queue is an empty list', () async {
      _handle('TripHostApi.pendingFinishedTrips', (_) => [<Object?>[]]);
      expect(await bridge.pendingFinishedTrips(), isEmpty);
    });
  });
}
