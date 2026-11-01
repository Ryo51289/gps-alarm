import 'package:flutter/widgets.dart';
import 'package:napstop/core/design/catalog/catalog_app.dart';
import 'package:napstop/core/design/fonts/font_licenses.dart';

/// Design system catalog entrypoint (dev only, spec T20 section 7.1):
/// `flutter run -t lib/main_catalog.dart`.
void main() {
  registerFontLicenses();
  runApp(const CatalogApp());
}
