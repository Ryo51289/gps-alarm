import 'package:flutter/material.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_view.dart';
import 'package:napstop/features/destination/presentation/widgets/destination_map.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Native state of the screen 2 map for [props] (T23.3 §3.3): draggable pin
/// and long press, never the user's location (T23 §9); a bus glyph in the
/// pin of a bus stop (T24.3 §6.6).
NapMapState destinationMapState(
  DestinationMapProps props, {
  required bool dark,
}) {
  final point = props.point;
  return NapMapState(
    pin: point,
    radiusM: point == null ? null : props.radiusM,
    pinDraggable: true,
    longPress: true,
    dark: dark,
    glyph: point != null && props.busStop ? MapPinGlyph.bus : null,
  );
}

/// Camera frame of the current choice, null without one.
NapMapFrame? destinationMapFrame(DestinationMapProps props) {
  final point = props.point;
  return point == null
      ? null
      : NapMapFrame(
          bounds: frameBounds(point, props.radiusM),
          padding: props.framePadding,
        );
}

/// The screen 2 map on iOS: [DestinationMapProps] → [NapMapView].
class AppleDestinationMap extends StatelessWidget {
  const new({required this.props, this.controllerFactory, super.key});

  final DestinationMapProps props;

  /// Tests only (MA04).
  final NapMapControllerFactory? controllerFactory;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final point = props.point;
    return NapMapView(
      state: destinationMapState(
        props,
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
      initial: point == null
          ? kVietnamBounds
          : frameBounds(point, props.radiusM),
      frame: destinationMapFrame(props),
      frameRequestId: props.cameraRequestId,
      semanticLabel: l.destinationMapA11yLabel,
      pinLabel: l.mapPinA11yLabel,
      onLongPress: props.onLongPress,
      onPinDragEnd: props.onPinDragEnd,
      controllerFactory: controllerFactory,
    );
  }
}
