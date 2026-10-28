/// Anchor grammar for expectation windows (spec T02 §6.6).
///
/// ```text
/// anchor := "start" | "end" | "arrival" | "overshoot"
///         | "gpsGap[" <int> "]." ("start" | "end")
///         | ("route" | "straight") "<=" <int metres>
/// ```
library;

/// Kind of an [Anchor].
enum AnchorKind {
  start,
  end,
  arrival,
  overshoot,
  gpsGapStart,
  gpsGapEnd,
  routeWithin,
  straightWithin,
}

/// Error raised when an anchor cannot be parsed or resolved.
final class AnchorException implements Exception {
  const new(this.message);

  final String message;

  @override
  String toString() => 'AnchorException: $message';
}

final RegExp _gap = RegExp(r'^gpsGap\[(0|[1-9]\d*)\]\.(start|end)$');
final RegExp _within = RegExp(r'^(route|straight)<=(0|[1-9]\d*)$');

/// Parsed anchor; [text] keeps the original spelling for `window`.
final class Anchor {
  const new(this.text, this.kind, [this.value = 0]);

  /// Parses [text]; throws [AnchorException] on a grammar error.
  factory parse(String text) {
    switch (text) {
      case 'start':
        return Anchor(text, AnchorKind.start);
      case 'end':
        return Anchor(text, AnchorKind.end);
      case 'arrival':
        return Anchor(text, AnchorKind.arrival);
      case 'overshoot':
        return Anchor(text, AnchorKind.overshoot);
    }
    final gap = _gap.firstMatch(text);
    if (gap != null) {
      final index = int.tryParse(gap.group(1)!);
      if (index == null) {
        throw AnchorException('gap index too large in "$text"');
      }
      return Anchor(
        text,
        gap.group(2) == 'start' ? AnchorKind.gpsGapStart : AnchorKind.gpsGapEnd,
        index,
      );
    }
    final within = _within.firstMatch(text);
    if (within != null) {
      final metres = int.tryParse(within.group(2)!);
      if (metres == null) {
        throw AnchorException('distance too large in "$text"');
      }
      return Anchor(
        text,
        within.group(1) == 'route'
            ? AnchorKind.routeWithin
            : AnchorKind.straightWithin,
        metres,
      );
    }
    throw AnchorException(
      'invalid anchor "$text" (expected start, end, arrival, overshoot, '
      'gpsGap[i].start, gpsGap[i].end, route<=M or straight<=M)',
    );
  }

  final String text;
  final AnchorKind kind;

  /// Gap index for `gpsGap[i]`, metres for `route<=` / `straight<=`.
  final int value;
}
