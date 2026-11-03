/// Battery guides of screen 9, per phone brand (T21 §6.3, D14). The content
/// is data (`assets/battery_guides.json` + ARB keys), so adding a brand needs
/// no code. Pure Dart.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';

/// Which settings page a step's "Mở Cài đặt của máy" opens.
enum GuideSettings {
  none,
  appDetails,
  batteryOptimization;

  /// The bridge target; null for [none].
  SettingsTargetMsg? get target => switch (this) {
    GuideSettings.none => null,
    GuideSettings.appDetails => SettingsTargetMsg.appDetails,
    GuideSettings.batteryOptimization => SettingsTargetMsg.batteryOptimization,
  };
}

/// One step: ARB keys of its texts and its settings page.
@immutable
final class GuideStep {
  const new({
    required this.id,
    required this.titleKey,
    required this.pathKey,
    required this.highlightKey,
    required this.settings,
  });

  final String id;
  final String titleKey;
  final String pathKey;
  final String highlightKey;
  final GuideSettings settings;

  /// The ARB keys of this step.
  List<String> get keys => [titleKey, pathKey, highlightKey];
}

@immutable
final class BatteryGuide {
  const new({
    required this.id,
    required this.labelKey,
    required this.manufacturers,
    required this.brands,
    required this.steps,
  });

  final String id;

  /// ARB key of the brand name; null only for [kGenericGuideId] (the chip
  /// uses `bgBrandOther`).
  final String? labelKey;

  /// Lower-case `Build.MANUFACTURER` / `Build.BRAND` values.
  final List<String> manufacturers;
  final List<String> brands;

  /// 1 to [kMaxGuideSteps] steps.
  final List<GuideStep> steps;

  bool get isGeneric => id == kGenericGuideId;
}

/// Id of the guide used when the brand is unknown.
const String kGenericGuideId = 'generic';

/// The schema version of `assets/battery_guides.json`.
const int kBatteryGuidesVersion = 1;

/// PRD §3 screen 9: at most 3 steps.
const int kMaxGuideSteps = 3;

@immutable
final class BatteryGuideCatalog {
  const new({required this.guides, required this.chipOrder});

  /// Parses `assets/battery_guides.json`. [resolves] says whether an ARB key
  /// exists. Throws [FormatException] when the version is not
  /// [kBatteryGuidesVersion] or the generic guide is missing or invalid. A
  /// guide with an unknown settings value, 0 or more than [kMaxGuideSteps]
  /// steps, or a key [resolves] rejects is dropped (not fatal).
  factory parse(String json, bool Function(String key) resolves) {
    // A malformed document throws FormatException from jsonDecode.
    final root = jsonDecode(json);
    if (root is! Map<String, Object?>) {
      throw const FormatException('battery guides: not an object');
    }
    if (root['version'] != kBatteryGuidesVersion) {
      throw const FormatException('battery guides: unsupported version');
    }
    final rawGuides = root['guides'];
    if (rawGuides is! List) {
      throw const FormatException('battery guides: no guides');
    }
    final guides = <BatteryGuide>[];
    for (final raw in rawGuides) {
      final guide = _guide(raw, resolves);
      if (guide != null && guides.every((g) => g.id != guide.id)) {
        guides.add(guide);
      }
    }
    if (guides.every((g) => !g.isGeneric)) {
      throw const FormatException('battery guides: no valid generic guide');
    }
    final rawOrder = root['chipOrder'];
    final chipOrder = <String>[
      if (rawOrder is List)
        for (final id in rawOrder)
          if (id is String &&
              id != kGenericGuideId &&
              guides.any((g) => g.id == id))
            id,
    ];
    return BatteryGuideCatalog(
      guides: List.unmodifiable(guides),
      chipOrder: List.unmodifiable(chipOrder),
    );
  }

  /// Always contains [kGenericGuideId].
  final List<BatteryGuide> guides;

  /// Ids shown as chips, in order (PRD: xiaomi, samsung, oppo, vivo).
  final List<String> chipOrder;

