import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:napstop/app/flavor.dart';
import 'package:napstop/core/bridge/core_bridge_provider.dart';
import 'package:napstop/core/device/device_providers.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/core/preferences/app_settings.dart';
import 'package:napstop/core/telemetry/remote_config/engine_params_providers.dart';
import 'package:napstop/features/feedback/data/feedback_launcher.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';
import 'package:napstop/features/feedback/presentation/feedback_fallback_dialog.dart';
import 'package:napstop/features/settings/presentation/settings_providers.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

final Logger _log = AppLog.named('feedback');

/// Screen 12 "Góp ý" (T28.4 §2): reads the device details, then opens the
/// mail composer; no mail app → the fallback dialog. No re-entry guard here:
/// the caller guards.
Future<void> openFeedback(BuildContext context, WidgetRef ref) async {
  final l = AppLocalizations.of(context);
  final copy = FeedbackCopy(
    subjectWord: l.feedbackSubjectWord,
    prompt: l.feedbackBodyPrompt,
    diagHeader: l.feedbackDiagHeader,
  );
  final launch = ref.read(feedbackLauncherProvider);
  final bridge = ref.read(coreBridgeProvider);
  final params = ref.read(engineParamsReaderProvider);
  // The sources are read before the first await (ref may go away).
  final d = await collectFeedbackDiagnostics(
    version: () => ref.read(appVersionProvider.future),
    device: () => ref.read(deviceInfoProvider.future),
    permissions: bridge.permissionStatus,
    paramsId: () => params.current().id,
    appLanguage: ref.read(appSettingsProvider).display.language,
    deviceLocale: WidgetsBinding.instance.platformDispatcher.locale
        .toLanguageTag(),
    flavor: AppFlavor.current,
  );
  final uri = feedbackMailtoUri(
    to: kFeedbackEmail,
    subject: feedbackSubject(copy, d),
    body: feedbackBody(copy, d),
  );
  bool ok;
  try {
    ok = await launch(uri);
  } on Exception {
    ok = false;
  }
  // PRIVACY: never the URI or the body.
  _log.info(ok ? 'composer opened' : 'no mail app');
  if (!ok && context.mounted) {
    await showFeedbackFallbackDialog(
      context,
      showCopiedSnack: showCopiedSnackFor(d.device),
    );
  }
}
