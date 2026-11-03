// Tester T21 (§6.1, D12, D13): screen 0 rows for every permission state on
// Android and iOS. The main risk: a row that looks "Đã bật" while the trip
// cannot start, or a button that does nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

import '../../../helpers/fake_core_bridge.dart';
import '../../../helpers/test_battery_guides.dart';

const List<PermissionStateMsg> _states = PermissionStateMsg.values;

Iterable<PermissionStatusMsg> _android() sync* {
  for (final location in LocationAccessMsg.values) {
    for (final precise in _states) {
      for (final services in [false, true]) {
        for (final notifications in _states) {
          for (final fsi in _states) {
            for (final exact in _states) {
              for (final battery in _states) {
                yield PermissionStatusMsg(
                  location: location,
                  precise: precise,
                  locationServicesEnabled: services,
                  notifications: notifications,
                  fullScreenIntent: fsi,
                  exactAlarm: exact,
                  batteryOptimizationIgnored: battery,
                  alarmKit: PermissionStateMsg.notApplicable,
                );
              }
            }
          }
        }
      }
    }
  }
}

Iterable<PermissionStatusMsg> _ios() sync* {
  for (final location in LocationAccessMsg.values) {
    for (final precise in _states) {
      for (final services in [false, true]) {
        for (final notifications in _states) {
          for (final alarmKit in _states) {
            yield iosPermissions(
              location: location,
              precise: precise,
              locationServicesEnabled: services,
              notifications: notifications,
              alarmKit: alarmKit,
            );
          }
        }
      }
    }
  }
}

const _stickies = <Set<OnboardingItemKind>>[
  {},
  {OnboardingItemKind.fullScreenIntent},
  {OnboardingItemKind.exactAlarm},
  {OnboardingItemKind.fullScreenIntent, OnboardingItemKind.exactAlarm},
];

/// States the native sides can send (T21 D2, §9): `precise` and
/// `notifications` are never notApplicable; iOS 26+ always reads AlarmKit,
/// below 26 it is notApplicable. Other inputs are contract violations: they
/// must not crash, but the invariants are not asserted on them.
bool _reachable(PermissionStatusMsg s, DeviceInfoMsg device) {
  if (s.precise == PermissionStateMsg.notApplicable ||
      s.notifications == PermissionStateMsg.notApplicable) {
    return false;
  }
  if (device.platform == PlatformMsg.ios) {
    final major = device.iosMajor ?? 0;
    return (major >= 26) == (s.alarmKit != PermissionStateMsg.notApplicable);
  }
  return true;
}

void _checkInvariants(
  PermissionStatusMsg s,
  DeviceInfoMsg device,
  List<OnboardingItem> items,
  Set<OnboardingItemKind> sticky,
) {
  if (!_reachable(s, device)) {
    return;
  }
  final why = '$s ${device.platform.name} sticky=$sticky -> $items';
  final check = checkStart(s, device);
  final android = device.platform == PlatformMsg.android;

  // Fixed order, no duplicates, location and notifications always shown.
  expect(items[0].kind, OnboardingItemKind.location, reason: why);
  expect(items[1].kind, OnboardingItemKind.notifications, reason: why);
  for (var i = 1; i < items.length; i++) {
    expect(items[i].kind.index, greaterThan(items[i - 1].kind.index));
  }

  for (final item in items) {
    // A done row never has a button; a missing row has exactly one action.
    if (item.isDone) {
      expect(item.request == null && item.settings == null, isTrue);
      expect(item.blocking, isFalse, reason: 'done but blocking: $why');
    } else {
      expect(
        (item.request == null) != (item.settings == null),
        isTrue,
        reason: 'not exactly one action: $why',
      );
    }
    // D13: a sheet before every system dialog and every special page.
    if (item.request != null) {
      expect(item.explainer, isNot(OnboardingExplainer.none), reason: why);
    }
    if (item.settings == SettingsTargetMsg.fullScreenIntent) {
      expect(item.explainer, OnboardingExplainer.fullScreenIntent);
    }
    if (item.settings == SettingsTargetMsg.exactAlarm) {
      expect(item.explainer, OnboardingExplainer.exactAlarm);
    }
    // Denied = straight to Settings, no sheet (D13).
    if (item.settings == SettingsTargetMsg.appDetails ||
        item.settings == SettingsTargetMsg.locationServices ||
        item.settings == SettingsTargetMsg.notifications) {
      expect(item.explainer, OnboardingExplainer.none, reason: why);
    }
    if (android) {
      expect(item.request, isNot(PermissionKindMsg.alarmKit), reason: why);
      expect(item.kind, isNot(OnboardingItemKind.alarmKit), reason: why);
    } else {
      expect(item.kind, isNot(OnboardingItemKind.fullScreenIntent));
      expect(item.kind, isNot(OnboardingItemKind.exactAlarm));
    }
  }

  // The screen never looks complete while the trip cannot start.
  if (!check.canStart) {
    expect(
      items.any((i) => i.blocking && !i.isDone),
      isTrue,
      reason: 'cannot start but no blocking row: $why',
    );
  } else {
    expect(items.any((i) => i.blocking), isFalse, reason: why);
  }

  // Android notifications never block (PRD §3.1).
  if (android) {
    expect(items[1].blocking, isFalse, reason: why);
  }

  // Optional Android rows: shown while not granted, kept once shown.
  if (android) {
    for (final (kind, state) in [
      (OnboardingItemKind.fullScreenIntent, s.fullScreenIntent),
      (OnboardingItemKind.exactAlarm, s.exactAlarm),
    ]) {
      final shown = items.any((i) => i.kind == kind);
      final notGranted =
          state == PermissionStateMsg.denied ||
          state == PermissionStateMsg.notDetermined;
      expect(shown, notGranted || sticky.contains(kind), reason: why);
    }
  }
}

