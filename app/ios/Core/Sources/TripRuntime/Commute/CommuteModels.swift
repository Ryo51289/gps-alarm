// Commute route, pure types (docs/specs/T23.8.md §5.2, §5.6). Foundation only, no CoreLocation.
// PRIVACY: CommuteRoute holds names and coordinates; every description here is redacted and nothing in this folder logs.
import Foundation
import Trip

/// towardB: triggered by entering A (track to B); towardA: triggered by entering B (track back to A).
public enum CommuteDirection: String, Codable, Sendable, CaseIterable {
    case towardB, towardA

    /// The point whose entry triggers this direction.
    public var triggerPoint: CommutePoint { self == .towardB ? .a : .b }
}

public enum CommutePoint: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case a = "A", b = "B"

    /// The direction started by entering this point.
    public var direction: CommuteDirection { self == .a ? .towardB : .towardA }
}

/// One direction's time window, local time of the device, `[startMinute, endMinute)`.
public struct CommuteWindow: Codable, Sendable, Equatable {
    public let enabled: Bool
    /// 0...1439, local.
    public let startMinute: Int
    /// Exclusive, startMinute < endMinute ≤ 1440.
    public let endMinute: Int
    /// bit0 = Monday … bit6 = Sunday, 1...127.
    public let weekdayMask: Int

    public init(enabled: Bool, startMinute: Int, endMinute: Int, weekdayMask: Int) {
        self.enabled = enabled
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.weekdayMask = weekdayMask
    }

    /// Monday to Friday (D2 default days).
    public static let weekdays = 0b001_1111

    /// weekdayIndex: 0 = Monday … 6 = Sunday.
    public func includes(weekdayIndex: Int) -> Bool {
        guard (0...6).contains(weekdayIndex) else { return false }
        return weekdayMask & (1 << weekdayIndex) != 0
    }

    public func includes(minuteOfDay m: Int) -> Bool { startMinute <= m && m < endMinute }
}

/// Has coordinates and place names: description redacted, never logged (T10 §10).
public struct CommuteRoute: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let revision: Int
    public let enabled: Bool
    public let nameA: String
    public let nameB: String
    public let aLat: Double
    public let aLng: Double
    public let bLat: Double
    public let bLng: Double
    public let towardB: CommuteWindow
    public let towardA: CommuteWindow
    /// tripId replaced at start (D13); destination of templateTowardB is B, of templateTowardA is A.
    public let templateTowardB: TripMeta
    public let templateTowardA: TripMeta

    public init(revision: Int, enabled: Bool, nameA: String, nameB: String, aLat: Double, aLng: Double, bLat: Double,
                bLng: Double, towardB: CommuteWindow, towardA: CommuteWindow, templateTowardB: TripMeta,
                templateTowardA: TripMeta) {
        self.revision = revision
        self.enabled = enabled
        self.nameA = nameA
        self.nameB = nameB
        self.aLat = aLat
        self.aLng = aLng
        self.bLat = bLat
        self.bLng = bLng
        self.towardB = towardB
        self.towardA = towardA
        self.templateTowardB = templateTowardB
        self.templateTowardA = templateTowardA
    }

    public func window(_ d: CommuteDirection) -> CommuteWindow { d == .towardB ? towardB : towardA }
    public func template(_ d: CommuteDirection) -> TripMeta { d == .towardB ? templateTowardB : templateTowardA }

    public var description: String { "CommuteRoute(<redacted>)" }
    public var debugDescription: String { description }
}

/// JSON form of CommuteRoute (route.json): templates without simulation, enums by name like StoredTripCodec.
extension CommuteRoute: Codable {
    private struct TemplateDTO: Codable {
        var tripId: String
        var destinationName: String
        var mode: String
        var distanceThresholdM: Int?
        var timeThresholdMin: Int?
        var preAlertEnabled: Bool
        var vehicleHint: String
        var alarm: RingSettings
        var engineParamsJson: String?

        init(_ m: TripMeta) {
            tripId = m.tripId
            destinationName = m.destinationName
            mode = StoredTripCodec.modeName(m.mode)
            distanceThresholdM = m.distanceThresholdM
            timeThresholdMin = m.timeThresholdMin
            preAlertEnabled = m.preAlertEnabled
            vehicleHint = StoredTripCodec.vehicleName(m.vehicleHint)
            alarm = m.alarm
            engineParamsJson = m.engineParamsJson
        }

