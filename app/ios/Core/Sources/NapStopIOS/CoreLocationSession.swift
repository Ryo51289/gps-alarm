// Continuous Core Location session for one trip (docs/specs/T17.md D8, §5.4). Never logs coordinates.
#if os(iOS)
import CoreLocation
import Foundation
import Trip
import TripRuntime

public final class CoreLocationSession: NSObject, LocationSession, CLLocationManagerDelegate, @unchecked Sendable {
    private var manager: CLLocationManager?
    private var backgroundSession: AnyObject?  // CLBackgroundActivitySession (iOS 17+)
    private weak var sink: LocationSink?
    private var lastCause: AvailabilityCause = .available
    private var running = false

    public override init() { super.init() }

    /// `UIBackgroundModes` must contain `location`, else setting allowsBackgroundLocationUpdates is fatal [CL-BG].
    static func hasLocationBackgroundMode() -> Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") ?? false
    }

    static func desired(_ a: LocationAccuracyClass) -> CLLocationAccuracy {
        switch a {
        case .hundredMeters: return kCLLocationAccuracyHundredMeters
        case .nearestTenMeters: return kCLLocationAccuracyNearestTenMeters
        case .best: return kCLLocationAccuracyBest
        }
    }

    public func start(_ spec: LocationRequestSpec, sink: LocationSink) async throws {
        guard Self.hasLocationBackgroundMode() else { throw LocationStartError.backgroundModeMissing }
        guard CLLocationManager.locationServicesEnabled() else { throw LocationStartError.servicesOff }
        try await MainActor.run {
            let m = manager ?? CLLocationManager()
            let status = m.authorizationStatus
            guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw LocationStartError.notAuthorized }
            m.delegate = self
            m.activityType = .otherNavigation
            m.distanceFilter = kCLDistanceFilterNone
            m.desiredAccuracy = Self.desired(spec.accuracy)
            m.pausesLocationUpdatesAutomatically = false
            m.allowsBackgroundLocationUpdates = true
            if #available(iOS 17.0, *), backgroundSession == nil {
                backgroundSession = CLBackgroundActivitySession()
            }
            self.sink = sink
            manager = m
            running = true
            lastCause = .available
            m.startUpdatingLocation()
        }
    }

    public func retune(_ spec: LocationRequestSpec) async {
        await MainActor.run { manager?.desiredAccuracy = Self.desired(spec.accuracy) }
    }

    public func stop() async {
        await MainActor.run {
            manager?.stopUpdatingLocation()
            manager?.allowsBackgroundLocationUpdates = false
            if #available(iOS 17.0, *) { (backgroundSession as? CLBackgroundActivitySession)?.invalidate() }
            backgroundSession = nil
            running = false
            sink = nil
        }
    }

    public func isRunning() async -> Bool { await MainActor.run { running } }

    public func lastKnown() async -> RawFix? {
        await MainActor.run { (manager ?? CLLocationManager()).location.map(Self.raw) }
    }

    static func raw(_ l: CLLocation) -> RawFix {
        RawFix(lat: l.coordinate.latitude, lng: l.coordinate.longitude, horizontalAccuracyM: l.horizontalAccuracy,
               speedMps: l.speed, timestampWallMs: Int64((l.timestamp.timeIntervalSince1970 * 1000).rounded(.down)))
    }

    // MARK: CLLocationManagerDelegate (main thread)

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let sink else { return }
        for l in locations.sorted(by: { $0.timestamp < $1.timestamp }) { sink.locationSession(didReceive: Self.raw(l)) }
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { recompute(manager) }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { recompute(manager) }
    }

    /// Reduced accuracy alone is not a revocation (§5.4).
    private func recompute(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let allowed = status == .authorizedWhenInUse || status == .authorizedAlways
        let sink = self.sink
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let services = CLLocationManager.locationServicesEnabled()
            let cause = LocationAccess(whenInUseOrAlways: allowed, fullAccuracy: true, servicesEnabled: services).availability
            DispatchQueue.main.async {
                guard let self, cause != self.lastCause else { return }
                self.lastCause = cause
                sink?.locationSession(availabilityChanged: cause)
            }
        }
    }
}
#endif
