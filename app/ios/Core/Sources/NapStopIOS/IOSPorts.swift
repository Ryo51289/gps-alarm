// Small iOS port implementations (docs/specs/T17.md §2): time, app state, device env, wake timer, background tasks.
// Swift 5 language mode (D1). Everything Apple-only is inside `#if os(iOS)`.
#if os(iOS)
import CoreLocation
import Darwin
import Foundation
import Trip
import TripRuntime
import UIKit
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Runs `body` on the main thread and returns its value (UIKit state).
func onMainSync<T>(_ body: () -> T) -> T {
    if Thread.isMainThread { return body() }
    return DispatchQueue.main.sync(execute: body)
}

/// Wall clock + ContinuousClock (continues while asleep [SW-CC]) + boot session id (D16).
public struct IOSTime: TimeSource {
    public init() {}

    public func wallMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }

    public func elapsedMs() -> Int64 {
        let clock = ContinuousClock()
        let d = clock.systemEpoch.duration(to: clock.now)
        let c = d.components
        return c.seconds * 1000 + c.attoseconds / 1_000_000_000_000_000
    }

    /// `kern.bootsessionuuid` (undocumented; nil → §5.3 fallback rule, RK-T17-8).
    public func bootSessionId() -> String? {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buf, &size, nil, 0) == 0 else { return nil }
        let s = String(cString: buf)
        return s.isEmpty ? nil : s
    }
}

public struct IOSAppState: AppStatePort {
    public init() {}
    public func activity() async -> AppActivity {
        await MainActor.run {
            switch UIApplication.shared.applicationState {
            case .active: return .active
            case .inactive: return .inactive
            case .background: return .background
            @unknown default: return .background
            }
        }
    }
}

public final class IOSDeviceEnv: DeviceEnv, @unchecked Sendable {
    /// One manager, touched only on the main thread (review #16).
    private var manager: CLLocationManager?

    public init() {}

    public func locationAccess() async -> LocationAccess {
        let services = CLLocationManager.locationServicesEnabled()  // never on main (§5.4)
        let (status, accuracy) = await MainActor.run { () -> (CLAuthorizationStatus, CLAccuracyAuthorization) in
            let m = self.manager ?? CLLocationManager()
            self.manager = m
            return (m.authorizationStatus, m.accuracyAuthorization)
        }
        return LocationAccess(whenInUseOrAlways: status == .authorizedWhenInUse || status == .authorizedAlways,
                              fullAccuracy: accuracy == .fullAccuracy, servicesEnabled: services)
    }

    public func channelAccess() async -> ChannelAccess {
        var ak = AlarmKitAuth.unavailable
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            switch AlarmManager.shared.authorizationState {
            case .authorized: ak = .authorized
            case .denied: ak = .denied
            case .notDetermined: ak = .notDetermined
            @unknown default: ak = .denied
            }
        }
        #endif
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let notif = settings.authorizationStatus == .authorized || settings.authorizationStatus == .ephemeral
        return ChannelAccess(alarmKit: ak, notifications: notif)
    }

    public func battery() async -> BatteryReading? {
        await MainActor.run {
            let d = UIDevice.current
            if !d.isBatteryMonitoringEnabled { d.isBatteryMonitoringEnabled = true }
            guard (0...1).contains(d.batteryLevel) else { return nil }
            let charging = d.batteryState == .charging || d.batteryState == .full
            return BatteryReading(levelPct: Int((d.batteryLevel * 100).rounded()), charging: charging)
        }
    }
}

/// Diagnostics fake alarm port (§5.13, IC04): the fake is the alarm channel, so the channel check of `startTrip` (D14)
/// must not depend on the Simulator's AlarmKit / notification permission.
public final class FakeChannelEnv: DeviceEnv, @unchecked Sendable {
    let base: DeviceEnv
    public init(base: DeviceEnv) { self.base = base }
    public func locationAccess() async -> LocationAccess { await base.locationAccess() }
    public func channelAccess() async -> ChannelAccess { ChannelAccess(alarmKit: .authorized, notifications: false) }
    public func battery() async -> BatteryReading? { await base.battery() }
}

/// In-process timer for the engine wake (D11). Fires `onFire(generation)` on a utility queue.
public final class DispatchWakeTimer: WakeTimer, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.napstop.trip.timer", qos: .utility)
    private let lock = NSLock()
    private var source: DispatchSourceTimer?
    var onFire: (@Sendable (Int64) -> Void)?

    public init() {}

    public func set(delayMs: Int64, generation: Int64) {
        lock.lock()
        source?.cancel()
        let s = DispatchSource.makeTimerSource(queue: queue)
        s.schedule(deadline: .now() + .milliseconds(Int(max(0, delayMs))), leeway: .milliseconds(100))
        s.setEventHandler { [weak self] in self?.onFire?(generation) }
        source = s
        lock.unlock()
        s.resume()
    }

    public func cancel() {
        lock.lock()
        source?.cancel()
        source = nil
        lock.unlock()
    }
}

public struct TaskSleeper: RuntimeSleeper {
    public init() {}
    public func sleep(ms: Int64) async { try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000) }
}

/// UIApplication.beginBackgroundTask (keeps the CPU while an alarm is being scheduled, S3 decision 6).
public final class UIKitBackgroundTasks: BackgroundTasks, @unchecked Sendable {
    private let lock = NSLock()
    private var next = 1
    private var ids: [Int: UIBackgroundTaskIdentifier] = [:]

    public init() {}

    public func begin(_ name: String) -> Int {
        lock.lock()
        let token = next
        next += 1
        lock.unlock()
        let id = onMainSync {
            UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in self?.end(token) }
        }
        if id == .invalid { return 0 }
        lock.lock()
        ids[token] = id
        lock.unlock()
        return token
    }

    public func end(_ token: Int) {
        lock.lock()
        let id = ids.removeValue(forKey: token)
        lock.unlock()
        guard let id else { return }
        onMainSync { UIApplication.shared.endBackgroundTask(id) }
    }
}
#endif
