/// Errors raised by the native core (spec T14 §4). Same wire codes as
/// Kotlin `BridgeErrors`.
library;

enum BridgeErrorCode {
  invalidConfig('invalid-config'),
  tripActive('trip-active'),
  simulationUnavailable('simulation-unavailable'),
  permissionMissing('permission-missing'),
  notForeground('not-foreground'),
  startFailed('start-failed'),
  requestInProgress('request-in-progress'),
  internal('internal'),

  /// Pigeon: no handler on the native side.
  channelError('channel-error'),
  unknown('');

  new(this.wire);

  final String wire;

  /// The code for [code], or [unknown] if it is not one of ours.
  static BridgeErrorCode fromWire(String code) {
    for (final c in values) {
      if (c != unknown && c.wire == code) {
        return c;
      }
    }
    return unknown;
  }
}

/// A failed bridge call. [toString] prints the raw code only: [message] and
/// [details] may name fields of the trip.
final class BridgeException implements Exception {
  const new(this.code, {required this.rawCode, this.message, this.details});

  final BridgeErrorCode code;
  final String rawCode;
  final String? message;
  final Object? details;

  @override
  String toString() => 'BridgeException($rawCode)';
}
