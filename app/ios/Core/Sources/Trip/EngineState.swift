// Engine state = snapshot v1 (T10 §7.1, T12 §4). Field order matches the snapshot key order.

struct FixRec: Sendable, Equatable {
    var fixAtMs: Int64
    var lat: Double
    var lng: Double
    var accM: Double
    var d: Double
    var groundSample: Double?
}

enum AlarmSource: Sendable, Equatable {
    case engine, fallback
    var jsonName: String { switch self { case .engine: "ENGINE"; case .fallback: "FALLBACK" } }
    init?(jsonName: String) {
        switch jsonName { case "ENGINE": self = .engine; case "FALLBACK": self = .fallback; default: return nil }
    }
}

struct AlarmState: Sendable, Equatable {
    var atMs: Int64?
    var reason: AlarmReason?
    var source: AlarmSource?
    var lastRingAtMs: Int64?
    var lastReason: AlarmReason?
    var ringing: Bool
    var snoozeCount: Int
    var snoozeUntilMs: Int64?
    var dismissedAtMs: Int64?

    static let empty = AlarmState(atMs: nil, reason: nil, source: nil, lastRingAtMs: nil, lastReason: nil, ringing: false,
                                  snoozeCount: 0, snoozeUntilMs: nil, dismissedAtMs: nil)
}

struct FallbackState: Sendable, Equatable {
    var targetAtMs: Int64?
    var emittedAtMs: Int64?
    var status: FallbackStatus
    var confirmedAtMs: Int64?
    var resync: Bool
    var near: Bool

    static let cleared = FallbackState(targetAtMs: nil, emittedAtMs: nil, status: .notSet, confirmedAtMs: nil,
                                       resync: false, near: false)
}

struct BatteryState: Sendable, Equatable {
    var levelPct: Int?
    var charging: Bool
    var segT0: Int64?
    var segL0: Int?
    var armed: Bool
    var riskEmitted: Bool
    var choice: UserActionKind?
    var choicePct: Int?

    static let initial = BatteryState(levelPct: nil, charging: false, segT0: nil, segL0: nil, armed: false,
                                      riskEmitted: false, choice: nil, choicePct: nil)
}

struct EndedState: Sendable, Equatable {
    var outcome: TripOutcome
    var endReason: EndReason
    var atMs: Int64
}

public struct EngineState: Sendable, Equatable {
    var snapshotVersion: Int
    var params: EngineParams
    var config: TripConfig
    var nowMs: Int64
    var startedAtMs: Int64
    var phase: TripPhase
    var gps: GpsStatus
    var locationCause: AvailabilityCause
    var last: FixRec?
    var stopAnchor: FixRec?
    var recent: [FixRec]
    var rejects: [FixRec]
    var dSmooth: Double?
    var dStartM: Double?
    var minD: Double?
    /// T10.5 round 3e: minD comes from a GPS-gap chord (not from an observed fix); gates the `notCloser` overshoot term.
    var minDChord: Bool = false
    var last3: [Double]
    var ground: Double?
    var closing: Double?
    var movingTimeS: Double
    var movingSamples: Int
    var movingDistM: Double
    var stopStartMs: Int64?
    var slow: Bool
    var cvGuard: [Double]
    var policy: SamplingPolicy?
    var policyIntervalAtLastFixS: Int
    var gpsLostAtMs: Int64?
    var lostEmittedBeforeFirstFix: Bool
    var preAlertArmed: Bool
    var preAlertFired: Bool
    var arrivedFired: Bool
    var alarm: AlarmState
    var overshootAtMs: Int64?
    var overshootPastM: Int?
    var fallback: FallbackState
    var battery: BatteryState
    var maxTripDurationS: Int
    var droppedFixes: Int
    var ended: EndedState?

    public var tripId: String { config.tripId }

    /// Initial state built by `start` (T12 §4).
    static func initial(config: TripConfig, params: EngineParams, nowMs: Int64) -> EngineState {
        EngineState(
            snapshotVersion: 1, params: params, config: config, nowMs: nowMs, startedAtMs: nowMs,
            phase: .acquiring, gps: .noFixYet, locationCause: .available,
            last: nil, stopAnchor: nil, recent: [], rejects: [],
            dSmooth: nil, dStartM: nil, minD: nil, minDChord: false, last3: [],
            ground: nil, closing: nil, movingTimeS: 0.0, movingSamples: 0, movingDistM: 0.0,
            stopStartMs: nil, slow: false, cvGuard: [],
            policy: nil, policyIntervalAtLastFixS: 0,
            gpsLostAtMs: nil, lostEmittedBeforeFirstFix: false,
            preAlertArmed: false, preAlertFired: false, arrivedFired: false,
            alarm: .empty, overshootAtMs: nil, overshootPastM: nil,
            fallback: .cleared, battery: .initial, maxTripDurationS: params.maxTripMinS, droppedFixes: 0, ended: nil)
    }
}