void main() {
  test('Android: every permission state x sticky set', () {
    var n = 0;
    final device = androidDevice();
    for (final s in _android()) {
      for (final sticky in _stickies) {
        final items = buildOnboardingItems(s, device, sticky: sticky);
        _checkInvariants(s, device, items, sticky);
        n++;
      }
    }
    expect(n, 4 * 4 * 2 * 4 * 4 * 4 * 4 * _stickies.length);
  });

  test('iOS 17 and 26: every permission state', () {
    for (final major in [17, 25, 26, 27]) {
      final device = iosDevice(major: major);
      for (final s in _ios()) {
        final items = buildOnboardingItems(s, device);
        _checkInvariants(s, device, items, const {});
        final alarmKitRow = items.any(
          (i) => i.kind == OnboardingItemKind.alarmKit,
        );
        expect(
          alarmKitRow,
          major >= 26 && s.alarmKit != PermissionStateMsg.notApplicable,
          reason: '$major $s',
        );
      }
    }
  });

  test('the row a user sees after each step of the Android dialogs', () {
    final device = androidDevice();
    OnboardingItem loc(PermissionStatusMsg s) =>
        buildOnboardingItems(s, device).first;
    // Fresh: "Cấp quyền" with the location sheet.
    var row = loc(
      androidPermissions(
        location: LocationAccessMsg.notDetermined,
        precise: PermissionStateMsg.notDetermined,
      ),
    );
    expect(row.state, OnboardingItemState.needed);
    expect(row.explainer, OnboardingExplainer.location);
    // "Gần đúng": "Bật Chính xác" with the precise sheet.
    row = loc(androidPermissions(precise: PermissionStateMsg.notDetermined));
    expect(row.state, OnboardingItemState.approximate);
    expect(row.request, PermissionKindMsg.location);
    expect(row.explainer, OnboardingExplainer.precise);
    // Upgrade refused: Settings (app details).
    row = loc(androidPermissions(precise: PermissionStateMsg.denied));
    expect(row.settings, SettingsTargetMsg.appDetails);
    // Denied twice: Settings.
    row = loc(
      androidPermissions(
        location: LocationAccessMsg.denied,
        precise: PermissionStateMsg.notDetermined,
      ),
    );
    expect(row.state, OnboardingItemState.denied);
    expect(row.settings, SettingsTargetMsg.appDetails);
    // Precise, but location services off: the location page, no sheet.
    row = loc(androidPermissions(locationServicesEnabled: false));
    expect(row.state, OnboardingItemState.servicesOff);
    expect(row.settings, SettingsTargetMsg.locationServices);
    expect(row.blocking, isTrue);
  });

  test('battery card: Android always, tone follows the exemption', () {
    final catalog = kTestBatteryGuideCatalog;
    for (final guide in catalog.guides) {
      for (final state in PermissionStateMsg.values) {
        final card = buildBatteryCard(
          androidPermissions(batteryOptimizationIgnored: state),
          androidDevice(),
          guide,
        );
        expect(card, isNotNull);
        expect(
          card!.tone,
          state == PermissionStateMsg.granted
              ? BatteryCardTone.neutral
              : BatteryCardTone.warning,
        );
        expect(card.stepCount, guide.steps.length);
        expect(card.brandKey, guide.id == kGenericGuideId ? null : isNotNull);
      }
      expect(buildBatteryCard(iosPermissions(), iosDevice(), guide), isNull);
    }
  });
}
