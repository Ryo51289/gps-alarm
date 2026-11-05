import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:napstop/core/design/nap_icons.dart';
import 'package:napstop/core/design/theme/nap_theme_context.dart';
import 'package:napstop/core/design/tokens/nap_metrics.dart';
import 'package:napstop/core/design/widgets/nap_switch_row.dart';

/// List row (spec T20 section 5.11): leading, title, subtitle, trailing,
/// optional chevron. Screen readers get one merged node.
///
/// [trailing] is capped at half the row width (inside the padding), so a
/// long value or badge wraps instead of overflowing at large text scales.
/// The row reports intrinsic sizes, so it also works inside
/// `IntrinsicWidth`/`IntrinsicHeight` (AlertDialog, SimpleDialog). When
/// leading + trailing + chevron do not fit, debug builds report it like a
/// `Row` ("overflowed", T28 N2).
final class NapListRow extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.selected = false,
    this.semanticsChecked,
    this.titleWeight = NapRowTitle.semibold,
    this.titleMaxLines = 2,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Usually a NapIconTile.
  final Widget? leading;

  /// Value text, NapBadge, compact NapButton, NapRadioIndicator...
  final Widget? trailing;

  /// Adds a decorative chevron at the end.
  final bool chevron;
  final VoidCallback? onTap;

  /// Highlighted with `accentContainer` (selected search result).
  final bool selected;

  /// Non-null makes the row a radio option with this checked state.
  final bool? semanticsChecked;
  final NapRowTitle titleWeight;
  final int titleMaxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final text = context.napText;
    final subtitle = this.subtitle;
    final radius = BorderRadius.circular(selected ? NapRadii.r12 : 0);
    final row = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: subtitle == null
            ? NapSizes.listRowMin
            : NapSizes.listRowWithSubtitleMin,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: NapSpace.s16,
          vertical: NapSpace.s12,
        ),
        child: _RowLayout(
          gap: NapSpace.s12,
          leading: leading,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: NapSpace.s2,
            children: [
              Text(
                title,
                maxLines: titleMaxLines,
                overflow: TextOverflow.ellipsis,
                style: titleWeight == NapRowTitle.semibold
                    ? text.titleSmall
                    : text.bodyMedium,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: text.bodySmall!.copyWith(color: c.textSecondary),
                ),
            ],
          ),
          trailing: trailing,
          end: chevron
              ? Icon(
                  NapIcons.chevron,
                  size: NapSizes.iconSmall,
                  color: c.textSecondary,
                )
              : null,
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        button: onTap != null ? true : null,
        selected: selected ? true : null,
        checked: semanticsChecked,
        inMutuallyExclusiveGroup: semanticsChecked != null ? true : null,
        child: Material(
          color: selected ? c.accentContainer : Colors.transparent,
          borderRadius: radius,
          clipBehavior: selected ? Clip.antiAlias : Clip.none,
          child: InkWell(onTap: onTap, borderRadius: radius, child: row),
        ),
      ),
    );
  }
}

/// Slots in visual (start to end) order.
enum _Slot { leading, title, trailing, end }

/// Same layout as `Row(spacing: gap, children: [leading, Expanded(title),
/// ConstrainedBox(maxWidth: width / 2, child: trailing), end])`, children
/// centered vertically.
///
/// A LayoutBuilder could compute the cap but cannot report intrinsic sizes;
/// a Flexible trailing would cap the title at half the width as well (Flex
/// does not hand unused flex space back). This render object does both.
final class _RowLayout
    extends SlottedMultiChildRenderObjectWidget<_Slot, RenderBox> {
  const new({
    required this.leading,
    required this.title,
    required this.trailing,
    required this.end,
    required this.gap,
  });

  final Widget? leading;
  final Widget title;
  final Widget? trailing;
  final Widget? end;
  final double gap;

  @override
  Iterable<_Slot> get slots => _Slot.values;

  @override
  Widget? childForSlot(_Slot slot) => switch (slot) {
    _Slot.leading => leading,
    _Slot.title => title,
    _Slot.trailing => trailing,
    _Slot.end => end,
  };

  @override
  _RenderRowLayout createRenderObject(BuildContext context) =>
      _RenderRowLayout(gap: gap, textDirection: Directionality.of(context));

  @override
  void updateRenderObject(BuildContext context, _RenderRowLayout renderObject) {
    renderObject
      ..gap = gap
      ..textDirection = Directionality.of(context);
  }
}

/// [used]: gaps plus every slot but the title (the title gets the rest).
typedef _Layout = ({
  Size size,
  Map<_Slot, Size> sizes,
  BoxConstraints title,
  double used,
});

