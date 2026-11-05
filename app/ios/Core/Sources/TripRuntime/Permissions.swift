// iOS permission contract and last-known distance, pure parts (docs/specs/T17.1.md §2; T21 §9; T23). The Apple side
// (`NapStopIOS.PermissionProbe`) only reads raw values; the Runner (`IOSPermissionHostApi`) copies the DTO into Pigeon.
import Foundation

/// Raw platform readings, no Apple types (filled by NapStopIOS.PermissionProbe).
public enum LocationAuthRaw: Sendable, Equatable, CaseIterable { case notDetermined, restricted, denied, whenInUse, always }
public enum AccuracyRaw: Sendable, Equatable, CaseIterable { case full, reduced }
public enum NotificationAuthRaw: Sendable, Equatable, CaseIterable { case notDetermined, denied, authorized, provisional, ephemeral }

public struct PermissionReadings: Sendable, Equatable {
    public let location: LocationAuthRaw
    public let accuracy: AccuracyRaw
    /// CLLocationManager.locationServicesEnabled(), never read on main.
    public let servicesEnabled: Bool
    public let notifications: NotificationAuthRaw
    /// Ports.swift (T17): unavailable on iOS < 26.
    public let alarmKit: AlarmKitAuth

    public init(location: LocationAuthRaw, accuracy: AccuracyRaw, servicesEnabled: Bool, notifications: NotificationAuthRaw,
                alarmKit: AlarmKitAuth) {
        self.location = location
        self.accuracy = accuracy
        self.servicesEnabled = servicesEnabled
        self.notifications = notifications
        self.alarmKit = alarmKit
    }

    /// The same readings as the T17 runtime sees them (`IOSDeviceEnv`): one source of truth for `startTrip` and screen 0.
    public var locationAccess: LocationAccess {
        LocationAccess(whenInUseOrAlways: location == .whenInUse || location == .always, fullAccuracy: accuracy == .full,
                       servicesEnabled: servicesEnabled)
    }

    public var channelAccess: ChannelAccess {
        ChannelAccess(alarmKit: alarmKit, notifications: notifications == .authorized || notifications == .ephemeral)
    }
}

/// Mirrors PermissionStatusMsg (names = Pigeon case names).
public enum LocationAccessDTO: String, Sendable, Equatable { case notDetermined, denied, whileInUse, always }
public enum PermissionStateDTO: String, Sendable, Equatable { case notDetermined, denied, granted, notApplicable }

public struct PermissionStatusDTO: Sendable, Equatable {
    public let location: LocationAccessDTO
    public let precise: PermissionStateDTO
    public let locationServicesEnabled: Bool
    public let notifications: PermissionStateDTO
    public let fullScreenIntent: PermissionStateDTO
    public let exactAlarm: PermissionStateDTO
    public let batteryOptimizationIgnored: PermissionStateDTO
    public let alarmKit: PermissionStateDTO

    public init(location: LocationAccessDTO, precise: PermissionStateDTO, locationServicesEnabled: Bool,
                notifications: PermissionStateDTO, fullScreenIntent: PermissionStateDTO, exactAlarm: PermissionStateDTO,
                batteryOptimizationIgnored: PermissionStateDTO, alarmKit: PermissionStateDTO) {
        self.location = location
        self.precise = precise
        self.locationServicesEnabled = locationServicesEnabled
        self.notifications = notifications
        self.fullScreenIntent = fullScreenIntent
        self.exactAlarm = exactAlarm
        self.batteryOptimizationIgnored = batteryOptimizationIgnored
        self.alarmKit = alarmKit
    }
}

/// T21 §9, cell by cell (no extra rule).
public enum PermissionMapper {
    public static func status(_ r: PermissionReadings) -> PermissionStatusDTO {
        PermissionStatusDTO(
            location: location(r.location),
            precise: precise(r.location, r.accuracy),
            locationServicesEnabled: r.servicesEnabled,
            notifications: notifications(r.notifications),
            fullScreenIntent: .notApplicable,
            exactAlarm: .notApplicable,
            batteryOptimizationIgnored: .notApplicable,
            alarmKit: alarmKit(r.alarmKit))
    }

    static func location(_ l: LocationAuthRaw) -> LocationAccessDTO {
        switch l {
        case .notDetermined: .notDetermined
        case .restricted, .denied: .denied
        case .whenInUse: .whileInUse
        case .always: .always
        }
    }

    /// Never notApplicable: without a location grant the accuracy is not known yet.
    static func precise(_ l: LocationAuthRaw, _ a: AccuracyRaw) -> PermissionStateDTO {
        guard l == .whenInUse || l == .always else { return .notDetermined }
        return a == .full ? .granted : .denied
    }

    /// Provisional notifications are quiet: not enough to wake anybody (T21 §9).
    static func notifications(_ n: NotificationAuthRaw) -> PermissionStateDTO {
        switch n {
        case .notDetermined: .notDetermined
        case .denied, .provisional: .denied
        case .authorized, .ephemeral: .granted
        }
    }

    static func alarmKit(_ a: AlarmKitAuth) -> PermissionStateDTO {
        switch a {
        case .unavailable: .notApplicable
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .granted
        }
    }
}

