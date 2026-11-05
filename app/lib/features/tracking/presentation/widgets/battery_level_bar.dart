import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Battery level with the "alarm" zone (T26 §4.6): 10 px track (r4), the
/// level in `danger`, then the zone 0..[alarmPct] drawn **over** it in
/// `dangerContainer` (the wireframe's #F8C9C5 has no token of its own) and
/// a 2×18 marker at [alarmPct], so the zone stays visible whatever the level
/// (review T26 #2). Decorative: the sheet subtitle already reads the level.
class BatteryLevelBar extends StatelessWidget {
  const new({required this.levelPct, required this.alarmPct, super.key});

  final int levelPct;
  final int alarmPct;

  static const double _height = 10;
  static const Size _markerSize = Size(2, 18);

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    Widget part(double fraction, Color color) => Align(
      alignment: AlignmentDirectional.centerStart,
      child: FractionallySizedBox(
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(
          height: _height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(NapRadii.r4),
          ),
        ),
      ),
    );
    final zone = (alarmPct / 100).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: SizedBox(
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
            part(levelPct / 100, c.danger),
            part(zone, c.dangerContainer.withValues(alpha: 0.7)),
            Align(
              alignment: AlignmentDirectional(zone * 2 - 1, 0),
              child: Container(
                width: _markerSize.width,
                height: _markerSize.height,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
