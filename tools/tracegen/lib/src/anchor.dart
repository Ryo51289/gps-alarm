/// Anchor grammar for expectation windows and time points (spec T02 §6.6,
/// T11 §2.3).
///
/// ```text
/// staticAnchor := "start" | "end" | "arrival" | "overshoot"
///               | "gpsGap[" <int> "]." ("start" | "end")
///               | ("route" | "straight") "<=" <int metres>
///               | "closest" | "closest.departT" | "kill"
/// runAnchor    := "event:" <event name> | "relaunch" | "osFallbackFired"
/// ```
library;

/// Event names of the fixture schema (v1 plus the T11 additions, T10 §2.3).
const List<String> kEventNames = [
  'preAlert',
  'alarm',
  'snoozed',
  'gpsLost',
  'gpsRecovered',
  'lowBatteryRisk',
  'overshoot',
  'arrived',
  'fallbackAlarmChanged',
  'samplingPolicyChanged',
  'tripEnded',
];

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
  closest,
  closestDepart,
  kill,
  event,
  relaunch,
  osFallbackFired,
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
const String _eventPrefix = 'event:';

/// Parsed anchor; [text] keeps the original spelling for `window`.
final class Anchor {
  const new(this.text, this.kind, [this.value = 0]);

  /// Parses [text]; throws [AnchorException] on a grammar error or an
  /// unknown event name.
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
      case 'closest':
        return Anchor(text, AnchorKind.closest);
      case 'closest.departT':
        return Anchor(text, AnchorKind.closestDepart);
      case 'kill':
        return Anchor(text, AnchorKind.kill);
      case 'relaunch':
        return Anchor(text, AnchorKind.relaunch);
      case 'osFallbackFired':
        return Anchor(text, AnchorKind.osFallbackFired);
    }
    if (text.startsWith(_eventPrefix)) {
      final name = text.substring(_eventPrefix.length);
      if (!kEventNames.contains(name)) {
        throw AnchorException('unknown event "$name" in "$text"');
      }
      return Anchor(text, AnchorKind.event);
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
      'gpsGap[i].start, gpsGap[i].end, route<=M, straight<=M, closest, '
      'closest.departT, kill, event:<name>, relaunch or osFallbackFired)',
    );
  }

  final String text;
  final AnchorKind kind;

  /// Gap index for `gpsGap[i]`, metres for `route<=` / `straight<=`.
  final int value;

  /// Whether the value is only known while running the engine.
  bool get isRun =>
      kind == AnchorKind.event ||
      kind == AnchorKind.relaunch ||
      kind == AnchorKind.osFallbackFired;

  /// Event name of an `event:<name>` anchor.
  String get eventName => text.substring(_eventPrefix.length);
}

/// Where an anchor is used (T11 §2.3 table).
enum AnchorUse {
  /// `expect[].notBefore/notAfter`.
  window,

  /// `expectFallback.modeAt`.
  modeAt,

  /// `gpsGaps[].until`.
  gapUntil,

  /// `config.kill`.
  kill,

  /// `config.actions[].at`.
  action,

  /// `config.relaunch.at`.
  relaunch,

  /// `expectAfter[].after`, `forbidAfter[].after`.
  after,

  /// `killSweep.from`, `killSweep.notAfter`, `killSweep.earlyFrom`
  /// (T11.1 §2): static anchors except `kill`.
  killSweep,
}

/// Error message when [anchor] may not be used in [use], or null.
String? anchorUseError(Anchor anchor, AnchorUse use) {
  final k = anchor.kind;
  final name = '"${anchor.text}"';
  switch (use) {
    case AnchorUse.window:
    case AnchorUse.modeAt:
      return anchor.isRun ? 'run-time anchor $name is not allowed here' : null;
    case AnchorUse.gapUntil:
      if (anchor.isRun ||
          k == AnchorKind.gpsGapStart ||
          k == AnchorKind.gpsGapEnd ||
          k == AnchorKind.kill ||
          k == AnchorKind.closest ||
          k == AnchorKind.closestDepart) {
        return 'anchor $name is not allowed in gpsGaps[].until';
      }
      return null;
    case AnchorUse.kill:
      if (anchor.isRun || k == AnchorKind.kill) {
        return 'anchor $name is not allowed in config.kill';
      }
      return null;
    case AnchorUse.action:
      return k == AnchorKind.osFallbackFired
          ? 'anchor $name is not allowed in config.actions'
          : null;
    case AnchorUse.relaunch:
      return k == AnchorKind.relaunch
          ? 'anchor $name is not allowed in config.relaunch'
          : null;
    case AnchorUse.after:
      return null;
    case AnchorUse.killSweep:
      if (anchor.isRun || k == AnchorKind.kill) {
        return 'anchor $name is not allowed in killSweep';
      }
      return null;
  }
}

/// Error message when a run-time [anchor] in an input (`config.actions[].at`,
/// `config.relaunch.at`) has `offsetS < sampleIntervalS`, or null (T11 §2.3,
/// review T11 #2). Checks (`expectAfter`, `forbidAfter`) are not inputs and
/// may use any offset.
String? inputRunOffsetError(
  Anchor anchor,
  AnchorUse use,
  int offsetS,
  int sampleIntervalS,
) {
  final input = use == AnchorUse.action || use == AnchorUse.relaunch;
  if (!input || !anchor.isRun || offsetS >= sampleIntervalS) {
    return null;
  }
  return 'run anchor in an input requires offsetS >= sampleIntervalS '
      '($sampleIntervalS)';
}
