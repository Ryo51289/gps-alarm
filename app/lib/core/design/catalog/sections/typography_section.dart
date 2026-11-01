import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// The 22 text styles with a sample full of stacked diacritics.
final class TypographySection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  static const String sample = 'Ấp Đồng Hới, Quảng Trị — ỗ ặ ữ ỹ Ẵ Ổ';

  @override
  Widget build(BuildContext context) {
    final t = context.napText;
    final m3 = <String, TextStyle?>{
      'displayLarge': t.displayLarge,
      'displayMedium': t.displayMedium,
      'displaySmall': t.displaySmall,
      'headlineLarge': t.headlineLarge,
      'headlineMedium': t.headlineMedium,
      'headlineSmall': t.headlineSmall,
      'titleLarge': t.titleLarge,
      'titleMedium': t.titleMedium,
      'titleSmall': t.titleSmall,
      'bodyLarge': t.bodyLarge,
      'bodyMedium': t.bodyMedium,
      'bodySmall': t.bodySmall,
      'labelLarge': t.labelLarge,
      'labelMedium': t.labelMedium,
      'labelSmall': t.labelSmall,
    };
    Widget entry(String name, TextStyle style, {bool upper = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: NapSpace.s4,
      children: [
        CatalogCaption(
          '$name  ${style.fontSize!.toStringAsFixed(0)} / '
          '${style.height} / w${style.fontWeight!.value}',
        ),
        Text(upper ? sample.toUpperCase() : sample, style: style),
      ],
    );
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Material 3 slots',
          children: [
            for (final MapEntry(key: name, value: style) in m3.entries)
              entry(name, style!),
          ],
        ),
        CatalogGroup(
          title: 'Additional styles',
          children: [
            for (final MapEntry(key: name, value: style)
                in NapTypography.extras.entries)
              entry(
                name,
                context.napStyle(style),
                upper: name == 'overline' || name == 'alarmOverline',
              ),
          ],
        ),
      ],
    );
  }
}
