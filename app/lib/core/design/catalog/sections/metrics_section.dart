import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_group.dart';
import 'package:napstop/core/design/design.dart';

/// Spacing scale, corner radii and shadows.
final class MetricsSection extends StatelessWidget {
  const new({this.includeDisabled = true, super.key});

  final bool includeDisabled;

  static const Map<String, double> _space = {
    's2': NapSpace.s2,
    's4': NapSpace.s4,
    's6': NapSpace.s6,
    's8': NapSpace.s8,
    's10': NapSpace.s10,
    's12': NapSpace.s12,
    's14': NapSpace.s14,
    's16': NapSpace.s16,
    's18': NapSpace.s18,
    's20': NapSpace.s20,
    's24': NapSpace.s24,
    's28': NapSpace.s28,
    's32': NapSpace.s32,
    's40': NapSpace.s40,
  };

  static const Map<String, double> _radii = {
    'r4': NapRadii.r4,
    'r6': NapRadii.r6,
    'r8': NapRadii.r8,
    'r10': NapRadii.r10,
    'r12': NapRadii.r12,
    'r14': NapRadii.r14,
    'r16': NapRadii.r16,
    'r20': NapRadii.r20,
    'r24': NapRadii.r24,
    'pill': NapRadii.pill,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final shadows = context.napShadows;
    final text = context.napText;
    Widget shadowBox(String name, List<BoxShadow> list) => Column(
      spacing: NapSpace.s8,
      children: [
        Container(
          width: 88,
          height: 48,
          decoration: BoxDecoration(
            color: c.surfaceFloating,
            borderRadius: BorderRadius.circular(NapRadii.r12),
            boxShadow: list,
            border: shadows.borderInsteadOfShadow
                ? Border.all(color: c.border)
                : null,
          ),
        ),
        CatalogCaption(name),
      ],
    );
    return CatalogSectionBody(
      children: [
        CatalogGroup(
          title: 'Spacing',
          children: [
            for (final MapEntry(key: name, value: v) in _space.entries)
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: Text(name, style: text.labelSmall),
                  ),
                  Container(width: v, height: 12, color: c.accent),
                ],
              ),
          ],
        ),
        CatalogGroup(
          title: 'Radii',
          children: [
            Wrap(
              spacing: NapSpace.s12,
              runSpacing: NapSpace.s12,
              children: [
                for (final MapEntry(key: name, value: r) in _radii.entries)
                  Column(
                    spacing: NapSpace.s4,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: c.fill,
                          border: Border.all(color: c.outline),
                          borderRadius: BorderRadius.circular(r),
                        ),
                      ),
                      CatalogCaption(name),
                    ],
                  ),
              ],
            ),
          ],
        ),
        CatalogGroup(
          title: 'Shadows',
          children: [
            Wrap(
              spacing: NapSpace.s20,
              runSpacing: NapSpace.s20,
              children: [
                shadowBox('floating', shadows.floating),
                shadowBox('thumb', shadows.thumb),
                shadowBox('sheet', shadows.sheet),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
