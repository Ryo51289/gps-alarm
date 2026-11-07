import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

/// What the map of screen 2 shows and reports (T23 §9). The contract every
/// map implementation follows (MapKit on iOS from T23.3, ADR-002).
@immutable
final class DestinationMapProps {
  const new({
    required this.point,
    required this.radiusM,
    required this.cameraRequestId,
    required this.bottomPadding,
    required this.onLongPress,
    required this.onPinDragEnd,
  });

  /// The pin, or null when nothing is chosen.
  final MapPoint? point;

  /// Alarm zone radius around [point].
  final double radiusM;

  /// A new value asks the camera to frame [point] and its zone.
  final int cameraRequestId;

  /// Height of the panel over the bottom of the map.
  final double bottomPadding;
  final ValueChanged<MapPoint> onLongPress;
  final ValueChanged<MapPoint> onPinDragEnd;

  @override
  String toString() => 'DestinationMapProps($cameraRequestId)';
}

typedef DestinationMapBuilder = Widget Function(DestinationMapProps props);

/// Builds the map of screen 2, or null when this platform has none yet:
/// screen 2 then shows `MapUnavailablePlaceholder` (T23.2 D4). Null on every
/// platform since Google Maps was removed (ADR-002); widget tests override it
/// with a fake (no platform view).
final destinationMapBuilderProvider = Provider<DestinationMapBuilder?>(
  (ref) => null,
);
