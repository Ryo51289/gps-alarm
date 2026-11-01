import 'package:flutter/material.dart';
import 'package:napstop/app/locales.dart';
import 'package:napstop/core/design/catalog/catalog_home.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Design system catalog (dev tool, spec T20 section 7.1). Run with
/// `flutter run -t lib/main_catalog.dart`; never imported by `main.dart`.
final class CatalogApp extends StatefulWidget {
  const new({super.key});

  @override
  State<CatalogApp> createState() => _CatalogAppState();
}

class _CatalogAppState extends State<CatalogApp> {
  NapThemeKind _kind = NapThemeKind.light;
  CatalogTextScale _textScale;
  Locale _locale = kAppSupportedLocales.first;

  @override
  Widget build(BuildContext context) {
    final textScale = _textScale;
    return MaterialApp(
      title: CatalogHome.title,
      debugShowCheckedModeBanner: false,
      theme: NapThemes.of(_kind),
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: kAppSupportedLocales,
      builder: (context, child) => textScale == null
          ? child!
          : MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      home: CatalogHome(
        kind: _kind,
        textScale: _textScale,
        locale: _locale,
        onKind: (k) => setState(() => _kind = k),
        onTextScale: (s) => setState(() => _textScale = s),
        onLocale: (l) => setState(() => _locale = l),
      ),
    );
  }
}
