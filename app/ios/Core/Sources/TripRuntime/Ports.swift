// Ports of the iOS trip runtime (docs/specs/T17.md §4.1). Implemented by NapStopIOS on the device and by fakes in tests.
import Foundation
import Trip

/// Trip clock inputs (§5.3). All engine times are on the trip clock.
public protocol TimeSource: Sendable {
    /// `Date().timeIntervalSince1970 * 1000`, floor.
    func wallMs() -> Int64
    /// ContinuousClock, continues while asleep [SW-CC].
    func elapsedMs() -> Int64
    /// `sysctlbyname("kern.bootsessionuuid")`; nil if unreadable.
    func bootSessionId() -> String?
}

/// One CLLocation, no Apple types. description/debugDescription redact coordinates (T10 §10).
public struct RawFix: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let lat: Double
    public let lng: Double
    /// CLLocation.horizontalAccuracy; < 0 = invalid.
    public let horizontalAccuracyM: Double
    /// CLLocation.speed; < 0 = invalid.
    public let speedMps: Double
    /// CLLocation.timestamp.
    public let timestampWallMs: Int64

    public init(lat: Double, lng: Double, horizontalAccuracyM: Double, speedMps: Double, timestampWallMs: Int64) {
        self.lat = lat
        self.lng = lng
        self.horizontalAccuracyM = horizontalAccuracyM
        self.speedMps = speedMps
        self.timestampWallMs = timestampWallMs
    }

    public var description: String { "RawFix(<redacted>)" }
    public var debugDescription: String { description }
}

/// `keepAlive` (T18.1 D9): the session that keeps the app running during a simulated trip; its fixes are dropped.
public enum LocationAccuracyClass: String, Sendable, Equatable { case hundredMeters, nearestTenMeters, best, keepAlive }

public struct LocationRequestSpec: Sendable, Equatable {
    public let accuracy: LocationAccuracyClass
    /// Throttle interval (D9); not passed to Core Location.
    public let intervalMs: Int64
    public init(accuracy: LocationAccuracyClass, intervalMs: Int64) {
        self.accuracy = accuracy
        self.intervalMs = intervalMs
    }

    /// T18.1 D9: lowest accuracy, fixes never reach the engine (no throttle interval).
    public static let keepAlive = LocationRequestSpec(accuracy: .keepAlive, intervalMs: 0)
}

public protocol LocationSink: AnyObject, Sendable {
    func locationSession(didReceive fix: RawFix)
    func locationSession(availabilityChanged cause: AvailabilityCause)
}

public protocol LocationSession: Sendable {
    /// First start MUST happen while the app is active (D8). Throws LocationStartError.
    func start(_ spec: LocationRequestSpec, sink: LocationSink) async throws
    func retune(_ spec: LocationRequestSpec) async
    func stop() async
    func isRunning() async -> Bool
    /// CLLocationManager.location; never requests a fix.
    func lastKnown() async -> RawFix?
}

public enum LocationStartError: Error, Equatable { case backgroundModeMissing, notAuthorized, servicesOff }

public enum AppActivity: Sendable, Equatable { case active, inactive, background }

public protocol AppStatePort: Sendable {
    /// UIApplication.shared.applicationState (main actor).
    func activity() async -> AppActivity
}

public struct LocationAccess: Sendable, Equatable {
    public let whenInUseOrAlways: Bool
    /// accuracyAuthorization == .fullAccuracy
    public let fullAccuracy: Bool
    /// CLLocationManager.locationServicesEnabled(), never on main.
    public let servicesEnabled: Bool
    /// T23.8 §5.5: authorizationStatus == .authorizedAlways. Only the commute feature reads it (C1: evaluator; the
    /// platform readers fill it in C2, until then it stays false).
    public let always: Bool
    public init(whenInUseOrAlways: Bool, fullAccuracy: Bool, servicesEnabled: Bool, always: Bool = false) {
        self.whenInUseOrAlways = whenInUseOrAlways
        self.fullAccuracy = fullAccuracy
        self.servicesEnabled = servicesEnabled
        self.always = always
    }

