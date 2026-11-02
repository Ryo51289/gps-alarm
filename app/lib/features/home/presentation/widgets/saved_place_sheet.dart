import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/home/presentation/home_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

enum SavedPlaceSheetAction { change, remove }

/// Long-press sheet of a filled saved place tile: change or remove.
Future<SavedPlaceSheetAction?> showSavedPlaceSheet(
  BuildContext context,
  SavedPlace place,
) => showNapSheet<SavedPlaceSheetAction>(
  context: context,
  builder: (context) => _SavedPlaceSheet(place: place),
);

class _SavedPlaceSheet extends StatelessWidget {
  const new({required this.place});

  final SavedPlace place;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NapSheetBody(
      title: l.slotLabel(place.slot),
      subtitle: place.destination.name,
      children: [
        NapListGroup(
          children: [
            NapListRow(
              title: l.homeSlotSheetChange,
              leading: const NapIconTile(icon: NapIcons.place),
              onTap: () =>
                  Navigator.of(context).pop(SavedPlaceSheetAction.change),
            ),
            NapListRow(
              title: l.homeSlotSheetRemove,
              leading: const NapIconTile(
                icon: NapIcons.error,
                tone: NapTone.danger,
              ),
              onTap: () =>
                  Navigator.of(context).pop(SavedPlaceSheetAction.remove),
            ),
          ],
        ),
      ],
    );
  }
}
