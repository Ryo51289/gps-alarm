// TC07: ThemeData of the 3 themes. TC09: caching. TC23 (part): NapMotion.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:napstop/core/design/design.dart';

typedef _Style = (double size, double height, FontWeight weight, double ls);

const Map<String, _Style> _scale = {
  'displayLarge': (52, 1.10, FontWeight.w700, 0),
  'displayMedium': (44, 1.10, FontWeight.w700, 0),
  'displaySmall': (40, 1.15, FontWeight.w700, 0),
  'headlineLarge': (30, 1.25, FontWeight.w700, 0),
  'headlineMedium': (26, 1.30, FontWeight.w700, 0),
  'headlineSmall': (22, 1.30, FontWeight.w700, 0),
  'titleLarge': (20, 1.30, FontWeight.w700, 0),
  'titleMedium': (17, 1.35, FontWeight.w600, 0),
  'titleSmall': (15, 1.40, FontWeight.w600, 0),
  'bodyLarge': (16, 1.50, FontWeight.w400, 0),
  'bodyMedium': (15, 1.50, FontWeight.w400, 0),
  'bodySmall': (13, 1.45, FontWeight.w400, 0),
  'labelLarge': (16, 1.25, FontWeight.w600, 0),
  'labelMedium': (14, 1.30, FontWeight.w600, 0),
  'labelSmall': (13, 1.35, FontWeight.w600, 0),
};

const Map<String, _Style> _extras = {
  'body14': (14, 1.50, FontWeight.w400, 0),
  'caption': (12, 1.40, FontWeight.w400, 0),
  'captionStrong': (12, 1.35, FontWeight.w600, 0),
  'overline': (13, 1.30, FontWeight.w600, 0.52),
  'alarmOverline': (14, 1.30, FontWeight.w700, 1.68),
  'etaSecondary': (18, 1.30, FontWeight.w400, 0),
  'mapLabel': (11, 1.30, FontWeight.w600, 0),
};

