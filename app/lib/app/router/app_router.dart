import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/app/router/app_shell.dart';
import 'package:napstop/app/router/placeholder_screen.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/destination/presentation/destination_screen.dart';
import 'package:napstop/features/home/presentation/home_screen.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Navigator of the full-screen routes; they cover the bottom navigation.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey(
  debugLabel: 'root',
);

/// The app router (T22 §3). T21 adds the first-run redirect and a
/// `refreshListenable` here. No route observer: route names never leave the
/// device (T29 §2).
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
      fullScreen(AppRoutes.onboarding, (l) => l.appScreenOnboardingTitle),
      fullScreen(AppRoutes.batteryGuide, (l) => l.appScreenBatteryGuideTitle),
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
        redirect: (_, state) =>
            state.extra is TripDraft ? null : AppRoutes.home,
        builder: (context, state) =>
            AlarmSettingsPlaceholder(draft: state.extra! as TripDraft),
      ),
      fullScreen(AppRoutes.tracking, (l) => l.appScreenTrackingTitle),
      fullScreen(AppRoutes.alarm, (l) => l.appScreenAlarmTitle),
      fullScreen(AppRoutes.overshoot, (l) => l.appScreenOvershootTitle),
    ],
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = createAppRouter();
  ref.onDispose(router.dispose);
  return router;
});
