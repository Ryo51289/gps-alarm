import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:napstop/core/design/design.dart';
import 'package:napstop/core/map/map_geometry.dart';
import 'package:napstop/core/map/map_wire.dart';
import 'package:napstop/core/map/nap_map_controller.dart';
import 'package:napstop/core/telemetry/telemetry.dart';
import 'package:napstop/core/telemetry/telemetry_providers.dart';

/// Builds the controller of a [NapMapView] (tests give it a fake channel).
typedef NapMapControllerFactory = NapMapController Function({
  required ValueChanged<NapMapEvent> onEvent,
  required void Function() onChannelError,
});

NapMapController _defaultController({
  required ValueChanged<NapMapEvent> onEvent,
  required void Function() onChannelError,
}) => NapMapController(onEvent: onEvent, onChannelError: onChannelError);

/// Every touch inside the map belongs to the map (D14): screen 4 scrolls,
/// the panel of screen 2 drags.
final Set<Factory<OneSequenceGestureRecognizer>> _eagerGestures = {
  const Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
};

/// Apple MapKit map, iOS only (T23.3 D1, ADR-002): a `UiKitView` of the
/// `MKMapView` registered by the Runner. Native only applies [state] and
/// [frame] and reports events (D4).
///
/// [state] changes are sent when they differ from the last one; [frame] is
/// sent when [frameRequestId] changes. [initial], [centerBounds],
/// [maxDistanceM], [eastLimit], [maxLngSpan], the accent colour and
/// [pinLabel] only count at creation.
class NapMapView extends ConsumerStatefulWidget {
  const new({
    required this.state,
    required this.initial,
    required this.semanticLabel,
    required this.pinLabel,
    this.frame,
    this.frameRequestId = 0,
    this.centerBounds = kCameraCenterBounds,
    this.maxDistanceM = kMaxCameraDistanceM,
    this.eastLimit = kVisibleEastLimitLng,
    this.maxLngSpan = kMaxVisibleLngSpan,
    this.onLongPress,
    this.onPinDragEnd,
    this.onReady,
    this.controllerFactory,
    super.key,
  });

  final NapMapState state;
  final MapBounds initial;
  final NapMapFrame? frame;
  final int frameRequestId;
  final MapBounds? centerBounds;

  /// D11 layer 1: starting largest camera distance (native measures and
  /// replaces it when [maxLngSpan] is set).
  final double? maxDistanceM;

  /// D11: the visible east edge never passes this longitude (layer 2).
  final double? eastLimit;

  /// D11 layer 1: widest visible longitude span.
  final double? maxLngSpan;
  final String semanticLabel;
  final String pinLabel;
  final ValueChanged<MapPoint>? onLongPress;
  final ValueChanged<MapPoint>? onPinDragEnd;
  final VoidCallback? onReady;
  final NapMapControllerFactory? controllerFactory;

  @override
  ConsumerState<NapMapView> createState() => NapMapViewState();
}

class NapMapViewState extends ConsumerState<NapMapView> {
  late final NapMapController _controller;
  late final AppLifecycleListener _lifecycle;
  bool _failureReported = false;
  bool _ready = false;

  /// Integration tests (MI*) send the `diag*` calls on this view's channel.
  @visibleForTesting
  int? get viewId => _controller.viewId;

  /// The native view reported `ready` (MI01).
  @visibleForTesting
  bool get isReady => _ready;

  @override
  void initState() {
    super.initState();
    final factory = widget.controllerFactory ?? _defaultController;
    _controller = factory(onEvent: _onEvent, onChannelError: _onChannelError);
    // Kept until the view exists, then sent (same as the creation params,
    // so the native side ignores nothing it needs).
    unawaited(_controller.setState(widget.state));
    _lifecycle = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void didUpdateWidget(NapMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state != oldWidget.state) {
      unawaited(_controller.setState(widget.state));
    }
    final frame = widget.frame;
    if (frame != null && widget.frameRequestId != oldWidget.frameRequestId) {
      unawaited(_controller.frame(frame));
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// D17: no location dot while the app is hidden. Sent directly: Flutter
  /// draws no frame while hidden, so a rebuild would not reach the view.
  void _onHide() {
    if (widget.state.showsUser) {
      unawaited(_controller.setState(widget.state.copyWith(showsUser: false)));
    }
  }

  void _onShow() => unawaited(_controller.setState(widget.state));

  void _onEvent(NapMapEvent e) {
    if (!mounted) {
      return;
    }
    switch (e) {
      case NapMapReady():
        _ready = true;
        widget.onReady?.call();
      case NapMapLongPress(:final at):
        widget.onLongPress?.call(at);
      case NapMapPinDragEnd(:final at):
        widget.onPinDragEnd?.call(at);
      case NapMapLoadFailed():
        _reportFailure(const NapMapLoadError());
    }
  }

  void _onChannelError() => _reportFailure(const NapMapChannelError());

  /// D15: once per view, type only. The screen keeps working.
  void _reportFailure(Object error) {
    if (_failureReported || !mounted) {
      return;
    }
    _failureReported = true;
    try {
      ref
          .read(telemetryProvider)
          .crash
          .recordNonFatal(
            error,
            StackTrace.current,
            NonFatalReason.mapsLoadFailed,
          );
    } on Object {
      // Telemetry never breaks the map.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      container: true,
      child: UiKitView(
        viewType: kNapMapViewType,
        creationParams: creationParams(
          state: widget.state,
          initial: widget.initial,
          centerBounds: widget.centerBounds,
          maxDistanceM: widget.maxDistanceM,
          eastLimit: widget.eastLimit,
          maxLngSpan: widget.maxLngSpan,
          accentArgb: context.napColors.accent.toARGB32(),
          pinLabel: widget.pinLabel,
        ),
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: _eagerGestures,
        onPlatformViewCreated: _controller.attach,
      ),
    );
  }
}

/// D15: MapKit could not load map data. Reported by type only (not a
/// `SafeDiagnostic`: no message is sent).
final class NapMapLoadError implements Exception {
  const new();
}

/// D15: a call on the map channel failed (`PlatformException`,
/// `MissingPluginException`). Reported by type only.
final class NapMapChannelError implements Exception {
  const new();
}
