import 'package:flutter/material.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_view.dart';
import 'package:napstop/l10n/gen/app_localizations.dart';

/// Radius framed by the card when the trip has no alarm zone (time and
/// smart modes, T23.3 §3.4).
const double kCardFrameRadiusM = 2000;

/// Card height: 32 % of the screen, between 200 and 320 pt (§3.4).
double trackingMapCardHeight(double screenHeight) =>
    (screenHeight * 0.32).clamp(200, 320).toDouble();

/// Native state of the screen 4 map: fixed pin, circle in distance mode,
/// MapKit's own location dot only when [showsUser] (D17).
NapMapState trackingMapState({
  required MapPoint destination,
  required double? radiusM,
  required bool showsUser,
  required bool dark,
}) => NapMapState(
  pin: destination,
  radiusM: radiusM,
  showsUser: showsUser,
  dark: dark,
);

/// Camera frame of the card: the destination and its zone; with
/// [includeUser] MapKit adds the user's location (it never reaches Dart).
NapMapFrame trackingMapFrame({
  required MapPoint destination,
  required double? radiusM,
  required bool includeUser,
  required bool animated,
}) => NapMapFrame(
  bounds: frameBounds(destination, radiusM ?? kCardFrameRadiusM),
  padding: const (
    top: kCameraPaddingPt,
    left: kCameraPaddingPt,
    bottom: kCameraPaddingPt,
    right: kCameraPaddingPt,
  ),
  animated: animated,
  includeUser: includeUser,
);

/// Screen 4 map card, iOS only (T23.3 Phần B, PO Q1 = A). The camera frames
/// the destination; the user's location is framed only after "Vị trí của
/// tôi" (ADR-002 §6.2).
class TrackingMapCard extends StatefulWidget {
  const new({
    required this.destination,
    required this.radiusM,
    required this.showsUser,
    required this.simulated,
    this.controllerFactory,
    super.key,
  });

  final MapPoint destination;

  /// Alarm zone (distance mode), else null: no circle.
  final double? radiusM;

  /// Real trip, location allowed and app visible.
  final bool showsUser;
  final bool simulated;

  /// Tests only.
  final NapMapControllerFactory? controllerFactory;

  @override
  State<TrackingMapCard> createState() => _TrackingMapCardState();
}

class _TrackingMapCardState extends State<TrackingMapCard> {
  NapMapFrame? _frame;
  int _frameRequestId = 0;
  bool _framedOnReady = false;

  void _requestFrame({required bool includeUser, required bool animated}) {
    setState(() {
      _frame = trackingMapFrame(
        destination: widget.destination,
        radiusM: widget.radiusM,
        includeUser: includeUser,
        animated: animated,
      );
      _frameRequestId++;
    });
  }

  void _onReady() {
    if (_framedOnReady || !mounted) {
      return;
    }
    _framedOnReady = true;
    _requestFrame(includeUser: false, animated: false);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.napColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NapSpace.s8,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(NapRadii.r16),
          child: SizedBox(
            height: trackingMapCardHeight(MediaQuery.sizeOf(context).height),
            child: NapMapView(
              state: trackingMapState(
                destination: widget.destination,
                radiusM: widget.radiusM,
                showsUser: widget.showsUser,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
              initial: frameBounds(
                widget.destination,
                widget.radiusM ?? kCardFrameRadiusM,
              ),
              frame: _frame,
              frameRequestId: _frameRequestId,
              maxDistanceM: kMaxCardCameraDistanceM,
              semanticLabel: l.trackingMapA11yLabel,
              pinLabel: l.mapPinA11yLabel,
              onReady: _onReady,
              controllerFactory: widget.controllerFactory,
            ),
          ),
        ),
        if (widget.simulated)
          Text(
            l.trackingMapSimulatedNote,
            style: context.napText.bodySmall!.copyWith(color: c.textSecondary),
          )
        else if (widget.showsUser)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: NapButton(
              label: l.trackingMapMyLocation,
              variant: NapButtonVariant.secondary,
              size: NapButtonSize.small,
              icon: NapIcons.gps,
              onPressed: () => _requestFrame(includeUser: true, animated: true),
            ),
          ),
      ],
    );
  }
}