/// How long `request(.location)` waits for the dialog (RK-T171-1): then it answers `status()` as it is.
public enum PermissionConstants {
    public static let promptTimeoutMs: Int64 = 60_000
}

/// Raw platform reads and prompts of `IOSPermissionHostApi` (implemented by NapStopIOS.PermissionProbe; fakes in tests).
/// PRIVACY: implementations never log a position, a distance or the station coordinates.
public protocol PermissionProbing: Sendable {
    func readings() async -> PermissionReadings
    /// `requestWhenInUseAuthorization()` when not determined; returns when determined or after `timeoutMs`.
    func requestLocation(timeoutMs: Int64) async
    /// Errors are swallowed (the caller reads the status again).
    func requestNotifications() async
    /// iOS < 26: no-op. Errors are swallowed.
    func requestAlarmKit() async
    /// `CLLocationManager.location`: never requests a fix, never prompts. `fix` is nil when not authorized.
    func lastKnown() async -> (fix: RawFix?, authorized: Bool, servicesEnabled: Bool)
    /// Metres from `fix` to each (lat, lng) pair of `pairs` (`CLLocation.distance(from:)`), same order.
    func distancesM(from fix: RawFix, to pairs: [Double]) -> [Double]
}

/// One permission prompt at a time (Pigeon contract "Errors: request-in-progress", as Android). Thread-safe.
public final class PermissionRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false

    public init() {}

    /// False when a request is already running.
    public func tryEnter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if busy { return false }
        busy = true
        return true
    }

    public func leave() {
        lock.lock()
        busy = false
        lock.unlock()
    }
}

/// Port of Android `LastKnownMath` (T23 TK02). Pure.
/// PRIVACY: distances leave the app rounded to what screen 2 shows, so a set of them to public stations cannot pin the
/// user down to a few metres (review T23 #3). Never log them.
public enum LastKnownMath {
    /// Most numbers accepted (50 stations).
    public static let maxNumbers = 100

    /// Even, non-empty, at most `maxNumbers`, finite, lat in [-90, 90], lng in [-180, 180].
    public static func validPairs(_ p: [Double]) -> Bool {
        if p.isEmpty || p.count % 2 != 0 || p.count > maxNumbers { return false }
        var i = 0
        while i < p.count {
            let lat = p[i], lng = p[i + 1]
            if !lat.isFinite || !lng.isFinite { return false }
            if lat < -90 || lat > 90 || lng < -180 || lng > 180 { return false }
            i += 2
        }
        return true
    }

    /// Nearest 10 m below 1 km, nearest 100 m from 1 km on (Kotlin `Math.round`: half up). Non-finite or <= 0 gives 0.
    public static func roundForDisplay(_ meters: Double) -> Double {
        if !meters.isFinite || meters <= 0 { return 0 }
        let step: Double = meters < 1_000 ? 10 : 100
        return (meters / step).rounded(.toNearestOrAwayFromZero) * step
    }

    /// Age from the fix timestamp (wall ms); fresh when 0 ≤ age ≤ maxAgeMs (a future timestamp counts as age 0).
    public static func isFresh(fixWallMs: Int64, nowWallMs: Int64, maxAgeMs: Int64) -> Bool {
        let (diff, overflow) = nowWallMs.subtractingReportingOverflow(fixWallMs)
        if overflow { return false }
        return max(0, diff) <= maxAgeMs
    }

    /// The cached fix when it may be used: permission at any level, location services on, valid and fresh.
    /// A negative horizontal accuracy marks an invalid CLLocation.
    public static func usableFix(_ fix: RawFix?, authorized: Bool, servicesEnabled: Bool, nowWallMs: Int64,
                                 maxAgeMs: Int64) -> RawFix? {
        guard authorized, servicesEnabled, maxAgeMs > 0, let fix else { return nil }
        guard fix.lat.isFinite, fix.lng.isFinite, fix.horizontalAccuracyM >= 0 else { return nil }
        guard isFresh(fixWallMs: fix.timestampWallMs, nowWallMs: nowWallMs, maxAgeMs: maxAgeMs) else { return nil }
        return fix
    }

    /// Rounded distances, or nil when the platform returned the wrong number of them.
    public static func forDisplay(_ meters: [Double], pairCount: Int) -> [Double]? {
        guard meters.count == pairCount else { return nil }
        return meters.map(roundForDisplay)
    }

    /// The whole `distancesFromLastKnownM` answer on top of a probe (T23 §6 on iOS): nil for invalid input, no permission,
    /// location off, or no fresh cached fix. Never prompts, never requests a fix.
    public static func distances(_ pairs: [Double], maxAgeMs: Int64, probe: PermissionProbing,
                                 nowWallMs: () -> Int64) async -> [Double]? {
        guard validPairs(pairs), maxAgeMs > 0 else { return nil }
        let r = await probe.lastKnown()
        guard let fix = usableFix(r.fix, authorized: r.authorized, servicesEnabled: r.servicesEnabled, nowWallMs: nowWallMs(),
                                  maxAgeMs: maxAgeMs) else { return nil }
        return forDisplay(probe.distancesM(from: fix, to: pairs), pairCount: pairs.count / 2)
    }
}
