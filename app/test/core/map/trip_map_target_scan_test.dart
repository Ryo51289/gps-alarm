// Review T23.3 #2: the screen 4 map reads the trip row and never writes
// history (T26 D15, U19 keeps one write path). trip_map_target.dart may only
// call `byId` on the repository.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trip_map_target.dart only reads the trip row (byId)', () {
    final code = File('lib/core/map/trip_map_target.dart')
        .readAsStringSync()
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'(^|\s)//.*'), ''))
        .join('\n');
    expect(RegExp(r'\.byId\(').allMatches(code), hasLength(1));
    const forbidden = [
      'insertStarted',
      'insert',
      'update',
      'delete',
      'upsert',
      'applyFinished',
      'markUnfinished',
      'pendingFinishedTrips',
      'ackFinishedTrips',
      'watchHistory',
      'watchRecent',
    ];
    final calls = RegExp(r'\.(\w+)\(').allMatches(code).map((m) => m[1]!);
    for (final word in forbidden) {
      expect(code.contains('.$word'), isFalse, reason: word);
    }
    // Every method called on `trips` is byId.
    final onTrips = RegExp(r'\btrips\.(\w+)').allMatches(code).map((m) => m[1]);
    expect(onTrips.toSet(), {'byId'});
    expect(calls, isNot(contains('insertStarted')));
  });
}
