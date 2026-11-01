import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_typography.dart';

/// Upper-case section label (spec T20 section 5.13). Screen readers read
/// [text] as given (not upper-cased). No built-in padding.
final class NapSectionHeader extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: text,
      child: ExcludeSemantics(
        child: Text(
          text.toUpperCase(),
          style: context
              .napStyle(NapTypography.overline)
              .copyWith(color: context.napColors.textSecondary),
        ),
      ),
    );
  }
}