    /// §5.4: reduced accuracy alone is not a revocation (fixes are dropped by FixFilter instead).
    public var availability: AvailabilityCause {
        if !whenInUseOrAlways { return .permissionRevoked }
        if !servicesEnabled { return .servicesOff }
        return .available
    }
}

/// unavailable = iOS < 26.
public enum AlarmKitAuth: Sendable, Equatable { case unavailable, notDetermined, denied, authorized }

public struct ChannelAccess: Sendable, Equatable {
    public let alarmKit: AlarmKitAuth
    /// .authorized or .ephemeral (T21 §9: provisional = false).
    public let notifications: Bool
    public init(alarmKit: AlarmKitAuth, notifications: Bool) {
        self.alarmKit = alarmKit
        self.notifications = notifications
    }
}

public struct BatteryReading: Sendable, Equatable {
    public let levelPct: Int
    public let charging: Bool
    public init(levelPct: Int, charging: Bool) {
        self.levelPct = levelPct
        self.charging = charging
    }
}

public protocol DeviceEnv: Sendable {
    func locationAccess() async -> LocationAccess
    func channelAccess() async -> ChannelAccess
    /// UIDevice battery, nil when unknown.
    func battery() async -> BatteryReading?
}

public enum TripNotice: Sendable, Equatable {
    case noGpsYet, permissionRevoked, servicesOff, fallbackFailed, interrupted
    case preAlert(distanceM: Int, etaS: Int?, byDistance: Bool)
    /// §5.6.3: neither channel could ring.
    case ringFailed

    /// Stable notification id suffix (§5.10): one notification per kind.
    public var kindName: String {
        switch self {
        case .noGpsYet: "noGpsYet"
        case .permissionRevoked: "permissionRevoked"
        case .servicesOff: "servicesOff"
        case .fallbackFailed: "fallbackFailed"
        case .interrupted: "interrupted"
        case .preAlert: "preAlert"
        case .ringFailed: "ringFailed"
        }
    }
}

public protocol TripNotifier: Sendable {
    func show(tripId: String, _ notice: TripNotice, destinationName: String?) async
    func clear(tripId: String, _ notice: TripNotice) async
    func clearAll(tripId: String) async
}

public protocol WakeTimer: Sendable {
    /// Fires runtime.onTimer(generation:) after `delayMs` real ms. Replaces the previous timer.
    func set(delayMs: Int64, generation: Int64)
    func cancel()
}

/// Budgets (§6); tests: manual.
public protocol RuntimeSleeper: Sendable { func sleep(ms: Int64) async }

/// UIApplication.beginBackgroundTask.
public protocol BackgroundTasks: Sendable {
    /// Token; 0 = none.
    func begin(_ name: String) -> Int
    func end(_ token: Int)
}

/// No-op in release builds. Fields never hold coordinates, distances or the destination name (§5.13).
public protocol RuntimeJournal: Sendable { func record(_ event: String, _ fields: [String: String]) }

public struct NoJournal: RuntimeJournal {
    public init() {}
    public func record(_ event: String, _ fields: [String: String]) {}
}

/// View + engine events of one Step. Awaited by the runtime (Publish ends when the sink has received it, §5.11).
public typealias RuntimeListener = @Sendable (_ tripId: String, _ view: TripView, _ batteryChoice: UserActionKind?,
                                              _ events: [TripEvent]) async -> Void

/// Diagnostics switches passed by the Runner (§5.13). The package never sees `NAPSTOP_DIAG`; default = everything off.
public struct RuntimeOptions: Sendable, Equatable {
    public let diagnostics: Bool
    public let fakeAlarms: Bool
    public init(diagnostics: Bool = false, fakeAlarms: Bool = false) {
        self.diagnostics = diagnostics
        self.fakeAlarms = fakeAlarms
    }

    /// The journal to use: the file journal only when diagnostics are on (IU36: default creates no file).
    public func journal(_ makeFileJournal: () -> RuntimeJournal) -> RuntimeJournal {
        diagnostics ? makeFileJournal() : NoJournal()
    }
}
