import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/logging/app_log.dart';
import 'package:napstop/features/feedback/domain/feedback_email.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

final Logger _log = AppLog.named('feedback');

/// No mail app opened (T28.4 §5): shows [kFeedbackEmail] with "Sao chép địa
/// chỉ" and "Đóng". [showCopiedSnack] false on Android 13+ (D10).
Future<void> showFeedbackFallbackDialog(
  BuildContext context, {
  required bool showCopiedSnack,
}) {
  // The calling screen's messenger, taken before the dialog is popped.
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    builder: (context) => _FeedbackFallbackDialog(
      onCopied: (copiedText) {
        if (!showCopiedSnack || messenger == null) {
          return;
        }
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(copiedText), persist: false));
      },
    ),
  );
}

class _FeedbackFallbackDialog extends StatelessWidget {
  const new({required this.onCopied});

  /// After the dialog closed; gets the localized "address copied" text.
  final ValueChanged<String> onCopied;

  Future<void> _copy(BuildContext context) async {
    // Everything context-dependent is read, and the dialog popped, before the
    // await: a second tap or Back during the clipboard call must not pop the
    // screen underneath (T28.4 test report bug #1).
    final copiedText = AppLocalizations.of(context).feedbackAddressCopied;
    Navigator.of(context).pop();
    onCopied(copiedText);
    try {
      await Clipboard.setData(const ClipboardData(text: kFeedbackEmail));
    } on PlatformException catch (e) {
      // Some ROMs throw from setPrimaryClip; not fatal (T28.4 test report #2).
      // The address is selectable in the dialog, so nothing is lost.
      _log.warning('clipboard write failed: ${e.code}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = l.feedbackNoMailTitle;
    return AlertDialog(
      semanticLabel: title,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NapSpace.s8,
        children: [
          Text(l.feedbackNoMailBody),
          SelectableText(kFeedbackEmail, style: context.napText.titleSmall),
        ],
      ),
      actions: [
        // Not full width: the dialog's OverflowBar lays them out.
        NapButton(
          key: const ValueKey('feedback-close'),
          label: l.feedbackClose,
          variant: NapButtonVariant.text,
          size: NapButtonSize.medium,
          expand: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        NapButton(
          key: const ValueKey('feedback-copy'),
          label: l.feedbackCopyAddress,
          size: NapButtonSize.medium,
          expand: false,
          onPressed: () => _copy(context),
        ),
      ],
    );
  }
}
