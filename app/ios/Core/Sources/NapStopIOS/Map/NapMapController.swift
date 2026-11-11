// Thin MapKit view of the NapStop map (docs/specs/T23.3.md §4.2, D4, D6–D13, D17; ADR-002 §3.4). It only applies the state
// and camera frames Dart sends and reports gestures; every decision stays in Dart.
// APIs (developer.apple.com, checked 2026-11-07):
//   MKMapView https://developer.apple.com/documentation/mapkit/mkmapview (setVisibleMapRect(_:edgePadding:animated:),
//     cameraBoundary, cameraZoomRange, convert(_:toCoordinateFrom:), showsUserLocation, showsCompass)
//   MKMapView.CameraBoundary https://developer.apple.com/documentation/mapkit/mkmapview/cameraboundary-swift.class
//   MKMapView.CameraZoomRange https://developer.apple.com/documentation/mapkit/mkmapview/camerazoomrange-swift.class
//   setCameraBoundary(_:animated:) https://developer.apple.com/documentation/mapkit/mkmapview/setcameraboundary(_:animated:)
//   setCameraZoomRange(_:animated:) https://developer.apple.com/documentation/mapkit/mkmapview/setcamerazoomrange(_:animated:)
//   mapViewDidChangeVisibleRegion(_:) https://developer.apple.com/documentation/mapkit/mkmapviewdelegate/mapviewdidchangevisibleregion(_:)
//   MKPointAnnotation https://developer.apple.com/documentation/mapkit/mkpointannotation
//   MKMarkerAnnotationView https://developer.apple.com/documentation/mapkit/mkmarkerannotationview
//   MKAnnotationView.isDraggable https://developer.apple.com/documentation/mapkit/mkannotationview/isdraggable
//   mapView(_:annotationView:didChange:fromOldState:)
//     https://developer.apple.com/documentation/mapkit/mkmapviewdelegate/mapview(_:annotationview:didchange:fromoldstate:)
//   MKCircle https://developer.apple.com/documentation/mapkit/mkcircle,
//   MKCircleRenderer https://developer.apple.com/documentation/mapkit/mkcirclerenderer
// PRIVACY: never logs (MC06 scans this file); the user's location stays in MapKit and is never sent to Dart.
#if os(iOS)
import CoreLocation
import MapKit
import UIKit

/// `MKMapView` that reports its first non-empty layout (a frame needs the view's size) and every later size change
/// (D11 layer 1 measures again: rotation, iPad, the screen 4 card).
final class NapMKMapView: MKMapView {
    var onFirstLayout: (() -> Void)?
    var onSizeChange: (() -> Void)?
    private var lastSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let callback = onFirstLayout {
            onFirstLayout = nil
            callback()
        }
        if bounds.size != lastSize {
            lastSize = bounds.size
            onSizeChange?()
        }
    }
}

