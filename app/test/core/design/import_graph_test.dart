// Tester (T20, TC34 strengthened): the catalog must not reach the release
// app through any import chain, not only direct imports. Walks the
// transitive imports/exports/parts of lib/main.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Files under lib/ reachable from [entry] (paths relative to the app dir,
/// with forward slashes).
Set<String> _reachable(String entry) {
  final seen = <String>{};
  final queue = [entry];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!seen.add(path)) {
      continue;
    }
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: 'missing $path');
    final dir = path.substring(0, path.lastIndexOf('/'));
    for (final m in _directive.allMatches(file.readAsStringSync())) {
      final uri = m.group(1)!;
      if (uri.startsWith('package:napstop/')) {
        queue.add('lib/${uri.substring('package:napstop/'.length)}');
      } else if (!uri.contains(':')) {
        queue.add(Uri.parse('$dir/$uri').normalizePath().toString());
      }
    }
  }
  return seen;
}

void main() {
  test('lib/main.dart never reaches the catalog transitively', () {
    final files = _reachable('lib/main.dart');
    // Sanity: the walk does follow the app and the design system.
    expect(files, contains('lib/app/app.dart'));
    expect(files, contains('lib/core/design/theme/nap_themes.dart'));
    expect(files, contains('lib/core/design/fonts/font_licenses.dart'));
    final leaks = files
        .where(
          (f) =>
              f.startsWith('lib/core/design/catalog/') ||
              f == 'lib/main_catalog.dart',
        )
        .toList();
    expect(leaks, isEmpty);
  });

  test('the catalog entrypoint does reach every catalog section', () {
    final files = _reachable('lib/main_catalog.dart');
    final sections = Directory('lib/core/design/catalog/sections')
        .listSync()
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'))
        .where((p) => p.endsWith('.dart'));
    expect(sections, hasLength(11));
    for (final s in sections) {
      expect(files, contains(s));
    }
  });
}
