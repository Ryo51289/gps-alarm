// alarmUpdates interpretation, ledger reconciliation and restore planning (docs/specs/T17.md §5.6.4, §5.8). Pure.
import Trip

public enum AlarmAction: Sendable, Hashable {
    /// Ledger lastFired first, then FallbackFired(firedAt = toTrip(wall)) (obligation 5).
    case fallbackFired(alarmId: String, kind: SystemAlarmKind, generation: Int64, firedAtWallMs: Int64)
    case cancel(id: String, channel: AlarmChannelKind)
    case stop(id: String, channel: AlarmChannelKind)
    /// ledger.now.seenAlerting = true, ringRetryPending = false.
    case nowSeenAlerting(id: String)
    /// Re-check after STOP_INTENT_GRACE_MS (obligation 6).
    case checkGone(id: String, goneAtWallMs: Int64)
}

public enum AlarmUpdateInterpreter {
    /// `protectedIds` (T17.2.1 §3): rescue alarms of snooze ring events the runtime has not handled yet; never cancelled here
    /// (the snooze handling takes or cancels them).
    public static func interpret(tripId: String?, prev: [SystemAlarmInfo], cur: [SystemAlarmInfo], ledger: AlarmLedger,
                                 expectedStops: Set<String>, nowWallMs: Int64,
                                 protectedIds: Set<String> = []) -> [AlarmAction] {
        var out: [AlarmAction] = []
        var prevById: [String: SystemAlarmInfo] = [:]
        for p in prev { prevById[p.id] = p }
        var curById: [String: SystemAlarmInfo] = [:]
        for c in cur { curById[c.id] = c }
        var cancelled = Set<String>()
        func cancelScheduled(_ pred: (SystemAlarmInfo) -> Bool) {
            for o in cur where o.tripId == tripId && o.state == .scheduled && pred(o) && !cancelled.contains(o.id)
                && !protectedIds.contains(o.id) {
                cancelled.insert(o.id)
                out.append(.cancel(id: o.id, channel: o.channel))
            }
        }
        if let tripId {
            for a in cur where a.tripId == tripId && a.state == .alerting && prevById[a.id]?.state != .alerting {
                switch a.kind {
                case .fallback, .guardSlot:
                    if ledger.lastFired?.alarmId != a.id {
                        out.append(.fallbackFired(alarmId: a.id, kind: a.kind, generation: a.generation,
                                                  firedAtWallMs: a.fireAtWallMs ?? nowWallMs))
                    }
                    // Obligation 4 (iOS): every other scheduled alarm of the trip (other slot, guard, unrung "now").
                    cancelScheduled { $0.id != a.id }
                case .now:
                    out.append(.nowSeenAlerting(id: a.id))
                    // K4 #3, #4; D6: only scheduled fallback/guard slots, never an alerting alarm.
                    cancelScheduled { $0.kind != .now }
                }
            }
            for p in prev where p.tripId == tripId && p.state == .alerting && curById[p.id]?.state != .alerting {
                if expectedStops.contains(p.id) { continue }
                out.append(.checkGone(id: p.id, goneAtWallMs: nowWallMs))
            }
        }
        for a in cur where ledger.endedTripIds.contains(a.tripId) && a.tripId != tripId {
            if a.state == .alerting { out.append(.stop(id: a.id, channel: a.channel)) }
            else if a.state == .scheduled { out.append(.cancel(id: a.id, channel: a.channel)) }
        }
        return out
    }
}

public enum LedgerReconciler {
    /// Runs before RestorePlanner. Returns the ledger to use and the system calls to make. T17.2.1 §3: a rescue alarm
    /// (RESCUE_GENERATION) is never adopted as the newest slot; one of `protectedIds` (rescue of a snooze ring event not
    /// handled yet) is left for the snooze handling, any other is an orphan and cancelled.
    public static func reconcile(_ ledger: AlarmLedger, list: [SystemAlarmInfo]?, activeTripId: String?, nowWallMs: Int64,
                                 protectedIds: Set<String> = [], toTrip: (Int64) -> Int64)
        -> (ledger: AlarmLedger, actions: [AlarmAction]) {
        guard let list else { return (ledger, []) }
        var l = ledger
        var actions: [AlarmAction] = []
        for a in list where l.endedTripIds.contains(a.tripId) && a.tripId != activeTripId {
            if a.state == .alerting { actions.append(.stop(id: a.id, channel: a.channel)) }
            else if a.state == .scheduled { actions.append(.cancel(id: a.id, channel: a.channel)) }
        }
        if let trip = activeTripId {
            let slots = list.filter { $0.tripId == trip && $0.state == .scheduled && $0.kind != .now }
            let currentAlive = l.current.map { c in list.contains { $0.id == c.alarmId } } ?? false
            let candidates = slots.filter { $0.generation != RuntimeConstants.rescueGeneration }
            if !currentAlive, let newest = candidates.max(by: { $0.generation < $1.generation }) {
                // Process died between schedule() and the ledger write: adopt the newest slot.
                let target = newest.fireAtWallMs ?? nowWallMs
                l.current = AlarmSlotRec(alarmId: newest.id, kind: newest.kind, generation: newest.generation,
                                         targetAtMs: toTrip(target), targetAtWallMs: target, setAtWallMs: nowWallMs,
                                         channel: newest.channel)
                if newest.generation >= l.nextGeneration { l.nextGeneration = newest.generation + 1 }
            }
            let keep = Set([l.current?.alarmId, l.stale?.alarmId].compactMap { $0 }).union(protectedIds)
            for s in slots where !keep.contains(s.id) { actions.append(.cancel(id: s.id, channel: s.channel)) }
            if var n = l.now, !n.confirmed, list.contains(where: { $0.id == n.alarmId }) {
                n.confirmed = true
                l.now = n
            }
        }
        return (l, actions)
    }
}

