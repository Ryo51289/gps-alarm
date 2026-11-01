import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Cards, list group and rows, icon tiles, section and screen headers.
final class CardsSection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    void noop() {}
    Widget cardText(String title, String body) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: NapSpace.s4,
      children: [
        Text(title, style: text.titleSmall),
        Text(body, style: text.bodySmall!.copyWith(color: c.textSecondary)),
      ],
    );
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Screen header',
          children: [
            NapScreenHeader(
              title: 'Cài đặt chung',
              onBack: noop,
              trailing: NapIconButton(
                icon: NapIcons.settings,
                semanticLabel: 'Cài đặt',
                onPressed: noop,
              ),
            ),
            const NapScreenHeader(title: 'Lịch sử chuyến đi'),
          ],
        ),
        CatalogGroup(
          title: 'Cards',
          children: [
            NapCard(child: cardText('outlined', 'Nền surface, viền border')),
            NapCard(
              variant: NapCardVariant.filled,
              child: cardText('filled', 'Nền fill'),
            ),
            NapCard(
              variant: NapCardVariant.accent,
              child: cardText('Sẵn sàng', 'Đã đủ quyền để theo dõi'),
            ),
            NapCard(
              variant: NapCardVariant.warning,
              child: Row(
                spacing: NapSpace.s12,
                children: [
                  const NapIconTile(
                    icon: NapIcons.batteryLow,
                    tone: NapTone.warning,
                    onFill: true,
                  ),
                  Expanded(
                    child: cardText(
                      'Tối ưu pin đang bật',
                      'Máy có thể dừng app khi đang ngủ',
                    ),
                  ),
                ],
              ),
            ),
            NapCard(
              onTap: noop,
              radius: NapRadii.r16,
              semanticLabel: 'Chuyến gần nhất',
              child: cardText('Chuyến gần nhất', 'Hà Nội - Đồng Hới'),
            ),
          ],
        ),
        CatalogGroup(
          title: 'List group',
          children: [
            NapListGroup(
              children: [
                NapListRow(
                  title: 'Ga Đồng Hới',
                  subtitle: 'Quảng Bình',
                  leading: const NapIconTile(icon: NapIcons.train),
                  chevron: true,
                  onTap: noop,
                ),
                NapListRow(
                  title: 'Bến xe Mỹ Đình',
                  subtitle: 'Hà Nội',
                  leading: const NapIconTile(
                    icon: NapIcons.coach,
                    tone: NapTone.accent,
                  ),
                  selected: true,
                  onTap: noop,
                ),
                NapListRow(
                  title: 'Âm báo',
                  titleWeight: NapRowTitle.regular,
                  trailing: Text(
                    'Chuông 1',
                    style: context
                        .napStyle(NapTypography.body14)
                        .copyWith(color: c.textSecondary),
                  ),
                  chevron: true,
                  onTap: noop,
                ),
                const NapListRow(
                  title: 'Chuyến 12/10',
                  trailing: NapBadge(
                    label: 'Tỉnh đúng lúc',
                    tone: NapTone.success,
                  ),
                ),
              ],
            ),
          ],
        ),
        CatalogGroup(
          title: 'Icon tiles',
          children: [
            Wrap(
              spacing: NapSpace.s8,
              runSpacing: NapSpace.s8,
              children: [
                for (final tone in NapTone.values)
                  NapIconTile(icon: NapIcons.place, tone: tone),
                const NapIconTile(
                  icon: NapIcons.batteryLow,
                  tone: NapTone.danger,
                  size: NapSizes.iconTileLarge,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
