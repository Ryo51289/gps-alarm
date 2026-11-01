import 'package:flutter/material.dart';
import 'package:napstop/core/design/nap_icons.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';

enum NapSearchFieldVariant { filled, floating }

/// Search input (spec T20 section 5.20). With [readOnly] and [onTap] it is a
/// button that opens the search screen (screen 1).
final class NapSearchField extends StatelessWidget {
  const new({
    required this.hint,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.trailing,
    this.variant = NapSearchFieldVariant.filled,
    super.key,
  });

  final String hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;

  /// E.g. the clear button of T23.
  final Widget? trailing;
  final NapSearchFieldVariant variant;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final shadows = context.napShadows;
    final filled = variant == NapSearchFieldVariant.filled;
    final minHeight = filled ? NapSizes.listRowMin : NapSizes.minTouch;
    final radius = BorderRadius.circular(filled ? NapRadii.r14 : NapRadii.pill);
    final textStyle = context.napText.bodyLarge!;
    final hintStyle = textStyle.copyWith(color: c.textSecondary);
    final bordered = filled || shadows.borderInsteadOfShadow;
    // Vertical padding that makes the text area itself at least 48 px high
    // (touch target of the text field node). The 1 px border adds to the
    // visible height, except for the 56 px filled field where it fits.
    final lineHeight = textStyle.fontSize! * textStyle.height!;
    final innerHeight = filled ? minHeight - 2 : NapSizes.minTouch;
    final vPad = (innerHeight - lineHeight) / 2;
    final asButton = readOnly && onTap != null;

    final input = asButton
        ? Padding(
            padding: EdgeInsets.symmetric(vertical: vPad),
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hintStyle,
            ),
          )
        : TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            onTap: onTap,
            readOnly: readOnly,
            autofocus: autofocus,
            style: textStyle,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: hintStyle,
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: vPad),
            ),
          );
    final content = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: bordered ? minHeight - 2 : minHeight,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: filled ? NapSpace.s16 : NapSpace.s14,
        ),
        child: Row(
          spacing: NapSpace.s10,
          children: [
            ExcludeSemantics(
              child: Icon(
                NapIcons.search,
                size: filled ? NapSizes.iconLarge : NapSizes.iconSmall,
                color: c.textSecondary,
              ),
            ),
            Expanded(child: input),
            ?trailing,
          ],
        ),
      ),
    );
    // The background is painted by the field itself, not with Ink: Ink paints
    // on the nearest ancestor Material, which sits below any opaque sibling
    // (the map of screen 2). The transparent Material gives the ripple and
    // the TextField their own ink layer above the background.
    final decoration = BoxDecoration(
      color: filled ? c.fill : c.surfaceFloating,
      borderRadius: radius,
      border: bordered ? Border.all(color: c.border) : null,
      boxShadow: filled ? null : shadows.floating,
    );
    // Inset by the border width, as Ink did.
    final inset = Padding(padding: decoration.padding, child: content);
    final field = DecoratedBox(
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: asButton
            ? InkWell(onTap: onTap, borderRadius: radius, child: inset)
            : inset,
      ),
    );
    if (!asButton) {
      return field;
    }
    // excludeSemantics also drops the tap action of the InkWell: set it here.
    return Semantics(
      button: true,
      label: hint,
      onTap: onTap,
      excludeSemantics: true,
      child: field,
    );
  }
}
