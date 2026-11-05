import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';

/// Released at or past this fraction of the track, the swipe counts
/// (= `SWIPE_COMPLETE_FRACTION` of the native screen, T16).
const double kSwipeCompleteFraction = 0.95;

/// "Vuốt hết thanh để tắt" of the Flutter alarm screen (T27 §8). Dragging
/// the knob to the end calls [onComplete]; false (or a throw) slides it back.
/// TalkBack: one action labelled [semanticsLabel] does the same.
final class SwipeToStopBar extends StatefulWidget {
  const new({
    required this.hint,
    required this.semanticsLabel,
    required this.onComplete,
    super.key,
  });

  /// Text in the track.
  final String hint;

  /// Label of the accessibility action.
  final String semanticsLabel;

  /// The swipe is complete; true when the alarm was stopped.
  final Future<bool> Function() onComplete;

  @override
  State<SwipeToStopBar> createState() => _SwipeToStopBarState();
}

const double _kTrackHeight = 72;
const double _kKnob = 60;
const double _kInset = (_kTrackHeight - _kKnob) / 2;

class _SwipeToStopBarState extends State<SwipeToStopBar> {
  double _fraction = 0;
  bool _busy = false;

  /// The pointer of the current drag was cancelled, not lifted.
  bool _pointerCancelled = false;

  Future<void> _complete() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _fraction = 1;
    });
    var ok = false;
    try {
      ok = await widget.onComplete();
    } on Object {
      ok = false;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (!ok) {
        _fraction = 0;
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails d, double travel) {
    if (_busy || travel <= 0) {
      return;
    }
    setState(() {
      _fraction = (_fraction + d.delta.dx / travel).clamp(0.0, 1.0);
    });
  }

  void _onDragCancel() {
    if (!_busy) {
      setState(() => _fraction = 0);
    }
  }

  void _onDragEnd() {
    if (_busy) {
      return;
    }
    if (_fraction >= kSwipeCompleteFraction && !_pointerCancelled) {
      unawaited(_complete());
    } else {
      setState(() => _fraction = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.napColors;
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticsLabel,
      hint: widget.hint,
      onTap: _busy ? null : () => unawaited(_complete()),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final travel = constraints.maxWidth - _kKnob - 2 * _kInset;
            // A pointer cancelled by the system (call, system gesture) ends
            // the drag through onEnd too: it must not count as a release.
            return Listener(
              onPointerDown: (_) => _pointerCancelled = false,
              onPointerCancel: (_) => _pointerCancelled = true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // The knob follows the finger from the touch down.
                dragStartBehavior: DragStartBehavior.down,
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, travel),
                onHorizontalDragEnd: (_) => _onDragEnd(),
                // Review T27 #5: a cancelled gesture (call, system gesture) is
                // not a release: the knob slides back.
                onHorizontalDragCancel: _onDragCancel,
                child: Container(
                  constraints: const BoxConstraints(minHeight: _kTrackHeight),
                  decoration: BoxDecoration(
                    color: c.track,
                    borderRadius: BorderRadius.circular(NapRadii.pill),
                  ),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: _kKnob + 2 * _kInset + NapSpace.s8,
                          right: NapSpace.s16,
                          top: NapSpace.s8,
                          bottom: NapSpace.s8,
                        ),
                        child: Text(
                          widget.hint,
                          style: context.napText.titleSmall?.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Positioned(
                        left: _kInset + _fraction * (travel < 0 ? 0 : travel),
                        child: Container(
                          width: _kKnob,
                          height: _kKnob,
                          decoration: BoxDecoration(
                            color: c.alarmAccent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: c.onAlarmAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
