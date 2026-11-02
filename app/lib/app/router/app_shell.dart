import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Bottom navigation with 3 tabs: Home, Trips, Settings (T22 §3.2, D6).
class AppShell extends StatelessWidget {
  const new({required this.shell, super.key});

  final StatefulNavigationShell shell;

  void _select(int index) =>
      shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return PopScope(
      // Back from another tab goes to Home; from Home it leaves the app.
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          shell.goBranch(0);
        }
      },
      child: Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _select,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const Icon(NapIcons.home),
              label: l.appNavHome,
            ),
            NavigationDestination(
              icon: const Icon(NapIcons.history),
              label: l.appNavTrips,
            ),
            NavigationDestination(
              icon: const Icon(NapIcons.settings),
              label: l.appNavSettings,
            ),
          ],
        ),
      ),
    );
  }
}
