import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/core/design/theme/nap_themes.dart';
import 'package:napstop/features/tracking/presentation/trip_launch_scope.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Brand name, not translated (CLAUDE.md); the only display string outside
/// ARB.
const String kAppName = 'NapStop';

/// The app. Must sit under a `ProviderScope` (main.dart).
class NapStopApp extends ConsumerWidget {
  const new({required this.flavor, super.key});

  /// Not used by the UI yet; T29 uses it to pick the Firebase configuration.
  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: kAppName,
      theme: NapThemes.light(),
      darkTheme: NapThemes.dark(),
      // themeMode: ThemeMode.system (default). T28 sets the user choice.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kAppSupportedLocales,
      routerConfig: ref.watch(appRouterProvider),
      // T26 D12: screen 4 when the app opens or returns with a running trip.
      builder: (context, child) => TripLaunchScope(child: child!),
    );
  }
}
