// The real assets/battery_guides.json as a ready catalog, parsed once per
// test isolate (T21). pumpAppHarness uses it so screens 0 and 9 never wait
// for the asset bundle inside fake async. Not a test file.
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Catalog of the real guides, keys checked against the vi ARB like the app.
final BatteryGuideCatalog kTestBatteryGuideCatalog = BatteryGuideCatalog.parse(
  File('assets/battery_guides.json').readAsStringSync(),
  (key) =>
      batteryGuideText(lookupAppLocalizations(const Locale('vi')), key) != null,
);
