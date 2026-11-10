import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/domain/address_search.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/widgets/result_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Apple Maps address suggestions under the station results (T23.5 §4.4).
/// Draws nothing while [AddressHidden]. The disclosure line is always there
/// when the section is: what is typed goes to Apple, the location does not.
///
/// PRIVACY: no logging; the texts shown are Apple's suggestions.
class AddressSection extends StatelessWidget {
  const new({
    required this.state,
    required this.isSelected,
    required this.onSelect,
    super.key,
  });

  final DestinationState state;
  final bool Function(AddressSuggestion s) isSelected;

  /// Called with the native index of the tapped row.
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final address = state.address;
    if (address is AddressHidden) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final List<AddressRow> rows;
    final int? resolvingIndex;
    final bool tappable;
    final Widget? note;
    switch (address) {
      case AddressHidden():
        return const SizedBox.shrink();
      case AddressLoading(:final previous):
        rows = previous;
        resolvingIndex = null;
        tappable = false;
        note = PanelNote(l.destinationAddressLoading, loading: true);
      case AddressResults(rows: final r, resolvingIndex: final i):
        rows = r;
        resolvingIndex = i;
        tappable = i == null;
        note = null;
      case AddressEmpty():
        rows = const [];
        resolvingIndex = null;
        tappable = false;
        note = PanelNote(l.destinationAddressEmpty);
      case AddressOffline():
        rows = const [];
        resolvingIndex = null;
        tappable = false;
        note = PanelNote(l.destinationAddressOffline);
      case AddressThrottled():
        rows = const [];
        resolvingIndex = null;
        tappable = false;
        note = PanelNote(l.destinationAddressThrottled);
      case AddressUnavailable():
        rows = const [];
        resolvingIndex = null;
        tappable = false;
        note = PanelNote(l.destinationAddressUnavailable);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
              l.destinationAddressHeader,
              style: context
                  .napStyle(NapTypography.caption)
                  .copyWith(color: c.textSecondary),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NapSpace.s16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: NapSpace.s8,
            children: [
              Icon(
                NapIcons.info,
                size: NapSizes.iconSmall,
                color: c.textSecondary,
              ),
              Expanded(
                child: Text(
                  l.destinationAddressDisclosure,
                  style: context.napText.bodySmall!.copyWith(
                    color: c.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final r in rows)
          ResultRow(
            key: ValueKey('address-${r.nativeIndex}'),
            icon: NapIcons.place,
            title: r.suggestion.title,
            subtitle: r.nativeIndex == resolvingIndex
                ? l.destinationAddressResolving
                : (r.suggestion.subtitle.isEmpty
                      ? l.destinationAddressRowFallback
                      : r.suggestion.subtitle),
            selected: isSelected(r.suggestion),
            busy: r.nativeIndex == resolvingIndex,
            onTap: tappable ? () => onSelect(r.nativeIndex) : null,
          ),
        ?note,
      ],
    );
  }
}