public enum RestorePlanner {
    /// `facts` = the stored engine state; `toTrip` converts a wall time with the (re-)anchored clock.
    public static func plan(_ facts: EngineFacts, ledger: AlarmLedger, events: [RingEventRec], list: [SystemAlarmInfo]?,
                            nowTripMs: Int64, toTrip: (Int64) -> Int64) -> RestoreInfo {
        func resolved(_ f: FiredRec) -> Int64 { f.firedAtMs ?? toTrip(f.firedAtWallMs) }
        // T17.2 §3.4: the newest event of the trip; dismiss/routeBack → DISMISSED, snooze → RANG (the runtime then feeds
        // UserAction(SNOOZE) when the engine is ALARMING). Same "fired at" for both.
        if let d = RingEventPicker.effective(events, tripId: facts.tripId) {
            var fired: Int64?
            if let lf = ledger.lastFired { fired = resolved(lf) }
            if fired == nil {
                let w = list?.first(where: { $0.id == d.alarmId })?.fireAtWallMs
                    ?? (ledger.now?.alarmId == d.alarmId ? ledger.now?.fireAtWallMs : nil)
                    ?? (ledger.current?.alarmId == d.alarmId ? ledger.current?.targetAtWallMs : nil)
                    ?? (ledger.stale?.alarmId == d.alarmId ? ledger.stale?.targetAtWallMs : nil)
                fired = w.map(toTrip)
            }
            if !d.endsTrip { return RestoreInfo(status: .rang, firedAtMs: fired ?? toTrip(d.atWallMs)) }
            return RestoreInfo(status: .dismissed, firedAtMs: fired ?? toTrip(d.atWallMs), dismissedAtMs: toTrip(d.atWallMs))
        }
        guard let list else { return RestoreInfo(status: .unknown) }
        if let a = list.first(where: { $0.tripId == facts.tripId && $0.state == .alerting }) {
            return RestoreInfo(status: .rang, firedAtMs: a.fireAtWallMs.map(toTrip) ?? nowTripMs)
        }
        let fb = facts.fallbackTargetAtMs
        if fb != nil, let lf = ledger.lastFired, resolved(lf) > facts.nowMs {
            return RestoreInfo(status: .rang, firedAtMs: resolved(lf))
        }
        guard let fb else { return RestoreInfo(status: .pending) }
        if let c = ledger.current, list.contains(where: { $0.id == c.alarmId && $0.state == .scheduled }) {
            return RestoreInfo(status: .pending)
        }
        if fb <= nowTripMs { return RestoreInfo(status: .rang, firedAtMs: fb) }
        return RestoreInfo(status: .missing)
    }
}

/// Spec "Sửa spec sau review vòng 1" R2 (replaces §5.8 step 2 / G3): after a restore in which the engine believes it is
/// ringing but nothing of the trip is alerting, ring again only when no system alarm ever took that ring.
public enum RestoreRingDecision: Sendable, Equatable {
    case none
    case silenced(atWallMs: Int64)
    case ring
}

public enum RestoreRingPolicy {
    /// `alarmWallMs` = ledger.now?.fireAtWallMs ?? toWall(engine lastRingAtMs). Only called when phase ∈ {ALARMING,
    /// OVERSHOT}, view.alarmRinging and no alarm of the trip is alerting.
    public static func decide(info: RestoreInfo, ledger: AlarmLedger, list: [SystemAlarmInfo]?, nowWallMs: Int64,
                              lagMs: Int64, graceMs: Int64, alarmWallMs: Int64) -> RestoreRingDecision {
        func scheduled(_ id: String) -> Bool { list?.contains { $0.id == id && $0.state == .scheduled } ?? false }
        // 1. A fallback/guard slot rang (K4 #8).
        if info.status == .rang { return .silenced(atWallMs: nowWallMs) }
        // 2. The system took the "now" alarm.
        if let n = ledger.now, n.confirmed {
            if list != nil && scheduled(n.alarmId) { return .none }
            if list == nil && nowWallMs < n.fireAtWallMs + graceMs { return .none }
            return .silenced(atWallMs: n.fireAtWallMs)
        }
        // 3. A guard slot (armed before PersistNow, D7) or a near fallback slot covers this ring.
        if let cover = [ledger.current, ledger.stale].compactMap({ $0 }).first(where: { $0.targetAtWallMs <= alarmWallMs + lagMs + 1_000 }) {
            if list != nil && scheduled(cover.alarmId) { return .none }
            if list == nil && nowWallMs < cover.targetAtWallMs { return .none }
            if cover.targetAtWallMs <= nowWallMs { return .silenced(atWallMs: cover.targetAtWallMs) }
            return .ring
        }
        // 4. The engine decided to ring and no system alarm took it (G3).
        return .ring
    }
}
