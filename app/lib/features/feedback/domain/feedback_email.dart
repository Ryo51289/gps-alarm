// T28.4: the feedback email (screen 12). Pure: builds the subject, body and
// `mailto:` URI from device details. PRIVACY (D6): nothing here may hold a
// location, a place or destination name, or trip data.
import 'package:meta/meta.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge.dart';
import 'package:napstop/core/preferences/display_preferences.dart';

/// PO 13/11/2026 (D3). Shown to the user in the fallback dialog.
const String kFeedbackEmail = 'giftff02@gmail.com';

/// Subject prefix, the same in every language so mail filters work (D7).
const String kFeedbackSubjectTag = '[NapStop]';

/// Separator line between the user's text and the diagnostics block.
const String kFeedbackSeparator = '-----';

/// Longest device/model text kept (OS strings are not trusted).
const int kFeedbackFieldMaxChars = 40;

/// App name in the "App:" line. `lib/app/app.dart` (kAppName) pulls in
/// Flutter widgets, so it is repeated here; a unit test keeps them equal.
const String _appName = 'NapStop';

/// Line break of the body (RFC 6068: `%0D%0A`, D4).
const String _crlf = '\r\n';

/// Localised texts the pure builder needs (from ARB).
@immutable
final class FeedbackCopy {
  const new({
    required this.subjectWord,
    required this.prompt,
    required this.diagHeader,
  });

  /// "Góp ý" / "Feedback".
  final String subjectWord;

  /// First line of the body (`feedbackBodyPrompt`).
  final String prompt;

  /// Header of the diagnostics block (`feedbackDiagHeader`).
  final String diagHeader;
}

/// Everything the feedback email may contain about the device (D5).
///
/// PRIVACY (D6): no field may hold a location, a place/destination name or
/// trip data. Do not add one.
@immutable
final class FeedbackDiagnostics {
  const new({
    required this.appVersion,
    required this.appBuild,
    required this.flavor,
    required this.device,
    required this.permissions,
    required this.appLanguage,
    required this.deviceLocale,
    required this.paramsId,
  });

  /// '0.1.0'; null when unreadable.
  final String? appVersion;

  /// '1'; null when unreadable.
  final String? appBuild;

  final AppFlavor flavor;

  /// null when unreadable.
  final DeviceInfoMsg? device;

  /// Permission states only; null when unreadable.
  final PermissionStatusMsg? permissions;

  final AppLanguage appLanguage;

  /// BCP 47, e.g. 'vi-VN'.
  final String deviceLocale;

  /// 'default' | 'invalid' | 8 hex; null when unreadable.
  final String? paramsId;
}

/// "0.1.0 (1)"; null when appVersion is null; "0.1.0" when build is
/// null/empty.
String? feedbackVersionLabel(FeedbackDiagnostics d) {
  final version = d.appVersion;
  if (version == null) {
    return null;
  }
  final build = d.appBuild;
  return build == null || build.isEmpty ? version : '$version ($build)';
}

/// `[NapStop] Góp ý — 0.1.0 (1)`; without version: `[NapStop] Góp ý`.
String feedbackSubject(FeedbackCopy copy, FeedbackDiagnostics d) {
  final base = '$kFeedbackSubjectTag ${copy.subjectWord}';
  final version = feedbackVersionLabel(d);
  return version == null ? base : '$base — $version';
}

/// Control characters (incl. \r \n \t) → space, trimmed, cut to
/// [kFeedbackFieldMaxChars].
String _clean(String raw) {
  final text = raw.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
  return text.length <= kFeedbackFieldMaxChars
      ? text
      : text.substring(0, kFeedbackFieldMaxChars).trimRight();
}

