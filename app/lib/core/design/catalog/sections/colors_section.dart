import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Every color token plus the contrast pairs of the current theme.
final class ColorsSection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final kind = c == NapColors.alarm
        ? NapThemeKind.alarm
        : (c == NapColors.dark ? NapThemeKind.dark : NapThemeKind.light);
    final pairs = napContrastPairs(c, kind);
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Tokens',
          children: [
            for (final MapEntry(key: name, value: color) in c.tokens.entries)
              Row(
                spacing: NapSpace.s12,
                children: [
                  Container(
                    width: 40,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(NapRadii.r6),
                      border: Border.all(color: c.outline),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: text.labelMedium),
                        CatalogCaption(_hex(color)),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
        CatalogGroup(
          title: 'Contrast',
          children: [
            for (final p in pairs)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: text.bodySmall),
                  Text(
                    '${p.ratio.toStringAsFixed(2)} '
                    '(min ${p.minRatio.toStringAsFixed(1)}) '
                    '${p.passes ? 'PASS' : 'FAIL'}',
                    style: text.labelSmall!.copyWith(
                      color: p.passes ? c.textPrimary : c.danger,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  static String _hex(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }
}