final class _RenderRowLayout extends RenderBox
    with
        SlottedContainerRenderObjectMixin<_Slot, RenderBox>,
        DebugOverflowIndicatorMixin {
  new({required this._gap, required this._textDirection});

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) {
      return;
    }
    _gap = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) {
      return;
    }
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _title => childForSlot(_Slot.title)!;

  /// Present slots in visual order.
  Iterable<_Slot> get _slots =>
      _Slot.values.where((slot) => childForSlot(slot) != null);

  /// Visual order: paint, hit test and semantics order.
  @override
  Iterable<RenderBox> get children => [
    for (final slot in _slots) childForSlot(slot)!,
  ];

  double get _gaps => _gap * math.max(0, _slots.length - 1);

  static double _cap(double width) => width.isFinite ? width / 2 : width;

  /// Width the slots ask for beyond the row in the last layout (N2).
  double _overflow = 0;

  // Intrinsics: the row is as wide as its children plus the gaps, and at
  // least twice its trailing: layout caps trailing at half the width, so at
  // `max(sum, 2 * trailing)` trailing gets its full width and the title keeps
  // at least its own (T28 N1).

  @override
  double computeMinIntrinsicWidth(double height) =>
      _intrinsicWidth((child) => child.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _intrinsicWidth((child) => child.getMaxIntrinsicWidth(height));

  double _intrinsicWidth(double Function(RenderBox child) widthOf) {
    final sum = _gaps + children.fold<double>(0, (sum, c) => sum + widthOf(c));
    final trailing = childForSlot(_Slot.trailing);
    return trailing == null ? sum : math.max(sum, 2 * widthOf(trailing));
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMinIntrinsicHeight(w));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, (child, w) => child.getMaxIntrinsicHeight(w));

  double _intrinsicHeight(
    double width,
    double Function(RenderBox child, double width) heightOf,
  ) {
    var height = 0.0;
    var used = _gaps;
    for (final slot in _slots) {
      if (slot == _Slot.title) {
        continue;
      }
      final child = childForSlot(slot)!;
      var childWidth = child.getMaxIntrinsicWidth(double.infinity);
      if (slot == _Slot.trailing) {
        childWidth = math.min(childWidth, _cap(width));
      }
      used += childWidth;
      height = math.max(height, heightOf(child, childWidth));
    }
    return math.max(
      height,
      heightOf(_title, math.max<double>(0, width - used)),
    );
  }

  // Layout.

  _Layout _layout(BoxConstraints constraints, ChildLayouter layoutChild) {
    final maxWidth = constraints.maxWidth;
    // Like a Row with centered children: loose height.
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    final sizes = <_Slot, Size>{};
    var used = _gaps;
    for (final slot in _slots) {
      if (slot == _Slot.title) {
        continue;
      }
      final size = layoutChild(
        childForSlot(slot)!,
        loose.copyWith(
          maxWidth: slot == _Slot.trailing ? _cap(maxWidth) : maxWidth,
        ),
      );
      sizes[slot] = size;
      used += size.width;
    }
    // The title fills the rest, like Expanded (loose when unbounded).
    final title = maxWidth.isFinite
        ? loose.tighten(width: math.max<double>(0, maxWidth - used))
        : loose;
    final titleSize = layoutChild(_title, title);
    sizes[_Slot.title] = titleSize;
    final width = maxWidth.isFinite ? maxWidth : used + titleSize.width;
    final height = sizes.values.fold<double>(
      0,
      (h, s) => math.max(h, s.height),
    );
    return (
      size: constraints.constrain(Size(width, height)),
      sizes: sizes,
      title: title,
      used: used,
    );
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _layout(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final layout = _layout(constraints, ChildLayoutHelper.dryLayoutChild);
    final distance = _title.getDryBaseline(layout.title, baseline);
    return distance == null
        ? null
        : distance +
              (layout.size.height - layout.sizes[_Slot.title]!.height) / 2;
  }

  @override
  void performLayout() {
    final layout = _layout(constraints, ChildLayoutHelper.layoutChild);
    size = layout.size;
    final maxWidth = constraints.maxWidth;
    _overflow = maxWidth.isFinite ? math.max(0, layout.used - maxWidth) : 0;
    final rtl = _textDirection == TextDirection.rtl;
    var x = 0.0;
    for (final slot in _slots) {
      final childSize = layout.sizes[slot]!;
      (childForSlot(slot)!.parentData! as BoxParentData).offset = Offset(
        rtl ? size.width - x - childSize.width : x,
        (size.height - childSize.height) / 2,
      );
      x += childSize.width + _gap;
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final title = _title;
    final distance = title.getDistanceToActualBaseline(baseline);
    return distance == null
        ? null
        : distance + (title.parentData! as BoxParentData).offset.dy;
  }

  // Paint and hit testing.

  @override
  void paint(PaintingContext context, Offset offset) {
    for (final child in children) {
      context.paintChild(
        child,
        (child.parentData! as BoxParentData).offset + offset,
      );
    }
    // Debug only, like RenderFlex: the slots run past the end (text
    // direction) of the row.
    assert(() {
      if (_overflow > precisionErrorTolerance) {
        final overflowRect = _textDirection == TextDirection.rtl
            ? Rect.fromLTWH(-_overflow, 0, size.width + _overflow, 0)
            : Rect.fromLTWH(0, 0, size.width + _overflow, 0);
        paintOverflowIndicator(
          context,
          offset,
          Offset.zero & size,
          overflowRect,
        );
      }
      return true;
    }(), 'debug overflow indicator');
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    for (final child in children) {
      final hit = result.addWithPaintOffset(
        offset: (child.parentData! as BoxParentData).offset,
        position: position,
        hitTest: (result, transformed) =>
            child.hitTest(result, position: transformed),
      );
      if (hit) {
        return true;
      }
    }
    return false;
  }
}
