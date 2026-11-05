import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Trip progress with the alarm marker (T26 §5 block 4), drawn with tokens:
/// 10 px track (r4), travelled part in `accent` (`textSecondary` while
/// estimated), a 2×18 marker in `textPrimary` with a caption under it.
class TripProgressBar extends StatelessWidget {
  const new({
    required this.progress,
    required this.semanticLabel,
    this.marker,
    this.markerLabel,
    this.estimated = false,
    super.key,
  });

  /// 0..1 (clamped).
  final double progress;

  /// 0..1; null hides the marker.
  final double? marker;

  /// "Báo".
  final String? markerLabel;
  final bool estimated;
  final String semanticLabel;

  static const double _height = 10;
  static const Size _markerSize = Size(2, 18);

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    final marker = this.marker?.clamp(0.0, 1.0);
    final markerLabel = this.markerLabel;
    final bar = SizedBox(
      height: _markerSize.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: _height,
            decoration: BoxDecoration(
              color: c.track,
              borderRadius: BorderRadius.circular(NapRadii.r4),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                height: _height,
                decoration: BoxDecoration(
                  color: estimated ? c.textSecondary : c.accent,
                  borderRadius: BorderRadius.circular(NapRadii.r4),
                ),
              ),
            ),
          ),
          if (marker != null)
            Align(
              alignment: AlignmentDirectional(marker * 2 - 1, 0),
              child: Container(
                width: _markerSize.width,
                height: _markerSize.height,
                color: c.textPrimary,
              ),
            ),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar,
            if (marker != null && markerLabel != null)
              Align(
                alignment: AlignmentDirectional(marker * 2 - 1, 0),
                child: Text(
                  markerLabel,
                  style: context
                      .napStyle(NapTypography.caption)
                      .copyWith(color: c.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
