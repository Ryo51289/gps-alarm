/// Rows and battery card of screen 0 (T21 §6.1, §6.2). Pure Dart.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/bridge/core_api.g.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/onboarding/domain/start_check.dart';

enum OnboardingItemKind {
  location,
  notifications,
  fullScreenIntent,
  exactAlarm,
  alarmKit,
}

/// done: nothing to do. needed: a system prompt can be shown. denied:
/// Settings only. approximate / servicesOff: only for location.
enum OnboardingItemState { done, needed, denied, approximate, servicesOff }

/// The sheet shown before an action (D13).
enum OnboardingExplainer {
  none,
  location,
  precise,
  notifications,
  fullScreenIntent,
  exactAlarm,
  alarmKit,
}

/// One row of screen 0.
@immutable
final class OnboardingItem {
  const new({
    required this.kind,
    required this.state,
    required this.blocking,
    this.request,
    this.settings,
    this.explainer = OnboardingExplainer.none,
  });

  final OnboardingItemKind kind;
  final OnboardingItemState state;

  /// Missing and listed in `checkStart(...).missing` (blocks "Bắt đầu theo
  /// dõi" on screen 3).
  final bool blocking;

  /// Exactly one of [request] / [settings] is set when [state] is not done.
  final PermissionKindMsg? request;
  final SettingsTargetMsg? settings;

  /// Sheet shown before the action.
  final OnboardingExplainer explainer;

  bool get isDone => state == OnboardingItemState.done;

  @override
  bool operator ==(Object other) =>
      other is OnboardingItem &&
      other.kind == kind &&
      other.state == state &&
      other.blocking == blocking &&
      other.request == request &&
      other.settings == settings &&
      other.explainer == explainer;

  @override
  int get hashCode =>
      Object.hash(kind, state, blocking, request, settings, explainer);

  @override
  String toString() => 'OnboardingItem(${kind.name}, ${state.name})';
}

bool _notGranted(PermissionStateMsg s) =>
    s == PermissionStateMsg.denied || s == PermissionStateMsg.notDetermined;

/// Rows in fixed order: location, notifications, fullScreenIntent,
/// exactAlarm, alarmKit. [sticky]: optional kinds already shown during this
/// visit of the screen; they stay (as done) once granted (D12).
List<OnboardingItem> buildOnboardingItems(
  PermissionStatusMsg s,
  DeviceInfoMsg device, {
  Set<OnboardingItemKind> sticky = const {},
}) {
  final missing = checkStart(s, device).missing;
  final android = device.platform == PlatformMsg.android;
  final ios = device.platform == PlatformMsg.ios;
  final alarmChannelMissing = missing.contains(StartRequirement.alarmChannel);
  final items = <OnboardingItem>[_location(s, missing)];

  final notificationsBlocking = ios && alarmChannelMissing;
  items.add(switch (s.notifications) {
    PermissionStateMsg.granted ||
    PermissionStateMsg.notApplicable => const OnboardingItem(
      kind: OnboardingItemKind.notifications,
      state: OnboardingItemState.done,
      blocking: false,
    ),
    PermissionStateMsg.notDetermined => OnboardingItem(
      kind: OnboardingItemKind.notifications,
      state: OnboardingItemState.needed,
      blocking: notificationsBlocking,
      request: PermissionKindMsg.notifications,
      explainer: OnboardingExplainer.notifications,
    ),
    PermissionStateMsg.denied => OnboardingItem(
      kind: OnboardingItemKind.notifications,
      state: OnboardingItemState.denied,
      blocking: notificationsBlocking,
      settings: SettingsTargetMsg.notifications,
    ),
  });

  if (android) {
    final fsi = _special(
      s.fullScreenIntent,
      OnboardingItemKind.fullScreenIntent,
      SettingsTargetMsg.fullScreenIntent,
      OnboardingExplainer.fullScreenIntent,
      sticky,
    );
    if (fsi != null) {
      items.add(fsi);
    }
    final exact = _special(
      s.exactAlarm,
      OnboardingItemKind.exactAlarm,
      SettingsTargetMsg.exactAlarm,
      OnboardingExplainer.exactAlarm,
      sticky,
    );
    if (exact != null) {
      items.add(exact);
    }
  }

  if (ios &&
      (device.iosMajor ?? 0) >= 26 &&
      s.alarmKit != PermissionStateMsg.notApplicable) {
    items.add(switch (s.alarmKit) {
      PermissionStateMsg.notDetermined => OnboardingItem(
        kind: OnboardingItemKind.alarmKit,
        state: OnboardingItemState.needed,
        blocking: alarmChannelMissing,
        request: PermissionKindMsg.alarmKit,
        explainer: OnboardingExplainer.alarmKit,
      ),
      PermissionStateMsg.denied => OnboardingItem(
        kind: OnboardingItemKind.alarmKit,
        state: OnboardingItemState.denied,
        blocking: alarmChannelMissing,
        settings: SettingsTargetMsg.appDetails,
      ),
      _ => const OnboardingItem(
        kind: OnboardingItemKind.alarmKit,
        state: OnboardingItemState.done,
        blocking: false,
      ),
    });
  }
  return List.unmodifiable(items);
}

