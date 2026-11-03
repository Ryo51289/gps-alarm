/// Last check before anything reaches the Analytics SDK (T29 §3). Pure Dart.
library;

import 'package:meta/meta.dart';
import 'package:napstop/core/telemetry/analytics/analytics_catalog.dart';
import 'package:napstop/core/telemetry/crash/safe_diagnostic.dart';
import 'package:napstop/core/telemetry/redaction/redactor.dart';

enum ViolationKind {
  unknownEvent,
  invalidEventName,
  tooManyParams,
  unknownParam,
  invalidParamName,
  rejectedValue,
  coordinateLike,
}

/// What the guard refused. Carries names only: never the value.
@immutable
final class GuardViolation implements SafeDiagnostic {
  const new(this.event, this.param, this.kind);

  final String event;
  final String? param;
  final ViolationKind kind;

  @override
  bool operator ==(Object other) =>
      other is GuardViolation &&
      other.event == event &&
      other.param == param &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(event, param, kind);

  @override
  String toString() => 'GuardViolation($event, ${param ?? '-'}, ${kind.name})';
}

/// SDK limit (T29 §2, F5).
const int kMaxEventParams = 25;

final RegExp _name = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');
final RegExp _reservedPrefix = RegExp('^(firebase_|google_|ga_)');

bool _validName(String n) => _name.hasMatch(n) && !_reservedPrefix.hasMatch(n);

/// Null = accepted. Checks, in order: event name (format, then catalog),
/// parameter count, then each parameter (name format, catalog,
/// [looksLikeCoordinate], spec). The event name is checked even if a
/// [catalog] lists it, so a bad catalog entry cannot pass.
GuardViolation? checkAnalyticsEvent(
  String name,
  Map<String, Object> params, {
  Map<String, Map<String, ParamSpec>>? catalog,
}) {
  if (!_validName(name)) {
    return GuardViolation(
      name.length > 40 ? '<long>' : name,
      null,
      ViolationKind.invalidEventName,
    );
  }
  final specs = (catalog ?? kAnalyticsCatalog)[name];
  if (specs == null) {
    return GuardViolation(name, null, ViolationKind.unknownEvent);
  }
  if (params.length > kMaxEventParams) {
    return GuardViolation(name, null, ViolationKind.tooManyParams);
  }
  for (final MapEntry(:key, :value) in params.entries) {
    if (!_validName(key)) {
      return GuardViolation(
        name,
        key.length > 40 ? '<long>' : key,
        ViolationKind.invalidParamName,
      );
    }
    final spec = specs[key];
    if (spec == null) {
      return GuardViolation(name, key, ViolationKind.unknownParam);
    }
    if (looksLikeCoordinate(value)) {
      return GuardViolation(name, key, ViolationKind.coordinateLike);
    }
    if (!spec.accepts(value)) {
      return GuardViolation(name, key, ViolationKind.rejectedValue);
    }
  }
  return null;
}

/// True for any `double`, a string holding a decimal number with 3 or more
/// fractional digits, or a string with a coordinate key name next to a
/// number (patterns in redactor.dart).
bool looksLikeCoordinate(Object value) {
  if (value is double) {
    return true;
  }
  if (value is String) {
    return kCoordinateNumberPattern.hasMatch(value) ||
        kCoordinateKeyPattern.hasMatch(value);
  }
  return false;
}
