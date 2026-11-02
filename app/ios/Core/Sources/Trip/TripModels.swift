// Public data types of the Trip Engine (T10 §2, T13 §4). Field names and order follow T10 §2.

// MARK: - Enums (lowerCamel in Swift, UPPER_SNAKE in JSON)

public enum AlarmMode: Sendable, Equatable, CaseIterable {
    case distance, time, smart
    public var jsonName: String {
        switch self { case .distance: "DISTANCE"; case .time: "TIME"; case .smart: "SMART" }
    }
    public init?(jsonName: String) {
        switch jsonName { case "DISTANCE": self = .distance; case "TIME": self = .time; case "SMART": self = .smart
        default: return nil }
    }
}

public enum VehicleKind: Sendable, Equatable, CaseIterable {
    case train, coach, bus, unknown
    public var jsonName: String {
        switch self { case .train: "TRAIN"; case .coach: "COACH"; case .bus: "BUS"; case .unknown: "UNKNOWN" }
    }
    public init?(jsonName: String) {
        switch jsonName { case "TRAIN": self = .train; case "COACH": self = .coach; case "BUS": self = .bus
        case "UNKNOWN": self = .unknown; default: return nil }
    }
}

public enum AvailabilityCause: Sendable, Equatable, CaseIterable {
    case available, permissionRevoked, servicesOff
    public var jsonName: String {
        switch self { case .available: "AVAILABLE"; case .permissionRevoked: "PERMISSION_REVOKED"; case .servicesOff: "SERVICES_OFF" }
    }
    public init?(jsonName: String) {
        switch jsonName { case "AVAILABLE": self = .available; case "PERMISSION_REVOKED": self = .permissionRevoked
        case "SERVICES_OFF": self = .servicesOff; default: return nil }
    }
}

public enum UserActionKind: Sendable, Equatable, CaseIterable {
    case dismiss, snooze, stopTrip, batteryMaxSaving, batteryAlarmAt5, batteryAlarmEarlier
    public var jsonName: String {
        switch self {
        case .dismiss: "DISMISS"; case .snooze: "SNOOZE"; case .stopTrip: "STOP_TRIP"
        case .batteryMaxSaving: "BATTERY_MAX_SAVING"; case .batteryAlarmAt5: "BATTERY_ALARM_AT_5"
        case .batteryAlarmEarlier: "BATTERY_ALARM_EARLIER"
        }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "DISMISS": self = .dismiss; case "SNOOZE": self = .snooze; case "STOP_TRIP": self = .stopTrip
        case "BATTERY_MAX_SAVING": self = .batteryMaxSaving; case "BATTERY_ALARM_AT_5": self = .batteryAlarmAt5
        case "BATTERY_ALARM_EARLIER": self = .batteryAlarmEarlier; default: return nil
        }
    }
}

public enum AlarmReason: Sendable, Equatable, CaseIterable {
    case distance, time, smartTime, smartDistance, smartSlowDistance, gpsLost, lowBattery,
         passedClosest, overshoot, snoozeEnd, timeout, fallback, fallbackMissed
    public var jsonName: String {
        switch self {
        case .distance: "DISTANCE"; case .time: "TIME"; case .smartTime: "SMART_TIME"; case .smartDistance: "SMART_DISTANCE"
        case .smartSlowDistance: "SMART_SLOW_DISTANCE"; case .gpsLost: "GPS_LOST"; case .lowBattery: "LOW_BATTERY"
        case .passedClosest: "PASSED_CLOSEST"; case .overshoot: "OVERSHOOT"; case .snoozeEnd: "SNOOZE_END"
        case .timeout: "TIMEOUT"; case .fallback: "FALLBACK"; case .fallbackMissed: "FALLBACK_MISSED"
        }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "DISTANCE": self = .distance; case "TIME": self = .time; case "SMART_TIME": self = .smartTime
        case "SMART_DISTANCE": self = .smartDistance; case "SMART_SLOW_DISTANCE": self = .smartSlowDistance
        case "GPS_LOST": self = .gpsLost; case "LOW_BATTERY": self = .lowBattery; case "PASSED_CLOSEST": self = .passedClosest
        case "OVERSHOOT": self = .overshoot; case "SNOOZE_END": self = .snoozeEnd; case "TIMEOUT": self = .timeout
        case "FALLBACK": self = .fallback; case "FALLBACK_MISSED": self = .fallbackMissed; default: return nil
        }
    }
}

