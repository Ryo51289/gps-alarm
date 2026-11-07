import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// One result of screen 2 (station or address), with a check mark when it is
/// the chosen destination and a progress indicator while it resolves.
class ResultRow extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.selected = false,
    this.busy = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool selected;

  /// Location of this address is being read.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final trailing = busy
        ? const SizedBox.square(
            dimension: NapSizes.iconSmall,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : selected
        ? Icon(NapIcons.check, color: c.success, size: NapSizes.icon)
        : null;
    return NapListRow(
      leading: NapIconTile(
        icon: icon,
        tone: selected ? NapTone.accent : NapTone.neutral,
      ),
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      selected: selected,
      onTap: onTap,
    );
  }
}

/// A secondary line of the panel (hint, empty state, loading).
class PanelNote extends StatelessWidget {
  const new(this.text, {this.loading = false, super.key});

  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NapSpace.s16,
        vertical: NapSpace.s12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: NapSpace.s10,
        children: [
          if (loading)
            const SizedBox.square(
              dimension: NapSizes.iconSmall,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          Expanded(
            child: Text(
              text,
              style: context.napText.bodySmall!.copyWith(
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
