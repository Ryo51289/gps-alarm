import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/app/router/app_shell.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/alarm/domain/route_back.dart';
import 'package:napstop/features/alarm/presentation/alarm_fallback_screen.dart';
import 'package:napstop/features/alarm/presentation/overshoot_screen.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_screen.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_screen.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/history/presentation/history_screen.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:napstop/features/settings/presentation/settings_screen.dart';
import 'package:napstop/features/settings/presentation/trip_defaults_screen.dart';
import 'package:napstop/features/tracking/presentation/tracking_screen.dart';

/// Navigator of the full-screen routes; they cover the bottom navigation.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey(
  debugLabel: 'root',
);

/// The app router (T22 §3). First run (T21 D10): main() picks
/// [initialLocation] (screen 0 or 1) from a stored flag; no redirect. No route
/// observer: route names never leave the device (T29 §2).
GoRouter createAppRouter({String initialLocation = AppRoutes.home}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.home),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, _) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.history,
                builder: (context, _) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, _) => const SettingsScreen(),
                routes: [
                  // `/settings/trip-defaults`, over the bottom navigation.
                  GoRoute(
                    path: 'trip-defaults',
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, _) => const TripDefaultsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, _) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.batteryGuide,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, _) => const BatteryGuideScreen(),
      ),
      GoRoute(
        path: AppRoutes.destination,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final query = state.uri.queryParameters;
          final pick = query['mode'] == kDestinationModePick;
          return DestinationScreen(
            pickMode: pick,
            // T23.7: unknown/missing value = plain picker (no slot). Ignored
            // outside pick mode.
            pickSlot: pick
                ? SavedPlaceSlot.values
                      .asNameMap()[query[kDestinationSlotParam]]
                : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.alarmSettings,
        parentNavigatorKey: rootNavigatorKey,
        // No usable extra (e.g. a route restored after the process died):
        // back to screen 1 (T25 §2.2).
        redirect: (_, state) => AlarmSettingsArgs.fromExtra(state.extra) == null
            ? AppRoutes.home
            : null,
        builder: (context, state) => AlarmSettingsScreen(
          args: AlarmSettingsArgs.fromExtra(state.extra)!,
        ),
      ),
      GoRoute(
        path: AppRoutes.tracking,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, _) => const TrackingScreen(),
      ),
      // T27 §5: the Flutter fallback of screen 5, pushed by
      // AlarmUiCoordinator over the current screen (D10).
      GoRoute(
        path: AppRoutes.alarm,
        parentNavigatorKey: rootNavigatorKey,
        redirect: (_, state) => isValidTripId(state.uri.queryParameters['trip'])
            ? null
            : AppRoutes.home,
        builder: (context, state) => AlarmFallbackScreen(
          // A new trip id is a new screen state.
          key: ValueKey(state.uri.queryParameters['trip']),
          tripId: state.uri.queryParameters['trip']!,
        ),
      ),
      // T27 §5: screen 8 after the alarm was dismissed (D9: reached by `go`).
      GoRoute(
        path: AppRoutes.overshoot,
        parentNavigatorKey: rootNavigatorKey,
        redirect: (_, state) =>
            OvershootArgs.fromUri(state.uri) == null ? AppRoutes.home : null,
        builder: (context, state) => OvershootScreen(
          // Another launch action while screen 8 shows: a fresh state.
          key: ValueKey(OvershootArgs.fromUri(state.uri)),
          args: OvershootArgs.fromUri(state.uri)!,
        ),
      ),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter(
    initialLocation: ref.read(startupLocationProvider),
  );
  ref.onDispose(router.dispose);
  return router;
});
