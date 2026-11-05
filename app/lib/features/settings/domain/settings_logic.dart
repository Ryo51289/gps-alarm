/// Pure rules of screen 12 "Cài đặt chung" (T28 §4).
library;

import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/core/preferences/alarm_preferences.dart';
import 'package:napstop/core/preferences/trip_settings.dart';

/// T16 `AlarmSounds.catalog` order. `default` is shown (and played) as
/// `horn`, like T16 maps it; after a pick one of these is stored.
const List<String> kAlarmSoundIds = ['horn', 'bell', 'beep', 'system'];

/// Like T16 `AlarmSounds.resolve`: unknown ids (and `default`) → `horn`.
String resolveSoundId(String id) => kAlarmSoundIds.contains(id) ? id : 'horn';

/// Volume slider of screen 12 (D12): percent of the phone's alarm volume.
const int kVolumeStepPct = 5;
const int kVolumeDivisions =
    (kMaxAlarmVolumePct - kMinAlarmVolumePct) ~/ kVolumeStepPct;

/// A slider value as a stored percent: step 5, inside 30..100.
int volumePctOf(double v) => ((v / kVolumeStepPct).round() * kVolumeStepPct)
    .clamp(kMinAlarmVolumePct, kMaxAlarmVolumePct);

/// Volume passed to `previewSound` (0..1).
double previewVolumeOf(AlarmPreferences p) => p.volumePct / 100;

/// Vibration options of screen 12 (no "off").
const List<VibrationMsg> kVibrationOptions = [
  VibrationMsg.light,
  VibrationMsg.medium,
  VibrationMsg.strong,
];

/// D11: "Ưu tiên phát qua tai nghe" is the default alarm style.
bool prefersHeadphones(TripSettings s) =>
    s.alarmStyle == AlarmStyle.headphonesOnly;

TripSettings withHeadphones(TripSettings s, {required bool on}) => s.copyWith(
  alarmStyle: on ? AlarmStyle.headphonesOnly : AlarmStyle.ringAndVibrate,
);

/// The UI goes back to "Nghe thử" after this; native stops by itself
/// (T16 PREVIEW_MAX_MS).
const Duration kPreviewUiReset = Duration(milliseconds: 10000);
