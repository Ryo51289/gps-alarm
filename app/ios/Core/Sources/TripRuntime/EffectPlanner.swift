// Step → effects (docs/specs/T17.md §4.5, §5.2). Pure, fixed order.
import Trip

public enum TrackingMode: Sendable, Equatable { case idle, starting, tracking, headless, ending }

public enum StopCause: Sendable, Equatable { case snoozed, dismissed, tripEnded }

public struct RingRequest: Sendable, Equatable {
    public let tripId: String
    public let reason: AlarmReason
    public let snoozeAllowed: Bool
    public let distanceM: Int?
    public let etaS: Int?
    public let batteryPct: Int?
    public let atWallMs: Int64
}

public enum Effect: Sendable, Equatable {
    /// D5, unless a live slot already rings in [nowWall, guardAtWallMs] (`EffectPlanner.needsGuard`, parity Android).
    case armRingGuard(guardAtWallMs: Int64)
    case persistNow(budgetMs: Int64)
    case ringNow(RingRequest)
    /// Re-enters the engine right after this Step.
    case feed(EngineInput)
    case stopRinging(StopCause)
    case notice(show: TripNotice?, clear: TripNotice?)
    /// Only in .tracking.
    case applySampling(LocationRequestSpec)
    /// §5.6.2; result → feed(.fallbackScheduled).
    case scheduleFallback(targetAtMs: Int64)
    /// Every fallback/guard slot of the trip (not on SUPERSEDED).
    case cancelFallbacks
    case setTimer(dueTripMs: Int64)
    case cancelTimer
    case persist
    case publish
    /// Stop/cancel all alarms, stop location, clear notices, finish (§5.7).
    case endTrip(FinishedRecord)
}

public struct RingFacts: Sendable, Equatable {
    /// Some alarm of the trip alerting, or a confirmed "now" not yet due + grace.
    public let ringingNow: Bool
    public let ringingKind: SystemAlarmKind?
    public let ringStartedAtWallMs: Int64?
    /// The ringing alarm (recorded as lastFired when a fallback/guard slot is fed as FallbackFired).
    public let ringingAlarmId: String?

    public init(ringingNow: Bool, ringingKind: SystemAlarmKind?, ringStartedAtWallMs: Int64?, ringingAlarmId: String? = nil) {
        self.ringingNow = ringingNow
        self.ringingKind = ringingKind
        self.ringStartedAtWallMs = ringStartedAtWallMs
        self.ringingAlarmId = ringingAlarmId
    }

    public static let none = RingFacts(ringingNow: false, ringingKind: nil, ringStartedAtWallMs: nil)
}

public struct PlanInput: Sendable {
    public let prevView: TripView?
    public let step: Step
    public let meta: TripMeta
    public let mode: TrackingMode
    public let facts: RingFacts
    public let ledger: AlarmLedger
    public let timerDueTripMs: Int64?
    public let params: EngineParams
    public let nowWallMs: Int64
    public let nowTripMs: Int64
    public let constants: RuntimeConstants
    /// Spec R1: `liveSlot(ledger, freshList)`, computed by the runtime for Steps with Alarm(ringNow).
    public let liveSlot: AlarmSlotRec?

    public init(prevView: TripView?, step: Step, meta: TripMeta, mode: TrackingMode, facts: RingFacts, ledger: AlarmLedger,
                timerDueTripMs: Int64?, params: EngineParams, nowWallMs: Int64, nowTripMs: Int64,
                constants: RuntimeConstants = .default, liveSlot: AlarmSlotRec? = nil) {
        self.liveSlot = liveSlot
        self.prevView = prevView
        self.step = step
        self.meta = meta
        self.mode = mode
        self.facts = facts
        self.ledger = ledger
        self.timerDueTripMs = timerDueTripMs
        self.params = params
        self.nowWallMs = nowWallMs
        self.nowTripMs = nowTripMs
        self.constants = constants
    }
}

public enum EffectPlanner {
    /// Spec R1: the first of [current, stale] still `scheduled` in the system list; nil when the list is unreadable
    /// (adding a guard is the safe side). A cancelled, rung or lost slot is never live.
    public static func liveSlot(_ l: AlarmLedger, list: [SystemAlarmInfo]?) -> AlarmSlotRec? {
        guard let list else { return nil }
        for c in [l.current, l.stale].compactMap({ $0 }) where list.contains(where: { $0.id == c.alarmId && $0.state == .scheduled }) {
            return c
        }
        return nil
    }

    /// Spec R1 (parity Android `cur.targetAtWallMs in nowWall..atWall`): a guard is needed unless the live slot rings in
    /// [nowWall, guardAt].
    public static func needsGuard(live: AlarmSlotRec?, nowWallMs: Int64, guardAtWallMs: Int64) -> Bool {
        guard let c = live else { return true }
        return c.targetAtWallMs < nowWallMs || c.targetAtWallMs > guardAtWallMs
    }

