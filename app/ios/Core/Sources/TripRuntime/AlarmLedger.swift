// Alarm ledger and ring event records (docs/specs/T17.md §4.3). Written around every schedule/cancel/ring (§5.6).
import Foundation

public struct AlarmSlotRec: Sendable, Codable, Equatable {
    public let alarmId: String
    /// fallback | guardSlot
    public let kind: SystemAlarmKind
    public let generation: Int64
    /// Trip clock (engine target; guard: toTrip(wall)).
    public let targetAtMs: Int64
    public let targetAtWallMs: Int64
    public let setAtWallMs: Int64
    public let channel: AlarmChannelKind

    public init(alarmId: String, kind: SystemAlarmKind, generation: Int64, targetAtMs: Int64, targetAtWallMs: Int64,
                setAtWallMs: Int64, channel: AlarmChannelKind) {
        self.alarmId = alarmId
        self.kind = kind
        self.generation = generation
        self.targetAtMs = targetAtMs
        self.targetAtWallMs = targetAtWallMs
        self.setAtWallMs = setAtWallMs
        self.channel = channel
    }
}

public struct NowRingRec: Sendable, Codable, Equatable {
    public let alarmId: String
    public let generation: Int64
    public let fireAtWallMs: Int64
    /// AlarmReason JSON name.
    public let reason: String
    /// schedule() returned (written false before, true after).
    public var confirmed: Bool
    public var seenAlerting: Bool
    public let channel: AlarmChannelKind

    public init(alarmId: String, generation: Int64, fireAtWallMs: Int64, reason: String, confirmed: Bool,
                seenAlerting: Bool, channel: AlarmChannelKind) {
        self.alarmId = alarmId
        self.generation = generation
        self.fireAtWallMs = fireAtWallMs
        self.reason = reason
        self.confirmed = confirmed
        self.seenAlerting = seenAlerting
        self.channel = channel
    }
}

public struct FiredRec: Sendable, Codable, Equatable {
    public let alarmId: String
    public let kind: SystemAlarmKind
    public let generation: Int64
    /// Trip clock; nil before the trip was loaded.
    public let firedAtMs: Int64?
    public let firedAtWallMs: Int64

    public init(alarmId: String, kind: SystemAlarmKind, generation: Int64, firedAtMs: Int64?, firedAtWallMs: Int64) {
        self.alarmId = alarmId
        self.kind = kind
        self.generation = generation
        self.firedAtMs = firedAtMs
        self.firedAtWallMs = firedAtWallMs
    }
}

public struct AlarmLedger: Sendable, Codable, Equatable {
    public var ledgerVersion: Int = 1
    public var activeTripId: String?
    public var nextGeneration: Int64 = 1
    /// Newest fallback/guard slot.
    public var current: AlarmSlotRec?
    /// Previous slot until its cancel succeeded (D4).
    public var stale: AlarmSlotRec?
    public var now: NowRingRec?
    public var lastFired: FiredRec?
    /// Newest last, ≤ ENDED_TRIP_IDS_MAX.
    public var endedTripIds: [String] = []
    public var interruptedAlerted = false

    public init() {}
    public static let empty = AlarmLedger()

    /// Ids this ledger knows for the active trip (current, stale, now).
    public var knownIds: [String] {
        [current?.alarmId, stale?.alarmId, now?.alarmId].compactMap { $0 }
    }

    public mutating func markEnded(_ tripId: String, max: Int) {
        endedTripIds.removeAll { $0 == tripId }
        endedTripIds.append(tripId)
        if endedTripIds.count > max { endedTripIds.removeFirst(endedTripIds.count - max) }
    }
}

/// Written by StopIntent (and the T17.2 secondary intents) before anything else (D12). ring_events.json = [RingEventRec],
/// newest last, ≤ 16.
public struct RingEventRec: Sendable, Codable, Equatable {
    /// dismiss = Stop (T17); snooze / routeBack = secondary button (T17.2 D4).
    public enum Action: String, Sendable, Codable { case dismiss, snooze, routeBack }
    public let tripId: String
    public let alarmId: String
    public let kind: SystemAlarmKind
    public let action: Action
    public let atWallMs: Int64

    public init(tripId: String, alarmId: String, kind: SystemAlarmKind, action: Action, atWallMs: Int64) {
        self.tripId = tripId
        self.alarmId = alarmId
        self.kind = kind
        self.action = action
        self.atWallMs = atWallMs
    }

    /// dismiss / routeBack end the trip; snooze does not.
    public var endsTrip: Bool { action != .snooze }
}

public enum RingEventPicker {
    /// T17.2 §3.4: the event of `tripId` that counts at restore. The newest by `atWallMs`; a dismiss/routeBack of the same
    /// alarm wins over a newer snooze (the user stopped that alarm). nil = none of this trip.
    public static func effective(_ events: [RingEventRec], tripId: String) -> RingEventRec? {
        let mine = events.filter { $0.tripId == tripId }
        guard var newest = mine.first else { return nil }
        for e in mine.dropFirst() where e.atWallMs >= newest.atWallMs { newest = e }
        if newest.action == .snooze,
           let end = mine.filter({ $0.alarmId == newest.alarmId && $0.endsTrip }).max(by: { $0.atWallMs < $1.atWallMs }) {
            return end
        }
        return newest
    }
}

/// launch_action.json (T17.2 D7): written by the route-back intent, taken once by `AlarmHostApi.consumeLaunchAction`.
/// No coordinates; `pastM` is the distance past the destination (T27 D6). Never logged.
public struct LaunchActionRec: Sendable, Codable, Equatable, CustomStringConvertible {
    public static let overshootRoute = "overshootRoute"
    public let kind: String
    public let tripId: String
    public let pastM: Int?
    public let atWallMs: Int64
    public let atElapsedMs: Int64
    public let bootSessionId: String?

    public init(kind: String = LaunchActionRec.overshootRoute, tripId: String, pastM: Int?, atWallMs: Int64,
                atElapsedMs: Int64, bootSessionId: String?) {
        self.kind = kind
        self.tripId = tripId
        self.pastM = pastM
        self.atWallMs = atWallMs
        self.atElapsedMs = atElapsedMs
        self.bootSessionId = bootSessionId
    }

    public var description: String { "LaunchActionRec(\(kind), pastM \(pastM == nil ? "unset" : "set"))" }
}

/// JSON helpers shared by the store implementations (no coordinates in any of these types).
public enum LedgerCodec {
    public static func encode<T: Encodable>(_ v: T) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return try e.encode(v)
    }

    public static func decode<T: Decodable>(_ type: T.Type, _ d: Data) throws -> T { try JSONDecoder().decode(type, from: d) }
}