        func meta(codingPath: [CodingKey]) throws -> TripMeta {
            let modes: [String: AlarmMode] = ["distance": .distance, "time": .time, "smart": .smart]
            let vehicles: [String: VehicleKind] = ["train": .train, "coach": .coach, "bus": .bus, "unknown": .unknown]
            guard let m = modes[mode], let v = vehicles[vehicleHint] else {
                throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "template: enum"))
            }
            return TripMeta(tripId: tripId, destinationName: destinationName, mode: m, distanceThresholdM: distanceThresholdM,
                            timeThresholdMin: timeThresholdMin, preAlertEnabled: preAlertEnabled, vehicleHint: v, alarm: alarm,
                            engineParamsJson: engineParamsJson)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case revision, enabled, nameA, nameB, aLat, aLng, bLat, bLng, towardB, towardA, templateTowardB, templateTowardA
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(revision: try c.decode(Int.self, forKey: .revision), enabled: try c.decode(Bool.self, forKey: .enabled),
                  nameA: try c.decode(String.self, forKey: .nameA), nameB: try c.decode(String.self, forKey: .nameB),
                  aLat: try c.decode(Double.self, forKey: .aLat), aLng: try c.decode(Double.self, forKey: .aLng),
                  bLat: try c.decode(Double.self, forKey: .bLat), bLng: try c.decode(Double.self, forKey: .bLng),
                  towardB: try c.decode(CommuteWindow.self, forKey: .towardB),
                  towardA: try c.decode(CommuteWindow.self, forKey: .towardA),
                  templateTowardB: try c.decode(TemplateDTO.self, forKey: .templateTowardB).meta(codingPath: c.codingPath),
                  templateTowardA: try c.decode(TemplateDTO.self, forKey: .templateTowardA).meta(codingPath: c.codingPath))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(revision, forKey: .revision)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(nameA, forKey: .nameA)
        try c.encode(nameB, forKey: .nameB)
        try c.encode(aLat, forKey: .aLat)
        try c.encode(aLng, forKey: .aLng)
        try c.encode(bLat, forKey: .bLat)
        try c.encode(bLng, forKey: .bLng)
        try c.encode(towardB, forKey: .towardB)
        try c.encode(towardA, forKey: .towardA)
        try c.encode(TemplateDTO(templateTowardB), forKey: .templateTowardB)
        try c.encode(TemplateDTO(templateTowardA), forKey: .templateTowardA)
    }
}

public enum RegionState: String, Codable, Sendable, CaseIterable { case unknown, inside, outside }

