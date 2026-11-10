// T23.5 AS-D06, AS-D08: wire format of the address channel, same cases as
// the Swift side (fixtures/address_search_wire/cases.json).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/features/destination/data/address_search_wire.dart';
import 'package:napstop/features/destination/domain/address_search.dart';

Map<String, Object?> _cases() => jsonDecode(
  File('../fixtures/address_search_wire/cases.json').readAsStringSync(),
) as Map<String, Object?>;

List<Map<String, Object?>> _list(String k) =>
    (_cases()[k]! as List).cast<Map<String, Object?>>();

void main() {
  test('AS-D06 encode', () {
    final c = encodeComplete(
      gen: 7,
      query: 'nguyen trai',
      region: kVietnamBounds,
    );
    expect(c, _list('completeRequest').first['input']);
    expect(
      encodeResolve(gen: 7, index: 2),
      _list('resolveRequest').first['input'],
    );
  });

  test('AS-D06 completeReply cases', () {
    for (final c in _list('completeReply')) {
      final r = decodeCompleteReply(c['input']);
      final name = c['name']! as String;
      if (c['valid']! as bool) {
        expect(r, isNotNull, reason: name);
        expect(r!.gen, c['gen'], reason: name);
        expect(r.status.name, c['status'], reason: name);
        expect(r.items.length, c['count'], reason: name);
      } else {
        expect(r, isNull, reason: name);
      }
    }
  });

  test('AS-D06 resolveReply cases', () {
    for (final c in _list('resolveReply')) {
      final r = decodeResolveReply(c['input']);
      final name = c['name']! as String;
      if (c['valid']! as bool) {
        expect(r, isNotNull, reason: name);
        expect(r!.status.name, c['status'], reason: name);
        expect(r.point != null, r.status == AddressStatus.ok, reason: name);
      } else {
        expect(r, isNull, reason: name);
      }
    }
  });

  test('AS-D06 more than 15 items are cut; NaN lat is rejected', () {
    final r = decodeCompleteReply({
      'gen': 1,
      'status': 'ok',
      'items': [
        for (var i = 0; i < 20; i++) {'t': 'T$i', 's': ''},
      ],
    });
    expect(r!.items.length, kMaxAddressItems);
    expect(r.items.first.title, 'T0');
    expect(
      decodeResolveReply({'status': 'ok', 'lat': double.nan, 'lng': 105.0}),
      isNull,
    );
  });

  test('AS-D08 toString prints no text and no coordinates', () {
    final ok = decodeResolveReply({
      'status': 'ok',
      'lat': 21.0312,
      'lng': 105.8512,
      'country': 'VN',
    })!;
    expect(ok.toString(), isNot(matches(RegExp('21|105'))));
    final c = decodeCompleteReply({
      'gen': 1,
      'status': 'ok',
      'items': [
        {'t': 'Bí mật', 's': 'Kín'},
      ],
    })!;
    expect(c.toString(), isNot(contains('Bí')));
  });
}
