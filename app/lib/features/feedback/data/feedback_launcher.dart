import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/display_preferences.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens the system mail composer (T28.4 D1). false = no app took it (also
/// on [PlatformException]). No `canLaunchUrl`: it would need `<queries>` /
/// `LSApplicationQueriesSchemes` (D2).
///
/// PRIVACY: the URI holds device details — never log it.
typedef FeedbackLauncher = Future<bool> Function(Uri uri);

/// Seam for widget tests.
final feedbackLauncherProvider = Provider<FeedbackLauncher>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      return false;
    }
  },
);

/// Max wait per diagnostics source.
const Duration kFeedbackReadTimeout = Duration(seconds: 1);

/// [read] with a [timeout]; a throw or timeout gives null.
Future<T?> _safe<T extends Object>(
  Future<T> Function() read,
  Duration timeout,
) async {
  try {
    return await Future.sync(read).timeout(timeout);
  } on Object {
    return null;
  }
}

/// Reads all sources in parallel; each failure or timeout gives null for
/// that part (never throws).
Future<FeedbackDiagnostics> collectFeedbackDiagnostics({
  required Future<AppVersion> Function() version,
  required Future<DeviceInfoMsg> Function() device,
  required Future<PermissionStatusMsg> Function() permissions,
  required String? Function() paramsId,
  required AppLanguage appLanguage,
  required String deviceLocale,
  required AppFlavor flavor,
  Duration timeout = kFeedbackReadTimeout,
}) async {
  String? id;
  try {
    id = paramsId();
  } on Object {
    id = null;
  }
  final (v, d, p) = await (
    _safe(version, timeout),
    _safe(device, timeout),
    _safe(permissions, timeout),
  ).wait;
  return FeedbackDiagnostics(
    appVersion: v?.version,
    appBuild: v?.build,
    flavor: flavor,
    device: d,
    permissions: p,
    appLanguage: appLanguage,
    deviceLocale: deviceLocale,
    paramsId: id,
  );
}
