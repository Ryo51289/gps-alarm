// T23.3 MW01-MW03, MW09: wire format v1 of the MapKit view.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/map/map_wire.dart';

const _pin = MapPoint(16.4637, 107.5909);

/// Every digit run of a coordinate, for the PRIVACY checks.
final _digits = RegExp('16|4637|107|5909');

Map<String, Object?> _cases() =>
    jsonDecode(File('../fixtures/map_wire/cases.json').readAsStringSync())
        as Map<String, Object?>;

List<Map<String, Object?>> _list(String key) =>
    (_cases()[key]! as List).cast<Map<String, Object?>>();

double? _d(Object? v) => (v as num?)?.toDouble();

MapPoint? _p(Object? v) {
  if (v == null) {
    return null;
  }
  final l = v as List;
  return MapPoint(_d(l[0])!, _d(l[1])!);
}

MapBounds _b(Object? v) {
  final m = v! as Map<String, Object?>;
  return MapBounds(
    south: _d(m['s'])!,
    west: _d(m['w'])!,
    north: _d(m['n'])!,
    east: _d(m['e'])!,
  );
}

NapMapState _state(Object? v) {
  final m = v! as Map<String, Object?>;
  return NapMapState(
    pin: _p(m['pin']),
    radiusM: _d(m['radiusM']),
    pinDraggable: m['pinDraggable']! as bool,
    longPress: m['longPress']! as bool,
    showsUser: m['showsUser']! as bool,
    dark: m['dark']! as bool,
    glyph: MapPinGlyph.fromWire(m['glyph']),
  );
}

NapMapFrame _frame(Object? v) {
  final m = v! as Map<String, Object?>;
  final pad = (m['pad']! as List).map(_d).toList();
  return NapMapFrame(
    bounds: _b(m['bounds']),
    padding: (top: pad[0]!, left: pad[1]!, bottom: pad[2]!, right: pad[3]!),
    animated: m['animated']! as bool,
    includeUser: m['includeUser']! as bool,
  );
}