  BatteryGuide get generic => byId(kGenericGuideId)!;

  BatteryGuide? byId(String id) {
    for (final g in guides) {
      if (g.id == id) {
        return g;
      }
    }
    return null;
  }

  static BatteryGuide? _guide(Object? raw, bool Function(String) resolves) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final id = raw['id'];
    final labelKey = raw['labelKey'];
    final match = raw['match'];
    final rawSteps = raw['steps'];
    if (id is! String || id.isEmpty || match is! Map<String, Object?>) {
      return null;
    }
    final generic = id == kGenericGuideId;
    if (generic ? labelKey != null : labelKey is! String) {
      return null;
    }
    if (labelKey is String && !resolves(labelKey)) {
      return null;
    }
    final manufacturers = _lowerStrings(match['manufacturers']);
    final brands = _lowerStrings(match['brands']);
    if (manufacturers == null || brands == null) {
      return null;
    }
    if (rawSteps is! List ||
        rawSteps.isEmpty ||
        rawSteps.length > kMaxGuideSteps) {
      return null;
    }
    final steps = <GuideStep>[];
    for (final s in rawSteps) {
      final step = _step(s, resolves);
      if (step == null) {
        return null;
      }
      steps.add(step);
    }
    return BatteryGuide(
      id: id,
      labelKey: labelKey as String?,
      manufacturers: manufacturers,
      brands: brands,
      steps: List.unmodifiable(steps),
    );
  }

  static GuideStep? _step(Object? raw, bool Function(String) resolves) {
    if (raw is! Map<String, Object?>) {
      return null;
    }
    final id = raw['id'];
    final title = raw['titleKey'];
    final path = raw['pathKey'];
    final highlight = raw['highlightKey'];
    final settings = raw['settings'];
    if (id is! String || title is! String || path is! String) {
      return null;
    }
    if (highlight is! String || settings is! String) {
      return null;
    }
    GuideSettings? parsed;
    for (final v in GuideSettings.values) {
      if (v.name == settings) {
        parsed = v;
      }
    }
    if (parsed == null || ![title, path, highlight].every(resolves)) {
      return null;
    }
    return GuideStep(
      id: id,
      titleKey: title,
      pathKey: path,
      highlightKey: highlight,
      settings: parsed,
    );
  }

  static List<String>? _lowerStrings(Object? raw) {
    if (raw is! List) {
      return null;
    }
    final out = <String>[];
    for (final v in raw) {
      if (v is! String) {
        return null;
      }
      out.add(v.trim().toLowerCase());
    }
    return List.unmodifiable(out);
  }
}

/// The guide of [device]: `brand` first, then `manufacturer`; trimmed,
/// case-insensitive. No match, or iOS: the generic guide.
BatteryGuide matchGuide(BatteryGuideCatalog catalog, DeviceInfoMsg device) {
  if (device.platform != PlatformMsg.android) {
    return catalog.generic;
  }
  final brand = device.brand.trim().toLowerCase();
  final manufacturer = device.manufacturer.trim().toLowerCase();
  if (brand.isNotEmpty) {
    for (final g in catalog.guides) {
      if (g.brands.contains(brand)) {
        return g;
      }
    }
  }
  if (manufacturer.isNotEmpty) {
    for (final g in catalog.guides) {
      if (g.manufacturers.contains(manufacturer)) {
        return g;
      }
    }
  }
  return catalog.generic;
}

/// Chip ids of screen 9: [detected] first when it is not generic and not in
/// `chipOrder`, then `chipOrder`, then the generic guide.
List<String> guideChips(BatteryGuideCatalog catalog, BatteryGuide detected) => [
  if (!detected.isGeneric && !catalog.chipOrder.contains(detected.id))
    detected.id,
  ...catalog.chipOrder,
  kGenericGuideId,
];

/// T29 `battery_guide_test.oem`: xiaomi | samsung | oppo | vivo | other.
String oemTelemetryId(String guideId) => switch (guideId) {
  'xiaomi' || 'samsung' || 'oppo' || 'vivo' => guideId,
  _ => 'other',
};
