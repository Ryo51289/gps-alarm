import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version line of screen 12: `version` = build name, `build` = build number.
typedef AppVersion = ({String version, String build});

/// Read once per session (D15). An error hides the version line; the logo
/// stays a long-press target. Tests override it.
final appVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return (version: info.version, build: info.buildNumber);
});