/// Deep equality where numbers compare by value (1000 == 1000.0).
bool _same(Object? a, Object? b) {
  if (a is num && b is num) {
    return a.toDouble() == b.toDouble();
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_same(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    return a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  return a == b;
}

void main() {
  group('MW01 state toWire', () {
    test('with a pin and every flag', () {
      const s = NapMapState(
        pin: _pin,
        radiusM: 1000,
        pinDraggable: true,
        longPress: true,
        showsUser: true,
        dark: true,
      );
      final w = s.toWire();
      expect(w.keys, {
        'pin',
        'radiusM',
        'pinDraggable',
        'longPress',
        'showsUser',
        'dark',
      });
      expect(w['pin'], isA<List<double>>());
      expect(w['pin'], [16.4637, 107.5909]);
      expect(w['radiusM'], isA<double>());
      expect(w['radiusM'], 1000.0);
      expect(w['pinDraggable'], isTrue);
      expect(w['longPress'], isTrue);
      expect(w['showsUser'], isTrue);
      expect(w['dark'], isTrue);
      expect(_digits.hasMatch(s.toString()), isFalse, reason: '$s');
    });

    test('without a pin', () {
      const s = NapMapState();
      final w = s.toWire();
      expect(w['pin'], isNull);
      expect(w['radiusM'], isNull);
      expect(w['pinDraggable'], isFalse);
      expect(w['showsUser'], isFalse);
      expect(s.toString(), contains('pin: none'));
    });

    test('BS-W07 glyph: sent only when set, part of equality', () {
      const bus = NapMapState(pin: _pin, radiusM: 500, glyph: MapPinGlyph.bus);
      expect(bus.toWire()['glyph'], 'bus');
      expect(
        const NapMapState(pin: _pin).toWire().containsKey('glyph'),
        isFalse,
      );
      expect(bus == const NapMapState(pin: _pin, radiusM: 500), isFalse);
      expect(bus.copyWith(showsUser: true).glyph, MapPinGlyph.bus);
      expect(MapPinGlyph.fromWire('bus'), MapPinGlyph.bus);
      expect(MapPinGlyph.fromWire('tram'), isNull);
      expect(MapPinGlyph.fromWire(null), isNull);
      expect(MapPinGlyph.fromWire(1), isNull);
      expect(_digits.hasMatch(bus.toString()), isFalse);
    });

    test('equality covers every field', () {
      const a = NapMapState(pin: _pin, radiusM: 1000);
      expect(a, const NapMapState(pin: _pin, radiusM: 1000));
      expect(a.hashCode, const NapMapState(pin: _pin, radiusM: 1000).hashCode);
      expect(a == const NapMapState(pin: _pin, radiusM: 900), isFalse);
      expect(a == const NapMapState(pin: _pin), isFalse);
      expect(a == a.copyWith(showsUser: true), isFalse);
      expect(
        a == const NapMapState(pin: _pin, radiusM: 1000, dark: true),
        isFalse,
      );
    });

    test('frame, bounds and creation params', () {
      const bounds = MapBounds(south: 1, west: 2, north: 3, east: 4);
      const f = NapMapFrame(
        bounds: bounds,
        padding: (top: 10, left: 20, bottom: 30, right: 40),
        includeUser: true,
      );
      expect(f.toWire(), {
        'bounds': {'s': 1.0, 'w': 2.0, 'n': 3.0, 'e': 4.0},
        'pad': [10.0, 20.0, 30.0, 40.0],
        'animated': true,
        'includeUser': true,
      });
      final c = creationParams(
        state: const NapMapState(pin: _pin),
        initial: bounds,
        accentArgb: 0xFF2B4FEC,
        pinLabel: 'Điểm đến',
      );
      expect(c['v'], kNapMapWireVersion);
      expect(c['centerBounds'], isNull);
      expect(c['maxDistanceM'], isNull);
      expect(c['accent'], 0xFF2B4FEC);
      expect(c['pinLabel'], 'Điểm đến');
      expect(c['initial'], bounds.toWire());
      expect(bounds.toString(), 'MapBounds');
      expect(_digits.hasMatch(f.toString()), isFalse);
      expect(napMapChannelName(7), 'app.napstop/nap_map/7');
    });

    test('bounds contains and intersects', () {
      const b = MapBounds(south: 10, west: 100, north: 20, east: 110);
      expect(b.contains(const MapPoint(15, 105)), isTrue);
      expect(b.contains(const MapPoint(10, 110)), isTrue);
      expect(b.contains(const MapPoint(21, 105)), isFalse);
      expect(
        b.intersects(
          const MapBounds(south: 19, west: 109, north: 30, east: 120),
        ),
        isTrue,
      );
      expect(
        b.intersects(
          const MapBounds(south: 21, west: 100, north: 30, east: 110),
        ),
        isFalse,
      );
    });
  });

  group('MW02 events', () {
    test('valid events decode', () {
      expect(decodeNapMapEvent('ready', null), isA<NapMapReady>());
      expect(decodeNapMapEvent('loadFailed', null), isA<NapMapLoadFailed>());
      final lp = decodeNapMapEvent('longPress', [16.47, 107.59]);
      expect(lp, isA<NapMapLongPress>());
      expect((lp! as NapMapLongPress).at, const MapPoint(16.47, 107.59));
      final drag = decodeNapMapEvent('pinDragEnd', [17.4688, 106.6223]);
      expect(drag, isA<NapMapPinDragEnd>());
      expect((drag! as NapMapPinDragEnd).at, const MapPoint(17.4688, 106.6223));
      expect(_digits.hasMatch(lp.toString()), isFalse);
    });
  });

  group('MW03 invalid args', () {
    final bad = <Object?>[
      [double.nan, 1.0],
      [1.0, double.infinity],
      [91.0, 0.0],
      [0.0, 181.0],
      [1.0],
      'x',
      null,
      [true, false],
      {'lat': 1.0, 'lng': 2.0},
    ];
    for (final (i, args) in bad.indexed) {
      test('longPress/pinDragEnd #$i', () {
        expect(decodeNapMapEvent('longPress', args), isNull);
        expect(decodeNapMapEvent('pinDragEnd', args), isNull);
        expect(decodePoint(args), isNull);
      });
    }

    test('unknown method or args where none expected', () {
      expect(decodeNapMapEvent('nope', null), isNull);
      expect(decodeNapMapEvent('diagState', null), isNull);
      expect(decodeNapMapEvent('ready', [1.0, 2.0]), isNull);
      expect(decodeNapMapEvent('loadFailed', 'x'), isNull);
    });
  });

  group('MW09 parity with fixtures/map_wire/cases.json', () {
    test('fixture version and size', () {
      final c = _cases();
      expect(c['version'], 1);
      for (final key in ['point', 'state', 'frame', 'creation']) {
        expect(_list(key), isNotEmpty, reason: key);
      }
    });

    for (final c in _list('point')) {
      test('point: ${c['name']}', () {
        final p = decodePoint(c['input']);
        expect(p != null, c['valid'], reason: '${c['name']}');
        if (p != null) {
          expect(_same(pointToWire(p), c['input']), isTrue);
        }
      });
    }

    for (final c in _list('state').where((c) => c['valid'] == true)) {
      test('state: ${c['name']}', () {
        // T24.3: the expected glyph replaces the input one (none = no key).
        final input = {...c['input']! as Map<String, Object?>}..remove('glyph');
        final glyph = c['glyph'];
        if (glyph != null) {
          input['glyph'] = glyph;
        }
        final s = _state(c['input']);
        expect(s.glyph?.name, glyph);
        expect(_same(s.toWire(), input), isTrue);
      });
    }

    for (final c in _list('frame').where((c) => c['valid'] == true)) {
      test('frame: ${c['name']}', () {
        expect(_same(_frame(c['input']).toWire(), c['input']), isTrue);
      });
    }

    for (final c in _list('creation').where((c) => c['valid'] == true)) {
      test('creation: ${c['name']}', () {
        final m = c['input']! as Map<String, Object?>;
        final center = m['centerBounds'];
        final wire = creationParams(
          state: _state(m['state']),
          initial: _b(m['initial']),
          centerBounds: center == null ? null : _b(center),
          maxDistanceM: _d(m['maxDistanceM']),
          eastLimit: _d(m['eastLimit']),
          maxLngSpan: _d(m['maxLngSpan']),
          accentArgb: m['accent']! as int,
          pinLabel: m['pinLabel']! as String,
        );
        expect(_same(wire, m), isTrue);
      });
    }

    test('invalid state/frame/creation cases exist for the Swift side', () {
      for (final key in ['state', 'frame', 'creation']) {
        expect(
          _list(key).where((c) => c['valid'] == false),
          isNotEmpty,
          reason: key,
        );
      }
    });
  });
}
