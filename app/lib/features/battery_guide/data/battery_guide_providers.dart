/// Data of screen 9 (T21 §6.3).
library;

import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Asset of the guides.
const String kBatteryGuidesAsset = 'assets/battery_guides.json';

/// The guides, loaded once and kept for the session. Every key must exist
/// in the Vietnamese source ARB. A failure stays until `ref.invalidate`
/// ("Thử lại").
final batteryGuideCatalogProvider = FutureProvider<BatteryGuideCatalog>((
  ref,
) async {
  final json = await rootBundle.loadString(kBatteryGuidesAsset);
  final vi = lookupAppLocalizations(const Locale('vi'));
  return BatteryGuideCatalog.parse(
    json,
    (key) => batteryGuideText(vi, key) != null,
  );
});
