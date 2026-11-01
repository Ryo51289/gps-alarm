import 'package:flutter/material.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/core/design/theme/nap_themes.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Brand name, not translated (CLAUDE.md); the only display string outside
/// ARB.
const String kAppName = 'NapStop';

class NapStopApp extends StatelessWidget {
  const new({required this.flavor, super.key});

  /// Not used by the UI yet; T29 uses it to pick the Firebase configuration.
  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      theme: NapThemes.light(),
      darkTheme: NapThemes.dark(),
      // themeMode: ThemeMode.system (default). T28 sets the user choice.
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kAppSupportedLocales,
      home: const _PlaceholderPage(),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          header: true,
          child: Text(
            kAppName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
    );
  }
}
