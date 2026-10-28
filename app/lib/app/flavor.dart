import 'package:flutter/services.dart' show appFlavor;

/// Build flavor. Unknown or missing values fall back to [dev] so that a
/// misconfigured build never talks to production services.
enum AppFlavor {
  dev,
  prod;

  /// Exact, case-sensitive match on the `--flavor` name.
  static AppFlavor parse(String? raw) => raw == 'prod' ? prod : dev;

  /// Flavor of the running build (from `--flavor` or pubspec `default-flavor`).
  static final AppFlavor current = parse(appFlavor);
}
