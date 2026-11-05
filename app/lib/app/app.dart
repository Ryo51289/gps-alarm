import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/app_background_tasks.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/app/router/app_router.dart';
import 'package:napstop/core/design/theme/nap_themes.dart';
import 'package:napstop/core/preferences/app_settings.dart';
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
    // Screen 12 (T28 §4.1): language and theme change at once. The router
    // does not depend on them, so the screen stack is kept.
    final display = ref.watch(appSettingsProvider.select((s) => s.display));
    return MaterialApp.router(
      title: kAppName,
      theme: NapThemes.light(),
      darkTheme: NapThemes.dark(),
      themeMode: display.themeMode,
      // Null follows the phone; a language other than vi/en shows vi (T20).
      locale: display.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kAppSupportedLocales,
      routerConfig: ref.watch(appRouterProvider),
      // History sync and the native language (T28 §3.2, §4.1).
      builder: (context, child) =>
          AppBackgroundTasks(child: child ?? const SizedBox.shrink()),
    );
  }
}
