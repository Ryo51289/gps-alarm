import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';

/// Route paths (T22 §3.1). Paths are a contract: later tasks never change
/// them; new sub-paths are announced in their spec.
abstract final class AppRoutes {
  /// Screen 1, shell branch 0.
  static const String home = '/home';

  /// Screen 11, shell branch 1.
  static const String history = '/trips';

  /// Screen 12, shell branch 2.
  static const String settings = '/settings';

  /// Screen 0 (T21).
  static const String onboarding = '/onboarding';

  /// Screen 9 (T21).
  static const String batteryGuide = '/battery-guide';

  /// Screen 2 (T23).
  static const String destination = '/destination';

  /// Screen 2 as a picker.
  static const String destinationPick = '/destination?mode=pick';

  /// Screen 3 (T25); `extra` must be a [TripDraft] or an
  /// `AlarmSettingsArgs` (preset, simulation).
  static const String alarmSettings = '/alarm-settings';

  /// Screen 4, with states 6 and 7 (T26).
  static const String tracking = '/tracking';

  /// Screen 5 (T27).
  static const String alarm = '/alarm';

  /// Screen 8 (T27).
  static const String overshoot = '/overshoot';
}

/// Query value of `/destination` that turns screen 2 into a picker:
/// confirming pops a [TripDestination] instead of opening screen 3.
const String kDestinationModePick = 'pick';

extension AppNavigation on BuildContext {
  /// Screen 2, normal flow (ends at screen 3).
  Future<void> openDestinationSearch() => push<void>(AppRoutes.destination);

  /// Screen 2 as a picker; null when the user backs out.
  Future<TripDestination?> pickDestination() =>
      push<TripDestination>(AppRoutes.destinationPick);

  /// Screen 3 prefilled with [draft].
  Future<void> openAlarmSettings(TripDraft draft) =>
      push<void>(AppRoutes.alarmSettings, extra: draft);

  /// Screen 4. Uses `go`: Back does not return to the previous screen.
  void openTracking() => go(AppRoutes.tracking);

  Future<void> openOnboarding() => push<void>(AppRoutes.onboarding);

  Future<void> openBatteryGuide() => push<void>(AppRoutes.batteryGuide);
}

/// Opens screen 2 as a picker. A seam for widget tests (screen 2 is a
/// placeholder until T23).
typedef DestinationPicker = Future<TripDestination?> Function(
  BuildContext context,
);

final destinationPickerProvider = Provider<DestinationPicker>(
  (ref) =>
      (context) => context.pickDestination(),
);
