// Tester T21 (§6.3, D14): brand detection on real-world Build values, the
// shipped asset (every OEM has vi + en copy), and a seeded fuzz of the JSON
// parser (it must never throw anything but FormatException).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

import '../../../helpers/fake_core_bridge.dart';

String _asset() => File('assets/battery_guides.json').readAsStringSync();

final AppLocalizations _vi = lookupAppLocalizations(const Locale('vi'));
final AppLocalizations _en = lookupAppLocalizations(const Locale('en'));

bool _resolvesVi(String key) => batteryGuideText(_vi, key) != null;

final _catalog = BatteryGuideCatalog.parse(_asset(), _resolvesVi);

String _guideFor(String manufacturer, String brand) => matchGuide(
  _catalog,
  androidDevice(manufacturer: manufacturer, brand: brand),
).id;

void main() {
  group('brand detection', () {
    test('real Build.MANUFACTURER / Build.BRAND pairs', () {
      const cases = <(String, String, String)>[
        ('Xiaomi', 'Xiaomi', 'xiaomi'),
        ('Xiaomi', 'Redmi', 'xiaomi'),
        ('Xiaomi', 'POCO', 'xiaomi'),
        ('Xiaomi', 'xiaomi', 'xiaomi'),
        ('samsung', 'samsung', 'samsung'),
        ('OPPO', 'OPPO', 'oppo'),
        ('OPPO', 'realme', 'realme'), // old Realme on the OPPO platform
        ('realme', 'realme', 'realme'),
        ('OnePlus', 'OnePlus', 'oneplus'),
        ('OPPO', 'OnePlus', 'oneplus'), // OnePlus on ColorOS
        ('vivo', 'vivo', 'vivo'),
        ('vivo', 'iQOO', 'vivo'),
        ('HUAWEI', 'HUAWEI', 'huawei'),
        ('HUAWEI', 'HONOR', 'honor'), // old Honor: brand wins
        ('HONOR', 'HONOR', 'honor'),
        // Unknown brand: the manufacturer decides.
        ('Xiaomi', 'Mi', 'xiaomi'),
        ('samsung', 'Galaxy', 'samsung'),
        // Known brand beats a different manufacturer.
        ('Xiaomi', 'samsung', 'samsung'),
        // Case and whitespace.
        ('  XIAOMI\t', '', 'xiaomi'),
        ('', ' Redmi\n', 'xiaomi'),
        ('', '   ', 'generic'),
        // Not in the catalog: "Khác".
        ('Google', 'google', 'generic'),
        ('motorola', 'motorola', 'generic'),
        ('HMD Global', 'Nokia', 'generic'),
        ('INFINIX MOBILITY LIMITED', 'Infinix', 'generic'),
        ('TECNO MOBILE LIMITED', 'TECNO', 'generic'),
        ('asus', 'asus', 'generic'),
        ('Sony', 'Sony', 'generic'),
        ('unknown', 'unknown', 'generic'),
        ('', '', 'generic'),
        // Look-alikes must not match.
        ('xiaomi-like', 'redmix', 'generic'),
        ('vivosmart', 'iqoo2', 'generic'),
      ];
      for (final (manufacturer, brand, expected) in cases) {
        expect(
          _guideFor(manufacturer, brand),
          expected,
          reason: '($manufacturer, $brand)',
        );
      }
    });

    test('iOS is always generic, whatever the strings say', () {
      final device = DeviceInfoMsg(
        platform: PlatformMsg.ios,
        manufacturer: 'Xiaomi',
        brand: 'Redmi',
        model: 'iPhone',
        osVersion: '26.0',
        iosMajor: 26,
      );
      expect(matchGuide(_catalog, device).id, kGenericGuideId);
    });

    test('every guide is reachable by each of its own values', () {
      for (final g in _catalog.guides.where((g) => !g.isGeneric)) {
        for (final b in g.brands) {
          expect(_guideFor('zz', b.toUpperCase()), g.id, reason: b);
        }
        for (final m in g.manufacturers) {
          expect(_guideFor(m.toUpperCase(), 'zz'), g.id, reason: m);
        }
      }
    });

    test('no brand or manufacturer belongs to two guides', () {
      final brands = <String, String>{};
      final manufacturers = <String, String>{};
      for (final g in _catalog.guides) {
        for (final b in g.brands) {
          expect(brands.putIfAbsent(b, () => g.id), g.id, reason: 'brand $b');
        }
        for (final m in g.manufacturers) {
          expect(
            manufacturers.putIfAbsent(m, () => g.id),
            g.id,
            reason: 'manufacturer $m',
          );
        }
      }
      expect(_catalog.generic.brands, isEmpty);
      expect(_catalog.generic.manufacturers, isEmpty);
    });

    test('chips: detected brand first, PRD four, then "Khác"', () {
      for (final g in _catalog.guides) {
        final chips = guideChips(_catalog, g);
        expect(chips.last, kGenericGuideId);
        expect(chips.toSet(), hasLength(chips.length), reason: g.id);
        expect(
          chips,
          containsAllInOrder(['xiaomi', 'samsung', 'oppo', 'vivo']),
        );
        expect(chips, contains(g.id));
        if (!g.isGeneric && !_catalog.chipOrder.contains(g.id)) {
          expect(chips.first, g.id);
        }
      }
      expect(batteryGuideText(_vi, 'bgBrandOther'), 'Khác');
      expect(batteryGuideText(_en, 'bgBrandOther'), 'Other');
    });
  });

  group('shipped asset', () {
    final raw = jsonDecode(_asset()) as Map<String, Object?>;
    final rawGuides = raw['guides']! as List<Object?>;

    test('nothing in the file is dropped by the parser', () {
      expect(_catalog.guides, hasLength(rawGuides.length));
      expect(raw['version'], 1);
    });

    test('every OEM has vi and en copy for every key, Vietnamese with '
        'diacritics and no "→"', () {
      final viDiacritic = RegExp('[À-ỹ]');
      for (final g in _catalog.guides) {
        final keys = [?g.labelKey, for (final s in g.steps) ...s.keys];
        expect(g.steps.length, inInclusiveRange(1, kMaxGuideSteps));
        for (final key in keys) {
          final vi = batteryGuideText(_vi, key);
          final en = batteryGuideText(_en, key);
          expect(vi?.trim(), isNotEmpty, reason: 'vi $key');
          expect(en?.trim(), isNotEmpty, reason: 'en $key');
          expect(vi, isNot(contains('→')), reason: key);
          expect(en, isNot(contains('→')), reason: key);
          if (!key.startsWith('bgBrand')) {
            expect(
              vi,
              matches(viDiacritic),
              reason: 'vi without diacritics: $key',
            );
          }
        }
        for (final s in g.steps) {
          expect(
            s.settings,
            isIn(GuideSettings.values),
            reason: '${g.id}/${s.id}',
          );
        }
        // Step ids are unique inside a guide.
        expect(g.steps.map((s) => s.id).toSet(), hasLength(g.steps.length));
      }
    });

    test('vi and en "›" paths have the same number of levels', () {
      for (final g in _catalog.guides) {
        for (final s in g.steps) {
          final vi = batteryGuideText(_vi, s.pathKey)!;
          final en = batteryGuideText(_en, s.pathKey)!;
          expect(
            '›'.allMatches(vi).length,
            '›'.allMatches(en).length,
            reason: s.pathKey,
          );
        }
      }
    });

    test('a guide that opens settings only uses pages the app can open', () {
      for (final g in _catalog.guides) {
        for (final s in g.steps) {
          final t = s.settings.target;
          expect(
            t == null ||
                t == SettingsTargetMsg.appDetails ||
                t == SettingsTargetMsg.batteryOptimization,
            isTrue,
          );
        }
      }
    });
  });

  group('parser fuzz (seeded)', () {
    Object? mutate(Object? node, Random r) {
      final pick = r.nextInt(10);
      if (pick == 0) {
        return [null, 42, 'x', true, <Object?>[], <String, Object?>{}][r
            .nextInt(6)];
      }
      if (node is Map<String, Object?>) {
        final copy = <String, Object?>{...node};
        if (copy.isNotEmpty && pick == 1) {
          copy.remove(copy.keys.elementAt(r.nextInt(copy.length)));
        }
        for (final k in copy.keys.toList()) {
          if (r.nextInt(4) == 0) {
            copy[k] = mutate(copy[k], r);
          }
        }
        return copy;
      }
      if (node is List<Object?>) {
        final copy = [...node];
        if (copy.isNotEmpty && pick == 1) {
          copy.removeAt(r.nextInt(copy.length));
        }
        if (copy.isNotEmpty && pick == 2) {
          copy.add(copy[r.nextInt(copy.length)]);
        }
        for (var i = 0; i < copy.length; i++) {
          if (r.nextInt(4) == 0) {
            copy[i] = mutate(copy[i], r);
          }
        }
        return copy;
      }
      return node;
    }

    test(
      '2000 mutations: a valid catalog or FormatException, nothing else',
      () {
        final base = jsonDecode(_asset());
        final r = Random(21);
        var ok = 0;
        var rejected = 0;
        for (var i = 0; i < 2000; i++) {
          final doc = jsonEncode(mutate(base, r));
          try {
            final c = BatteryGuideCatalog.parse(doc, _resolvesVi);
            ok++;
            expect(c.byId(kGenericGuideId), isNotNull);
            for (final g in c.guides) {
              expect(g.steps.length, inInclusiveRange(1, kMaxGuideSteps));
              expect(g.isGeneric ? g.labelKey : 'x', g.isGeneric ? null : 'x');
              for (final s in g.steps) {
                for (final k in s.keys) {
                  expect(_resolvesVi(k), isTrue);
                }
              }
            }
            expect(c.chipOrder.every((id) => c.byId(id) != null), isTrue);
            expect(c.chipOrder, isNot(contains(kGenericGuideId)));
            // Matching never throws on a parsed catalog.
            matchGuide(c, androidDevice(manufacturer: 'Xiaomi', brand: 'x'));
          } on FormatException {
            rejected++;
          }
        }
        expect(ok, greaterThan(0));
        expect(rejected, greaterThan(0));
      },
    );

    test('truncated documents throw FormatException', () {
      final doc = _asset();
      for (var cut = 0; cut < doc.length; cut += 97) {
        expect(
          () => BatteryGuideCatalog.parse(doc.substring(0, cut), _resolvesVi),
          throwsFormatException,
          reason: 'cut at $cut',
        );
      }
      for (final bad in ['[]', 'null', '42', '"x"', '{}']) {
        expect(
          () => BatteryGuideCatalog.parse(bad, _resolvesVi),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });
}
