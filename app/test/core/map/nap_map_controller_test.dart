// T23.3 MC01-MC06: the Dart end of the per-view map channel.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_controller.dart';

const _s1 = NapMapState(pin: MapPoint(16.47, 107.59), radiusM: 1000);
const _s2 = NapMapState(pin: MapPoint(17.47, 106.62), radiusM: 1000);
const _f1 = NapMapFrame(
  bounds: MapBounds(south: 16, west: 107, north: 17, east: 108),
  padding: (top: 1, left: 2, bottom: 3, right: 4),
);

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Records what Dart sends on channel [id]; [fail] makes every call throw.
List<MethodCall> _record(int id, {bool fail = false}) {
  final calls = <MethodCall>[];
  final channel = MethodChannel(napMapChannelName(id));
  _messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    if (fail) {
      throw PlatformException(code: 'boom');
    }
    return null;
  });
  addTearDown(() => _messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// Native → Dart call on channel [id].
Future<void> _emit(int id, String method, [Object? args]) =>
    _messenger.handlePlatformMessage(
      napMapChannelName(id),
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MC01 calls before attach are sent on attach, state first', () async {
    final calls = _record(7);
    final c = NapMapController(onEvent: (_) {}, onChannelError: () {});
    await c.setState(_s1);
    await c.frame(_f1);
    expect(calls, isEmpty);
    expect(c.isAttached, isFalse);
    c.attach(7);
    await pumpEventQueue();
    expect(c.viewId, 7);
    expect(calls.map((m) => m.method), ['setState', 'frame']);
    expect(calls[0].arguments, _s1.toWire());
    expect(calls[1].arguments, _f1.toWire());
    c.dispose();
  });

  test('MC02 an equal state is sent once', () async {
    final calls = _record(8);
    final c = NapMapController(onEvent: (_) {}, onChannelError: () {})
      ..attach(8);
    await c.setState(_s1);
    await c.setState(_s1);
    await c.setState(_s2);
    await c.setState(_s2);
    expect(calls.map((m) => m.arguments), [_s1.toWire(), _s2.toWire()]);
    // Frames are always sent (a new request may frame the same box).
    await c.frame(_f1);
    await c.frame(_f1);
    expect(calls.where((m) => m.method == 'frame'), hasLength(2));
    c.dispose();
  });

  test('MC03 events reach onEvent; bad payloads are dropped', () async {
    final events = <NapMapEvent>[];
    final c = NapMapController(onEvent: events.add, onChannelError: () {})
      ..attach(9);
    await _emit(9, 'longPress', [16.47, 107.59]);
    expect(events.single, isA<NapMapLongPress>());
    expect(
      (events.single as NapMapLongPress).at,
      const MapPoint(16.47, 107.59),
    );
    await _emit(9, 'longPress', [91.0, 0.0]);
    await _emit(9, 'longPress', 'x');
    await _emit(9, 'whatever');
    expect(events, hasLength(1));
    await _emit(9, 'ready');
    await _emit(9, 'pinDragEnd', [17.0, 106.0]);
    await _emit(9, 'loadFailed');
    expect(events.map((e) => e.runtimeType), [
      NapMapLongPress,
      NapMapReady,
      NapMapPinDragEnd,
      NapMapLoadFailed,
    ]);
    c.dispose();
  });

  test('MC04 a failing channel never throws, reported once', () async {
    final calls = _record(10, fail: true);
    var errors = 0;
    final c = NapMapController(onEvent: (_) {}, onChannelError: () => errors++)
      ..attach(10);
    await c.setState(_s1);
    await c.frame(_f1);
    await c.setState(_s2);
    expect(errors, 1);
    expect(calls, hasLength(3));
    // Not applied natively: the same state is tried again.
    await c.setState(_s2);
    expect(calls, hasLength(4));
    c.dispose();
  });

  test('MC04 a missing plugin is caught too', () async {
    var errors = 0;
    final c = NapMapController(onEvent: (_) {}, onChannelError: () => errors++)
      ..attach(11); // No handler: MissingPluginException.
    await c.setState(_s1);
    expect(errors, 1);
    c.dispose();
  });

  test('MC05 after dispose nothing is sent or received', () async {
    final calls = _record(12);
    final events = <NapMapEvent>[];
    final c = NapMapController(onEvent: events.add, onChannelError: () {})
      ..attach(12)
      ..dispose();
    await c.setState(_s1);
    await c.frame(_f1);
    await _emit(12, 'longPress', [16.47, 107.59]);
    expect(calls, isEmpty);
    expect(events, isEmpty);
    // Attach after dispose is a no-op too.
    c.attach(13);
    expect(c.isAttached, isFalse);
  });

  test('MC05 a custom channel factory is used', () async {
    final calls = _record(99);
    final c = NapMapController(
      onEvent: (_) {},
      onChannelError: () {},
      channelFor: (_) => MethodChannel(napMapChannelName(99)),
    )..attach(1);
    await c.setState(_s1);
    expect(calls, hasLength(1));
    c.dispose();
  });

  test('MC06 no logging in the map code (D16)', () {
    final roots = [
      'lib/core/map',
      'ios/Core/Sources/NapStopIOS/Map',
      'ios/Runner/Map',
    ];
    final files = [
      for (final r in roots)
        ...Directory(r).listSync(recursive: true).whereType<File>(),
      File(
        'lib/features/destination/presentation/widgets/apple_destination_map.dart',
      ),
      File('lib/features/tracking/presentation/widgets/tracking_map_card.dart'),
    ].where((f) => f.path.endsWith('.dart') || f.path.endsWith('.swift'));
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'log(': RegExp(r'\blog\('),
      'os_log': RegExp(r'\bos_log\b'),
      'NSLog': RegExp(r'\bNSLog\b'),
      'Logger': RegExp(r'\bLogger\b'),
      'dart:developer': RegExp('dart:developer'),
    };
    final names = <String>[];
    for (final f in files) {
      names.add(f.path.replaceAll(r'\', '/'));
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${f.path}');
      }
    }
    expect(
      names.where((n) => n.endsWith('.swift')),
      hasLength(greaterThanOrEqualTo(3)),
    );
    expect(
      names.where((n) => n.endsWith('.dart')),
      hasLength(greaterThanOrEqualTo(7)),
    );
  });
}