/// Android: "Android 15 (API 35)"; iOS: "iOS 26.1"; osVersion empty →
/// "Android (API 35)" / "iOS".
String osLabel(DeviceInfoMsg d) {
  final version = _clean(d.osVersion);
  switch (d.platform) {
    case PlatformMsg.android:
      final name = version.isEmpty ? 'Android' : 'Android $version';
      final sdk = d.androidSdkInt;
      return sdk == null ? name : '$name (API $sdk)';
    case PlatformMsg.ios:
      return version.isEmpty ? 'iOS' : 'iOS $version';
  }
}

/// Android: manufacturer + ' ' + model, except when model already starts with
/// manufacturer (case-insensitive) → model only. iOS: model. Empty →
/// "unknown".
String deviceLabel(DeviceInfoMsg d) {
  final model = _clean(d.model);
  final String label;
  switch (d.platform) {
    case PlatformMsg.android:
      final maker = _clean(d.manufacturer);
      label =
          maker.isEmpty || model.toLowerCase().startsWith(maker.toLowerCase())
          ? model
          : '$maker $model'.trim();
    case PlatformMsg.ios:
      label = model;
  }
  return label.isEmpty ? 'unknown' : label;
}

/// "location=always, precise=granted, location_services=on, …"; entries
/// whose state is notApplicable are left out.
String permissionsLabel(PermissionStatusMsg s) {
  final entries = <String>['location=${s.location.name}'];
  void add(String key, PermissionStateMsg state) {
    if (state != PermissionStateMsg.notApplicable) {
      entries.add('$key=${state.name}');
    }
  }

  add('precise', s.precise);
  entries.add('location_services=${s.locationServicesEnabled ? 'on' : 'off'}');
  add('notifications', s.notifications);
  add('full_screen', s.fullScreenIntent);
  add('exact_alarm', s.exactAlarm);
  add('battery_unrestricted', s.batteryOptimizationIgnored);
  add('alarmkit', s.alarmKit);
  return entries.join(', ');
}

/// Diagnostics lines (fixed English labels, D7); a line whose source is
/// null is left out. "App:" and "Language:" are always present.
List<String> diagnosticsLines(FeedbackDiagnostics d) {
  final device = d.device;
  final permissions = d.permissions;
  final paramsId = d.paramsId;
  return [
    'App: $_appName ${feedbackVersionLabel(d) ?? '?'}, ${d.flavor.name}',
    if (device != null) ...[
      'OS: ${osLabel(device)}',
      'Device: ${deviceLabel(device)}',
    ],
    'Language: app=${d.appLanguage.name}, device=${_clean(d.deviceLocale)}',
    if (permissions != null) 'Permissions: ${permissionsLabel(permissions)}',
    if (paramsId != null) 'Engine: ${_clean(paramsId)}',
  ];
}

/// prompt, four empty lines, separator, header, diagnostics; joined with
/// CRLF (D4).
String feedbackBody(FeedbackCopy copy, FeedbackDiagnostics d) => [
  copy.prompt,
  '',
  '',
  '',
  '',
  kFeedbackSeparator,
  copy.diagHeader,
  ...diagnosticsLines(d),
].join(_crlf);

/// `mailto:<to>?subject=<enc>&body=<enc>`, each value through
/// [Uri.encodeComponent] (RFC 6068, D4): spaces stay `%20`, never `+`.
Uri feedbackMailtoUri({
  required String to,
  required String subject,
  required String body,
}) {
  assert(
    !to.contains('?') && !to.contains('&') && !RegExp(r'\s').hasMatch(to),
    'to must be a plain address',
  );
  return Uri.parse(
    'mailto:$to?subject=${Uri.encodeComponent(subject)}'
    '&body=${Uri.encodeComponent(body)}',
  );
}

/// The "copied" snackbar is shown unless the device is Android with
/// SDK ≥ 33, which confirms a copy itself (D10). Unknown → true.
bool showCopiedSnackFor(DeviceInfoMsg? device) {
  if (device == null || device.platform != PlatformMsg.android) {
    return true;
  }
  final sdk = device.androidSdkInt;
  return sdk == null || sdk < 33;
}
