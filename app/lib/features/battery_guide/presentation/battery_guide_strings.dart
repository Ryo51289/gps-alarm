/// ARB text of the keys used in `assets/battery_guides.json` (T21 §6.3).
library;

import 'package:napstop/l10n/gen/app_localizations.dart';

/// The text of [key]; null when [key] is unknown. One case per `bg*` key of
/// the ARB files (a test checks that none is missing or orphaned).
String? batteryGuideText(AppLocalizations l, String key) => switch (key) {
  'bgBrandXiaomi' => l.bgBrandXiaomi,
  'bgBrandSamsung' => l.bgBrandSamsung,
  'bgBrandOppo' => l.bgBrandOppo,
  'bgBrandVivo' => l.bgBrandVivo,
  'bgBrandRealme' => l.bgBrandRealme,
  'bgBrandOnePlus' => l.bgBrandOnePlus,
  'bgBrandHuawei' => l.bgBrandHuawei,
  'bgBrandHonor' => l.bgBrandHonor,
  'bgBrandOther' => l.bgBrandOther,
  'bgLockTitle' => l.bgLockTitle,
  'bgLockHighlight' => l.bgLockHighlight,
  'bgPullDownLockPath' => l.bgPullDownLockPath,
  'bgXiaomi1Title' => l.bgXiaomi1Title,
  'bgXiaomi1Path' => l.bgXiaomi1Path,
  'bgXiaomi1Highlight' => l.bgXiaomi1Highlight,
  'bgXiaomi2Title' => l.bgXiaomi2Title,
  'bgXiaomi2Path' => l.bgXiaomi2Path,
  'bgXiaomi2Highlight' => l.bgXiaomi2Highlight,
  'bgXiaomi3Path' => l.bgXiaomi3Path,
  'bgSamsung1Title' => l.bgSamsung1Title,
  'bgSamsung1Path' => l.bgSamsung1Path,
  'bgSamsung1Highlight' => l.bgSamsung1Highlight,
  'bgSamsung2Title' => l.bgSamsung2Title,
  'bgSamsung2Path' => l.bgSamsung2Path,
  'bgSamsung2Highlight' => l.bgSamsung2Highlight,
  'bgSamsung3Title' => l.bgSamsung3Title,
  'bgSamsung3Highlight' => l.bgSamsung3Highlight,
  'bgColorOs1Title' => l.bgColorOs1Title,
  'bgColorOs1Path' => l.bgColorOs1Path,
  'bgColorOs1Highlight' => l.bgColorOs1Highlight,
  'bgColorOs2Title' => l.bgColorOs2Title,
  'bgColorOs2Highlight' => l.bgColorOs2Highlight,
  'bgColorOs3Path' => l.bgColorOs3Path,
  'bgVivo1Title' => l.bgVivo1Title,
  'bgVivo1Path' => l.bgVivo1Path,
  'bgVivo1Highlight' => l.bgVivo1Highlight,
  'bgVivo2Title' => l.bgVivo2Title,
  'bgVivo2Path' => l.bgVivo2Path,
  'bgVivo2Highlight' => l.bgVivo2Highlight,
  'bgHuawei1Title' => l.bgHuawei1Title,
  'bgHuawei1Path' => l.bgHuawei1Path,
  'bgHuawei1Highlight' => l.bgHuawei1Highlight,
  'bgHuawei2Title' => l.bgHuawei2Title,
  'bgHuawei2Path' => l.bgHuawei2Path,
  'bgHuawei2Highlight' => l.bgHuawei2Highlight,
  'bgGeneric1Title' => l.bgGeneric1Title,
  'bgGeneric1Path' => l.bgGeneric1Path,
  'bgGeneric1Highlight' => l.bgGeneric1Highlight,
  'bgGeneric2Title' => l.bgGeneric2Title,
  'bgGeneric2Path' => l.bgGeneric2Path,
  'bgGeneric2Highlight' => l.bgGeneric2Highlight,
  _ => null,
};

/// Countdown of the background check, `m:ss` (e.g. 0:24). Negative is 0:00.
String formatCountdown(Duration d) {
  final seconds = d.isNegative ? 0 : (d.inMilliseconds + 999) ~/ 1000;
  final s = (seconds % 60).toString().padLeft(2, '0');
  return '${seconds ~/ 60}:$s';
}
