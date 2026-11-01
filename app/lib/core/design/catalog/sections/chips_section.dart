import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Chips (3 styles, compact, disabled) and badges (2 sizes x 5 tones).
final class ChipsSection extends StatefulWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  State<ChipsSection> createState() => _ChipsSectionState();
}

class _ChipsSectionState extends State<ChipsSection> {
  int _distance = 1;
  int _dismiss = 0;
  int _filter = 0;

  static const _distances = ['500 m', '1 km', '2 km', '5 km'];
  static const _dismissals = ['Vuốt hết thanh', 'Lắc máy', 'Giải phép tính'];
  static const _filters = ['Tất cả', 'Ga tàu', 'Bến xe'];

  @override
  Widget build(BuildContext context) {
    Widget row(
      NapChipStyle style,
      List<String> labels,
      int selected,
      ValueChanged<int> onSelect, {
      bool compact = false,
    }) => Wrap(
      spacing: NapSpace.s8,
      runSpacing: NapSpace.s4,
      children: [
        for (var i = 0; i < labels.length; i++)
          NapChip(
            label: labels[i],
            selected: i == selected,
            style: style,
            compact: compact,
            onTap: () => setState(() => onSelect(i)),
          ),
      ],
    );
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'choice',
          children: [
            row(
              NapChipStyle.choice,
              _distances,
              _distance,
              (i) => _distance = i,
            ),
          ],
        ),
        CatalogGroup(
          title: 'choicePill',
          children: [
            row(
              NapChipStyle.choicePill,
              _dismissals,
              _dismiss,
              (i) => _dismiss = i,
            ),
          ],
        ),
        CatalogGroup(
          title: 'filter, compact',
          children: [
            row(NapChipStyle.filter, _filters, _filter, (i) => _filter = i),
            row(
              NapChipStyle.filter,
              _filters,
              _filter,
              (i) => _filter = i,
              compact: true,
            ),
            if (widget.includeDisabled)
              const Wrap(
                spacing: NapSpace.s8,
                children: [
                  NapChip(label: '10 km', selected: false, onTap: null),
                  NapChip(label: '20 km', selected: true, onTap: null),
                ],
              ),
          ],
        ),
        CatalogGroup(
          title: 'Badges',
          children: [
            for (final size in NapBadgeSize.values)
              Wrap(
                spacing: NapSpace.s8,
                runSpacing: NapSpace.s8,
                children: [
                  for (final tone in NapTone.values)
                    NapBadge(label: _badgeLabel(tone), tone: tone, size: size),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static String _badgeLabel(NapTone tone) => switch (tone) {
    NapTone.neutral => 'Sẵn sàng',
    NapTone.accent => 'Báo trong vòng 1 km',
    NapTone.success => 'Tỉnh đúng lúc',
    NapTone.warning => 'Báo lại',
    NapTone.danger => 'Lỡ trạm',
  };
}
