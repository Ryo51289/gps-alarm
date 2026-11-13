// T28.4 S01: the feedback feature cannot reach trips, places or the database
// (D6), and never prints.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _bannedImports = [
  'core/trip/',
  'core/db',
  'package:drift',
  'features/destination/',
  'features/history/',
  'features/tracking/',
  'features/alarm/',
  'core/location',
  'saved_place',
  // Tester additions (review minor #2): more modules holding places,
  // coordinates or trip data.
  'features/home/',
  'core/map',
  'features/simulation/',
  'features/alarm_settings/',
  'core/format/distance_format',
  'core/telemetry/redaction',
  'station',
  'geolocator',
  'location',
];

/// Shared settings plumbing the spec wires in; its own imports are not
/// followed by S01b.
const List<String> _notFollowed = ['lib/core/preferences/app_settings.dart'];

final RegExp _import = RegExp(
  r'''^\s*(import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// `package:napstop/...` and relative imports of [from] as `lib/` paths.
List<String> _localImports(File from) {
  final out = <String>[];
  for (final m in _import.allMatches(from.readAsStringSync())) {
    final target = m.group(2)!;
    if (target.startsWith('package:napstop/')) {
      out.add('lib/${target.substring('package:napstop/'.length)}');
    } else if (!target.contains(':')) {
      out.add(File('${from.parent.path}/$target').uri.normalizePath().path);
    }
  }
  return out;
}

List<File> _feedbackFiles() =>
    Directory('lib/features/feedback')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

void main() {
  test('S01 feedback sources: no trip/place/db imports, no print', () {
    final files = _feedbackFiles();
    expect(files, hasLength(greaterThanOrEqualTo(4)));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final m in _import.allMatches(source)) {
        final target = m.group(2)!;
        for (final banned in _bannedImports) {
          expect(
            target.contains(banned),
            isFalse,
            reason: '${file.path} imports $target',
          );
        }
      }
      expect(
        source.contains(RegExp(r'\bprint\(')),
        isFalse,
        reason: '${file.path} calls print',
      );
    }
  });

  // Tester addition (review minor #2): a direct import of a harmless module
  // must not pull trip, place or database code in either.
  test('S01b no trip/place/db module reachable through local imports', () {
    const reachBanned = [
      'lib/core/trip/',
      'lib/core/db/',
      'lib/core/map/',
      'lib/features/destination/',
      'lib/features/history/',
      'lib/features/tracking/',
      'lib/features/alarm/',
      'lib/features/home/',
      'lib/features/simulation/',
      'lib/features/alarm_settings/',
    ];
    final seen = <String, String>{}; // path -> first importer
    final queue = <String>[];
    for (final f in _feedbackFiles()) {
      final p = f.uri.normalizePath().path;
      seen[p] = '(root)';
      queue.add(p);
    }
    while (queue.isNotEmpty) {
      final path = queue.removeLast();
      final file = File(path);
      // Not followed (spec §3 wiring): `appSettingsProvider` is read for
      // `display.language` only; AppSettings itself holds the trip defaults
      // (TripDraft types). Anything else reaching trip code fails.
      if (!file.existsSync() || _notFollowed.any(path.endsWith)) {
        continue;
      }
      for (final next in _localImports(file)) {
        final key = File(next).uri.normalizePath().path;
        if (seen.containsKey(key)) {
          continue;
        }
        seen[key] = path;
        queue.add(key);
      }
    }
    final hits = [
      for (final p in seen.keys)
        if (reachBanned.any(p.contains)) '$p (from ${seen[p]})',
    ];
    expect(hits, isEmpty);
  });
}
