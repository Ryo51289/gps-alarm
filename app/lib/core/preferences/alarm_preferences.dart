/// Global alarm sound settings (screen 12, T28 edits them; T25 reads them).
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';

/// T16 maps 'default' to the default sound ("Còi tàu").
const String kDefaultAlarmSoundId = 'default';

/// Longest stored sound id.
const int kMaxAlarmSoundIdLength = 64;

/// Volume range of screen 12, percent.
const int kMinAlarmVolumePct = 30;
const int kMaxAlarmVolumePct = 100;

@immutable
final class AlarmPreferences {
  const new({
    required this.soundId,
    required this.volumePct,
    required this.rampUp,
    required this.vibration,
    required this.flash,
  });

  final String soundId;

  /// 30..100 (screen 12 slider, step 5).
  final int volumePct;
  final bool rampUp;

  /// light | medium | strong (screen 12 has no "off").
  final VibrationMsg vibration;
  final bool flash;

  /// Default state of the screen 12 wireframe.
  static const AlarmPreferences defaults = AlarmPreferences(
    soundId: kDefaultAlarmSoundId,
    volumePct: 100,
    rampUp: true,
    vibration: VibrationMsg.strong,
    flash: false,
  );

  @override
  bool operator ==(Object other) =>
      other is AlarmPreferences &&
      other.soundId == soundId &&
      other.volumePct == volumePct &&
      other.rampUp == rampUp &&
      other.vibration == vibration &&
      other.flash == flash;

  @override
  int get hashCode => Object.hash(soundId, volumePct, rampUp, vibration, flash);

  @override
  String toString() =>
      'AlarmPreferences($soundId, $volumePct, $rampUp, ${vibration.name}, '
      '$flash)';
}
