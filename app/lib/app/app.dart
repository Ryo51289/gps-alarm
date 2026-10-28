import 'package:flutter/material.dart';
import 'package:napstop/app/flavor.dart';

/// Brand name. Not translated, so it is the only display string allowed
/// outside ARB until gen-l10n is set up (T20).
const String kAppName = 'NapStop';

class NapStopApp extends StatelessWidget {
  const new({required this.flavor, super.key});

  /// Not used by the UI yet; T29 uses it to pick the Firebase configuration.
  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: kAppName, home: _PlaceholderPage());
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