public enum GpsLostCause: Sendable, Equatable, CaseIterable {
    case noFixTimeout, neverAcquired, permissionRevoked, servicesOff
    public var jsonName: String {
        switch self {
        case .noFixTimeout: "NO_FIX_TIMEOUT"; case .neverAcquired: "NEVER_ACQUIRED"
        case .permissionRevoked: "PERMISSION_REVOKED"; case .servicesOff: "SERVICES_OFF"
        }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "NO_FIX_TIMEOUT": self = .noFixTimeout; case "NEVER_ACQUIRED": self = .neverAcquired
        case "PERMISSION_REVOKED": self = .permissionRevoked; case "SERVICES_OFF": self = .servicesOff; default: return nil
        }
    }
}

public enum FallbackCause: Sendable, Equatable, CaseIterable {
    case eta, snooze, superseded, tripEnded, resync
    public var jsonName: String {
        switch self {
        case .eta: "ETA"; case .snooze: "SNOOZE"; case .superseded: "SUPERSEDED"; case .tripEnded: "TRIP_ENDED"
        case .resync: "RESYNC"
        }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "ETA": self = .eta; case "SNOOZE": self = .snooze; case "SUPERSEDED": self = .superseded
        case "TRIP_ENDED": self = .tripEnded; case "RESYNC": self = .resync; default: return nil
        }
    }
}

public enum TripOutcome: Sendable, Equatable, CaseIterable {
    case onTime, snoozed, missed, cancelled
    public var jsonName: String {
        switch self { case .onTime: "ON_TIME"; case .snoozed: "SNOOZED"; case .missed: "MISSED"; case .cancelled: "CANCELLED" }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "ON_TIME": self = .onTime; case "SNOOZED": self = .snoozed; case "MISSED": self = .missed
        case "CANCELLED": self = .cancelled; default: return nil
        }
    }
}

public enum EndReason: Sendable, Equatable, CaseIterable {
    case dismissed, userStop, alarmUnanswered
    public var jsonName: String {
        switch self { case .dismissed: "DISMISSED"; case .userStop: "USER_STOP"; case .alarmUnanswered: "ALARM_UNANSWERED" }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "DISMISSED": self = .dismissed; case "USER_STOP": self = .userStop; case "ALARM_UNANSWERED": self = .alarmUnanswered
        default: return nil
        }
    }
}

public enum SamplingTier: Int, Sendable, Equatable, Comparable, CaseIterable {
    case sparse = 0, medium, dense
    public static func < (a: SamplingTier, b: SamplingTier) -> Bool { a.rawValue < b.rawValue }
    public var jsonName: String {
        switch self { case .sparse: "SPARSE"; case .medium: "MEDIUM"; case .dense: "DENSE" }
    }
    public init?(jsonName: String) {
        switch jsonName { case "SPARSE": self = .sparse; case "MEDIUM": self = .medium; case "DENSE": self = .dense
        default: return nil }
    }
}

public enum AccuracyLevel: Sendable, Equatable, CaseIterable {
    case balanced, high
    public var jsonName: String { switch self { case .balanced: "BALANCED"; case .high: "HIGH" } }
    public init?(jsonName: String) {
        switch jsonName { case "BALANCED": self = .balanced; case "HIGH": self = .high; default: return nil }
    }
}

