// Raw permission reads and prompts for `IOSPermissionHostApi` (docs/specs/T17.1.md §3, D2–D4, D7; T21 §9).
// Swift 5 language mode (D1 of T17). Everything Apple-only is inside `#if os(iOS)`.
// PRIVACY: never logs a position, a distance or station coordinates; errors are logged by type name only.
#if os(iOS)
import CoreLocation
import Foundation
import os
import TripRuntime
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

public final class PermissionProbe: NSObject, PermissionProbing, CLLocationManagerDelegate, @unchecked Sendable {
    private let logger = Logger(subsystem: "app.napstop", category: "permission")
    /// Own manager (D3), created and touched on the main thread only; its delegate calls arrive there too.
    private var manager: CLLocationManager?
    /// Callers waiting for the location dialog, by token. Main thread only.
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]
    private var nextWaiter = 0

    public override init() { super.init() }

    /// Main thread only.
    private func locationManager() -> CLLocationManager {
        if let m = manager { return m }
        let m = CLLocationManager()
        m.delegate = self
        manager = m
        return m
    }

    /// `locationServicesEnabled()` may block: never on the main thread (D2).
    private static func servicesEnabled() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .userInitiated).async { c.resume(returning: CLLocationManager.locationServicesEnabled()) }
        }
    }

    static func location(_ s: CLAuthorizationStatus) -> LocationAuthRaw {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedWhenInUse: return .whenInUse
        case .authorizedAlways: return .always
        @unknown default: return .denied
        }
    }

    static func notifications(_ s: UNAuthorizationStatus) -> NotificationAuthRaw {
        switch s {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .denied
        }
    }

    /// Same reading as `IOSDeviceEnv.channelAccess()` (T17).
    static func alarmKit() -> AlarmKitAuth {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: return .authorized
            case .denied: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .denied
            }
        }
        #endif
        return .unavailable
    }

    public func readings() async -> PermissionReadings {
        let services = await Self.servicesEnabled()
        let (status, accuracy) = await MainActor.run { () -> (CLAuthorizationStatus, CLAccuracyAuthorization) in
            let m = self.locationManager()
            return (m.authorizationStatus, m.accuracyAuthorization)
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return PermissionReadings(location: Self.location(status), accuracy: accuracy == .fullAccuracy ? .full : .reduced,
                                  servicesEnabled: services, notifications: Self.notifications(settings.authorizationStatus),
                                  alarmKit: Self.alarmKit())
    }

    /// When In Use only, never Always [CL-AUTH]. Already determined: returns at once (iOS does not ask twice).
    public func requestLocation(timeoutMs: Int64) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                let m = self.locationManager()
                guard m.authorizationStatus == .notDetermined else {
                    c.resume()
                    return
                }
                let token = self.nextWaiter
                self.nextWaiter += 1
                self.waiters[token] = c
                m.requestWhenInUseAuthorization()
                // RK-T171-1: the delegate may never be called (the user left the app); answer the status as it is.
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(max(0, timeoutMs)))) {
                    self.waiters.removeValue(forKey: token)?.resume()
                }
            }
        }
    }

    public func requestNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("notification request failed (\(String(describing: type(of: error)), privacy: .public))")
        }
    }

    public func requestAlarmKit() async {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            do {
                _ = try await AlarmManager.shared.requestAuthorization()
            } catch {
                logger.error("alarm request failed (\(String(describing: type(of: error)), privacy: .public))")
            }
        }
        #endif
    }

    public func lastKnown() async -> (fix: RawFix?, authorized: Bool, servicesEnabled: Bool) {
        let services = await Self.servicesEnabled()
        return await MainActor.run { () -> (fix: RawFix?, authorized: Bool, servicesEnabled: Bool) in
            let m = self.locationManager()
            let s = m.authorizationStatus
            let authorized = s == .authorizedWhenInUse || s == .authorizedAlways
            // Any accuracy level counts (D7), like COARSE on Android.
            return (authorized ? m.location.map(CoreLocationSession.raw) : nil, authorized, services)
        }
    }

    public func distancesM(from fix: RawFix, to pairs: [Double]) -> [Double] {
        let from = CLLocation(latitude: fix.lat, longitude: fix.lng)
        return stride(from: 0, to: pairs.count - 1, by: 2).map { i in
            from.distance(from: CLLocation(latitude: pairs[i], longitude: pairs[i + 1]))
        }
    }

    // MARK: CLLocationManagerDelegate (main thread)

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined, !waiters.isEmpty else { return }
        let ready = waiters.values
        waiters.removeAll()
        for c in ready { c.resume() }
    }
}
#endif