OnboardingItem _location(
  PermissionStatusMsg s,
  List<StartRequirement> missing,
) {
  final blocking =
      missing.contains(StartRequirement.location) ||
      missing.contains(StartRequirement.precise) ||
      missing.contains(StartRequirement.locationServices);
  const kind = OnboardingItemKind.location;
  final hasLocation =
      s.location == LocationAccessMsg.whileInUse ||
      s.location == LocationAccessMsg.always;
  if (s.location == LocationAccessMsg.notDetermined) {
    return OnboardingItem(
      kind: kind,
      state: OnboardingItemState.needed,
      blocking: blocking,
      request: PermissionKindMsg.location,
      explainer: OnboardingExplainer.location,
    );
  }
  if (!hasLocation) {
    return OnboardingItem(
      kind: kind,
      state: OnboardingItemState.denied,
      blocking: blocking,
      settings: SettingsTargetMsg.appDetails,
    );
  }
  if (s.precise == PermissionStateMsg.notDetermined) {
    return OnboardingItem(
      kind: kind,
      state: OnboardingItemState.approximate,
      blocking: blocking,
      request: PermissionKindMsg.location,
      explainer: OnboardingExplainer.precise,
    );
  }
  if (s.precise == PermissionStateMsg.denied) {
    return OnboardingItem(
      kind: kind,
      state: OnboardingItemState.approximate,
      blocking: blocking,
      settings: SettingsTargetMsg.appDetails,
    );
  }
  if (!s.locationServicesEnabled) {
    return OnboardingItem(
      kind: kind,
      state: OnboardingItemState.servicesOff,
      blocking: blocking,
      settings: SettingsTargetMsg.locationServices,
    );
  }
  return OnboardingItem(
    kind: kind,
    state: OnboardingItemState.done,
    blocking: blocking,
  );
}

/// Full-screen intent / exact alarm: shown while not granted, or when
/// [sticky] (already shown in this visit).
OnboardingItem? _special(
  PermissionStateMsg state,
  OnboardingItemKind kind,
  SettingsTargetMsg target,
  OnboardingExplainer explainer,
  Set<OnboardingItemKind> sticky,
) {
  if (!_notGranted(state) && !sticky.contains(kind)) {
    return null;
  }
  if (state == PermissionStateMsg.granted ||
      state == PermissionStateMsg.notApplicable) {
    return OnboardingItem(
      kind: kind,
      state: OnboardingItemState.done,
      blocking: false,
    );
  }
  return OnboardingItem(
    kind: kind,
    state: OnboardingItemState.denied,
    blocking: false,
    settings: target,
    explainer: explainer,
  );
}

/// The kinds of [items] (the controller unions them into its sticky set).
Set<OnboardingItemKind> kindsOf(List<OnboardingItem> items) => {
  for (final i in items) i.kind,
};

enum BatteryCardTone { warning, neutral }

/// The battery optimization card of screen 0 (Android only).
@immutable
final class BatteryCardModel {
  const new({
    required this.tone,
    required this.guideId,
    required this.brandKey,
    required this.stepCount,
  });

  /// warning: battery optimization still applies.
  final BatteryCardTone tone;

  /// e.g. "xiaomi", "generic".
  final String guideId;

  /// ARB key of the brand name; null for the generic guide.
  final String? brandKey;
  final int stepCount;

  @override
  bool operator ==(Object other) =>
      other is BatteryCardModel &&
      other.tone == tone &&
      other.guideId == guideId &&
      other.brandKey == brandKey &&
      other.stepCount == stepCount;

  @override
  int get hashCode => Object.hash(tone, guideId, brandKey, stepCount);

  @override
  String toString() =>
      'BatteryCardModel(${tone.name}, $guideId, $brandKey, $stepCount)';
}

/// Null on iOS.
BatteryCardModel? buildBatteryCard(
  PermissionStatusMsg s,
  DeviceInfoMsg device,
  BatteryGuide guide,
) {
  if (device.platform != PlatformMsg.android) {
    return null;
  }
  return BatteryCardModel(
    tone: s.batteryOptimizationIgnored == PermissionStateMsg.granted
        ? BatteryCardTone.neutral
        : BatteryCardTone.warning,
    guideId: guide.id,
    brandKey: guide.isGeneric ? null : guide.labelKey,
    stepCount: guide.steps.length,
  );
}
