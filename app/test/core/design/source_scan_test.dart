// TC34: the catalog never reaches the release app.
// TC35: no font download, no hard-coded strings, no logging in the design
// system.
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
  final catalogImport = RegExp('core/design/catalog/');

  test('TC34 only main_catalog.dart imports the catalog', () {
    final appFiles = [
      File('lib/main.dart'),
      ..._dartFiles('lib/app'),
      ..._dartFiles('lib/features'),
      ..._dartFiles('lib/core')
          .where((f) => !_norm(f).contains('lib/core/design/catalog/')),
    ];
    expect(appFiles.length, greaterThan(20));
    for (final f in appFiles) {
      expect(
        catalogImport.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: _norm(f),
      );
    }
    expect(
      File('lib/main_catalog.dart').readAsStringSync(),
      contains('core/design/catalog/catalog_app.dart'),
    );
    expect(
      File('lib/core/design/design.dart').readAsStringSync(),
      isNot(matches(RegExp("^export '.*catalog", multiLine: true))),
      reason: 'design.dart must not export the catalog',
    );
  });

  test('TC35 no google_fonts, no font URLs', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('google_fonts')),
    );
    for (final f in _dartFiles('lib')) {
      final text = f.readAsStringSync();
      expect(text, isNot(contains('fonts.googleapis.com')), reason: _norm(f));
      expect(text, isNot(contains('fonts.gstatic.com')), reason: _norm(f));
    }
  });

  test('TC35 design system: ASCII only, no print/debugPrint', () {
    final files = _dartFiles('lib/core/design')
        .where((f) => !_norm(f).contains('lib/core/design/catalog/'))
        .toList();
    expect(files.length, greaterThanOrEqualTo(30));
    final nonAscii = RegExp(r'[^\x00-\x7F]');
    final logging = RegExp(r'\b(print|debugPrint)\(');
    for (final f in files) {
      final text = f.readAsStringSync();
      expect(nonAscii.hasMatch(text), isFalse, reason: _norm(f));
      expect(logging.hasMatch(text), isFalse, reason: _norm(f));
    }
  });
}
