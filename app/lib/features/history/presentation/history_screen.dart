import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/clock.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/trip_draft.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';
import 'package:napstop/core/trip/trip_providers.dart';
import 'package:napstop/features/history/data/history_sync.dart';
import 'package:napstop/features/history/domain/history_logic.dart';
import 'package:napstop/features/history/presentation/history_providers.dart';
import 'package:napstop/features/history/presentation/history_strings.dart';
import 'package:napstop/features/history/presentation/widgets/history_stats_card.dart';
import 'package:napstop/features/history/presentation/widgets/history_trip_tile.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Screen 11 "Lịch sử" (T28 §3.4): month stats, vehicle filter, the trips
/// (newest first) with their result and a one-tap "Đặt lại".
class HistoryScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  /// Back to "Tất cả" when the app restarts.
  HistoryFilter _filter = HistoryFilter.all;

  void _showSnack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), action: action, persist: false),
      );
  }

  /// Screen 3 prefilled (T22 D7), unless a trip is running.
  void _restart(TripRecord r) {
    if (ref.read(activeTripProvider).value != null) {
      final l = AppLocalizations.of(context);
      _showSnack(
        l.homeActiveTripBusy,
        action: SnackBarAction(
          label: l.homeActiveTripOpen,
          onPressed: () => context.openTracking(),
        ),
      );
      return;
    }
    unawaited(context.openAlarmSettings(TripDraft.fromRecord(r)));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = ref.watch(clockProvider)();
    final history = ref.watch(historyProvider);
    final stats = ref.watch(monthStatsProvider).value ?? HistoryStats.empty;
    final active = ref.watch(activeTripProvider);
    final activeTripId = active.value?.tripId;
    final activeKnown = active.hasValue || active.hasError;

    final rows = history.hasError
        ? null
        : filterHistory(history.value ?? const [], _filter);
    final header = <Widget>[
      NapScreenHeader(title: l.appScreenHistoryTitle),
      const SizedBox(height: NapSpace.s16),
      HistoryStatsCard(stats: stats, month: now),
      const SizedBox(height: NapSpace.s16),
      Wrap(
        spacing: NapSpace.s8,
        runSpacing: NapSpace.s8,
        children: [
          for (final f in HistoryFilter.values)
            NapChip(
              label: l.filterLabel(f),
              style: NapChipStyle.filter,
              selected: f == _filter,
              onTap: () => setState(() => _filter = f),
            ),
        ],
      ),
      const SizedBox(height: NapSpace.s16),
    ];

    final Widget? message;
    if (history.hasError) {
      message = _Message(
        text: l.historyError,
        action: NapButton(
          label: l.commonRetry,
          variant: NapButtonVariant.secondary,
          size: NapButtonSize.small,
          onPressed: () => ref.invalidate(historyProvider),
        ),
      );
    } else if (!history.hasValue) {
      message = null;
    } else if (rows!.isEmpty) {
      message = _Message(
        text: (history.value ?? const []).isEmpty
            ? l.historyEmpty
            : l.historyEmptyFilter,
      );
    } else {
      message = null;
    }

    final count = rows?.length ?? 0;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(historySyncProvider).sync(),
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              NapSpace.page,
              NapSpace.s8,
              NapSpace.page,
              NapSpace.s24,
            ),
            itemCount: header.length + (message != null ? 1 : count),
            itemBuilder: (context, i) {
              if (i < header.length) {
                return header[i];
              }
              if (message != null) {
                return message;
              }
              final r = rows![i - header.length];
              final status = historyStatusOf(
                r,
                activeTripId: activeTripId,
                activeKnown: activeKnown,
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: NapSpace.s8),
                child: NapCard(
                  padding: EdgeInsets.zero,
                  child: HistoryTripTile(
                    key: ValueKey(r.id),
                    record: r,
                    status: status,
                    now: now,
                    onTap: status == HistoryStatus.running
                        ? () => context.openTracking()
                        : null,
                    // Not while the running trip is unknown (review T28 #4).
                    onRestart: activeKnown && canRestart(r, status)
                        ? () => _restart(r)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const new({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final action = this.action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: NapSpace.s24),
      child: Column(
        spacing: NapSpace.s12,
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: context.napText.bodyMedium!.copyWith(
              color: context.napColors.textSecondary,
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
