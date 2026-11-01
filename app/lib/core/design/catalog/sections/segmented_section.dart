import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Segmented controls: regular 3, compact 2 and 3, disabled.
final class SegmentedSection extends StatefulWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  State<SegmentedSection> createState() => _SegmentedSectionState();
}

class _SegmentedSectionState extends State<SegmentedSection> {
  int _mode = 0;
  int _unit = 0;
  int _theme = 2;

  static const List<NapSegment<int>> _modes = [
    NapSegment(value: 0, label: 'Khoảng cách'),
    NapSegment(value: 1, label: 'Thời gian'),
    NapSegment(value: 2, label: 'Thông minh'),
  ];
  static const List<NapSegment<int>> _units = [
    NapSegment(value: 0, label: 'km'),
    NapSegment(value: 1, label: 'mi'),
  ];
  static const List<NapSegment<int>> _themes = [
    NapSegment(value: 0, label: 'Sáng'),
    NapSegment(value: 1, label: 'Tối'),
    NapSegment(value: 2, label: 'Theo máy'),
  ];

  @override
  Widget build(BuildContext context) {
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'regular',
          children: [
            NapSegmentedControl<int>(
              segments: _modes,
              selected: _mode,
              semanticLabel: 'Báo khi',
              onChanged: (v) => setState(() => _mode = v),
            ),
          ],
        ),
        CatalogGroup(
          title: 'compact',
          children: [
            NapSegmentedControl<int>(
              segments: _units,
              selected: _unit,
              size: NapSegmentedSize.compact,
              onChanged: (v) => setState(() => _unit = v),
            ),
            NapSegmentedControl<int>(
              segments: _themes,
              selected: _theme,
              size: NapSegmentedSize.compact,
              onChanged: (v) => setState(() => _theme = v),
            ),
            if (widget.includeDisabled)
              NapSegmentedControl<int>(
                segments: _themes,
                selected: 0,
                size: NapSegmentedSize.compact,
                onChanged: null,
              ),
          ],
        ),
      ],
    );
  }
}
