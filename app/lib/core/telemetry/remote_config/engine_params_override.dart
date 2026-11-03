/// Remote Config `trip_engine_params`, pure part (T29 §6, T25 §2.3). T29's
/// `EngineParamsSource` imports this file and implements
/// [EngineParamsReader]; the API here does not change.
///
/// PRIVACY: never log [EngineParamsOverride.json] (T29 §6).
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:napstop/core/telemetry/remote_config/strict_json.dart';
import 'package:napstop/core/text/kotlin_blank.dart';

const String kTripEngineParamsKey = 'trip_engine_params';

/// Longest accepted value, UTF-16 code units (T14 V11).
const int kEngineParamsMaxChars = 16384;

/// The active value of `trip_engine_params`, read once per trip setup.
@immutable
final class EngineParamsOverride {
  const new({required this.json, required this.id});

  /// Sent verbatim as `TripConfigMsg.engineParamsJson`; null means engine
  /// defaults (T10 §5).
  final String? json;

  /// 'default' | 'invalid' | [fnv1a32Hex] of [json]: `trip_start.params_id`
  /// and the `engine_params_id` custom key.
  final String id;

  static const EngineParamsOverride defaults = EngineParamsOverride(
    json: null,
    id: 'default',
  );

  static const EngineParamsOverride invalid = EngineParamsOverride(
    json: null,
    id: 'invalid',
  );

  @override
  bool operator ==(Object other) =>
      other is EngineParamsOverride && other.json == json && other.id == id;

  @override
  int get hashCode => Object.hash(json, id);

  @override
  String toString() => 'EngineParamsOverride($id)';
}

/// T29 §6: blank (Kotlin `isBlank`, like the engine) →
/// [EngineParamsOverride.defaults]; longer than [kEngineParamsMaxChars] or
/// not a JSON object → [EngineParamsOverride.invalid]; otherwise
/// `raw` verbatim with its hash.
///
/// "JSON object" uses the engine grammar ([parseStrictJson]), so a value the
/// engine would reject as malformed is never sent as if it applied.
EngineParamsOverride parseEngineParamsOverride(String raw) {
  if (isBlankLikeKotlin(raw)) {
    return EngineParamsOverride.defaults;
  }
  if (raw.length > kEngineParamsMaxChars) {
    return EngineParamsOverride.invalid;
  }
  try {
    if (parseStrictJson(raw) is! Map<String, Object?>) {
      return EngineParamsOverride.invalid;
    }
  } on FormatException {
    return EngineParamsOverride.invalid;
  }
  return EngineParamsOverride(json: raw, id: fnv1a32Hex(raw));
}

/// FNV-1a 32 bit over the UTF-8 bytes of [s], 8 lower-case hex digits.
String fnv1a32Hex(String s) {
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(s)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// Implemented by T29's `EngineParamsSource`. [current] is synchronous.
abstract interface class EngineParamsReader {
  EngineParamsOverride current();
}

/// Always the engine defaults (tests, or a build without Remote Config).
final class DefaultEngineParamsReader implements EngineParamsReader {
  const new();

  @override
  EngineParamsOverride current() => EngineParamsOverride.defaults;
}
