/// Screen 8 "Chỉ đường quay lại" (T27 §4.4): the Google Maps URL, the
/// `/overshoot` query and the auto-open rule. Pure.
library;

import 'package:meta/meta.dart';
import 'package:napstop/app/router/app_routes.dart';
import 'package:napstop/core/trip/domain/trip_record.dart';

/// Largest `past` accepted in the `/overshoot` query (1 000 km), as natively.
const int kOvershootPastMax = 1000000;

/// D12: auto-open Maps only for a trip started this recently (T10 §4.13 cap).
const Duration kAutoOpenMaxAge = Duration(hours: 48);

final RegExp _tripIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Whether [id] is a valid trip id (same rule as native `validTripId`).
bool isValidTripId(String? id) => id != null && _tripIdPattern.hasMatch(id);

/// Maps URLs directions to the destination (D8): no origin (Maps uses the
/// device location), no travel mode. Null when lat/lng are not finite or
/// out of range. Fixed 6 decimals with '.', whatever the locale.
///
/// PRIVACY: the URI holds the destination coordinates — never log it, never
/// put it in telemetry.
Uri? routeBackUri(double lat, double lng) {
  if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
    return null;
  }
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
  });
}

/// Location of the Flutter fallback of screen 5 (D10): `/alarm?trip=<id>`.
String alarmFallbackLocation(String tripId) =>
    Uri(path: AppRoutes.alarm, queryParameters: {'trip': tripId}).toString();

/// D12: auto-open only for a recent trip.
bool mayAutoOpen(TripRecord? r, DateTime now) =>
    r != null &&
    now.millisecondsSinceEpoch - r.startedAtMs <=
        kAutoOpenMaxAge.inMilliseconds;

/// Query of `/overshoot` (D9): `?trip=<id>[&past=<m>][&open=1]`.
///
/// PRIVACY: [toString] prints neither the trip id nor the distance.
@immutable
final class OvershootArgs {
  const new({required this.tripId, this.pastM, this.autoOpen = false});

  /// Trip of the screen; its destination is read from drift (D7).
  final String tripId;

  /// Metres past the destination when the alarm was dismissed; null =
  /// unknown.
  final int? pastM;

  /// Open Google Maps once on arrival (from "Xem đường quay lại", D12).
  final bool autoOpen;

  /// Null when `trip` is missing or not a valid id. A `past` that is not an
  /// integer in 0..[kOvershootPastMax] reads as unknown.
  static OvershootArgs? fromUri(Uri uri) {
    final q = uri.queryParameters;
    final trip = q['trip'];
    if (!isValidTripId(trip)) {
      return null;
    }
    final past = int.tryParse(q['past'] ?? '');
    return OvershootArgs(
      tripId: trip!,
      pastM: past != null && past >= 0 && past <= kOvershootPastMax
          ? past
          : null,
      autoOpen: q['open'] == '1',
    );
  }

  /// The `/overshoot` location of these arguments.
  String toLocation() => Uri(
    path: AppRoutes.overshoot,
    queryParameters: {
      'trip': tripId,
      'past': ?pastM?.toString(),
      if (autoOpen) 'open': '1',
    },
  ).toString();

  @override
  bool operator ==(Object other) =>
      other is OvershootArgs &&
      other.tripId == tripId &&
      other.pastM == pastM &&
      other.autoOpen == autoOpen;

  @override
  int get hashCode => Object.hash(tripId, pastM, autoOpen);

  @override
  String toString() =>
      'OvershootArgs(past: ${pastM == null ? 'unset' : 'set'}, '
      'open: $autoOpen)';
}
