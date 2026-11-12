// The app's kKindPrefixes must equal the table in tools/stationgen (spec T24
// §4.3: one table shared by the tool and the app), like the shared fold
// vectors for foldVi. T24.3 §6.3: the app adds bus stop rows the tool does
// not have, and "tram xe buyt" is busStop in the app, bus in the tool.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/domain/station_query.dart';

/// Bus stop rows of the app that the tool has (as bus).
const Set<String> _sharedBusStopRows = {'tram xe buyt'};

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

/// The tool has no busStop kind: its row reads bus.
String _toolKind(StationKind k) => k == StationKind.busStop ? 'bus' : k.name;

void main() {
  test('tool and app kind prefix tables are identical (same order)', () {
    // App rows without the app-only bus stop rows, busStop read as bus.
    final app = [
      for (final (words, kind) in kKindPrefixes)
        if (kind != StationKind.busStop ||
            _sharedBusStopRows.contains(words.join(' ')))
          '${words.join(' ')}→${_toolKind(kind)}',
    ];
    final tool = toolTable();
    expect(tool, hasLength(9));
    expect(app, tool);
  });

  test('T24.3 app-only bus stop rows (longer first)', () {
    expect(
      [
        for (final (words, kind) in kKindPrefixes)
          if (kind == StationKind.busStop) words.join(' '),
      ],
      [
        'diem dung xe buyt',
        'tram xe buyt',
        'diem dung',
        'tram dung',
        'tram buyt',
      ],
    );
  });
}
