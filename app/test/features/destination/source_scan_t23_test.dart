// T23 TS40–TS41: no logging anywhere in screen 2 (queries, names and
// coordinates are location data), layer and import boundaries, and the
// Places request never carries the user's position.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final files = [
    ..._dartFiles('lib/features/destination'),
    ..._dartFiles('lib/core/text'),
  ];

  test('TS40 files exist', () {
    expect(files.length, greaterThanOrEqualTo(20));
  });

  test('TS40 no logging', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'log(': RegExp(r'\blog\('),
      'dart:developer': RegExp('dart:developer'),
    };
    for (final f in files) {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('TS40 domain is pure Dart', () {
    for (final f in _dartFiles('lib/features/destination/domain')) {
      final text = f.readAsStringSync();
      expect(text.contains('package:flutter'), isFalse, reason: _norm(f));
      expect(text.contains('google_maps_flutter'), isFalse, reason: _norm(f));
    }
  });

  test('TS40 only destination_map.dart imports the map SDK', () {
    final users = [
      for (final f in _dartFiles('lib'))
        if (f.readAsStringSync().contains('package:google_maps_flutter'))
          _norm(f),
    ];
    expect(users, [
      'lib/features/destination/presentation/widgets/destination_map.dart',
    ]);
  });

  test('TS40 only places_client.dart imports package:http', () {
    final users = [
      for (final f in _dartFiles('lib'))
        if (f.readAsStringSync().contains('package:http/')) _norm(f),
    ];
    // The provider file creates the client it hands to PlacesClient.
    expect(users.toSet(), {
      'lib/features/destination/data/places/places_client.dart',
      'lib/features/destination/data/destination_providers.dart',
    });
  });

  test('TS41 the Places client never sends a position', () {
    final text = File('lib/features/destination/data/places/places_client.dart')
        .readAsStringSync();
    for (final word in ['locationBias', 'locationRestriction', 'origin']) {
      expect(text.contains(word), isFalse, reason: word);
    }
  });
}
