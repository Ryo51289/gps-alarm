// TC12: ARB files (Vietnamese source + English) stay in sync.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

void main() {
  final vi = _read('lib/l10n/app_vi.arb');
  final en = _read('lib/l10n/app_en.arb');

  test('TC12 locales, same keys, descriptions, commonBack', () {
    expect(vi['@@locale'], 'vi');
    expect(en['@@locale'], 'en');
    expect(_messageKeys(en), _messageKeys(vi));
    for (final key in _messageKeys(vi)) {
      final meta = vi['@$key'] as Map<String, dynamic>?;
      final description = meta?['description'] as String?;
      expect(description, isNotNull, reason: '@$key.description');
      expect(description!.trim(), isNotEmpty, reason: '@$key.description');
    }
    expect(vi['commonBack'], 'Quay lại');
    expect(en['commonBack'], 'Back');
  });

  test('TC12 l10n.yaml uses the Vietnamese template', () {
    final yaml = File('l10n.yaml').readAsStringSync();
    expect(yaml, contains('template-arb-file: app_vi.arb'));
    expect(yaml, contains('output-dir: lib/l10n/gen'));
    expect(yaml, contains('preferred-supported-locales: [vi]'));
  });

  test('iOS Info.plist declares the app languages (vi, en)', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(
      plist,
      matches(
        RegExp(
          r'<key>CFBundleLocalizations</key>\s*<array>\s*'
          r'<string>vi</string>\s*<string>en</string>\s*</array>',
        ),
      ),
    );
  });
}
