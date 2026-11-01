import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Static sheet body inside a sheet container, and a real modal sheet.
final class SheetSection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  static Widget body(VoidCallback onDone) => NapSheetBody(
    leading: const NapIconTile(
      icon: NapIcons.batteryLow,
      tone: NapTone.danger,
      size: NapSizes.iconTileLarge,
    ),
    title: 'Pin còn 15%',
    subtitle: 'Còn khoảng 40 km tới nơi',
    primaryAction: NapButton(label: 'Áp dụng', onPressed: onDone),
    footnote: 'Có thể đổi trong Cài đặt',
    children: [
      NapOptionCard(
        title: 'Tiếp tục theo dõi',
        description: 'Báo thức vẫn chạy',
        selected: true,
        onTap: onDone,
      ),
      NapOptionCard(
        title: 'Tiết kiệm pin',
        description: 'Cập nhật vị trí thưa hơn',
        selected: false,
        onTap: onDone,
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Sheet container + body',
          children: [NapSheetContainer(child: body(noop))],
        ),
        CatalogGroup(
          title: 'Modal',
          children: [
            NapButton(
              label: 'Mở sheet',
              variant: NapButtonVariant.secondary,
              size: NapButtonSize.medium,
              onPressed: () => showNapSheet<void>(
                context: context,
                builder: (sheetContext) =>
                    body(() => Navigator.of(sheetContext).pop()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
