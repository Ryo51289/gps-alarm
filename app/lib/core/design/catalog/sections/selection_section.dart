import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Switch rows, option cards (row and tile), radio rows.
final class SelectionSection extends StatefulWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  State<SelectionSection> createState() => _SelectionSectionState();
}

class _SelectionSectionState extends State<SelectionSection> {
  bool _vibrate = true;
  bool _quiet = false;
  int _battery = 0;
  int _style = 0;
  String _language = 'vi';

  @override
  Widget build(BuildContext context) {
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Switch rows',
          children: [
            NapListGroup(
              children: [
                NapSwitchRow(
                  title: 'Rung khi báo',
                  subtitle: 'Rung mạnh kèm âm thanh',
                  value: _vibrate,
                  onChanged: (v) => setState(() => _vibrate = v),
                ),
                NapSwitchRow(
                  title: 'Báo cả khi máy im lặng',
                  value: _quiet,
                  titleWeight: NapRowTitle.regular,
                  onChanged: (v) => setState(() => _quiet = v),
                ),
                if (widget.includeDisabled)
                  const NapSwitchRow(
                    title: 'Đèn flash',
                    subtitle: 'Máy không hỗ trợ',
                    value: false,
                    onChanged: null,
                  ),
              ],
            ),
          ],
        ),
        CatalogGroup(
          title: 'Option cards: row',
          children: [
            for (final (i, title, description) in const [
              (0, 'Tiếp tục theo dõi', 'Báo thức vẫn chạy khi pin yếu'),
              (1, 'Tiết kiệm pin', 'Giảm tần suất cập nhật vị trí'),
            ])
              NapOptionCard(
                title: title,
                description: description,
                selected: _battery == i,
                onTap: () => setState(() => _battery = i),
              ),
          ],
        ),
        CatalogGroup(
          title: 'Option cards: tile',
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: NapSpace.s8,
                children: [
                  for (final (i, title, icon) in const [
                    (0, 'Âm thanh', NapIcons.alarm),
                    (1, 'Rung', NapIcons.vibrate),
                    (2, 'Tai nghe', NapIcons.headphones),
                  ])
                    Expanded(
                      child: NapOptionCard(
                        title: title,
                        icon: icon,
                        layout: NapOptionLayout.tile,
                        selected: _style == i,
                        onTap: () => setState(() => _style = i),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        CatalogGroup(
          title: 'Radio rows',
          children: [
            NapListGroup(
              children: [
                for (final (code, name) in const [
                  ('vi', 'Tiếng Việt'),
                  ('en', 'English'),
                ])
                  NapListRow(
                    title: name,
                    titleWeight: NapRowTitle.regular,
                    semanticsChecked: _language == code,
                    trailing: NapRadioIndicator(selected: _language == code),
                    onTap: () => setState(() => _language = code),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
