// T23.5 AS-D07: the MethodChannel client sends the right method and
// arguments and rejects malformed answers.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/data/address_search_client.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kAddressSearchChannel);
  final calls = <MethodCall>[];
  Object? answer;

  setUp(() {
    calls.clear();
    answer = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answer;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  const client = MethodChannelAddressSearchClient();

  test('complete sends v, gen, query and the Vietnam region', () async {
    answer = {'gen': 4, 'status': 'ok', 'items': <Object?>[]};
    final r = await client.complete(gen: 4, query: 'kim ma');
    expect(r.status, AddressStatus.ok);
    expect(calls.single.method, 'complete');
    final args = calls.single.arguments as Map;
    expect(args['v'], 1);
    expect(args['gen'], 4);
    expect(args['query'], 'kim ma');
    expect((args['region'] as Map).keys, containsAll(['s', 'w', 'n', 'e']));
  });

  test('resolve and cancel', () async {
    answer = {'status': 'ok', 'lat': 21.0, 'lng': 105.8, 'country': 'VN'};
    final r = await client.resolve(gen: 4, index: 1);
    expect(r.point, isNotNull);
    expect(calls.single.method, 'resolve');
    expect(calls.single.arguments, {'v': 1, 'gen': 4, 'index': 1});
    answer = null;
    await client.cancel();
    expect(calls.last.method, 'cancel');
    expect(calls.last.arguments, isNull);
  });

  test('a malformed or null answer throws the protocol exception', () async {
    answer = null;
    await expectLater(
      client.complete(gen: 1, query: 'abc'),
      throwsA(isA<AddressSearchProtocolException>()),
    );
    answer = {'status': 'ok'};
    await expectLater(
      client.resolve(gen: 1, index: 0),
      throwsA(isA<AddressSearchProtocolException>()),
    );
  });
}
