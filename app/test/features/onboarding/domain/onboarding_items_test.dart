// U01-U11: rows and battery card of screen 0 (T21 §6.1, §6.2; PRD §3.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';

import '../../../helpers/fake_core_bridge.dart';

OnboardingItem _item(List<OnboardingItem> items, OnboardingItemKind kind) =>
    items.singleWhere((i) => i.kind == kind);

List<OnboardingItemKind> _kinds(List<OnboardingItem> items) =>
    items.map((i) => i.kind).toList();

const _xiaomi = BatteryGuide(
  id: 'xiaomi',
  labelKey: 'bgBrandXiaomi',
  manufacturers: ['xiaomi'],
  brands: ['xiaomi', 'redmi'],
  steps: [
    GuideStep(
      id: 'a',
      titleKey: 't',
      pathKey: 'p',
      highlightKey: 'h',
      settings: GuideSettings.appDetails,
    ),
    GuideStep(
      id: 'b',
      titleKey: 't',
      pathKey: 'p',
      highlightKey: 'h',
      settings: GuideSettings.none,
    ),
    GuideStep(
      id: 'c',
      titleKey: 't',
      pathKey: 'p',
      highlightKey: 'h',
      settings: GuideSettings.none,
    ),
  ],
);

const _generic = BatteryGuide(
  id: kGenericGuideId,
  labelKey: null,
  manufacturers: [],
  brands: [],
  steps: [
    GuideStep(
      id: 'a',
      titleKey: 't',
      pathKey: 'p',
      highlightKey: 'h',
      settings: GuideSettings.appDetails,
    ),
    GuideStep(
      id: 'b',
      titleKey: 't',
      pathKey: 'p',
      highlightKey: 'h',
      settings: GuideSettings.none,
    ),
  ],
);

