import 'package:flutter/material.dart';
import 'package:napstop/core/design/catalog/catalog_sections.dart';
import 'package:napstop/core/design/design.dart';

/// Text scale choice of the catalog; null follows the system setting.
typedef CatalogTextScale = double?;

/// Catalog start page: theme / text scale / language switches and the list
/// of sections.
final class CatalogHome extends StatelessWidget {
  const new({
    required this.kind,
    required this.textScale,
    required this.locale,
    required this.onKind,
    required this.onTextScale,
    required this.onLocale,
    super.key,
  });

  final NapThemeKind kind;
  final CatalogTextScale textScale;
  final Locale locale;
  final ValueChanged<NapThemeKind> onKind;
  final ValueChanged<CatalogTextScale> onTextScale;
  final ValueChanged<Locale> onLocale;

  static const String title = 'NapStop design catalog';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(NapSpace.page),
          children: [
            const NapScreenHeader(title: title),
            const SizedBox(height: NapSpace.s16),
            const NapSectionHeader('Theme'),
            const SizedBox(height: NapSpace.s8),
            NapSegmentedControl<NapThemeKind>(
              segments: [
                for (final k in NapThemeKind.values)
                  NapSegment(value: k, label: k.name),
              ],
              selected: kind,
              size: NapSegmentedSize.compact,
              semanticLabel: 'Theme',
              onChanged: onKind,
            ),
            const SizedBox(height: NapSpace.s16),
            const NapSectionHeader('Text scale'),
            const SizedBox(height: NapSpace.s8),
            NapSegmentedControl<CatalogTextScale>(
              segments: const [
                NapSegment(value: null, label: 'System'),
                NapSegment(value: 1, label: '1.0'),
                NapSegment(value: 1.3, label: '1.3'),
                NapSegment(value: 2, label: '2.0'),
              ],
              selected: textScale,
              size: NapSegmentedSize.compact,
              semanticLabel: 'Text scale',
              onChanged: onTextScale,
            ),
            const SizedBox(height: NapSpace.s16),
            const NapSectionHeader('Language'),
            const SizedBox(height: NapSpace.s8),
            NapSegmentedControl<String>(
              segments: const [
                NapSegment(value: 'vi', label: 'vi'),
                NapSegment(value: 'en', label: 'en'),
              ],
              selected: locale.languageCode,
              size: NapSegmentedSize.compact,
              semanticLabel: 'Language',
              onChanged: (code) => onLocale(Locale(code)),
            ),
            const SizedBox(height: NapSpace.section),
            NapListGroup(
              children: [
                for (final section in kCatalogSections)
                  NapListRow(
                    title: section.title,
                    chevron: true,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CatalogSectionPage(section: section),
                      ),
                    ),
                  ),
                NapListRow(
                  title: 'Licenses',
                  chevron: true,
                  onTap: () =>
                      showLicensePage(context: context, applicationName: title),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One section on its own page, with a back button.
final class CatalogSectionPage extends StatelessWidget {
  const new({required this.section, super.key});

  final CatalogSection section;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                NapSpace.page,
                NapSpace.s8,
                NapSpace.page,
                0,
              ),
              child: NapScreenHeader(
                title: section.title,
                onBack: () => Navigator.of(context).pop(),
              ),
            ),
            section.builder(includeDisabled: true),
          ],
        ),
      ),
    );
  }
}