@MainActor
public final class NapMapController: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
    public let view: MKMapView
    public var onReady: (() -> Void)?
    public var onLongPress: ((MapCoordinate) -> Void)?
    public var onPinDragEnd: ((MapCoordinate) -> Void)?
    public var onLoadFailed: (() -> Void)?

    /// Last state applied (diagnostics read it).
    public private(set) var state: MapStateWire = .empty

    private let accent: UIColor
    private let pinLabel: String
    private let initial: MapBoundsWire
    private let longPressRecognizer = UILongPressGestureRecognizer()
    private var pin: MKPointAnnotation?
    private var circle: MKCircle?
    private var laidOut = false
    private var pendingFrame: MapFrameWire?
    private var readySent = false
    private var loadFailedSent = false
    private var locationManager: CLLocationManager?
    // D11.
    private let centerBounds: MapBoundsWire?
    private let eastLimit: Double?
    private let maxLngSpan: Double?
    private var boundaryEast: Double?
    private var measureScheduled = false
    /// The initial camera (the `initial` box, centered) is re-applied, with no time limit, after every layout, load and
    /// drift until the user acts on the map or Dart frames something (T23.3 round 7: a timed window raced the resizes
    /// of a slow CI runner, MI01 at 102°E on `ci/ios-all-t235b`). See `applyInitialCamera`.
    private var initialCameraPending = true
    private var applyingInitialCamera = false
    private var initialCameraApplyCount = 0
    private static let initialCameraMaxApplies = 24
    private let createdAt = ProcessInfo.processInfo.systemUptime
    private var initialCameraLog: [String] = []
    /// Why the initial camera stopped being re-applied ("frame", "gesture:<recognizer>", "longPress", "pinDrag"); nil
    /// while it is still pending. Only read by the `diagState` command of NAPSTOP_DIAG builds (no logging, MC06).
    public private(set) var initialCameraEndReason: String?
    /// Number of times the initial camera was applied (diagnostics).
    public var initialCameraApplied: Int { initialCameraApplyCount }
    /// "<reason>@<ms since creation>" of the last applications (diagnostics).
    public var initialCameraEvents: [String] { initialCameraLog }
    /// Set while `frame` moves the boundary and the camera together: layer 2 must not undo it half-way.
    private var boundaryUpdatesSuspended = false
    private static let boundaryHysteresis = 0.02
    /// Current `maxCenterCoordinateDistance` (diagnostics).
    public private(set) var maxDistanceM: Double?

    private static let pinReuseId = "napstop.pin"
    /// §2 `ready`: also sent this long after creation when MapKit never finishes loading (Simulator without network).
    private static let readyFallbackNs: UInt64 = 3_000_000_000

    public init(creation: MapCreationWire) {
        let mapView = NapMKMapView(frame: .zero)
        view = mapView
        accent = UIColor(napARGB: creation.accentARGB)
        pinLabel = creation.pinLabel
        initial = creation.initial
        centerBounds = creation.centerBounds
        eastLimit = creation.eastLimit
        maxLngSpan = creation.maxLngSpan
        super.init()
        view.delegate = self
        // D12: no compass, pitch or rotation; Apple's POIs stay (they help find a stop that is not in the dataset).
        view.showsCompass = false
        view.isPitchEnabled = false
        view.isRotateEnabled = false
        view.showsUserLocation = false
        // D11: the boundary limits the CENTER only (layers 2, 3), the zoom range how far out the camera goes (layer 1;
        // the creation value only until the first measure).
        if let c = creation.centerBounds {
            view.cameraBoundary = MKMapView.CameraBoundary(mapRect: Self.mapRect(c))
            boundaryEast = c.e
        }
        if let d = creation.maxDistanceM {
            view.cameraZoomRange = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: d)
            maxDistanceM = d
        }
        // D8: long press, recognized together with the map's own gestures.
        longPressRecognizer.minimumPressDuration = 0.5
        longPressRecognizer.addTarget(self, action: #selector(longPressed(_:)))
        longPressRecognizer.delegate = self
        view.addGestureRecognizer(longPressRecognizer)
        mapView.onFirstLayout = { [weak self] in self?.didFirstLayout() }
        mapView.onSizeChange = { [weak self] in self?.scheduleSpanMeasure() }
        apply(creation.state)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.readyFallbackNs)
            self?.sendReady()
        }
    }

    // MARK: - Dart → native

    /// D6, D7, D12, D13, D17. Never moves the camera.
    public func apply(_ s: MapStateWire) {
        state = s
        view.overrideUserInterfaceStyle = s.dark ? .dark : .light
        applyPin(s)
        applyCircle(s)
        longPressRecognizer.isEnabled = s.longPress
        let showUser = s.showsUser && locationAuthorized()
        if view.showsUserLocation != showUser {
            view.showsUserLocation = showUser
        }
    }

    /// D10. Kept until the view has a size. `includeUser` adds MapKit's user location when it has one.
    public func frame(_ f: MapFrameWire) {
        guard laidOut else {
            pendingFrame = f
            return
        }
        endInitialCamera("frame")
        var rect = Self.mapRect(f.bounds)
        if f.includeUser, view.showsUserLocation, let location = view.userLocation.location {
            rect = rect.union(MKMapRect(origin: MKMapPoint(location.coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let pad = UIEdgeInsets(
            top: CGFloat(f.pad.top), left: CGFloat(f.pad.left), bottom: CGFloat(f.pad.bottom),
            right: CGFloat(f.pad.right))
        // R2-1 (review T23.3): the center boundary follows the span on screen (D11 layer 2); zoomed out it sits west of
        // the eastern stations and MapKit would clamp this frame there. Set it first for the span of the TARGET box.
        guard let c = centerBounds, let limit = eastLimit,
            let target = MapCameraGuard.targetLngSpan(
                rectLngSpan: Self.degrees(rect.size.width), rectHeightLng: Self.degrees(rect.size.height),
                viewWidth: Double(view.bounds.width), viewHeight: Double(view.bounds.height), padTop: f.pad.top,
                padLeft: f.pad.left, padBottom: f.pad.bottom, padRight: f.pad.right)
        else {
            view.setVisibleMapRect(rect, edgePadding: pad, animated: f.animated)
            return
        }
        let east = max(c.w, MapCameraGuard.centerEastLimit(visibleLngSpan: target, capEast: c.e, eastLimit: limit))
        // Raising the boundary while zoomed out: an animation could pass wide AND east (islands in view) on its way;
        // jump instead. Lowering it is always safe to animate.
        var animated = f.animated
        if let current = boundaryEast, east > current + Self.boundaryHysteresis { animated = false }
        boundaryUpdatesSuspended = true
        setBoundaryEast(east, force: true)
        view.setVisibleMapRect(rect, edgePadding: pad, animated: animated)
        boundaryUpdatesSuspended = false
        if !animated { updateCenterBoundary() }
    }

    /// The D8 path from a point of the view: annotation hit → ignored (that is a pin drag), else converted and reported.
    /// Also used by the `diagLongPress` command of the Runner.
    public func longPress(atViewPoint point: CGPoint) {
        guard state.longPress else { return }
        if let hit = view.hitTest(point, with: nil), Self.isInsideAnnotationView(hit) { return }
        let c = view.convert(point, toCoordinateFrom: view)
        guard MapWire.validLatLng(c.latitude, c.longitude) else { return }
        onLongPress?(MapCoordinate(lat: c.latitude, lng: c.longitude))
    }

    /// What the end of a pin drag does (D6), also used by the `diagDragPin` command of the Runner.
    public func endPinDrag(at c: MapCoordinate) {
        guard let p = pin, MapWire.validLatLng(c.lat, c.lng) else { return }
        p.coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
        onPinDragEnd?(c)
    }

    /// The platform view is going away (D17): MapKit stops the location dot, no more callbacks.
    public func shutdown() {
        view.showsUserLocation = false
        view.delegate = nil
        longPressRecognizer.isEnabled = false
        onReady = nil
        onLongPress = nil
        onPinDragEnd = nil
        onLoadFailed = nil
    }

    /// Pins other than MapKit's user location.
    public var pinCount: Int { view.annotations.filter { !($0 is MKUserLocation) }.count }

    // MARK: - MKMapViewDelegate

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation { return nil }
        let marker =
            (mapView.dequeueReusableAnnotationView(withIdentifier: Self.pinReuseId) as? MKMarkerAnnotationView)
            ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: Self.pinReuseId)
        marker.annotation = annotation
        marker.markerTintColor = accent
        marker.canShowCallout = false
        marker.isDraggable = state.pinDraggable
        marker.displayPriority = .required
        marker.isAccessibilityElement = true
        marker.accessibilityLabel = pinLabel
        return marker
    }

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let c = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
        let r = MKCircleRenderer(circle: c)
        r.strokeColor = accent
        r.lineWidth = 2
        r.fillColor = accent.withAlphaComponent(0.08)
        return r
    }

    public func mapView(
        _ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState,
        fromOldState oldState: MKAnnotationView.DragState
    ) {
        switch newState {
        case .ending:
            view.dragState = .none
            endInitialCamera("pinDrag")  // R4-1
            guard let c = view.annotation?.coordinate, MapWire.validLatLng(c.latitude, c.longitude) else { return }
            onPinDragEnd?(MapCoordinate(lat: c.latitude, lng: c.longitude))
        case .canceling:
            view.dragState = .none
        default:
            break
        }
    }

    /// R4-1 (review T23.3): a pan or pinch by the user ends the initial-camera window, so a later size change (rotation,
    /// text size) does not move the camera back to the first box.
    public func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
        if let active = activeGesture() { endInitialCamera("gesture:\(type(of: active))") }
    }

    /// A gesture of the map (its own recognizers live on an internal subview) actually in progress: `.began` or
    /// `.changed` only (CI `ci/ios-all-t233c`: with `.ended` counted too, MI01 was back at 102°E; a recognizer left in
    /// `.ended` most likely ended the window before the D9 resize). `diagState.initialCameraEnd` reports the reason.
    private func activeGesture() -> UIGestureRecognizer? {
        let recognizers = (view.gestureRecognizers ?? []) + view.subviews.flatMap { $0.gestureRecognizers ?? [] }
        return recognizers.first { $0 !== longPressRecognizer && ($0.state == .began || $0.state == .changed) }
    }

    /// The `diagZoomOutAt` command acts like a user gesture (NAPSTOP_DIAG tests only).
    public func cancelInitialCamera(_ reason: String) { endInitialCamera(reason) }

    private func endInitialCamera(_ reason: String) {
        guard initialCameraPending else { return }
        initialCameraPending = false
        initialCameraEndReason = reason
    }

    /// D11 layer 2: lower or raise the east limit of the center with the span now visible.
    public func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        updateCenterBoundary()
        reapplyInitialCameraIfDrifted()
    }

    public func mapViewDidFinishLoadingMap(_ mapView: MKMapView) {
        applyInitialCamera("loaded")
        sendReady()
    }

    public func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
        applyInitialCamera("rendered")
    }

    public func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
        guard !loadFailedSent else { return }
        loadFailedSent = true
        onLoadFailed?()
    }

    // MARK: - UIGestureRecognizerDelegate

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - private

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        endInitialCamera("longPress")  // R4-1: the user acts on the map, never move the camera back
        longPress(atViewPoint: g.location(in: view))
    }

    /// D11 layer 1: after the layout has settled (next main-queue turn), measure the span and the camera distance and
    /// set the largest distance so that the view spans at most `maxLngSpan` degrees. Measured again on every size change.
    private func scheduleSpanMeasure() {
        guard !measureScheduled else { return }
        measureScheduled = true
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.measureScheduled = false
            self.measureSpan()
            self.applyInitialCamera("resize")
        }
    }

    private func measureSpan() {
        guard let maxSpan = maxLngSpan else { return }
        let span = MKCoordinateRegion(view.visibleMapRect).span.longitudeDelta
        guard
            let d = MapCameraGuard.maxDistance(
                currentDistance: view.camera.centerCoordinateDistance, currentLngSpan: span, maxLngSpan: maxSpan),
            let range = MKMapView.CameraZoomRange(maxCenterCoordinateDistance: d)
        else { return }
        maxDistanceM = d
        view.setCameraZoomRange(range, animated: false)
        updateCenterBoundary()
    }

    /// D11 layer 2: east edge of the center boundary = `min(capEast, eastLimit − span / 2)`, never west of its west edge.
    /// Reset only when it moved by more than 0.02° (a boundary change moves the camera, which calls back here).
    private func updateCenterBoundary() {
        guard !boundaryUpdatesSuspended, let c = centerBounds, let limit = eastLimit else { return }
        setBoundaryEast(centerEastBoundary(forSpan: Self.lngSpan(view.visibleMapRect), centerBounds: c, eastLimit: limit))
    }

    /// East edge of the center boundary for a view spanning `span` degrees. The span is capped at `maxLngSpan`: layer 1
    /// keeps the real span below it, so a larger one is a view in transition (resize, first layout) and must not
    /// collapse the boundary onto its west edge, which pinned the camera center at 102°E (CI `ci/ios-all-t235b`, MI01).
    private func centerEastBoundary(forSpan span: Double, centerBounds c: MapBoundsWire, eastLimit limit: Double) -> Double {
        let capped = maxLngSpan.map { min(span, $0) } ?? span
        return max(c.w, MapCameraGuard.centerEastLimit(visibleLngSpan: capped, capEast: c.e, eastLimit: limit))
    }

    private func setBoundaryEast(_ east: Double, force: Bool = false) {
        guard let c = centerBounds else { return }
        if !force, let current = boundaryEast, abs(current - east) <= Self.boundaryHysteresis { return }
        guard let boundary = MKMapView.CameraBoundary(mapRect: Self.mapRect(MapBoundsWire(s: c.s, w: c.w, n: c.n, e: east)))
        else { return }
        boundaryEast = east
        view.setCameraBoundary(boundary, animated: false)
    }

    private static func lngSpan(_ r: MKMapRect) -> Double { MKCoordinateRegion(r).span.longitudeDelta }

    /// Map points as degrees of longitude (Mercator map points are square, so this also measures heights; R3-1).
    private static func degrees(_ mapPoints: Double) -> Double { mapPoints * 360 / MKMapSize.world.width }

    /// Current east edge of the center boundary (diagnostics).
    public var centerBoundaryEast: Double? { boundaryEast }

    private func didFirstLayout() {
        laidOut = true
        applyInitialCamera("layout")
        if let f = pendingFrame {
            pendingFrame = nil
            frame(f)
        }
    }

    /// First CI runs (07/11, MI01/MI05f): a box larger than the zoom range allows (Vietnam on screen 2) set from
    /// `layoutSubviews` left the camera center pinned to the boundary's west edge (102°E). The initial box is applied
    /// with an explicit camera center, and the center boundary first set for the span it will have (as `frame` does,
    /// capped at `maxLngSpan`). Deterministic, not timed: it runs after the first layout, every size change, the map
    /// finishing loading or rendering, and whenever the center drifted from the box, until the user acts on the map or
    /// Dart frames something (`endInitialCamera`). A cap on the number of applications guards against a loop.
    private func applyInitialCamera(_ reason: String) {
        guard initialCameraPending, laidOut, !applyingInitialCamera, view.bounds.width > 0, view.bounds.height > 0,
            initialCameraApplyCount < Self.initialCameraMaxApplies
        else { return }
        applyingInitialCamera = true
        defer { applyingInitialCamera = false }
        initialCameraApplyCount += 1
        let ms = Int((ProcessInfo.processInfo.systemUptime - createdAt) * 1000)
        initialCameraLog.append("\(reason)@\(ms)")
        if initialCameraLog.count > 24 { initialCameraLog.removeFirst() }
        let rect = Self.mapRect(initial)
        if let c = centerBounds, let limit = eastLimit,
            let target = MapCameraGuard.targetLngSpan(
                rectLngSpan: Self.degrees(rect.size.width), rectHeightLng: Self.degrees(rect.size.height),
                viewWidth: Double(view.bounds.width), viewHeight: Double(view.bounds.height), padTop: 0, padLeft: 0,
                padBottom: 0, padRight: 0)
        {
            boundaryUpdatesSuspended = true
            setBoundaryEast(centerEastBoundary(forSpan: target, centerBounds: c, eastLimit: limit), force: true)
        }
        view.setVisibleMapRect(rect, animated: false)
        view.setCamera(
            MKMapCamera(
                lookingAtCenter: Self.initialCenter(initial), fromDistance: view.camera.centerCoordinateDistance, pitch: 0,
                heading: 0),
            animated: false)
        boundaryUpdatesSuspended = false
        updateCenterBoundary()
    }

    /// A region change that is not a user gesture moved the center off the initial box (a layout, a boundary change):
    /// put it back.
    private func reapplyInitialCameraIfDrifted() {
        guard initialCameraPending, laidOut, !applyingInitialCamera, activeGesture() == nil else { return }
        let want = Self.initialCenter(initial)
        let have = view.centerCoordinate
        if abs(have.latitude - want.latitude) > 0.05 || abs(have.longitude - want.longitude) > 0.05 {
            applyInitialCamera("drift")
        }
    }

    private static func initialCenter(_ b: MapBoundsWire) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (b.s + b.n) / 2, longitude: (b.w + b.e) / 2)
    }

    private func sendReady() {
        guard !readySent else { return }
        readySent = true
        onReady?()
    }

    private func applyPin(_ s: MapStateWire) {
        guard let c = s.pin else {
            if let p = pin {
                view.removeAnnotation(p)
                pin = nil
            }
            return
        }
        let coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
        if let p = pin {
            // Only when it moved: no flicker.
            if p.coordinate.latitude != c.lat || p.coordinate.longitude != c.lng {
                p.coordinate = coordinate
            }
            view.view(for: p)?.isDraggable = s.pinDraggable
        } else {
            let p = MKPointAnnotation()
            p.coordinate = coordinate
            pin = p
            view.addAnnotation(p)
        }
    }

    private func applyCircle(_ s: MapStateWire) {
        var wanted: (MapCoordinate, Double)?
        if let c = s.pin, let r = s.radiusM { wanted = (c, r) }
        if let old = circle, let w = wanted, old.radius == w.1, old.coordinate.latitude == w.0.lat,
            old.coordinate.longitude == w.0.lng
        {
            return
        }
        if let old = circle {
            view.removeOverlay(old)
            circle = nil
        }
        if let w = wanted {
            let added = MKCircle(center: CLLocationCoordinate2D(latitude: w.0.lat, longitude: w.0.lng), radius: w.1)
            circle = added
            view.addOverlay(added, level: .aboveRoads)
        }
    }

    /// MapKit draws the location dot only with permission; never asks for it here (screen 0/T17.1 does).
    private func locationAuthorized() -> Bool {
        let manager = locationManager ?? CLLocationManager()
        locationManager = manager
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        default: return false
        }
    }

    static func isInsideAnnotationView(_ v: UIView) -> Bool {
        var current: UIView? = v
        while let c = current {
            if c is MKAnnotationView { return true }
            current = c.superview
        }
        return false
    }

    static func mapRect(_ b: MapBoundsWire) -> MKMapRect {
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: b.n, longitude: b.w))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: b.s, longitude: b.e))
        return MKMapRect(
            x: min(nw.x, se.x), y: min(nw.y, se.y), width: abs(se.x - nw.x), height: abs(se.y - nw.y))
    }

    static func boundsWire(_ r: MKMapRect) -> MapBoundsWire {
        let nw = MKMapPoint(x: r.minX, y: r.minY).coordinate
        let se = MKMapPoint(x: r.maxX, y: r.maxY).coordinate
        return MapBoundsWire(s: se.latitude, w: nw.longitude, n: nw.latitude, e: se.longitude)
    }

    /// Visible area (diagnostics).
    public var visibleBounds: MapBoundsWire { Self.boundsWire(view.visibleMapRect) }
}

extension UIColor {
    convenience init(napARGB argb: UInt32) {
        self.init(
            red: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
    }
}
#endif