public enum TripPhase: Sendable, Equatable, CaseIterable {
    case acquiring, tracking, alarming, snoozed, overshot, ended
    public var jsonName: String {
        switch self {
        case .acquiring: "ACQUIRING"; case .tracking: "TRACKING"; case .alarming: "ALARMING"; case .snoozed: "SNOOZED"
        case .overshot: "OVERSHOT"; case .ended: "ENDED"
        }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "ACQUIRING": self = .acquiring; case "TRACKING": self = .tracking; case "ALARMING": self = .alarming
        case "SNOOZED": self = .snoozed; case "OVERSHOT": self = .overshot; case "ENDED": self = .ended; default: return nil
        }
    }
}

public enum GpsStatus: Sendable, Equatable, CaseIterable {
    case noFixYet, ok, lost
    public var jsonName: String { switch self { case .noFixYet: "NO_FIX_YET"; case .ok: "OK"; case .lost: "LOST" } }
    public init?(jsonName: String) {
        switch jsonName { case "NO_FIX_YET": self = .noFixYet; case "OK": self = .ok; case "LOST": self = .lost
        default: return nil }
    }
}

/// `notSet` ↔ JSON "NONE" (avoids confusion with `Optional.none`, like T14 `FallbackStatusMsg.notSet`).
public enum FallbackStatus: Sendable, Equatable, CaseIterable {
    case notSet, requested, confirmed, failed
    public var jsonName: String {
        switch self { case .notSet: "NONE"; case .requested: "REQUESTED"; case .confirmed: "CONFIRMED"; case .failed: "FAILED" }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "NONE": self = .notSet; case "REQUESTED": self = .requested; case "CONFIRMED": self = .confirmed
        case "FAILED": self = .failed; default: return nil
        }
    }
}

public enum FallbackRestoreStatus: Sendable, Equatable, CaseIterable {
    case rang, dismissed, pending, missing, unknown
    public var jsonName: String {
        switch self {
        case .rang: "RANG"; case .dismissed: "DISMISSED"; case .pending: "PENDING"; case .missing: "MISSING"
        case .unknown: "UNKNOWN"
        }
    }
    public init?(jsonName: String) {
        switch jsonName {
        case "RANG": self = .rang; case "DISMISSED": self = .dismissed; case "PENDING": self = .pending
        case "MISSING": self = .missing; case "UNKNOWN": self = .unknown; default: return nil
        }
    }
}

// MARK: - Config and input

public struct TripConfig: Sendable, Equatable {
    public var tripId: String
    public var destLat: Double
    public var destLng: Double
    public var mode: AlarmMode
    public var distanceThresholdM: Int?
    public var timeThresholdMin: Int?
    public var preAlertEnabled: Bool
    public var vehicleHint: VehicleKind

    public init(tripId: String, destLat: Double, destLng: Double, mode: AlarmMode, distanceThresholdM: Int?,
                timeThresholdMin: Int?, preAlertEnabled: Bool, vehicleHint: VehicleKind) {
        self.tripId = tripId
        self.destLat = destLat
        self.destLng = destLng
        self.mode = mode
        self.distanceThresholdM = distanceThresholdM
        self.timeThresholdMin = timeThresholdMin
        self.preAlertEnabled = preAlertEnabled
        self.vehicleHint = vehicleHint
    }
}

/// Thrown by `TripEngine.start` (T12 C11). Message `"<field>: <rule>"`, never a value.
public struct TripConfigError: Error, Sendable, Equatable, CustomStringConvertible {
    public let field: String
    public let rule: String
    public init(field: String, rule: String) { self.field = field; self.rule = rule }
    public var description: String { "\(field): \(rule)" }
}

public struct LocationFix: Sendable, Equatable {
    public var atMs: Int64
    public var fixAtMs: Int64
    public var lat: Double
    public var lng: Double
    public var accuracyM: Double
    public var speedMps: Double?

    public init(atMs: Int64, fixAtMs: Int64, lat: Double, lng: Double, accuracyM: Double, speedMps: Double?) {
        self.atMs = atMs
        self.fixAtMs = fixAtMs
        self.lat = lat
        self.lng = lng
        self.accuracyM = accuracyM
        self.speedMps = speedMps
    }
}

