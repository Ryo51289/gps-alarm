import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/core/trip/domain/trip_destination.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';

/// Route paths (T22 §3.1). Paths are a contract: later tasks never change
/// them; new sub-paths are announced in their spec.
abstract final class AppRoutes {
  /// Screen 1, shell branch 0.
  static const String home = '/home';

  /// Screen 11, shell branch 1.
  static const String history = '/trips';

  /// Screen 12, shell branch 2.
  static const String settings = '/settings';

  /// Screen 12 > "Mặc định cho chuyến mới" (T28 §4.4), full screen.
  static const String tripDefaults = '/settings/trip-defaults';

  /// Screen 0 (T21).
  static const String onboarding = '/onboarding';

  /// Screen 9 (T21).
  static const String batteryGuide = '/battery-guide';

  /// Screen 2 (T23).
  static const String destination = '/destination';

  /// Screen 2 as a picker.
  static const String destinationPick = '/destination?mode=pick';

  /// Screen 2 as a picker for [slot] (T23.7).
  static String destinationPickFor(SavedPlaceSlot slot) =>
      '$destinationPick&$kDestinationSlotParam=${slot.name}';

  /// Screen 3 (T25); `extra` must be a [TripDraft] or an
  /// `AlarmSettingsArgs` (preset, simulation).
  static const String alarmSettings = '/alarm-settings';

  /// Screen 4, with states 6 and 7 (T26).
  static const String tracking = '/tracking';

  /// Screen 5 (T27), the Flutter fallback: `/alarm?trip=<id>`.
  static const String alarm = '/alarm';

  /// Screen 8 (T27): `/overshoot?trip=<id>[&past=<m>][&open=1]`
  /// (`OvershootArgs`).
  static const String overshoot = '/overshoot';
}

/// Query value of `/destination` that turns screen 2 into a picker:
/// confirming pops a [TripDestination] instead of opening screen 3.
const String kDestinationModePick = 'pick';

/// Query key of `/destination?mode=pick` naming the saved place slot the
/// pick goes into (T23.7). Value: `SavedPlaceSlot.name`.
const String kDestinationSlotParam = 'slot';

extension AppNavigation on BuildContext {
  /// Screen 2, normal flow (ends at screen 3).
  Future<void> openDestinationSearch() => push<void>(AppRoutes.destination);

  /// Screen 2 as a picker; null when the user backs out. With [slot], the
  /// confirm button reads `Lưu vào <slot>` and Back with a pending choice
  /// asks first (T23.7).
  Future<TripDestination?> pickDestination({SavedPlaceSlot? slot}) =>
      push<TripDestination>(
        slot == null
            ? AppRoutes.destinationPick
            : AppRoutes.destinationPickFor(slot),
      );

  /// Screen 3 prefilled with [draft].
  Future<void> openAlarmSettings(TripDraft draft) =>
      push<void>(AppRoutes.alarmSettings, extra: draft);

  /// Screen 3 with full arguments (T28: simulation entry of screen 12).
  Future<void> openAlarmSettingsWith(AlarmSettingsArgs args) =>
      push<void>(AppRoutes.alarmSettings, extra: args);

  /// Screen 12 > defaults for new trips (T28).
  Future<void> openTripDefaults() => push<void>(AppRoutes.tripDefaults);

  /// Screen 4. Uses `go`: Back does not return to the previous screen.
  void openTracking() => go(AppRoutes.tracking);

  /// Screen 8 (T27 D9). Uses `go`: the trip is over, nothing to go back to.
  void openOvershoot(OvershootArgs args) => go(args.toLocation());

  Future<void> openOnboarding() => push<void>(AppRoutes.onboarding);

  Future<void> openBatteryGuide() => push<void>(AppRoutes.batteryGuide);
}

/// Opens screen 2 as a picker for [slot]. A seam for widget tests.
typedef DestinationPicker = Future<TripDestination?> Function(
  BuildContext context,
  SavedPlaceSlot slot,
);

final destinationPickerProvider = Provider<DestinationPicker>(
  (ref) =>
      (context, slot) => context.pickDestination(slot: slot),
);
