import 'dart:async';

import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// The two privacy switches of screen 12 (T28 §4.2 block 5, T29 §10). They
/// show the user's CHOICE (`controller.current`), not what collects (debug
/// builds never collect). A change re-reads `current` at once: the
/// controller only notifies after its disk write (review T29 R4-2).
class ConsentSwitches extends StatefulWidget {
  const new({required this.controller, super.key});

  final TelemetryConsentController controller;

  @override
  State<ConsentSwitches> createState() => _ConsentSwitchesState();
}

class _ConsentSwitchesState extends State<ConsentSwitches> {
  @override
  void initState() {
    super.initState();
    // A late read of the stored consent (adoptLoaded) and finished writes.
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ConsentSwitches oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _set({bool? crash, bool? analytics}) {
    ConsentChoice? choice({required bool? on}) => switch (on) {
      null => null,
      true => ConsentChoice.granted,
      false => ConsentChoice.denied,
    };
    unawaited(
      widget.controller.update(
        crash: choice(on: crash),
        analytics: choice(on: analytics),
      ),
    );
    // `current` already holds the answer.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final current = widget.controller.current;
    return NapListGroup(
      children: [
        NapSwitchRow(
          title: l.settingsCrashReports,
          subtitle: l.settingsCrashReportsHint,
          value: current.crash == ConsentChoice.granted,
          onChanged: (v) => _set(crash: v),
        ),
        NapSwitchRow(
          title: l.settingsUsageStats,
          subtitle: l.settingsUsageStatsHint,
          value: current.analytics == ConsentChoice.granted,
          onChanged: (v) => _set(analytics: v),
        ),
      ],
    );
  }
}
