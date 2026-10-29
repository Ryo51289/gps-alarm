import CoreLocation
import Foundation

/// CLLocationManager wrapper (S3 §6.4). Delegate API on purpose: T17 can reuse it on iOS 16.
///
/// Privacy (D4): coordinates stay in memory (`lastLocation`, for the distance between fixes and the S3-13 walk centre);
/// only accuracy, speed, age and distance are logged.
/// Created on the main thread, so delegate callbacks arrive on the main thread.
final class LocationRecorder: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()

    /// Called on the main thread after each batch of fixes, with the time of the callback.
    var onFix: ((Date) -> Void)?
    var onAuthChange: (() -> Void)?

    private(set) var running = false
    private(set) var phase: Phase = .dense
    private(set) var fixCount = 0
    private(set) var lastLocation: CLLocation?

    private var session: CLBackgroundActivitySession?
    private let events = EventLog.shared

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .otherNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUse() { manager.requestWhenInUseAuthorization() }

    func requestAlways() { manager.requestAlwaysAuthorization() }

    /// Starts continuous updates. Call while the app is in the foreground (CLBackgroundActivitySession, When In Use).
    func start(phase: Phase) {
        self.phase = phase
        manager.desiredAccuracy = Self.accuracy(phase)
        manager.allowsBackgroundLocationUpdates = true
        if session == nil { session = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
        running = true
        events.log("loc_start", [
            "phase": .str(phase.rawValue), "accuracy": .str(Self.accuracyName(phase)), "bgSession": .flag(session != nil),
        ])
    }

    func setPhase(_ phase: Phase) {
        self.phase = phase
        manager.desiredAccuracy = Self.accuracy(phase)
    }

    func stop() {
        guard running || session != nil else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        session?.invalidate()
        session = nil
        running = false
        lastLocation = nil
        events.log("loc_stop", ["phase": .str(phase.rawValue), "accuracy": .str(Self.accuracyName(phase)), "bgSession": false])
    }

    static func accuracy(_ phase: Phase) -> CLLocationAccuracy {
        phase == .dense ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
    }

    static func accuracyName(_ phase: Phase) -> String {
        phase == .dense ? "best" : "hundredMeters"
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let now = Date()
        for location in locations {
            fixCount += 1
            let distance = lastLocation.map { location.distance(from: $0) }
            lastLocation = location
            let speed: Double? = location.speed >= 0 ? location.speed : nil
            events.log("fix", [
                "n": .num(fixCount),
                "acc": .num((location.horizontalAccuracy * 10).rounded() / 10),
                "spd": .num(speed.map { ($0 * 10).rounded() / 10 }),
                "ageMs": .num(Int(now.timeIntervalSince(location.timestamp) * 1000)),
                "dM": .num(distance.map { ($0 * 10).rounded() / 10 }),
            ])
        }
        onFix?(now)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let ns = error as NSError
        events.log("loc_error", ["code": .num(ns.code), "msg": .str(ns.domain)])
    }

    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        events.log("loc_paused")
    }

    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        events.log("loc_resumed")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        events.log("auth_change", [
            "status": .str(StatusNames.location(manager.authorizationStatus)),
            "accuracy": .str(StatusNames.accuracy(manager.accuracyAuthorization)),
        ])
        onAuthChange?()
    }
}
