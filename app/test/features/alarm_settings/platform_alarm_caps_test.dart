// T28.3 PU01-PU02: which alarm options each platform honours.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/alarm_settings/data/platform_alarm_caps_provider.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_hints.dart';
import 'package:napstop/features/alarm_settings/domain/platform_alarm_caps.dart';

import '../../helpers/fake_core_bridge.dart';

void main() {
  test('PU01 platformAlarmCapsOf: iOS → ios; Android, macOS → android', () {
    expect(platformAlarmCapsOf(TargetPlatform.iOS), PlatformAlarmCaps.ios);
    expect(
      platformAlarmCapsOf(TargetPlatform.android),
      PlatformAlarmCaps.android,
    );
    expect(
      platformAlarmCapsOf(TargetPlatform.macOS),
      PlatformAlarmCaps.android,
    );
  });

  test('PU01 Android offers every option, iOS none of them', () {
    const a = PlatformAlarmCaps.android;
    const i = PlatformAlarmCaps.ios;
    final android = [
      a.alarmStyleChoice,
      a.dismissMethodChoice,
      a.volumeSlider,
      a.rampUp,
      a.vibrationLevels,
      a.flash,
      a.headphones,
      a.systemSoundPreview,
      a.nativeAlarmScreen,
    ];
    final ios = [
      i.alarmStyleChoice,
      i.dismissMethodChoice,
      i.volumeSlider,
      i.rampUp,
      i.vibrationLevels,
      i.flash,
      i.headphones,
      i.systemSoundPreview,
      i.nativeAlarmScreen,
    ];
    expect(android, everyElement(isTrue));
    expect(ios, everyElement(isFalse));
  });

  test('PU01 the provider follows defaultTargetPlatform', () {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final ios = ProviderContainer.test();
    expect(ios.read(platformAlarmCapsProvider), PlatformAlarmCaps.ios);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final android = ProviderContainer.test();
    expect(android.read(platformAlarmCapsProvider), PlatformAlarmCaps.android);
    debugDefaultTargetPlatformOverride = null;
  });

  test('PU02 canPreviewSound: only iOS + system is false', () {
    for (final (caps, id, expected) in [
      (PlatformAlarmCaps.ios, 'horn', true),
      (PlatformAlarmCaps.ios, 'system', false),
      (PlatformAlarmCaps.android, 'horn', true),
      (PlatformAlarmCaps.android, 'system', true),
    ]) {
      expect(canPreviewSound(caps, id), expected, reason: '$id $caps');
    }
  });

  // Test report #1 / O1: one rule for screens 1, 3 and 4.
  test('ringsInSilentIfKnown: iOS < 26 never; iOS 26+ unknown = null', () {
    expect(ringsInSilentIfKnown(null, null), isNull);
    expect(ringsInSilentIfKnown(null, androidDevice()), isTrue);
    expect(ringsInSilentIfKnown(androidPermissions(), androidDevice()), isTrue);
    // iOS before 26: no AlarmKit, whatever the permissions say.
    expect(ringsInSilentIfKnown(null, iosDevice(major: 17)), isFalse);
    expect(
      ringsInSilentIfKnown(iosPermissions(), iosDevice(major: 25)),
      isFalse,
    );
    expect(ringsInSilent(null, iosDevice(major: 17)), isFalse);
    // iOS 26+: depends on AlarmKit; unknown permissions = null.
    expect(ringsInSilentIfKnown(null, iosDevice(major: 27)), isNull);
    expect(ringsInSilentIfKnown(iosPermissions(), iosDevice()), isTrue);
    expect(
      ringsInSilentIfKnown(
        iosPermissions(alarmKit: PermissionStateMsg.notDetermined),
        iosDevice(),
      ),
      isFalse,
    );
    // The T25 boolean keeps "unknown = true" for Android and iOS 26+.
    expect(ringsInSilent(null, null), isTrue);
    expect(ringsInSilent(null, iosDevice(major: 27)), isTrue);
  });
}