public enum EngineInput: Sendable, Equatable {
    case locationFix(LocationFix)
    case tick(atMs: Int64)
    case batterySample(atMs: Int64, levelPct: Int, charging: Bool)
    case locationAvailability(atMs: Int64, cause: AvailabilityCause)
    case fallbackScheduled(atMs: Int64, fallbackAtMs: Int64, ok: Bool)
    case fallbackFired(atMs: Int64, firedAtMs: Int64)
    case alarmSilenced(atMs: Int64, silencedAtMs: Int64)
    case userAction(atMs: Int64, action: UserActionKind)

    public var atMs: Int64 {
        switch self {
        case let .locationFix(f): f.atMs
        case let .tick(a), let .batterySample(a, _, _), let .locationAvailability(a, _), let .fallbackScheduled(a, _, _),
             let .fallbackFired(a, _), let .alarmSilenced(a, _), let .userAction(a, _): a
        }
    }
}

// MARK: - Events

public struct SamplingPolicy: Sendable, Equatable {
    public let tier: SamplingTier
    public let intervalS: Int
    public let minIntervalS: Int
    public let accuracy: AccuracyLevel
    public init(tier: SamplingTier, intervalS: Int, minIntervalS: Int, accuracy: AccuracyLevel) {
        self.tier = tier; self.intervalS = intervalS; self.minIntervalS = minIntervalS; self.accuracy = accuracy
    }
}

public struct TripSummary: Sendable, Equatable {
    public let startedAtMs: Int64
    public let alarmAtMs: Int64?
    public let alarmReason: AlarmReason?
    public let dismissedAtMs: Int64?
    public let snoozeCount: Int
    public let travelledM: Int
    public let vehicleGuess: VehicleKind
}

/// Case order = order of events inside a Step (T10 §2.3).
public enum TripEvent: Sendable, Equatable {
    case gpsRecovered(GpsRecovered)
    case gpsLost(GpsLost)
    case arrived(Arrived)
    case alarm(Alarm)
    case overshoot(Overshoot)
    case preAlert(PreAlert)
    case snoozed(Snoozed)
    case lowBatteryRisk(LowBatteryRisk)
    case samplingPolicyChanged(SamplingPolicyChanged)
    case fallbackAlarmChanged(FallbackAlarmChanged)
    case tripEnded(TripEnded)

    public struct PreAlert: Sendable, Equatable { public let atMs: Int64; public let distanceM: Int; public let etaS: Int? }
    public struct Alarm: Sendable, Equatable {
        public let atMs: Int64; public let reason: AlarmReason; public let ringNow: Bool
        public let snoozeAllowed: Bool; public let distanceM: Int?; public let etaS: Int?; public let batteryPct: Int?
    }
    public struct Snoozed: Sendable, Equatable { public let atMs: Int64; public let untilMs: Int64 }
    public struct GpsLost: Sendable, Equatable { public let atMs: Int64; public let cause: GpsLostCause; public let lastFixAgeS: Int? }
    public struct GpsRecovered: Sendable, Equatable { public let atMs: Int64; public let lostForS: Int }
    public struct LowBatteryRisk: Sendable, Equatable {
        public let atMs: Int64; public let levelPct: Int; public let availableMin: Int; public let neededMin: Int
    }
    public struct Overshoot: Sendable, Equatable { public let atMs: Int64; public let pastM: Int }
    public struct Arrived: Sendable, Equatable { public let atMs: Int64; public let distanceM: Int }
    public struct FallbackAlarmChanged: Sendable, Equatable {
        public let atMs: Int64; public let fallbackAtMs: Int64?; public let cause: FallbackCause
    }
    public struct SamplingPolicyChanged: Sendable, Equatable { public let atMs: Int64; public let policy: SamplingPolicy }
    public struct TripEnded: Sendable, Equatable {
        public let atMs: Int64; public let outcome: TripOutcome; public let endReason: EndReason; public let summary: TripSummary
    }

