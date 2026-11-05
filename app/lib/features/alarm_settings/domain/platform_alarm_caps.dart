/// What the alarm of the running platform can honour (T28.3 D2, PLAN-ios
/// Q2 = A). Pure Dart: the platform is picked in
/// `data/platform_alarm_caps_provider.dart`.
library;

import 'package:meta/meta.dart';

/// Which alarm options a screen may offer. Android honours all of them; on
/// iOS the alarm is the system Alarms UI (AlarmKit, T17), so only the sound
/// and snooze apply. Hidden options keep their stored value (D4).
@immutable
final class PlatformAlarmCaps {
  const new({
    required this.alarmStyleChoice,
    required this.dismissMethodChoice,
    required this.volumeSlider,
    required this.rampUp,
    required this.vibrationLevels,
    required this.flash,
    required this.headphones,
    required this.systemSoundPreview,
    required this.nativeAlarmScreen,
  });

  /// "Kiểu báo": ring + vibrate / vibrate only / headphones only.
  final bool alarmStyleChoice;

  /// "Cách tắt báo": swipe / shake / math.
  final bool dismissMethodChoice;

  /// Alarm volume slider of screen 12.
  final bool volumeSlider;
  final bool rampUp;
  final bool vibrationLevels;
  final bool flash;

  /// "Ưu tiên tai nghe" and the headphones tile of screen 4.
  final bool headphones;

  /// "Nghe thử" for the `system` sound.
  final bool systemSoundPreview;

  /// The app's own full-screen alarm screen, which screen 5 can bring back
  /// ("Mở màn báo thức"). iOS: `showAlarmScreen` is always false (T17.2 D9).
  final bool nativeAlarmScreen;

  static const android = PlatformAlarmCaps(
    alarmStyleChoice: true,
    dismissMethodChoice: true,
    volumeSlider: true,
    rampUp: true,
    vibrationLevels: true,
    flash: true,
    headphones: true,
    systemSoundPreview: true,
    nativeAlarmScreen: true,
  );

  static const ios = PlatformAlarmCaps(
    alarmStyleChoice: false,
    dismissMethodChoice: false,
    volumeSlider: false,
    rampUp: false,
    vibrationLevels: false,
    flash: false,
    headphones: false,
    systemSoundPreview: false,
    nativeAlarmScreen: false,
  );
}

/// Whether "Nghe thử" may play [resolvedSoundId] (already passed through
/// `resolveSoundId`).
bool canPreviewSound(PlatformAlarmCaps caps, String resolvedSoundId) =>
    caps.systemSoundPreview || resolvedSoundId != 'system';
