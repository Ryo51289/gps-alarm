import 'dart:async';

import 'package:flutter/services.dart';
import 'package:napstop/core/map/map_wire.dart';

typedef NapMapChannelFactory = MethodChannel Function(int viewId);

MethodChannel _defaultChannel(int viewId) =>
    MethodChannel(napMapChannelName(viewId));

/// Dart end of one MapKit view's channel (T23.3 §3.2, D3). Sends state and
/// camera frames, decodes events. Calls made before [attach] are kept (the
/// last state, the last frame) and sent on attach, state first.
///
/// PRIVACY: never logs a payload; a failed call is reported once, without
/// its content, through the `onChannelError` callback.
final class NapMapController {
  new({
    required this._onEvent,
    required this._onChannelError,
    this._channelFor = _defaultChannel,
  });

  final ValueChanged<NapMapEvent> _onEvent;
  final void Function() _onChannelError;
  final NapMapChannelFactory _channelFor;

  MethodChannel? _channel;
  int? _viewId;
  bool _disposed = false;
  bool _errorReported = false;
  NapMapState? _sent;
  NapMapState? _pendingState;
  NapMapFrame? _pendingFrame;

  /// The platform view id once attached.
  int? get viewId => _viewId;

  bool get isAttached => _channel != null && !_disposed;

  /// The platform view [viewId] exists: listen to it, send what waits.
  void attach(int viewId) {
    if (_disposed || _channel != null) {
      return;
    }
    final channel = _channelFor(viewId);
    _channel = channel;
    _viewId = viewId;
    channel.setMethodCallHandler(_handle);
    final state = _pendingState;
    final frame = _pendingFrame;
    _pendingState = null;
    _pendingFrame = null;
    if (state != null) {
      unawaited(setState(state));
    }
    if (frame != null) {
      unawaited(this.frame(frame));
    }
  }

  /// Skipped when equal to the last state sent.
  Future<void> setState(NapMapState s) async {
    if (_disposed) {
      return;
    }
    final channel = _channel;
    if (channel == null) {
      _pendingState = s;
      return;
    }
    if (s == _sent) {
      return;
    }
    _sent = s;
    try {
      await channel.invokeMethod<void>('setState', s.toWire());
    } on Object {
      // Not applied natively: the next state is sent even if equal.
      if (_sent == s) {
        _sent = null;
      }
      _reportError();
    }
  }

  Future<void> frame(NapMapFrame f) async {
    if (_disposed) {
      return;
    }
    final channel = _channel;
    if (channel == null) {
      _pendingFrame = f;
      return;
    }
    try {
      await channel.invokeMethod<void>('frame', f.toWire());
    } on Object {
      _reportError();
    }
  }

  /// Stops listening; every later call is a no-op.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _channel?.setMethodCallHandler(null);
    _pendingState = null;
    _pendingFrame = null;
  }

  void _reportError() {
    if (_errorReported || _disposed) {
      return;
    }
    _errorReported = true;
    _onChannelError();
  }

  Future<Object?> _handle(MethodCall call) async {
    if (_disposed) {
      return null;
    }
    final event = decodeNapMapEvent(call.method, call.arguments);
    if (event != null) {
      _onEvent(event);
    }
    return null;
  }
}
