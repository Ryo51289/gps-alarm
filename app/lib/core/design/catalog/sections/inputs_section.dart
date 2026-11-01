import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Labeled slider, big values, search fields.
final class InputsSection extends StatefulWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  State<InputsSection> createState() => _InputsSectionState();
}

class _InputsSectionState extends State<InputsSection> {
  double _distance = 1500;

  static String _km(double m) =>
      m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Labeled slider',
          children: [
            NapBigValue(
              value: _km(_distance),
              leading: 'Còn cách',
              size: NapBigValueSize.l,
              alignment: WrapAlignment.center,
            ),
            NapLabeledSlider(
              value: _distance,
              min: 200,
              max: 10000,
              divisions: 98,
              semanticLabel: 'Khoảng cách báo',
              semanticFormatter: _km,
              minLabel: '200 m',
              maxLabel: '10 km',
              onChanged: (v) => setState(() => _distance = v),
            ),
          ],
        ),
        const CatalogGroup(
          title: 'Big value',
          children: [
            NapBigValue(value: '152 km', trailing: '~2 giờ 10 phút'),
            NapBigValue(
              value: '~148 km',
              trailing: 'Đang ước tính',
              estimated: true,
            ),
          ],
        ),
        CatalogGroup(
          title: 'Search fields',
          children: [
            NapSearchField(
              hint: 'Bạn muốn đến đâu?',
              readOnly: true,
              onTap: noop,
            ),
            const NapSearchField(
              hint: 'Tìm ga, bến xe',
              variant: NapSearchFieldVariant.floating,
            ),
          ],
        ),
      ],
    );
  }
}