    public var atMs: Int64 {
        switch self {
        case let .gpsRecovered(e): e.atMs
        case let .gpsLost(e): e.atMs
        case let .arrived(e): e.atMs
        case let .alarm(e): e.atMs
        case let .overshoot(e): e.atMs
        case let .preAlert(e): e.atMs
        case let .snoozed(e): e.atMs
        case let .lowBatteryRisk(e): e.atMs
        case let .samplingPolicyChanged(e): e.atMs
        case let .fallbackAlarmChanged(e): e.atMs
        case let .tripEnded(e): e.atMs
        }
    }

    /// Fixture name (README §3.1).
    public var fixtureName: String {
        switch self {
        case .gpsRecovered: "gpsRecovered"; case .gpsLost: "gpsLost"; case .arrived: "arrived"; case .alarm: "alarm"
        case .overshoot: "overshoot"; case .preAlert: "preAlert"; case .snoozed: "snoozed"
        case .lowBatteryRisk: "lowBatteryRisk"; case .samplingPolicyChanged: "samplingPolicyChanged"
        case .fallbackAlarmChanged: "fallbackAlarmChanged"; case .tripEnded: "tripEnded"
        }
    }

    /// Sort rank inside a Step (T10 §2.3).
    var sortRank: Int {
        switch self {
        case .gpsRecovered: 0; case .gpsLost: 1; case .arrived: 2; case .alarm: 3; case .overshoot: 4; case .preAlert: 5
        case .snoozed: 6; case .lowBatteryRisk: 7; case .samplingPolicyChanged: 8; case .fallbackAlarmChanged: 9
        case .tripEnded: 10
        }
    }
}

// MARK: - View, Step, restore info

public struct TripView: Sendable, Equatable {
    public let tripId: String
    public let atMs: Int64
    public let phase: TripPhase
    public let gps: GpsStatus
    public let locationCause: AvailabilityCause
    public let distanceM: Int?
    public let routeDistanceEstM: Int?
    public let distanceErrorM: Int?
    public let isEstimated: Bool
    public let etaS: Int?
    public let etaMinS: Int?
    public let etaMaxS: Int?
    public let speedKmh: Double?
    public let progress: Double?
    public let alarmMarkerProgress: Double?
    public let predictedAlarmAtMs: Int64?
    public let samplingPolicy: SamplingPolicy?
    public let fallbackAtMs: Int64?
    public let fallbackStatus: FallbackStatus
    public let batteryPct: Int?
    public let batteryRisk: Bool
    public let preAlertFired: Bool
    public let alarmAtMs: Int64?
    public let alarmReason: AlarmReason?
    public let alarmRinging: Bool
    public let snoozeCount: Int
    public let snoozeUntilMs: Int64?
    public let overshootPastM: Int?
    public let outcome: TripOutcome?
    public let vehicleGuess: VehicleKind
    public let travelledM: Int
    public let droppedFixes: Int
    public let wakeAtMs: Int64?
}

public struct Step: Sendable {
    public let state: EngineState
    public let events: [TripEvent]
    public let view: TripView
}

public struct RestoreInfo: Sendable, Equatable {
    public var status: FallbackRestoreStatus
    public var firedAtMs: Int64?
    public var dismissedAtMs: Int64?
    public init(status: FallbackRestoreStatus, firedAtMs: Int64? = nil, dismissedAtMs: Int64? = nil) {
        self.status = status; self.firedAtMs = firedAtMs; self.dismissedAtMs = dismissedAtMs
    }
}

/// Thrown by `TripEngine.decodeSnapshot`; message `"snapshot: <rule>"`, never content.
public struct SnapshotError: Error, Sendable, Equatable, CustomStringConvertible {
    public let rule: String
    public init(rule: String) { self.rule = rule }
    public var description: String { "snapshot: \(rule)" }
}