/// Bookkeeping of the evaluator and the controller (napstop_trip/commute/state.json). No coordinates, no names.
public struct CommuteState: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public var revision: Int
    /// Last known state per point (D6); missing = unknown. Only `inside`/`outside` are stored: an `unknown` event keeps it.
    public var lastState: [CommutePoint: RegionState]
    /// Date of the last inside/outside event per point (dedupe of (identifier, date, state); out-of-order check, D18).
    public var lastEventAtMs: [CommutePoint: Int64]
    /// "towardB@2026-11-14": direction already started that local day (D7). Pruned after COMMUTE_FIRED_KEEP_DAYS.
    public var firedKeys: [String]
    /// Same key format: one failure notice per direction per day (§5.10).
    public var failureNoticeKeys: [String]
    public var guardTrip: DepartureGuardState?

    public init(revision: Int, lastState: [CommutePoint: RegionState] = [:], lastEventAtMs: [CommutePoint: Int64] = [:],
                firedKeys: [String] = [], failureNoticeKeys: [String] = [], guardTrip: DepartureGuardState? = nil) {
        self.revision = revision
        self.lastState = lastState
        self.lastEventAtMs = lastEventAtMs
        self.firedKeys = firedKeys
        self.failureNoticeKeys = failureNoticeKeys
        self.guardTrip = guardTrip
    }

    /// State for a new route revision (§5.10 "Đổi tuyến"): region states forgotten (D6), day keys and guard kept.
    public func rebased(to revision: Int) -> CommuteState {
        if revision == self.revision { return self }
        return CommuteState(revision: revision, firedKeys: firedKeys, failureNoticeKeys: failureNoticeKeys,
                            guardTrip: guardTrip)
    }

    /// Records a successful start of `direction` on local day `dateKey` (called by the controller on `.started`).
    public func markingFired(_ direction: CommuteDirection, dateKey: String) -> CommuteState {
        let k = CommuteDayKey.make(direction, dateKey: dateKey)
        var s = self
        if !s.firedKeys.contains(k) { s.firedKeys.append(k) }
        return s
    }

    /// Records a failure notice; false when one was already shown for this direction and day.
    public func markingFailureNotice(_ direction: CommuteDirection, dateKey: String) -> (CommuteState, isNew: Bool) {
        let k = CommuteDayKey.make(direction, dateKey: dateKey)
        if failureNoticeKeys.contains(k) { return (self, false) }
        var s = self
        s.failureNoticeKeys.append(k)
        return (s, true)
    }

    /// Drops day keys that are malformed or more than `keepDays` days away from `todayKey` (either side).
    public func pruned(todayKey: String, keepDays: Int) -> CommuteState {
        guard let today = LocalClock.dayNumber(dateKey: todayKey) else { return self }
        func keep(_ k: String) -> Bool {
            guard let d = CommuteDayKey.parse(k)?.dateKey, let n = LocalClock.dayNumber(dateKey: d) else { return false }
            return abs(today - n) <= Int64(keepDays)
        }
        var s = self
        s.firedKeys = firedKeys.filter(keep)
        s.failureNoticeKeys = failureNoticeKeys.filter(keep)
        return s
    }

    public var description: String {
        func st(_ p: CommutePoint) -> String { (lastState[p] ?? .unknown).rawValue }
        return "CommuteState(rev=\(revision), A=\(st(.a)), B=\(st(.b)), fired=\(firedKeys.count), "
            + "notices=\(failureNoticeKeys.count), guard=\(guardTrip != nil))"
    }

    public var debugDescription: String { description }
}

/// "<direction>@<yyyy-MM-dd>".
public enum CommuteDayKey {
    public static func make(_ d: CommuteDirection, dateKey: String) -> String { "\(d.rawValue)@\(dateKey)" }

    public static func parse(_ k: String) -> (direction: CommuteDirection, dateKey: String)? {
        let parts = k.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let d = CommuteDirection(rawValue: String(parts[0])),
              LocalClock.dayNumber(dateKey: String(parts[1])) != nil else { return nil }
        return (d, String(parts[1]))
    }
}

/// Durable record of an automatic start, read by HistorySync before finished trips (D14). No coordinates, no names.
public struct AutoStartRecord: Codable, Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let tripId: String
    public let direction: CommuteDirection
    public let revision: Int
    public let startedAtWallMs: Int64

    public init(tripId: String, direction: CommuteDirection, revision: Int, startedAtWallMs: Int64) {
        self.tripId = tripId
        self.direction = direction
        self.revision = revision
        self.startedAtWallMs = startedAtWallMs
    }

    public var description: String {
        "AutoStartRecord(\(tripId), \(direction.rawValue), rev=\(revision), at=\(startedAtWallMs))"
    }

    public var debugDescription: String { description }
}

public struct RegionEvent: Sendable, Equatable {
    /// "nc.r<revision>.<A|B>"
    public let identifier: String
    /// inside = satisfied, outside = unsatisfied.
    public let state: RegionState
    /// CLMonitor.Event.date (legacy API: time of the callback).
    public let dateWallMs: Int64
    /// Any of the CLMonitor deny / insufficient-in-use flags.
    public let authorizationDenied: Bool

    public init(identifier: String, state: RegionState, dateWallMs: Int64, authorizationDenied: Bool = false) {
        self.identifier = identifier
        self.state = state
        self.dateWallMs = dateWallMs
        self.authorizationDenied = authorizationDenied
    }
}

public struct TriggerContext: Sendable, Equatable {
    /// Wall time when the event is processed.
    public let nowWallMs: Int64
    /// TimeZone.current.secondsFromGMT(for: event date) (D8).
    public let utcOffsetS: Int
    public let access: LocationAccess
    public let tripActive: Bool
    /// iOS ≥ COMMUTE_MIN_IOS (D5).
    public let osSupported: Bool

