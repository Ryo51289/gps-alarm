import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Status tiles (3 tones) and banners (4 tones, title, action).
final class StatusSection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return CatalogSectionBody(
      children: [
        const CatalogGroup(
          title: 'Status tiles',
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: NapSpace.s8,
                children: [
                  Expanded(
                    child: NapStatusTile(
                      icon: NapIcons.gps,
                      title: 'GPS tốt',
                      subtitle: '±8 m',
                      tone: NapTone.success,
                    ),
                  ),
                  Expanded(
                    child: NapStatusTile(
                      icon: NapIcons.battery,
                      title: 'Pin 64%',
                      subtitle: 'Đủ tới nơi',
                    ),
                  ),
                  Expanded(
                    child: NapStatusTile(
                      icon: NapIcons.gpsOff,
                      title: 'Đang ước tính',
                      subtitle: 'Mất GPS 2 phút',
                      tone: NapTone.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        CatalogGroup(
          title: 'Banners',
          children: [
            const NapBanner(
              message: 'Qua hầm có thể mất GPS một lúc, app vẫn ước tính.',
            ),
            NapBanner(
              tone: NapTone.warning,
              title: 'Khoảng cách quá gần',
              message: 'Xe chạy nhanh có thể tới nơi trước khi kịp báo.',
              action: NapButton(
                label: 'Tăng lên 2 km',
                onPressed: noop,
                variant: NapButtonVariant.secondary,
                size: NapButtonSize.small,
              ),
            ),
            const NapBanner(
              tone: NapTone.danger,
              message: 'Chưa có quyền vị trí. App không thể báo thức.',
            ),
            const NapBanner(
              tone: NapTone.success,
              title: 'Đã bật',
              message: 'Báo thức sẽ kêu cả khi máy im lặng.',
            ),
          ],
        ),
      ],
    );
  }
}
