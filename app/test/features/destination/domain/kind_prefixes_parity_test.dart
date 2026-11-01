// The app's kKindPrefixes must equal the table in tools/stationgen (spec T24
// §4.3: one table shared by the tool and the app), like the shared fold
// vectors for foldVi.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/domain/station_query.dart';

/// Reads `kKindPrefixes` from the tool's Dart source as `words→kind` lines.
List<String> toolTable() {
  final src = File('../tools/stationgen/lib/src/prefixes.dart')
      .readAsStringSync();
  final start = src.indexOf('kKindPrefixes = [');
  expect(start, isNonNegative, reason: 'table not found in tool source');
  final body = src.substring(start, src.indexOf('];', start));
  final entry = RegExp(r'\(\[([^\]]*)\],\s*StationKind\.(\w+)\)');
  String words(String list) =>
      list.split(',').map((w) => w.trim().replaceAll("'", '')).join(' ');
  return [for (final m in entry.allMatches(body)) '${words(m[1]!)}→${m[2]}'];
}

void main() {
  test('tool and app kind prefix tables are identical (same order)', () {
    final app = [
      for (final (words, kind) in kKindPrefixes)
        '${words.join(' ')}→${kind.name}',
    ];
    final tool = toolTable();
    expect(tool, hasLength(9));
    expect(app, tool);
  });
}
