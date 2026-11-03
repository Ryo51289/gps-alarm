// U18: every key of battery_guides.json has text in vi and en; no orphan
// `bg*` key in the ARB files. Plus the countdown format.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

Set<String> _jsonKeys() {
  final doc = jsonDecode(
    File('assets/battery_guides.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final keys = <String>{};
  for (final g in doc['guides']! as List<Object?>) {
    final guide = g! as Map<String, Object?>;
    final label = guide['labelKey'];
    if (label is String) {
      keys.add(label);
    }
    for (final s in guide['steps']! as List<Object?>) {
      final step = s! as Map<String, Object?>;
      keys
        ..add(step['titleKey']! as String)
        ..add(step['pathKey']! as String)
        ..add(step['highlightKey']! as String);
    }
  }
  return keys;
}

void main() {
  final vi = lookupAppLocalizations(const Locale('vi'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('U18 every JSON key resolves in vi and en', () {
    for (final key in _jsonKeys()) {
      expect(batteryGuideText(vi, key), isNotEmpty, reason: 'vi $key');
      expect(batteryGuideText(en, key), isNotEmpty, reason: 'en $key');
    }
    expect(batteryGuideText(vi, 'bgBrandOther'), 'Khác');
    expect(batteryGuideText(vi, 'unknownKey'), isNull);
  });

  test('U18 no orphan bg* key in app_vi.arb', () {
    final arb = jsonDecode(
      File('lib/l10n/app_vi.arb').readAsStringSync(),
    ) as Map<String, Object?>;
    final used = {..._jsonKeys(), 'bgBrandOther'};
    for (final key in arb.keys.where((k) => k.startsWith('bg'))) {
      expect(used, contains(key), reason: key);
      expect(batteryGuideText(vi, key), isNotNull, reason: key);
    }
  });

  test('countdown m:ss', () {
    expect(formatCountdown(const Duration(seconds: 30)), '0:30');
    expect(formatCountdown(const Duration(milliseconds: 23400)), '0:24');
    expect(formatCountdown(const Duration(seconds: 75)), '1:15');
    expect(formatCountdown(Duration.zero), '0:00');
    expect(formatCountdown(const Duration(seconds: -3)), '0:00');
  });
}
