import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/app/router/app_shell.dart';
import 'package:napstop/app/router/placeholder_screen.dart';
import 'package:napstop/features/alarm_settings/domain/alarm_settings_args.dart';
import 'package:napstop/features/alarm_settings/presentation/alarm_settings_screen.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_screen.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/features/onboarding/data/onboarding_progress.dart';
import 'package:napstop/features/onboarding/presentation/onboarding_screen.dart';
import 'package:napstop/features/tracking/presentation/tracking_screen.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Navigator of the full-screen routes; they cover the bottom navigation.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey(
  debugLabel: 'root',
);

/// The app router (T22 §3). First run (T21 D10): main() picks
/// [initialLocation] (screen 0 or 1) from a stored flag; no redirect. No route
/// observer: route names never leave the device (T29 §2).
GoRouter createAppRouter({String initialLocation = AppRoutes.home}) {
  GoRoute fullScreen(String path, String Function(AppLocalizations l) title) =>
      GoRoute(
        path: path,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, _) =>
            PlaceholderScreen(title: title(AppLocalizations.of(context))),
      );

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
                builder: (context, _) => PlaceholderScreen(
                  title: AppLocalizations.of(context).appScreenHistoryTitle,
                  showBack: false,
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, _) => PlaceholderScreen(
                  title: AppLocalizations.of(context).appScreenSettingsTitle,
                  showBack: false,
                ),
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
        builder: (context, state) => DestinationScreen(
          pickMode: state.uri.queryParameters['mode'] == kDestinationModePick,
        ),
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
      fullScreen(AppRoutes.alarm, (l) => l.appScreenAlarmTitle),
      fullScreen(AppRoutes.overshoot, (l) => l.appScreenOvershootTitle),
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
