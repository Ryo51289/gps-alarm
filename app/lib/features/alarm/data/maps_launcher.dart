import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a Google Maps URL outside the app (T27 §4.5, D8). false or a throw
/// is a failure. No `canLaunchUrl`: it would need `<queries>` (D8).
///
/// PRIVACY: the URI holds the destination coordinates — never log it.
typedef MapsLauncher = Future<bool> Function(Uri uri);

/// Seam for widget tests.
final mapsLauncherProvider = Provider<MapsLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
