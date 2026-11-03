import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/trip/domain/saved_place.dart';
import 'package:napstop/features/destination/presentation/destination_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// "Lưu vào" sheet of screen 2 (T23 §10): the three slots with what each
/// holds now. Returns the chosen slot, or null.
Future<SavedPlaceSlot?> showSavePlaceSheet(
  BuildContext context,
  Map<SavedPlaceSlot, SavedPlace> current,
) => showNapSheet<SavedPlaceSlot>(
  context: context,
  builder: (context) => SavePlaceSheet(current: current),
);

/// Icon of a saved place slot.
IconData _slotIcon(SavedPlaceSlot slot) => switch (slot) {
  SavedPlaceSlot.home => NapIcons.home,
  SavedPlaceSlot.hometown => NapIcons.place,
  SavedPlaceSlot.work => NapIcons.work,
};

class SavePlaceSheet extends StatelessWidget {
  const new({required this.current, super.key});

  final Map<SavedPlaceSlot, SavedPlace> current;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return NapSheetBody(
      title: l.destinationSaveSheetTitle,
      children: [
        for (final slot in SavedPlaceSlot.values)
          NapListRow(
            key: ValueKey('save-slot-${slot.name}'),
            leading: NapIconTile(icon: _slotIcon(slot)),
            title: l.savedSlotLabel(slot),
            subtitle: switch (current[slot]) {
              final SavedPlace p => l.destinationSaveSheetCurrent(
                p.destination.name,
              ),
              null => l.destinationSaveSheetEmpty,
            },
            onTap: () => Navigator.of(context).pop(slot),
          ),
      ],
    );
  }
}
