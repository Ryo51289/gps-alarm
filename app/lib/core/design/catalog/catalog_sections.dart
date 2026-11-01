import 'package:flutter/widgets.dart';
import 'package:napstop/core/design/catalog/sections/buttons_section.dart';
import 'package:napstop/core/design/catalog/sections/cards_section.dart';
import 'package:napstop/core/design/catalog/sections/chips_section.dart';
import 'package:napstop/core/design/catalog/sections/colors_section.dart';
import 'package:napstop/core/design/catalog/sections/inputs_section.dart';
import 'package:napstop/core/design/catalog/sections/metrics_section.dart';
import 'package:napstop/core/design/catalog/sections/segmented_section.dart';
import 'package:napstop/core/design/catalog/sections/selection_section.dart';
import 'package:napstop/core/design/catalog/sections/sheet_section.dart';
import 'package:napstop/core/design/catalog/sections/status_section.dart';
import 'package:napstop/core/design/catalog/sections/typography_section.dart';

/// One page of the catalog.
final class CatalogSection {
  const new({required this.id, required this.title, required this.builder});

  /// File-name friendly id (golden file names).
  final String id;
  final String title;

  /// Builds the section; `includeDisabled: false` drops disabled samples
  /// (their text is exempt from the contrast checks).
  final Widget Function({required bool includeDisabled}) builder;
}

/// The 11 sections, in display order.
final List<CatalogSection> kCatalogSections = [
  CatalogSection(
    id: 'colors',
    title: 'Colors',
    builder: ({required includeDisabled}) =>
        ColorsSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'typography',
    title: 'Typography',
    builder: ({required includeDisabled}) =>
        TypographySection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'metrics',
    title: 'Spacing, radii, shadows',
    builder: ({required includeDisabled}) =>
        MetricsSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'buttons',
    title: 'Buttons',
    builder: ({required includeDisabled}) =>
        ButtonsSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'chips',
    title: 'Chips and badges',
    builder: ({required includeDisabled}) =>
        ChipsSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'segmented',
    title: 'Segmented control',
    builder: ({required includeDisabled}) =>
        SegmentedSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'selection',
    title: 'Switch, option, radio',
    builder: ({required includeDisabled}) =>
        SelectionSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'cards',
    title: 'Cards and lists',
    builder: ({required includeDisabled}) =>
        CardsSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'status',
    title: 'Status and banners',
    builder: ({required includeDisabled}) =>
        StatusSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'sheet',
    title: 'Bottom sheet',
    builder: ({required includeDisabled}) =>
        SheetSection(includeDisabled: includeDisabled),
  ),
  CatalogSection(
    id: 'inputs',
    title: 'Slider, big value, search',
    builder: ({required includeDisabled}) =>
        InputsSection(includeDisabled: includeDisabled),
  ),
];
