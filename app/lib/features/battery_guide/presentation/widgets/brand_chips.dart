import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/battery_guide/domain/battery_guide.dart';
import 'package:napstop/features/battery_guide/presentation/battery_guide_strings.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Brand chips of screen 9 (T21 §8.1).
class BrandChips extends StatelessWidget {
  const new({
    required this.catalog,
    required this.ids,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  final BatteryGuideCatalog catalog;
  final List<String> ids;
  final String selectedId;

  /// Null locks the chips (check running).
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final onSelect = this.onSelect;
    return Wrap(
      spacing: NapSpace.s8,
      runSpacing: NapSpace.s8,
      children: [
        for (final id in ids)
          NapChip(
            key: ValueKey('brand-$id'),
            label: _label(l, id),
            selected: id == selectedId,
            style: NapChipStyle.filter,
            compact: true,
            onTap: onSelect == null ? null : () => onSelect(id),
          ),
      ],
    );
  }

  String _label(AppLocalizations l, String id) {
    final key = catalog.byId(id)?.labelKey;
    return key == null ? l.bgBrandOther : batteryGuideText(l, key) ?? id;
  }
}
