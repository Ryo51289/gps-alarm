import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';

/// Rounded group of rows with a divider between rows
/// (spec T20 section 5.10).
final class NapListGroup extends StatelessWidget {
  const new({required this.children, this.bordered = true, super.key});

  final List<Widget> children;

  /// 1 px `border` outline; false on the alarm screens.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(NapRadii.r14),
        side: bordered ? BorderSide(color: c.border) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}
