import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/features/destination/presentation/widgets/apple_destination_map.dart';

/// What the map of screen 2 shows and reports (T23 §9). The contract every
/// map implementation follows (MapKit on iOS from T23.3, ADR-002).
@immutable
final class DestinationMapProps {
  const new({
    required this.point,
    required this.radiusM,
    required this.cameraRequestId,
    required this.framePadding,
    required this.onLongPress,
    required this.onPinDragEnd,
  });

  /// The pin, or null when nothing is chosen.
  final MapPoint? point;

  /// Alarm zone radius around [point].
  final double radiusM;

  /// A new value asks the camera to frame [point] and its zone.
  final int cameraRequestId;

  /// Edge insets used when framing [point] (T23.3 §3.1
  /// `destinationFramePadding`): what the top bar, the badge and the panel
  /// cover, plus a margin. Since T23.3 the map ends at the lowest resting
  /// position of the panel (D9), so this no longer keeps any logo visible.
  final MapPadding framePadding;
  final ValueChanged<MapPoint> onLongPress;
  final ValueChanged<MapPoint> onPinDragEnd;

  @override
  String toString() => 'DestinationMapProps($cameraRequestId)';
}

typedef DestinationMapBuilder = Widget Function(DestinationMapProps props);

/// Builds the map of screen 2: Apple MapKit on iOS (T23.3), null elsewhere
/// (no map on Android until T23.4): screen 2 then shows
/// `MapUnavailablePlaceholder` (T23.2 D4). Widget tests override it with a
/// fake (no platform view).
final destinationMapBuilderProvider = Provider<DestinationMapBuilder?>(
  (ref) => defaultTargetPlatform == TargetPlatform.iOS
      ? (props) => AppleDestinationMap(props: props)
      : null,
);
