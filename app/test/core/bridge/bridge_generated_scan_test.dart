// Tester additions for T14 D09 (privacy): the generated Dart/Kotlin/Swift
// files, not only the Pigeon input, hold no coordinate-like identifier
// outside TripHostApi.startTrip. Generated toString()/description prints every
// field of a message class (Pigeon >= 27), so a coordinate field in any of
// them would end up in logs.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _generated = [
  'lib/core/bridge/core_api.g.dart',
  'android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt',
  'ios/Runner/Bridge/CoreApi.g.swift',
];

/// The only coordinate identifiers allowed: the startTrip parameters and the
/// local copies the generated Kotlin/Swift handlers decode them into.
const _allowed = {'destLat', 'destLng', 'destLatArg', 'destLngArg'};

/// Words of an identifier that mean "coordinate".
const _coordinateWords = {
  'lat',
  'lng',
  'lon',
  'latitude',
  'longitude',
  'coord',
  'coords',
  'coordinate',
  'coordinates',
  'geo',
  'geopoint',
  'position',
  'e7',
};

/// [code] without `/* */` and `//` comments (generated doc comments copy the
/// Pigeon input's prose, which talks about coordinates).
String _stripComments(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .split('\n')
    .map((l) => l.replaceFirst(RegExp('//.*'), ''))
    .join('\n');

/// camelCase / snake_case words of [identifier], lower case.
List<String> _words(String identifier) => identifier
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp('([A-Z])([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase()
    .split('_')
    .where((w) => w.isNotEmpty)
    .toList();

bool _isCoordinate(String identifier) =>
    _words(identifier).any(_coordinateWords.contains);

Set<String> _coordinateIdentifiers(String code) =>
    RegExp(r'[A-Za-z_]\w*')
        .allMatches(code)
        .map((m) => m[0]!)
        .where(_isCoordinate)
        .toSet();

void main() {
  test('word splitter flags coordinate names only', () {
    for (final name in [
      'destLat',
      'destLatArg',
      'lastPosition',
      'latE7',
      'geoPoint',
      'stop_coords',
      'userLongitude',
      'LAT',
    ]) {
      expect(_isCoordinate(name), isTrue, reason: name);
    }
    for (final name in [
      'platform',
      'PlatformMsg',
      'Long',
      'toLong',
      'simulation',
      'location',
      'destinationName',
      'pigeonVar_list',
      'translate',
      'along',
    ]) {
      expect(_isCoordinate(name), isFalse, reason: name);
    }
  });

  for (final path in _generated) {
    test('D09+ $path: coordinates only as startTrip arguments', () {
      final code = _stripComments(File(path).readAsStringSync());
      final found = _coordinateIdentifiers(code);
      expect(found, isNotEmpty, reason: 'startTrip must carry destLat/destLng');
      expect(found.difference(_allowed), isEmpty);

      // No message type mentions them: split at every type declaration
      // (Swift messages are structs) and check the segments of the *Msg
      // types (their fields, toString/description, encode/decode).
      final starts = RegExp(
        r'\b(?:class|struct|enum|protocol|extension)\s+(\w+)',
      ).allMatches(code).toList();
      var messageClasses = 0;
      for (var i = 0; i < starts.length; i++) {
        final name = starts[i][1]!;
        if (!name.endsWith('Msg')) {
          continue;
        }
        messageClasses++;
        final end = i + 1 < starts.length ? starts[i + 1].start : code.length;
        final body = code.substring(starts[i].start, end);
        expect(_coordinateIdentifiers(body), isEmpty, reason: '$name in $path');
      }
      expect(messageClasses, greaterThanOrEqualTo(19), reason: path);

      // Every occurrence sits in the startTrip handler: the nearest preceding
      // API method name is startTrip.
      for (final m in RegExp(r'\bdest(Lat|Lng)\w*').allMatches(code)) {
        final before = code.substring(0, m.start);
        final lastMethod = RegExp(
          r'\b(startTrip|stopTrip|currentTrip|setBatteryChoice|dismiss|snooze'
          r'|pendingFinishedTrips|ackFinishedTrips)\b',
        ).allMatches(before).last[1];
        expect(lastMethod, 'startTrip', reason: '${m[0]} in $path');
      }
    });
  }
}
