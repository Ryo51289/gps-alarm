import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Answer of [showLeaveSaveDialog].
enum LeaveSaveChoice { save, discard }

/// `Lưu vào <slot>?` asked when leaving the picker with a pending choice
/// (T23.7). Null = dismissed (barrier, system back): stay on screen 2.
Future<LeaveSaveChoice?> showLeaveSaveDialog(
  BuildContext context, {
  required String slotLabel,
  required String destinationName,
}) {
  return showDialog<LeaveSaveChoice>(
    context: context,
    builder: (context) => _LeaveSaveDialog(
      slotLabel: slotLabel,
      destinationName: destinationName,
    ),
  );
}

class _LeaveSaveDialog extends StatelessWidget {
  const new({required this.slotLabel, required this.destinationName});

  final String slotLabel;
  final String destinationName;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = l.destinationLeaveSaveTitle(slotLabel);
    return AlertDialog(
      semanticLabel: title,
      title: Text(title),
      content: Text(
        l.destinationLeaveSaveBody(destinationName),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        // Not full width: the dialog's OverflowBar lays them out.
        NapButton(
          key: const ValueKey('leave-discard'),
          label: l.destinationLeaveDiscard,
          variant: NapButtonVariant.text,
          size: NapButtonSize.medium,
          expand: false,
          onPressed: () => Navigator.of(context).pop(LeaveSaveChoice.discard),
        ),
        NapButton(
          key: const ValueKey('leave-save'),
          label: l.destinationLeaveSave,
          size: NapButtonSize.medium,
          expand: false,
          onPressed: () => Navigator.of(context).pop(LeaveSaveChoice.save),
        ),
      ],
    );
  }
}