void main() {
  final android = androidDevice();

  test('U01 Android, everything granted: two done rows, nothing blocks', () {
    final items = buildOnboardingItems(androidPermissions(), android);
    expect(_kinds(items), [
      OnboardingItemKind.location,
      OnboardingItemKind.notifications,
    ]);
    expect(items.every((i) => i.isDone && !i.blocking), isTrue);
  });

  test('U02 location not determined: needed, request, sheet, blocking', () {
    final items = buildOnboardingItems(
      androidPermissions(
        location: LocationAccessMsg.notDetermined,
        precise: PermissionStateMsg.notDetermined,
      ),
      android,
    );
    expect(
      _item(items, OnboardingItemKind.location),
      const OnboardingItem(
        kind: OnboardingItemKind.location,
        state: OnboardingItemState.needed,
        blocking: true,
        request: PermissionKindMsg.location,
        explainer: OnboardingExplainer.location,
      ),
    );
  });

  test('U03 location denied: Settings, no sheet, blocking', () {
    final items = buildOnboardingItems(
      androidPermissions(location: LocationAccessMsg.denied),
      android,
    );
    expect(
      _item(items, OnboardingItemKind.location),
      const OnboardingItem(
        kind: OnboardingItemKind.location,
        state: OnboardingItemState.denied,
        blocking: true,
        settings: SettingsTargetMsg.appDetails,
      ),
    );
  });

  test('U04 approximate: (a) precise can be asked, (b) Settings only', () {
    final a = buildOnboardingItems(
      androidPermissions(precise: PermissionStateMsg.notDetermined),
      android,
    );
    expect(
      _item(a, OnboardingItemKind.location),
      const OnboardingItem(
        kind: OnboardingItemKind.location,
        state: OnboardingItemState.approximate,
        blocking: true,
        request: PermissionKindMsg.location,
        explainer: OnboardingExplainer.precise,
      ),
    );
    final b = buildOnboardingItems(
      androidPermissions(precise: PermissionStateMsg.denied),
      android,
    );
    expect(
      _item(b, OnboardingItemKind.location),
      const OnboardingItem(
        kind: OnboardingItemKind.location,
        state: OnboardingItemState.approximate,
        blocking: true,
        settings: SettingsTargetMsg.appDetails,
      ),
    );
  });

  test('U05 location services off: servicesOff, blocking', () {
    final items = buildOnboardingItems(
      androidPermissions(locationServicesEnabled: false),
      android,
    );
    expect(
      _item(items, OnboardingItemKind.location),
      const OnboardingItem(
        kind: OnboardingItemKind.location,
        state: OnboardingItemState.servicesOff,
        blocking: true,
        settings: SettingsTargetMsg.locationServices,
      ),
    );
  });

  test('U06 Android notifications never block', () {
    final needed = buildOnboardingItems(
      androidPermissions(notifications: PermissionStateMsg.notDetermined),
      android,
    );
    expect(
      _item(needed, OnboardingItemKind.notifications),
      const OnboardingItem(
        kind: OnboardingItemKind.notifications,
        state: OnboardingItemState.needed,
        blocking: false,
        request: PermissionKindMsg.notifications,
        explainer: OnboardingExplainer.notifications,
      ),
    );
    final denied = buildOnboardingItems(
      androidPermissions(notifications: PermissionStateMsg.denied),
      android,
    );
    expect(
      _item(denied, OnboardingItemKind.notifications),
      const OnboardingItem(
        kind: OnboardingItemKind.notifications,
        state: OnboardingItemState.denied,
        blocking: false,
        settings: SettingsTargetMsg.notifications,
      ),
    );
  });

  test('U07 full-screen and exact alarm rows only when missing, sticky', () {
    final a = buildOnboardingItems(
      androidPermissions(
        fullScreenIntent: PermissionStateMsg.denied,
        exactAlarm: PermissionStateMsg.notDetermined,
      ),
      android,
    );
    expect(_kinds(a), [
      OnboardingItemKind.location,
      OnboardingItemKind.notifications,
      OnboardingItemKind.fullScreenIntent,
      OnboardingItemKind.exactAlarm,
    ]);
    expect(
      _item(a, OnboardingItemKind.fullScreenIntent),
      const OnboardingItem(
        kind: OnboardingItemKind.fullScreenIntent,
        state: OnboardingItemState.denied,
        blocking: false,
        settings: SettingsTargetMsg.fullScreenIntent,
        explainer: OnboardingExplainer.fullScreenIntent,
      ),
    );
    expect(
      _item(a, OnboardingItemKind.exactAlarm),
      const OnboardingItem(
        kind: OnboardingItemKind.exactAlarm,
        state: OnboardingItemState.denied,
        blocking: false,
        settings: SettingsTargetMsg.exactAlarm,
        explainer: OnboardingExplainer.exactAlarm,
      ),
    );

    final b = buildOnboardingItems(
      androidPermissions(),
      android,
      sticky: kindsOf(a),
    );
    expect(_item(b, OnboardingItemKind.fullScreenIntent).isDone, isTrue);
    expect(_item(b, OnboardingItemKind.exactAlarm).isDone, isTrue);

    final c = buildOnboardingItems(androidPermissions(), android);
    expect(_kinds(c), [
      OnboardingItemKind.location,
      OnboardingItemKind.notifications,
    ]);
  });

  test('U08 iOS 26: AlarmKit row; no alarm channel blocks both', () {
    final items = buildOnboardingItems(
      iosPermissions(
        alarmKit: PermissionStateMsg.notDetermined,
        notifications: PermissionStateMsg.notDetermined,
      ),
      iosDevice(),
    );
    expect(_kinds(items), [
      OnboardingItemKind.location,
      OnboardingItemKind.notifications,
      OnboardingItemKind.alarmKit,
    ]);
    expect(_item(items, OnboardingItemKind.notifications).blocking, isTrue);
    expect(
      _item(items, OnboardingItemKind.alarmKit),
      const OnboardingItem(
        kind: OnboardingItemKind.alarmKit,
        state: OnboardingItemState.needed,
        blocking: true,
        request: PermissionKindMsg.alarmKit,
        explainer: OnboardingExplainer.alarmKit,
      ),
    );
  });

  test('U09 iOS 17 / iOS 26 with AlarmKit granted', () {
    final a = buildOnboardingItems(
      iosPermissions(
        notifications: PermissionStateMsg.denied,
        alarmKit: PermissionStateMsg.notApplicable,
      ),
      iosDevice(major: 17),
    );
    expect(_kinds(a), [
      OnboardingItemKind.location,
      OnboardingItemKind.notifications,
    ]);
    final notifications = _item(a, OnboardingItemKind.notifications);
    expect(notifications.blocking, isTrue);
    expect(notifications.settings, SettingsTargetMsg.notifications);

    final b = buildOnboardingItems(
      iosPermissions(notifications: PermissionStateMsg.denied),
      iosDevice(),
    );
    expect(_item(b, OnboardingItemKind.notifications).blocking, isFalse);
    expect(_item(b, OnboardingItemKind.alarmKit).isDone, isTrue);
  });

  test('U10 fixed order; every open row has exactly one action', () {
    const states = PermissionStateMsg.values;
    var count = 0;
    for (final location in LocationAccessMsg.values) {
      for (final precise in states) {
        for (final services in [true, false]) {
          for (final other in states) {
            for (final device in [android, iosDevice(), iosDevice(major: 17)]) {
              final s = device.platform == PlatformMsg.android
                  ? androidPermissions(
                      location: location,
                      precise: precise,
                      locationServicesEnabled: services,
                      notifications: other,
                      fullScreenIntent: other,
                      exactAlarm: other,
                    )
                  : iosPermissions(
                      location: location,
                      precise: precise,
                      locationServicesEnabled: services,
                      notifications: other,
                      alarmKit: other,
                    );
              final items = buildOnboardingItems(s, device);
              final order = _kinds(items).map((k) => k.index).toList();
              expect(order, [...order]..sort(), reason: '$s');
              expect(order.toSet().length, order.length);
              expect(items.first.kind, OnboardingItemKind.location);
              expect(items[1].kind, OnboardingItemKind.notifications);
              for (final i in items) {
                if (i.isDone) {
                  expect(i.request == null && i.settings == null, isTrue);
                } else {
                  expect(
                    (i.request == null) != (i.settings == null),
                    isTrue,
                    reason: '$i',
                  );
                }
              }
              count++;
            }
          }
        }
      }
    }
    expect(count, 4 * 4 * 2 * 4 * 3);
  });

  test('U11 battery card', () {
    expect(buildBatteryCard(iosPermissions(), iosDevice(), _generic), isNull);
    expect(
      buildBatteryCard(
        androidPermissions(
          batteryOptimizationIgnored: PermissionStateMsg.denied,
        ),
        android,
        _xiaomi,
      ),
      const BatteryCardModel(
        tone: BatteryCardTone.warning,
        guideId: 'xiaomi',
        brandKey: 'bgBrandXiaomi',
        stepCount: 3,
      ),
    );
    expect(
      buildBatteryCard(androidPermissions(), android, _xiaomi)?.tone,
      BatteryCardTone.neutral,
    );
    expect(
      buildBatteryCard(androidPermissions(), android, _generic),
      const BatteryCardModel(
        tone: BatteryCardTone.neutral,
        guideId: kGenericGuideId,
        brandKey: null,
        stepCount: 2,
      ),
    );
  });
}
