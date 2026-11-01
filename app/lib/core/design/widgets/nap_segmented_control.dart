import 'package:flutter/material.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/tokens/nap_motion.dart';

/// One option of a [NapSegmentedControl].
final class NapSegment<T> {
  const new({required this.value, required this.label});

  final T value;
  final String label;
}

enum NapSegmentedSize { regular, compact }

/// iOS-style segmented control (spec T20 section 5.5): 2 to 4 options, one
/// selected. Each option's touch area covers the track padding (52 px
/// regular, 48 px compact).
final class NapSegmentedControl<T> extends StatelessWidget {
  new({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.size = NapSegmentedSize.regular,
    this.semanticLabel,
    super.key,
  }) : assert(
         segments.length >= 2 && segments.length <= 4,
         'NapSegmentedControl needs 2 to 4 segments',
       ),
       assert(
         segments.map((s) => s.value).toSet().length == segments.length,
         'Segment values must be unique',
       ),
       assert(
         segments.any((s) => s.value == selected),
         'selected must be one of the segment values',
       );

  final List<NapSegment<T>> segments;
  final T selected;

  /// Null disables the control. Not called when the selected option is
  /// tapped again.
  final ValueChanged<T>? onChanged;
  final NapSegmentedSize size;

  /// Group label read by screen readers, e.g. "Alarm when".
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final compact = size == NapSegmentedSize.compact;
    const pad = NapSizes.segmentPadding;
    const halfGap = NapSizes.segmentPadding / 2;
    final itemHeight = compact
        ? NapSizes.segmentItemCompact
        : NapSizes.segmentItem;
    final itemRadius = compact ? NapRadii.r8 : NapRadii.r10;
    final duration = NapMotion.of(context, NapMotion.fast);
    final labelStyle = context.napText.labelMedium!;
    final enabled = onChanged != null;

    final items = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isSelected = segment.value == selected;
      final onTap = !enabled || isSelected
          ? null
          : () => onChanged!(segment.value);
      items.add(
        Expanded(
          child: Semantics(
            button: true,
            inMutuallyExclusiveGroup: true,
            selected: isSelected,
            enabled: enabled,
            label: segment.label,
            onTap: onTap,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  i == 0 ? pad : halfGap,
                  pad,
                  i == segments.length - 1 ? pad : halfGap,
                  pad,
                ),
                child: AnimatedContainer(
                  duration: duration,
                  curve: NapMotion.curve,
                  constraints: BoxConstraints(minHeight: itemHeight),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    horizontal: NapSpace.s8,
                    vertical: NapSpace.s4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? c.segmentThumb : Colors.transparent,
                    borderRadius: BorderRadius.circular(itemRadius),
                    boxShadow: isSelected ? context.napShadows.thumb : null,
                  ),
                  child: Text(
                    segment.label,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: !enabled
                          ? c.textPrimary.withValues(alpha: 0.38)
                          : isSelected
                          ? c.textPrimary
                          : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.fill,
          borderRadius: BorderRadius.circular(
            compact ? NapRadii.r12 : NapRadii.r14,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          ),
        ),
      ),
    );
  }
}