    public static func plan(_ p: PlanInput) -> [Effect] {
        var fx: [Effect] = []
        let view = p.step.view
        var alarmEvent: TripEvent.Alarm?
        for case let .alarm(a) in p.step.events { alarmEvent = a; break }
        if let a = alarmEvent, a.ringNow {
            let guardAt = p.nowWallMs + Int64(p.params.fallbackLagS) * 1000
            // No guard when an alarm of the trip is already ringing (live "now", or a fallback/guard slot fed below):
            // it could only ring a second time ~30 s later (ITR31 b, overshoot while the first ring is live).
            if !p.facts.ringingNow, needsGuard(live: p.liveSlot, nowWallMs: p.nowWallMs, guardAtWallMs: guardAt) { fx.append(.armRingGuard(guardAtWallMs: guardAt)) }
            fx.append(.persistNow(budgetMs: p.constants.preRingPersistBudgetMs))
            let f = p.facts
            if f.ringingNow && (f.ringingKind == .fallback || f.ringingKind == .guardSlot) {
                // Obligation 3: a fallback/guard alarm of this trip is ringing right now.
                let started = f.ringStartedAtWallMs.map { p.nowTripMs - max(0, p.nowWallMs - $0) } ?? p.nowTripMs
                fx.append(.feed(.fallbackFired(atMs: p.nowTripMs, firedAtMs: started)))
            } else if f.ringingNow && f.ringingKind == .now {
                // One ring per trip: the "now" alarm is live already.
            } else {
                fx.append(.ringNow(RingRequest(tripId: p.meta.tripId, reason: a.reason, snoozeAllowed: a.snoozeAllowed,
                                               distanceM: a.distanceM, etaS: a.etaS, batteryPct: a.batteryPct,
                                               atWallMs: p.nowWallMs)))
            }
        }
        var ended: TripEvent.TripEnded?
        for e in p.step.events {
            switch e {
            case .snoozed: fx.append(.stopRinging(.snoozed))
            case let .preAlert(x):
                fx.append(.notice(show: .preAlert(distanceM: x.distanceM, etaS: x.etaS, byDistance: p.meta.mode == .distance),
                                  clear: nil))
            case let .samplingPolicyChanged(x):
                if p.mode == .tracking { fx.append(.applySampling(LocationRequestMapper.spec(x.policy, p.params))) }
            case let .gpsLost(x):
                switch x.cause {
                case .neverAcquired: fx.append(.notice(show: .noGpsYet, clear: nil))
                case .permissionRevoked: fx.append(.notice(show: .permissionRevoked, clear: nil))
                case .servicesOff: fx.append(.notice(show: .servicesOff, clear: nil))
                case .noFixTimeout: break
                }
            case .gpsRecovered:
                fx.append(.notice(show: nil, clear: .noGpsYet))
                fx.append(.notice(show: nil, clear: .permissionRevoked))
                fx.append(.notice(show: nil, clear: .servicesOff))
            case let .fallbackAlarmChanged(x):
                if let at = x.fallbackAtMs {
                    fx.append(.scheduleFallback(targetAtMs: at))
                } else if x.cause != .superseded {
                    fx.append(.cancelFallbacks)
                }
            case let .tripEnded(x): ended = x
            default: break
            }
        }
        if view.fallbackStatus == .failed && p.prevView?.fallbackStatus != .failed {
            fx.append(.notice(show: .fallbackFailed, clear: nil))
        }
        if view.fallbackStatus == .confirmed && p.prevView?.fallbackStatus == .failed {
            fx.append(.notice(show: nil, clear: .fallbackFailed))
        }
        if ended == nil {
            var due = view.wakeAtMs
            if p.mode == .tracking {
                let awake = p.nowTripMs + p.constants.awakeTickMaxMs
                due = min(due ?? awake, awake)
            }
            if due != p.timerDueTripMs {
                if let d = due { fx.append(.setTimer(dueTripMs: d)) } else { fx.append(.cancelTimer) }
            }
        }
        fx.append(.persist)
        fx.append(.publish)
        if let e = ended { fx.append(.endTrip(FinishedRecordBuilder.fromEvent(tripId: p.meta.tripId, e))) }
        return fx
    }
}

/// §5.6.1: is something of this trip ringing (or about to)?
public enum RingFactsReader {
    public static func facts(tripId: String, list: [SystemAlarmInfo], ledger: AlarmLedger, nowWallMs: Int64,
                             constants: RuntimeConstants = .default) -> RingFacts {
        if let a = list.first(where: { $0.tripId == tripId && $0.state == .alerting }) {
            return RingFacts(ringingNow: true, ringingKind: a.kind, ringStartedAtWallMs: a.fireAtWallMs, ringingAlarmId: a.id)
        }
        if let n = ledger.now, n.confirmed, !n.seenAlerting, nowWallMs <= n.fireAtWallMs + constants.nowAlertGraceMs {
            return RingFacts(ringingNow: true, ringingKind: .now, ringStartedAtWallMs: n.fireAtWallMs, ringingAlarmId: n.alarmId)
        }
        return .none
    }
}

/// T17.2 (review T17 round 3 risk): a slot of the ledger whose time has passed and which is gone from a readable `list()`
/// although the runtime never saw it ring (`lastFired`). It rang while the app was suspended and was stopped, maybe by
/// the user on the lock screen, whose StopIntent can still be on its way. A "now" ring decided meanwhile waits for
/// STOP_INTENT_GRACE_MS first. Pure.
public enum RingHold {
    public static func slot(_ l: AlarmLedger, list: [SystemAlarmInfo], nowWallMs: Int64) -> AlarmSlotRec? {
        [l.current, l.stale].compactMap { $0 }.first { s in
            s.targetAtWallMs <= nowWallMs && l.lastFired?.alarmId != s.alarmId && !list.contains { $0.id == s.alarmId }
        }
    }
}
