import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';
import 'package:napstop/features/destination/domain/station.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/destination_strings.dart';
import 'package:napstop/features/destination/presentation/widgets/result_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// What the bus stop section shows (T24.3 §6.4).
enum BusStopSectionMode {
  /// Nothing (not loaded yet, query too short, or a hidden failure).
  hidden,
  startTyping,
  loading,
  error,
  empty,
  rows,
}

/// Pure decision of [BusStopSection]: chip "Trạm buýt" shows every state;
/// chip "Tất cả" only shows loading and rows (a failure or no match hides
/// the section there, D10), from [kBusStopAllMinQueryChars] letters.
BusStopSectionMode busStopSectionMode(DestinationState state) {
  final standalone = state.filter == DestinationFilter.busStop;
  if (!standalone && state.filter != DestinationFilter.all) {
    return BusStopSectionMode.hidden;
  }
  final chars = queryChars(state.query);
  if (standalone && chars < kMinOfflineQueryChars) {
    return BusStopSectionMode.startTyping;
  }
  if (!standalone && chars < kBusStopAllMinQueryChars) {
    return BusStopSectionMode.hidden;
  }
  final catalog = state.busCatalog;
  if (catalog == null) {
    return BusStopSectionMode.hidden;
  }
  if (catalog.isLoading && !catalog.hasValue) {
    return BusStopSectionMode.loading;
  }
  if (catalog.hasError && !catalog.hasValue) {
    return standalone ? BusStopSectionMode.error : BusStopSectionMode.hidden;
  }
  if (state.busStops.isNotEmpty) {
    return BusStopSectionMode.rows;
  }
  return standalone ? BusStopSectionMode.empty : BusStopSectionMode.hidden;
}

/// The bus stop section shows rows or is loading them: the stations' "no
/// match" lines are then left out (review T24.3 #1).
bool busStopsPending(DestinationState state) =>
    switch (busStopSectionMode(state)) {
      BusStopSectionMode.rows || BusStopSectionMode.loading => true,
      _ => false,
    };

/// Bus stop rows of screen 2 (T24.3 §6.4): the whole list on chip "Trạm
/// buýt", a short section with a header on chip "Tất cả".
///
/// PRIVACY: no logging; only the query typed by the user is shown back.
class BusStopSection extends StatelessWidget {
  const new({
    required this.state,
    required this.isSelected,
    required this.onSelect,
    required this.onRetry,
    this.addressOn = false,
    super.key,
  });

  final DestinationState state;
  final bool Function(Station s) isSelected;
  final ValueChanged<Station> onSelect;
  final VoidCallback onRetry;

  /// T23.5: the "start typing" note mentions addresses.
  final bool addressOn;

  @override
  Widget build(BuildContext context) {
    final mode = busStopSectionMode(state);
    if (mode == BusStopSectionMode.hidden) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final standalone = state.filter == DestinationFilter.busStop;
    final note = switch (mode) {
      BusStopSectionMode.startTyping => PanelNote(
        addressOn
            ? l.destinationStartTypingWithAddress
            : l.destinationStartTyping,
      ),
      BusStopSectionMode.loading => PanelNote(
        l.destinationBusStopLoading,
        loading: true,
      ),
      BusStopSectionMode.error => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NapSpace.s16,
          vertical: NapSpace.s8,
        ),
        child: NapBanner(
          message: l.destinationBusStopLoadError,
          action: NapButton(
            label: l.commonRetry,
            variant: NapButtonVariant.secondary,
            size: NapButtonSize.small,
            onPressed: onRetry,
          ),
        ),
      ),
      BusStopSectionMode.empty => PanelNote(
        l.destinationBusStopEmpty(state.query.trim()),
      ),
      BusStopSectionMode.rows || BusStopSectionMode.hidden => null,
    };
    return Column(
      key: const ValueKey('bus-stop-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!standalone)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NapSpace.s16,
              NapSpace.s16,
              NapSpace.s16,
              NapSpace.s4,
            ),
            child: Semantics(
              header: true,
              child: Text(
                l.destinationBusStopHeader,
                style: context
                    .napStyle(NapTypography.caption)
                    .copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ?note,
        if (mode == BusStopSectionMode.rows)
          for (final m in state.busStops)
            ResultRow(
              key: ValueKey('bus-stop-${m.station.id}'),
              icon: stationKindIcon(m.station.kind),
              title: m.station.name,
              subtitle: l.stationRowSubtitle(
                m.station,
                state.distanceByStationId[m.station.id],
              ),
              selected: isSelected(m.station),
              onTap: () => onSelect(m.station),
            ),
      ],
    );
  }
}
