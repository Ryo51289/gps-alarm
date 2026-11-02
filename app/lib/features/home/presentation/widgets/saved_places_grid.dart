import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/home/presentation/widgets/saved_place_tile.dart';

/// The three saved place tiles in one row, all the same height.
class SavedPlacesGrid extends StatelessWidget {
  const new({
    required this.places,
    required this.onTap,
    required this.onLongPress,
    this.locked = false,
    this.loading = false,
    super.key,
  });

  final Map<SavedPlaceSlot, SavedPlace> places;
  final void Function(SavedPlaceSlot slot, SavedPlace? place) onTap;
  final void Function(SavedPlace place) onLongPress;

  /// Database error: tiles shown empty and disabled.
  final bool locked;

  /// Saved places not read yet: placeholder tiles, not tappable.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: NapSpace.s10,
        children: [
          for (final slot in SavedPlaceSlot.values)
            Expanded(child: _tile(slot, locked ? null : places[slot])),
        ],
      ),
    );
  }

  Widget _tile(SavedPlaceSlot slot, SavedPlace? place) => SavedPlaceTile(
    slot: slot,
    place: place,
    onTap: locked || loading ? null : () => onTap(slot, place),
    onLongPress: place == null ? null : () => onLongPress(place),
    loading: loading,
  );
}
