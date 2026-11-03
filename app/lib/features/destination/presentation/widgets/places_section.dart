import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/data/places/places_models.dart';
import 'package:napstop/features/destination/presentation/destination_controller.dart';
import 'package:napstop/features/destination/presentation/widgets/google_maps_attribution.dart';
import 'package:napstop/features/destination/presentation/widgets/result_row.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Address search of chip "Địa chỉ" (T23 §9): disclosure, then the state of
/// the Places request, then "Google Maps" under the suggestions.
class PlacesSection extends StatelessWidget {
  const new({required this.places, required this.onSelect, super.key});

  final PlacesUiState places;
  final ValueChanged<PlacePrediction> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Widget banner(String message, NapTone tone) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NapSpace.s16,
        vertical: NapSpace.s8,
      ),
      child: NapBanner(message: message, tone: tone, announce: true),
    );
    final places = this.places;
    final body = <Widget>[
      ...switch (places) {
        PlacesUiNotConfigured() => [
          banner(l.destinationPlacesNotConfigured, NapTone.neutral),
        ],
        PlacesUiTypeMore() => [PanelNote(l.destinationPlacesTypeMore)],
        PlacesUiLoading() => [
          PanelNote(l.destinationPlacesLoading, loading: true),
        ],
        PlacesUiEmpty() => [PanelNote(l.destinationPlacesEmpty)],
        PlacesUiOffline() => [
          banner(l.destinationPlacesOffline, NapTone.warning),
        ],
        PlacesUiUnavailable() => [
          banner(l.destinationPlacesUnavailable, NapTone.warning),
        ],
        PlacesUiResults(:final predictions, :final resolvingId) => [
          for (final p in predictions)
            ResultRow(
              key: ValueKey('place-${p.placeId}'),
              icon: NapIcons.place,
              title: p.mainText,
              subtitle: p.secondaryText,
              busy: resolvingId == p.placeId,
              onTap: resolvingId == null ? () => onSelect(p) : null,
            ),
          const GoogleMapsAttribution(),
        ],
      },
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PanelNote(l.destinationPlacesDisclosure, icon: NapIcons.info),
        ...body,
      ],
    );
  }
}
