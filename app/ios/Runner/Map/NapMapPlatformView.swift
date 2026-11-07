import CoreLocation
import Flutter
import MapKit
import NapStopIOS
import UIKit

/// Factory of the MapKit platform view `app.napstop/nap_map` (docs/specs/T23.3.md §4.3, D1–D3), registered in
/// `AppDelegate.didInitializeImplicitFlutterEngine`. Flutter docs "Hosting native iOS views"
/// (https://docs.flutter.dev/platform-integration/ios/platform-views): `FlutterPlatformViewFactory`
/// (https://api.flutter.dev/ios-embedder/protocol_flutter_platform_view_factory-p.html), creation params decoded by
/// `createArgsCodec`. Flutter creates and disposes platform views on the platform (main) thread.
final class NapMapViewFactory: NSObject, FlutterPlatformViewFactory {
  static let pluginKey = "NapStopMap"

  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    NapMapPlatformView(frame: frame, viewId: viewId, args: args, messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

/// One map: a `NapMapController` (package NapStopIOS) and its own channel `app.napstop/nap_map/<viewId>` (D3, no Pigeon:
/// T14 D5). Invalid messages are ignored (§2). The `diag*` commands exist only with NAPSTOP_DIAG (Debug and the
/// diagnostic IPA): the compilation condition of the Runner does not reach the local package, so they live here (RK2).
/// PRIVACY: never logs a payload or a coordinate.
final class NapMapPlatformView: NSObject, FlutterPlatformView {
  private let controller: NapMapController
  private let mapView: UIView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, args: Any?, messenger: FlutterBinaryMessenger) {
    // Invalid creation params: Vietnam, nothing chosen; never a crash.
    let creation = MapWire.creation(args) ?? .fallback
    let channel = FlutterMethodChannel(name: MapWire.channelName(viewId), binaryMessenger: messenger)
    let controller = MainActor.assumeIsolated { () -> NapMapController in
      let c = NapMapController(creation: creation)
      c.view.frame = frame
      c.onReady = { channel.invokeMethod("ready", arguments: nil) }
      c.onLongPress = { p in channel.invokeMethod("longPress", arguments: MapWire.pointArgs(p)) }
      c.onPinDragEnd = { p in channel.invokeMethod("pinDragEnd", arguments: MapWire.pointArgs(p)) }
      c.onLoadFailed = { channel.invokeMethod("loadFailed", arguments: nil) }
      return c
    }
    self.controller = controller
    self.mapView = MainActor.assumeIsolated { controller.view }
    self.channel = channel
    super.init()
    channel.setMethodCallHandler { call, result in
      MainActor.assumeIsolated { NapMapPlatformView.handle(controller, call, result) }
    }
  }

  func view() -> UIView { mapView }

  deinit {
    channel.setMethodCallHandler(nil)
    let c = controller
    if Thread.isMainThread {
      MainActor.assumeIsolated { c.shutdown() }
    } else {
      DispatchQueue.main.async { MainActor.assumeIsolated { c.shutdown() } }
    }
  }

  @MainActor
  private static func handle(_ controller: NapMapController, _ call: FlutterMethodCall, _ result: FlutterResult) {
    switch call.method {
    case "setState":
      if let s = MapWire.state(call.arguments) { controller.apply(s) }
      result(nil)
    case "frame":
      if let f = MapWire.frame(call.arguments) { controller.frame(f) }
      result(nil)
    default:
      #if NAPSTOP_DIAG
        if diag(controller, call, result) { return }
      #endif
      result(FlutterMethodNotImplemented)
    }
  }

  #if NAPSTOP_DIAG
    /// Integration tests on the Simulator (MI01–MI06): drive the D8/D6 paths and read the native state.
    @MainActor
    private static func diag(_ controller: NapMapController, _ call: FlutterMethodCall, _ result: FlutterResult) -> Bool {
      let map = controller.view
      switch call.method {
      case "diagLongPress":
        guard let c = MapWire.coordinate(call.arguments) else {
          result(FlutterError(code: "bad-args", message: nil, details: nil))
          return true
        }
        // Same path as a finger: coordinate → point of the view → D8 (annotation check, convert back).
        let point = map.convert(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng), toPointTo: map)
        controller.longPress(atViewPoint: point)
        result(nil)
      case "diagDragPin":
        guard let c = MapWire.coordinate(call.arguments) else {
          result(FlutterError(code: "bad-args", message: nil, details: nil))
          return true
        }
        controller.endPinDrag(at: c)
        result(nil)
      case "diagZoomOutAt":
        guard let c = MapWire.coordinate(call.arguments) else {
          result(FlutterError(code: "bad-args", message: nil, details: nil))
          return true
        }
        // Far beyond the zoom range: MapKit clamps it to cameraBoundary / cameraZoomRange (D11).
        let camera = MKMapCamera(
          lookingAtCenter: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng), fromDistance: 50_000_000,
          pitch: 0, heading: 0)
        map.setCamera(camera, animated: false)
        result(nil)
      case "diagState":
        let state = controller.state
        let center = map.centerCoordinate
        result([
          "annotations": controller.pinCount,
          "overlays": map.overlays.count,
          "radiusM": state.radiusM.map { $0 as Any } ?? NSNull(),
          "pinDraggable": state.pinDraggable,
          "showsUser": map.showsUserLocation,
          "visible": MapWire.boundsArgs(controller.visibleBounds),
          "center": [center.latitude, center.longitude],
          "distanceM": map.camera.centerCoordinateDistance,
          "maxDistanceM": controller.maxDistanceM.map { $0 as Any } ?? NSNull(),
          "boundaryEast": controller.centerBoundaryEast.map { $0 as Any } ?? NSNull(),
          "initialCameraEnd": controller.initialCameraEndReason.map { $0 as Any } ?? NSNull(),
          "pin": state.pin.map { MapWire.pointArgs($0) as Any } ?? NSNull(),
        ] as [String: Any])
      default:
        return false
      }
      return true
    }
  #endif
}
