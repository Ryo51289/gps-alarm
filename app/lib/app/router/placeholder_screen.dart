import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/features/home/presentation/home_format.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Stand-in for a screen that a later task builds (T22 §3.3). Each task
/// replaces the builder of its route and deletes its placeholder.
class PlaceholderScreen extends StatelessWidget {
  const new({required this.title, this.showBack = true, this.body, super.key});

  final String title;

  /// False on the shell tabs.
  final bool showBack;

  /// Extra content under the placeholder text.
  final Widget? body;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            NapSpace.page,
            NapSpace.s8,
            NapSpace.page,
            NapSpace.s16,
          ),
          children: [
            NapScreenHeader(
              title: title,
              onBack: showBack ? () => context.pop() : null,
            ),
            const SizedBox(height: NapSpace.s16),
            Text(
              AppLocalizations.of(context).appPlaceholderBody,
              style: context.napText.bodyMedium!.copyWith(
                color: c.textSecondary,
              ),
            ),
            if (body != null) ...[const SizedBox(height: NapSpace.s16), body!],
          ],
        ),
      ),
    );
  }
}

/// Screen 3 placeholder: shows the received draft so that "restart in one
/// tap" can be tested end to end before T25. T25 replaces it.
class AlarmSettingsPlaceholder extends StatelessWidget {
  const new({required this.draft, super.key});

  final TripDraft draft;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final alarm = draft.alarm;
    return PlaceholderScreen(
      title: l.appScreenAlarmSettingsTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NapSpace.s4,
        children: [
          Text(draft.destination.name, style: context.napText.titleMedium),
          if (alarm != null)
            Text(
              alarmSummary(alarm, l, Localizations.localeOf(context)),
              style: context.napText.bodyMedium,
            ),
        ],
      ),
    );
  }
}