    public init(nowWallMs: Int64, utcOffsetS: Int, access: LocationAccess, tripActive: Bool, osSupported: Bool) {
        self.nowWallMs = nowWallMs
        self.utcOffsetS = utcOffsetS
        self.access = access
        self.tripActive = tripActive
        self.osSupported = osSupported
    }
}

public enum SkipReason: String, Sendable, CaseIterable {
    case unknownIdentifier, staleRevision, duplicate, notEntry, firstDetermination, stale, routeDisabled, directionDisabled,
         outsideWindow, weekday, alreadyFiredToday, tripActive, notAlways, notPrecise, servicesOff, unsupportedOs,
         outOfOrder  // D18 (after review C1)
}

public enum TriggerDecision: Sendable, Equatable {
    case start(CommuteDirection, dateKey: String)
    case skip(SkipReason)
}

/// Native constants (§5.6, D16: no Remote Config).
public struct CommuteConstants: Sendable, Equatable {
    /// COMMUTE_REGION_RADIUS_M
    public let regionRadiusM: Double
    /// COMMUTE_EVENT_MAX_STALE_MS
    public let eventMaxStaleMs: Int64
    /// COMMUTE_DEPART_TIMEOUT_MS
    public let departTimeoutMs: Int64
    /// COMMUTE_DEPART_MIN_PROGRESS_M
    public let departMinProgressM: Int
    /// COMMUTE_MIN_AB_M
    public let minAbM: Double
    /// COMMUTE_AB_MARGIN_M: margin added to the stationary alarm reach R of the templates (D12, §5.6a).
    public let abThresholdMarginM: Double
    /// COMMUTE_WINDOW_MIN_MIN / COMMUTE_WINDOW_MAX_MIN
    public let windowMinMin: Int
    public let windowMaxMin: Int
    /// COMMUTE_FIRED_KEEP_DAYS
    public let firedKeepDays: Int
    /// COMMUTE_MIN_IOS (major version).
    public let minIosMajor: Int
    public let monitorName: String

    public init(regionRadiusM: Double, eventMaxStaleMs: Int64, departTimeoutMs: Int64, departMinProgressM: Int, minAbM: Double,
                abThresholdMarginM: Double, windowMinMin: Int, windowMaxMin: Int, firedKeepDays: Int, minIosMajor: Int,
                monitorName: String) {
        self.regionRadiusM = regionRadiusM
        self.eventMaxStaleMs = eventMaxStaleMs
        self.departTimeoutMs = departTimeoutMs
        self.departMinProgressM = departMinProgressM
        self.minAbM = minAbM
        self.abThresholdMarginM = abThresholdMarginM
        self.windowMinMin = windowMinMin
        self.windowMaxMin = windowMaxMin
        self.firedKeepDays = firedKeepDays
        self.minIosMajor = minIosMajor
        self.monitorName = monitorName
    }

    public static let `default` = CommuteConstants(
        regionRadiusM: 200, eventMaxStaleMs: 600_000, departTimeoutMs: 2_700_000, departMinProgressM: 300, minAbM: 2_000,
        abThresholdMarginM: 1_000, windowMinMin: 15, windowMaxMin: 720, firedKeepDays: 8, minIosMajor: 17,
        monitorName: "napstop.commute")
}

/// Condition identifiers "nc.r<revision>.A" / "nc.r<revision>.B" (§5.6).
public enum CommuteRegionId {
    public static func make(revision: Int, point: CommutePoint) -> String { "nc.r\(revision).\(point.rawValue)" }

    /// Canonical form only: decimal revision ≥ 0 without sign or leading zero.
    public static func parse(_ id: String) -> (revision: Int, point: CommutePoint)? {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "nc", parts[1].hasPrefix("r"),
              let point = CommutePoint(rawValue: String(parts[2])) else { return nil }
        let digits = parts[1].dropFirst()
        guard !digits.isEmpty, digits.allSatisfy({ $0 >= "0" && $0 <= "9" }),
              let rev = Int(digits), String(rev) == digits else { return nil }
        return (rev, point)
    }
}
