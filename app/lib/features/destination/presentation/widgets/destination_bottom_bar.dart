import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Bottom of the panel (T23 §9): "Lưu điểm này" (hidden when picking) and
/// the main "Chọn …" button.
class DestinationBottomBar extends StatelessWidget {
  const new({
    required this.confirmLabel,
    required this.saveLabel,
    required this.onConfirm,
    required this.onSave,
    required this.showSave,
    super.key,
  });

  final String confirmLabel;
  final String saveLabel;

  /// Null disables the buttons (nothing chosen).
  final VoidCallback? onConfirm;
  final VoidCallback? onSave;
  final bool showSave;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return ColoredBox(
      color: c.surface,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          NapSpace.page,
          NapSpace.s12,
          NapSpace.page,
          NapSpace.s24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Row(
          spacing: NapSpace.s10,
          children: [
            if (showSave)
              NapIconButton(
                icon: NapIcons.bookmark,
                semanticLabel: saveLabel,
                onPressed: onSave,
                size: NapSizes.buttonLarge,
                square: true,
              ),
            Expanded(
              child: NapButton(label: confirmLabel, onPressed: onConfirm),
            ),
          ],
        ),
      ),
    );
  }
}
