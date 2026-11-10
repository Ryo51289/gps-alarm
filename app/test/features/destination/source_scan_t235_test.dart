// T23.5 AS-D09: no logging in the address search (typed text, suggestions and
// coordinates are location-like data) and layer boundaries.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<File> _files(String dir, String ext) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(ext))
        .toList();

String _norm(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final swift = [
    ..._files('ios/Core/Sources/NapStopIOS/Search', '.swift'),
    File('ios/Runner/Map/AddressSearchChannel.swift'),
  ];
  final dart = [
    ..._files('lib/features/destination', '.dart'),
    File('lib/core/map/map_wire.dart'),
  ];

  test('AS-D09 the files exist', () {
    expect(swift.length, 3);
    for (final f in swift) {
      expect(f.existsSync(), isTrue, reason: _norm(f));
    }
  });

  test('AS-D09 no logging in the Swift address search', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'NSLog': RegExp(r'\bNSLog\b'),
      'os_log': RegExp(r'\bos_log\b'),
      'Logger(': RegExp(r'\bLogger\('),
      'dump(': RegExp(r'\bdump\('),
    };
    for (final f in swift) {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('AS-D09 no logging in the Dart address search', () {
    final forbidden = <String, RegExp>{
      'print(': RegExp(r'\bprint\('),
      'debugPrint(': RegExp(r'\bdebugPrint\('),
      'log(': RegExp(r'\blog\('),
      'dart:developer': RegExp('dart:developer'),
    };
    for (final f in dart) {
      final text = f.readAsStringSync();
      for (final MapEntry(key: label, value: re) in forbidden.entries) {
        expect(re.hasMatch(text), isFalse, reason: '$label in ${_norm(f)}');
      }
    }
  });

  test('AS-D09 address_search domain does not import Flutter', () {
    final text = File('lib/features/destination/domain/address_search.dart')
        .readAsStringSync();
    expect(text.contains('package:flutter'), isFalse);
  });

  test('AS-D09 destination_map does not import the address search', () {
    final text = File(
      'lib/features/destination/presentation/widgets/destination_map.dart',
    ).readAsStringSync();
    expect(text.contains('address_search'), isFalse);
  });

  test('AS-D09 the search sends no user location', () {
    // D11: nothing of the address search reads or sends the position.
    for (final f in swift) {
      final text = f.readAsStringSync();
      expect(text.contains('CLLocationManager'), isFalse, reason: _norm(f));
      expect(text.contains('showsUserLocation'), isFalse, reason: _norm(f));
    }
  });
}
