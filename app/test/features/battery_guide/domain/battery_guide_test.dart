// U15-U17, U19, U21 (oem): battery guide data and brand matching (T21 §6.3).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';

import '../../../helpers/fake_core_bridge.dart';

String _asset() => File('assets/battery_guides.json').readAsStringSync();

bool _any(String _) => true;

Map<String, Object?> _guideJson(
  String id, {
  String? labelKey = 'bgBrandXiaomi',
  int steps = 1,
  String settings = 'none',
  String titleKey = 'bgLockTitle',
}) => {
  'id': id,
  'labelKey': id == 'generic' ? null : labelKey,
  'match': {
    'manufacturers': [id],
    'brands': [id],
  },
  'steps': [
    for (var i = 0; i < steps; i++)
      {
        'id': 's$i',
        'titleKey': titleKey,
        'pathKey': 'bgPullDownLockPath',
        'highlightKey': 'bgLockHighlight',
        'settings': settings,
      },
  ],
};

String _doc(List<Map<String, Object?>> guides, {int version = 1}) =>
    jsonEncode({
      'version': version,
      'chipOrder': ['a', 'b'],
      'guides': guides,
    });

DeviceInfoMsg _phone(String manufacturer, String brand) =>
    androidDevice(manufacturer: manufacturer, brand: brand);

void main() {
  group('U15 the real asset', () {
    final catalog = BatteryGuideCatalog.parse(_asset(), _any);

    test('9 guides, PRD chip order, 1-3 steps each', () {
      expect(catalog.guides.map((g) => g.id), [
        'xiaomi',
        'samsung',
        'oppo',
        'realme',
        'oneplus',
        'vivo',
        'huawei',
        'honor',
        'generic',
      ]);
      expect(catalog.chipOrder, ['xiaomi', 'samsung', 'oppo', 'vivo']);
      for (final g in catalog.guides) {
        expect(g.steps.length, inInclusiveRange(1, 3), reason: g.id);
      }
      expect(catalog.generic.steps.length, 2);
      expect(catalog.generic.labelKey, isNull);
    });

    test('ColorOS brands and Huawei/Honor share their steps', () {
      List<String> keys(String id) => [
        for (final s in catalog.byId(id)!.steps) ...[
          s.id,
          ...s.keys,
          s.settings.name,
        ],
      ];
      expect(keys('realme'), keys('oppo'));
      expect(keys('oneplus'), keys('oppo'));
      expect(keys('honor'), keys('huawei'));
    });

    test('settings targets of the steps', () {
      expect(catalog.byId('xiaomi')!.steps.map((s) => s.settings.target), [
        SettingsTargetMsg.appDetails,
        SettingsTargetMsg.appDetails,
        null,
      ]);
      expect(
        catalog.byId('huawei')!.steps[1].settings.target,
        SettingsTargetMsg.batteryOptimization,
      );
    });
  });

  group('U16 parse errors', () {
    test('version 2 and a missing generic guide are fatal', () {
      expect(
        () => BatteryGuideCatalog.parse(
          _doc([_guideJson('generic')], version: 2),
          _any,
        ),
        throwsFormatException,
      );
      expect(
        () => BatteryGuideCatalog.parse(_doc([_guideJson('a')]), _any),
        throwsFormatException,
      );
      expect(
        () => BatteryGuideCatalog.parse('not json', _any),
        throwsFormatException,
      );
    });

    test('a generic guide that is invalid is fatal too', () {
      expect(
        () => BatteryGuideCatalog.parse(
          _doc([_guideJson('generic', steps: 0)]),
          _any,
        ),
        throwsFormatException,
      );
    });

    test('bad guides are dropped, the rest is kept', () {
      final catalog = BatteryGuideCatalog.parse(
        _doc([
          _guideJson('a', settings: 'autostart'),
          _guideJson('b', titleKey: 'bgNoSuchKey'),
          _guideJson('c', steps: 4),
          _guideJson('d'),
          _guideJson('generic', steps: 2),
        ]),
        (key) => key != 'bgNoSuchKey',
      );
      expect(catalog.guides.map((g) => g.id), ['d', 'generic']);
      // Chips only list guides that survived.
      expect(catalog.chipOrder, isEmpty);
    });
  });

  test('U17 brand first, then manufacturer, case and spaces ignored', () {
    final catalog = BatteryGuideCatalog.parse(_asset(), _any);
    final cases = <(DeviceInfoMsg, String)>[
      (_phone('Xiaomi', 'Redmi'), 'xiaomi'),
      (_phone('Xiaomi', 'POCO'), 'xiaomi'),
      (_phone('samsung', 'samsung'), 'samsung'),
      (_phone('OPPO', 'OPPO'), 'oppo'),
      (_phone('realme', 'realme'), 'realme'),
      (_phone('OnePlus', 'OnePlus'), 'oneplus'),
      (_phone('vivo', 'iQOO'), 'vivo'),
      (_phone('HUAWEI', 'HONOR'), 'honor'),
      (_phone('HONOR', 'HONOR'), 'honor'),
      (_phone('HUAWEI', 'HUAWEI'), 'huawei'),
      (_phone('Google', 'google'), 'generic'),
      (_phone('', ''), 'generic'),
      (_phone(' Xiaomi ', ''), 'xiaomi'),
      (iosDevice(), 'generic'),
    ];
    for (final (device, id) in cases) {
      expect(
        matchGuide(catalog, device).id,
        id,
        reason: '${device.manufacturer}/${device.brand}',
      );
    }
  });

  test('U19 chips: detected brand outside the PRD four comes first', () {
    final catalog = BatteryGuideCatalog.parse(_asset(), _any);
    expect(guideChips(catalog, catalog.byId('xiaomi')!), [
      'xiaomi',
      'samsung',
      'oppo',
      'vivo',
      'generic',
    ]);
    expect(guideChips(catalog, catalog.byId('realme')!), [
      'realme',
      'xiaomi',
      'samsung',
      'oppo',
      'vivo',
      'generic',
    ]);
    expect(guideChips(catalog, catalog.generic), [
      'xiaomi',
      'samsung',
      'oppo',
      'vivo',
      'generic',
    ]);
  });

  // T29 (T21 proposal 4, Q1 = A): the four draft brands have their own tag.
  test(
    'U21 oemTelemetryId keeps the eight guide brands, the rest is other',
    () {
      for (final id in [
        'xiaomi',
        'samsung',
        'oppo',
        'vivo',
        'realme',
        'oneplus',
        'huawei',
        'honor',
      ]) {
        expect(oemTelemetryId(id), id);
      }
      for (final id in ['generic', 'other', 'Xiaomi', 'nokia', '']) {
        expect(oemTelemetryId(id), 'other');
      }
    },
  );
}
