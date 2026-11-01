import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// 6 variants x 4 sizes, icon, pill, disabled; icon buttons.
final class ButtonsSection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  static const Map<NapButtonVariant, String> _labels = {
    NapButtonVariant.primary: 'Bắt đầu theo dõi',
    NapButtonVariant.secondary: 'Mở Cài đặt của máy',
    NapButtonVariant.tonal: 'Nghe thử báo thức',
    NapButtonVariant.danger: 'Dừng theo dõi',
    NapButtonVariant.text: 'Tắt báo thức',
    NapButtonVariant.link: 'Đổi',
  };

  @override
  Widget build(BuildContext context) {
    void noop() {}
    return CatalogSectionBody(
      children: [
        for (final MapEntry(key: variant, value: label) in _labels.entries)
          CatalogGroup(
            title: variant.name,
            children: [
              NapButton(label: label, onPressed: noop, variant: variant),
              NapButton(
                label: label,
                onPressed: noop,
                variant: variant,
                size: NapButtonSize.medium,
              ),
              Wrap(
                spacing: NapSpace.s8,
                runSpacing: NapSpace.s4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  NapButton(
                    label: label,
                    onPressed: noop,
                    variant: variant,
                    size: NapButtonSize.small,
                  ),
                  NapButton(
                    label: 'Nghe thử',
                    onPressed: noop,
                    variant: variant,
                    size: NapButtonSize.compact,
                  ),
                ],
              ),
            ],
          ),
        CatalogGroup(
          title: 'Icon, pill, disabled',
          children: [
            NapButton(
              label: 'Nghe thử báo thức',
              icon: NapIcons.headphones,
              onPressed: noop,
              variant: NapButtonVariant.tonal,
            ),
            NapButton(
              label: 'Báo lại sau 1 phút',
              icon: NapIcons.snooze,
              onPressed: noop,
              variant: NapButtonVariant.secondary,
              pill: true,
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: NapButton(
                label: 'Nghe thử',
                icon: NapIcons.play,
                onPressed: noop,
                variant: NapButtonVariant.secondary,
                size: NapButtonSize.compact,
              ),
            ),
            if (includeDisabled) ...[
              const NapButton(label: 'Bắt đầu theo dõi', onPressed: null),
              const NapButton(
                label: 'Mở Cài đặt của máy',
                onPressed: null,
                variant: NapButtonVariant.secondary,
                size: NapButtonSize.medium,
              ),
            ],
          ],
        ),
        CatalogGroup(
          title: 'Icon buttons',
          children: [
            Wrap(
              spacing: NapSpace.s12,
              runSpacing: NapSpace.s12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                NapIconButton(
                  icon: NapIcons.back,
                  semanticLabel: 'Quay lại',
                  onPressed: noop,
                  variant: NapIconButtonVariant.plain,
                ),
                NapIconButton(
                  icon: NapIcons.settings,
                  semanticLabel: 'Cài đặt',
                  onPressed: noop,
                ),
                NapIconButton(
                  icon: NapIcons.gps,
                  semanticLabel: 'Vị trí của tôi',
                  onPressed: noop,
                  variant: NapIconButtonVariant.floating,
                  size: 48,
                ),
                NapIconButton(
                  icon: NapIcons.bookmark,
                  semanticLabel: 'Lưu điểm',
                  onPressed: noop,
                  variant: NapIconButtonVariant.floating,
                  size: NapSizes.iconTileLarge,
                  square: true,
                ),
                if (includeDisabled)
                  const NapIconButton(
                    icon: NapIcons.redo,
                    semanticLabel: 'Đặt lại',
                    onPressed: null,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
