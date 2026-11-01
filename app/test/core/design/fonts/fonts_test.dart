// TC10: bundled Be Vietnam Pro in the font manifest. TC11: OFL license.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('TC10 manifest has the 4 weights and every file loads', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
    final family = manifest.cast<Map<String, dynamic>>().singleWhere(
      (f) => f['family'] == kNapFontFamily,
    );
    final fonts = (family['fonts'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    const base = 'assets/fonts/BeVietnamPro';
    final expected = {
      '$base/BeVietnamPro-Regular.ttf': 400,
      '$base/BeVietnamPro-Medium.ttf': 500,
      '$base/BeVietnamPro-SemiBold.ttf': 600,
      '$base/BeVietnamPro-Bold.ttf': 700,
    };
    expect(fonts, hasLength(4));
    expect({for (final f in fonts) f['asset']: f['weight']}, expected);
    for (final asset in expected.keys) {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(10 * 1024), reason: asset);
    }
    final ofl = await rootBundle.loadString(kBeVietnamProLicenseAsset);
    expect(ofl, contains('SIL Open Font License'));
  });

  group('TC11 license registry', () {
    setUp(() {
      LicenseRegistry.reset();
      resetFontLicenseRegistration();
    });

    test('registers one OFL entry, read lazily', () async {
      registerFontLicenses();
      registerFontLicenses(); // idempotent
      final entries = [
        await for (final e in LicenseRegistry.licenses)
          if (e.packages.contains(kBeVietnamProLicensePackage)) e,
      ];
      expect(entries, hasLength(1));
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL Open Font License'));
      expect(
        text,
        contains('Copyright 2021 The Be Vietnam Pro Project Authors'),
      );
    });
  });
}