Map<String, TextStyle?> _slots(TextTheme t) => {
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

void _expectStyle(TextStyle s, _Style e, String name) {
  final (size, height, weight, ls) = e;
  expect(s.fontSize, size, reason: name);
  expect(s.height, height, reason: name);
  expect(s.fontWeight, weight, reason: name);
  expect(s.letterSpacing, ls, reason: name);
  expect(s.leadingDistribution, TextLeadingDistribution.even, reason: name);
}

void main() {
  for (final kind in NapThemeKind.values) {
    test('TC07 ThemeData of ${kind.name}', () {
      final theme = NapThemes.of(kind);
      final c = NapThemes.colorsOf(kind);
      expect(
        theme.brightness,
        kind == NapThemeKind.light ? Brightness.light : Brightness.dark,
      );
      expect(theme.useMaterial3, isTrue);
      expect(theme.materialTapTargetSize, MaterialTapTargetSize.padded);
      expect(theme.visualDensity, VisualDensity.standard);
      expect(theme.scaffoldBackgroundColor, c.background);
      expect(theme.canvasColor, c.background);
      expect(theme.extension<NapColors>(), c);
      expect(
        theme.extension<NapShadows>(),
        kind == NapThemeKind.light ? NapShadows.light : NapShadows.dark,
      );

      for (final MapEntry(key: name, value: style) in _slots(
        theme.textTheme,
      ).entries) {
        expect(style!.fontFamily, kNapFontFamily, reason: name);
        expect(style.color, c.textPrimary, reason: name);
        _expectStyle(style, _scale[name]!, name);
      }

      final s = theme.colorScheme;
      final expected = <String, (Color, Color)>{
        'primary': (s.primary, c.accent),
        'onPrimary': (s.onPrimary, c.onAccent),
        'primaryContainer': (s.primaryContainer, c.accentContainer),
        'onPrimaryContainer': (s.onPrimaryContainer, c.onAccentContainer),
        'secondary': (s.secondary, c.inverseSurface),
        'onSecondary': (s.onSecondary, c.onInverseSurface),
        'secondaryContainer': (s.secondaryContainer, c.fill),
        'onSecondaryContainer': (s.onSecondaryContainer, c.textPrimary),
        'tertiary': (s.tertiary, c.success),
        'onTertiary': (s.onTertiary, c.onSuccess),
        'tertiaryContainer': (s.tertiaryContainer, c.successContainer),
        'onTertiaryContainer': (s.onTertiaryContainer, c.success),
        'error': (s.error, c.danger),
        'onError': (s.onError, c.onDanger),
        'errorContainer': (s.errorContainer, c.dangerContainer),
        'onErrorContainer': (s.onErrorContainer, c.danger),
        'surface': (s.surface, c.background),
        'onSurface': (s.onSurface, c.textPrimary),
        'onSurfaceVariant': (s.onSurfaceVariant, c.textSecondary),
        'surfaceContainerLowest': (s.surfaceContainerLowest, c.surface),
        'surfaceContainerLow': (s.surfaceContainerLow, c.surface),
        'surfaceBright': (s.surfaceBright, c.surface),
        'surfaceContainer': (s.surfaceContainer, c.fill),
        'surfaceContainerHigh': (s.surfaceContainerHigh, c.track),
        'surfaceContainerHighest': (s.surfaceContainerHighest, c.track),
        'surfaceDim': (s.surfaceDim, c.track),
        'surfaceTint': (s.surfaceTint, Colors.transparent),
        'outline': (s.outline, c.outline),
        'outlineVariant': (s.outlineVariant, c.border),
        'inverseSurface': (s.inverseSurface, c.inverseSurface),
        'onInverseSurface': (s.onInverseSurface, c.onInverseSurface),
        'inversePrimary': (
          s.inversePrimary,
          kind == NapThemeKind.light
              ? const Color(0xFF8CA2FF)
              : const Color(0xFF2348D1),
        ),
        'shadow': (s.shadow, Colors.black),
        'scrim': (s.scrim, c.scrim),
      };
      for (final MapEntry(key: role, value: (actual, want))
          in expected.entries) {
        expect(actual.toARGB32(), want.toARGB32(), reason: role);
      }

      expect(theme.bottomSheetTheme.modalBarrierColor!.toARGB32(), 0x8C0F1115);
      expect(theme.bottomSheetTheme.dragHandleSize, const Size(40, 4));
      expect(theme.dividerTheme.color, c.divider);
      expect(theme.navigationBarTheme.height, 64);
      expect(theme.sliderTheme.trackHeight, 4);
    });
  }

  test('TC07 additional styles match the spec scale', () {
    expect(NapTypography.extras.keys.toSet(), _extras.keys.toSet());
    for (final MapEntry(key: name, value: style)
        in NapTypography.extras.entries) {
      expect(style.color, isNull, reason: name);
      expect(style.fontFamily, isNull, reason: name);
      _expectStyle(style, _extras[name]!, name);
    }
  });

  test('TC09 themes are cached per kind and font family', () {
    expect(identical(NapThemes.light(), NapThemes.light()), isTrue);
    expect(
      identical(NapThemes.light(), NapThemes.of(NapThemeKind.light)),
      isTrue,
    );
    final test = NapThemes.light(fontFamily: 'FlutterTest');
    expect(identical(test, NapThemes.light()), isFalse);
    expect(test.textTheme.bodyMedium!.fontFamily, 'FlutterTest');
    expect(identical(NapThemes.dark(), NapThemes.alarm()), isFalse);
  });

  testWidgets('TC23 NapMotion.of honors reduced motion', (tester) async {
    late Duration normal;
    late Duration reduced;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            normal = NapMotion.of(context, NapMotion.fast);
            return MediaQuery(
              data: const MediaQueryData(disableAnimations: true),
              child: Builder(
                builder: (context) {
                  reduced = NapMotion.of(context, NapMotion.fast);
                  return const SizedBox();
                },
              ),
            );
          },
        ),
      ),
    );
    expect(normal, const Duration(milliseconds: 150));
    expect(reduced, Duration.zero);
  });

  // Review T20 #6: the filled button theme must not turn
  // FilledButton.tonal into a primary button.
  for (final kind in NapThemeKind.values) {
    testWidgets('filled button theme: FilledButton vs tonal (${kind.name})', (
      tester,
    ) async {
      final c = NapThemes.colorsOf(kind);
      await tester.pumpWidget(
        MaterialApp(
          theme: NapThemes.of(kind),
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('primary')),
                FilledButton.tonal(
                  onPressed: () {},
                  child: const Text('tonal'),
                ),
                const FilledButton(onPressed: null, child: Text('off')),
              ],
            ),
          ),
        ),
      );
      Material materialOf(String label) => tester.widget<Material>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first,
      );
      Color textOf(String label) => tester
          .widget<DefaultTextStyle>(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(DefaultTextStyle),
                )
                .first,
          )
          .style
          .color!;
      expect(materialOf('primary').color, c.accent);
      expect(textOf('primary'), c.onAccent);
      expect(materialOf('tonal').color, c.fill);
      expect(textOf('tonal'), c.textPrimary);
      // Disabled: Material 3 defaults, onSurface (= textPrimary) at 12% / 38%
      // (quantized to 8-bit alpha, like NapButton within 1/255).
      void expectFaded(Color actual, double alpha) {
        expect(actual.withValues(alpha: 1), c.textPrimary, reason: '$alpha');
        expect(actual.a, closeTo(alpha, 1 / 255), reason: '$alpha');
      }

      expectFaded(materialOf('off').color!, 0.12);
      expectFaded(textOf('off'), 0.38);
      // Geometry still comes from the large NapButton.
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'tonal')).height,
        greaterThanOrEqualTo(NapSizes.buttonLarge),
      );
      expect(
        (materialOf('tonal').shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(NapRadii.r16),
      );
    });
  }
}
