import 'package:flutter/widgets.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/onboarding/domain/onboarding_items.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Texts and icons of one screen 0 row (T21 §7.2).
typedef OnboardingRowTexts = ({
  String title,
  String subtitle,
  String? action,
  IconData icon,
});

/// Texts of an explainer sheet (T21 §7.3).
typedef ExplainerTexts = ({
  String title,
  String body,
  String? hint,
  String primary,
  IconData icon,
});

extension OnboardingStrings on AppLocalizations {
  OnboardingRowTexts onboardingRow(OnboardingItem item) {
    final state = item.state;
    final denied = state == OnboardingItemState.denied;
    // Settings rows say "Mở Cài đặt" (services off: "Bật định vị").
    String? action() {
      if (item.isDone) {
        return null;
      }
      if (state == OnboardingItemState.servicesOff) {
        return onboardingActionLocationServices;
      }
      if (item.settings != null) {
        return permOpenSettings;
      }
      if (state == OnboardingItemState.approximate) {
        return onboardingActionPrecise;
      }
      return onboardingActionAllow;
    }

    return switch (item.kind) {
      OnboardingItemKind.location => (
        title: permLocationRowTitle,
        subtitle: switch (state) {
          OnboardingItemState.done => permLocationRowOn,
          OnboardingItemState.needed => permLocationRowNeeded,
          OnboardingItemState.denied => permLocationRowDenied,
          OnboardingItemState.approximate => permLocationRowApprox,
          OnboardingItemState.servicesOff => permLocationRowServicesOff,
        },
        action: action(),
        icon: NapIcons.place,
      ),
      OnboardingItemKind.notifications => (
        title: permNotificationsRowTitle,
        subtitle: denied ? permRowDeniedSettings : permNotificationsRowNeeded,
        action: action(),
        icon: NapIcons.alarm,
      ),
      OnboardingItemKind.fullScreenIntent => (
        title: permFullScreenTitle,
        subtitle: permFullScreenRowNeeded,
        action: action(),
        icon: NapIcons.fullScreen,
      ),
      OnboardingItemKind.exactAlarm => (
        title: permExactAlarmRowTitle,
        subtitle: permExactAlarmRowNeeded,
        action: action(),
        icon: NapIcons.alarmClock,
      ),
      OnboardingItemKind.alarmKit => (
        title: permAlarmKitRowTitle,
        subtitle: denied ? permAlarmKitDenied : permAlarmKitRowNeeded,
        action: action(),
        icon: NapIcons.alarmClock,
      ),
    };
  }

  /// Null for [OnboardingExplainer.none].
  ExplainerTexts? explainer(OnboardingExplainer e) => switch (e) {
    OnboardingExplainer.none => null,
    OnboardingExplainer.location => (
      title: permLocationTitle,
      body: permLocationBody,
      hint: permLocationHint,
      primary: onboardingContinue,
      icon: NapIcons.place,
    ),
    OnboardingExplainer.precise => (
      title: permLocationPreciseTitle,
      body: permLocationPreciseRequired,
      hint: permLocationHint,
      primary: onboardingContinue,
      icon: NapIcons.place,
    ),
    OnboardingExplainer.notifications => (
      title: permNotificationsTitle,
      body: permNotificationsBody,
      hint: null,
      primary: onboardingContinue,
      icon: NapIcons.alarm,
    ),
    OnboardingExplainer.fullScreenIntent => (
      title: permFullScreenTitle,
      body: permFullScreenBody,
      hint: null,
      primary: permOpenSettings,
      icon: NapIcons.fullScreen,
    ),
    OnboardingExplainer.exactAlarm => (
      title: permExactAlarmTitle,
      body: permExactAlarmBody,
      hint: null,
      primary: permOpenSettings,
      icon: NapIcons.alarmClock,
    ),
    OnboardingExplainer.alarmKit => (
      title: permAlarmKitTitle,
      body: permAlarmKitBody,
      hint: null,
      primary: onboardingContinue,
      icon: NapIcons.alarmClock,
    ),
  };
}
