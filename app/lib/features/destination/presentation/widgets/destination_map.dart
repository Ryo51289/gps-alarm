import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/features/destination/domain/destination_logic.dart';

/// What the map of screen 2 shows and reports (T23 §9).
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

/// Builds the map; widget tests override it with a fake (no platform view).
final destinationMapBuilderProvider = Provider<DestinationMapBuilder>(
  (ref) =>
      (props) => GoogleDestinationMap(props: props),
);

/// Whole Vietnam, never the user's position (T23 §9).
const CameraPosition _kVietnam = CameraPosition(
  target: LatLng(16, 106),
  zoom: 5,
);

/// Hue of the destination marker (accent blue).
const double _kMarkerHue = 227;

/// Google map with the draggable destination pin and the alarm zone. Only
/// built when the build has a key (T23 D4). The only file importing the map
/// SDK: [MapPoint] and [LatLng] are converted here.
class GoogleDestinationMap extends StatefulWidget {
  const new({required this.props, super.key});

  final DestinationMapProps props;

  @override
  State<GoogleDestinationMap> createState() => _GoogleDestinationMapState();
}

class _GoogleDestinationMapState extends State<GoogleDestinationMap> {
  GoogleMapController? _controller;

  @override
  void didUpdateWidget(GoogleDestinationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.props.cameraRequestId != oldWidget.props.cameraRequestId) {
      unawaited(_frame());
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onCreated(GoogleMapController controller) {
    _controller = controller;
    if (widget.props.point != null) {
      unawaited(_frame());
    }
  }

  Future<void> _frame() async {
    final controller = _controller;
    final point = widget.props.point;
    if (controller == null || point == null) {
      return;
    }
    final (sw, ne) = circleBounds(point, widget.props.radiusM);
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(sw.lat, sw.lng),
            northeast: LatLng(ne.lat, ne.lng),
          ),
          kCameraPaddingPx,
        ),
      );
    } on PlatformException {
      // T29: NonFatalReason.mapsLoadFailed (no telemetry before T29). The
      // screen keeps working without the camera move.
    }
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.props;
    final point = props.point;
    final accent = context.napColors.accent;
    final at = point == null ? null : LatLng(point.lat, point.lng);
    return GoogleMap(
      initialCameraPosition: _kVietnam,
      onMapCreated: _onCreated,
      // Explicit on purpose (T23 §9, privacy): never the user's position.
      // ignore: avoid_redundant_argument_values
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      padding: EdgeInsets.only(bottom: props.bottomPadding),
      // No onTap: a stray tap must never move the destination (T23 D8).
      onLongPress: (p) => props.onLongPress(MapPoint(p.latitude, p.longitude)),
      markers: {
        if (at != null)
          Marker(
            markerId: const MarkerId('dest'),
            position: at,
            draggable: true,
            icon: BitmapDescriptor.defaultMarkerWithHue(_kMarkerHue),
            onDragEnd: (p) =>
                props.onPinDragEnd(MapPoint(p.latitude, p.longitude)),
          ),
      },
      circles: {
        if (at != null)
          Circle(
            circleId: const CircleId('zone'),
            center: at,
            radius: props.radiusM,
            strokeWidth: 2,
            strokeColor: accent,
            fillColor: accent.withValues(alpha: 0.08),
          ),
      },
    );
  }
}
