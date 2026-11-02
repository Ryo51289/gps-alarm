import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Minimum height of a saved place tile.
const double kSavedPlaceTileMinHeight = 88;

/// One of the three saved place tiles (T22 §9.2). [place] null: empty tile
/// ("Thêm"). [onTap] null: locked (database error). [loading]: the saved
/// places are not read yet; a placeholder bar instead of "Thêm", never
/// tappable (a tap must not overwrite a place that is not shown yet).
class SavedPlaceTile extends StatelessWidget {
  const new({
    required this.slot,
    required this.place,
    required this.onTap,
    this.onLongPress,
    this.loading = false,
    super.key,
  });

  final SavedPlaceSlot slot;
  final SavedPlace? place;
  final VoidCallback? onTap;

  /// Only for a filled tile: opens the change/remove sheet.
  final VoidCallback? onLongPress;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    final place = this.place;
    final label = l.slotLabel(slot);
    final icon = place == null && !loading
        ? NapIcons.add
        : switch (slot) {
            SavedPlaceSlot.home => NapIcons.home,
            SavedPlaceSlot.hometown => NapIcons.place,
            SavedPlaceSlot.work => NapIcons.work,
          };
    final onTap = loading ? null : this.onTap;
    final onLongPress = place == null || loading ? null : this.onLongPress;
    final subtitleStyle = context
        .napStyle(NapTypography.caption)
        .copyWith(color: c.textSecondary);
    final Widget subtitle = loading
        ? _LoadingBar(color: c.fill)
        : Text(
            place?.destination.name ?? l.homeSlotAdd,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: subtitleStyle,
          );
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      label: loading
          ? label
          : place == null
          ? l.homeSlotAddSemantics(label)
          : '$label, ${place.destination.name}',
      onTap: onTap,
      onLongPress: onLongPress,
      onLongPressHint: onLongPress == null ? null : l.homeSlotEditHint,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: NapCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(
            horizontal: NapSpace.s14,
            vertical: NapSpace.s12,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: kSavedPlaceTileMinHeight - 2 * NapSpace.s12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: NapSpace.s8,
              children: [
                Icon(
                  icon,
                  size: NapSizes.iconLarge,
                  color: place == null ? c.textSecondary : c.accent,
                ),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.napText.titleSmall,
                ),
                subtitle,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stand-in for the second line while the saved places load.
class _LoadingBar extends StatelessWidget {
  const new({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: NapSpace.s12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(NapRadii.r4),
      ),
    );
  }
}
