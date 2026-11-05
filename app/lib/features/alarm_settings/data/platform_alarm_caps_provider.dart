import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/features/alarm_settings/domain/platform_alarm_caps.dart';

/// iOS → [PlatformAlarmCaps.ios]; every other platform (Android, test
/// host) → [PlatformAlarmCaps.android] (T28.3 §2).
PlatformAlarmCaps platformAlarmCapsOf(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
    ? PlatformAlarmCaps.ios
    : PlatformAlarmCaps.android;

/// Synchronous, so options never blink when a screen opens (T28.3 D1).
/// Tests set `debugDefaultTargetPlatformOverride` or override this.
final platformAlarmCapsProvider = Provider<PlatformAlarmCaps>(
  (ref) => platformAlarmCapsOf(defaultTargetPlatform),
);
