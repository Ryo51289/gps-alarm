import 'package:meta/meta.dart';

/// A WGS84 point. The map widget converts it to and from the platform type
/// (moved here from `destination_logic.dart` by T23.3, re-exported there).
@immutable
final class MapPoint {
  const new(this.lat, this.lng);

  final double lat;
  final double lng;

  @override
  bool operator ==(Object other) =>
      other is MapPoint && other.lat == lat && other.lng == lng;

  @override
  int get hashCode => Object.hash(lat, lng);

  /// PRIVACY: no coordinates.
  @override
  String toString() => 'MapPoint';
}
