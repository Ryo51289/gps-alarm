// Trip Engine reducer (T10 §2.5, §3, §4.12, §7.2; T12 §5 C1–C14).

public enum TripEngine {
    /// T10 §3 `start` (T12 C3): initial state, then steps 3–10 as a Tick without input. Throws `TripConfigError` (C11).
    public static func start(config: TripConfig, params: EngineParams, nowMs: Int64) throws(TripConfigError) -> Step {
        try validate(config)
        var w = StepWork(s: EngineState.initial(config: config, params: params, nowMs: nowMs), now: nowMs)
        w.runFromStep3()
        return w.finish()
    }

    /// One input → one Step (T10 §4.12).
    public static func reduce(_ state: EngineState, _ input: EngineInput) -> Step {
        // 1. Clamp the clock; ENDED ignores every input.
        if state.phase == .ended { return endedStep(state) }
        var w = StepWork(s: state, now: TMath.max(state.nowMs, input.atMs))
        w.s.nowMs = w.now
        // 2. Input.
        w.applyInput(input)
        // 3–10.
        w.runFromStep3()
        return w.finish()
    }

    /// Restore after the process restarts (T10 §7.2, T12 C1, C6).
    public static func restore(_ state: EngineState, nowMs: Int64, info: RestoreInfo) -> Step {
        if state.phase == .ended { return endedStep(state) }
        var w = StepWork(s: state, now: TMath.max(state.nowMs, nowMs))
        w.s.nowMs = w.now
        if w.restoreBranch(info) { return w.finish() }   // DISMISSED: no Tick
        w.runFromStep3()                                  // as reduce(s, Tick(now)); events merged after restore events
        return w.finish()
    }

    public static func encodeSnapshot(_ state: EngineState) -> String { SnapshotCodec.encode(state) }

    public static func decodeSnapshot(_ json: String) throws(SnapshotError) -> EngineState { try SnapshotCodec.decode(json) }

    // MARK: - Internals

    static func validate(_ c: TripConfig) throws(TripConfigError) {
        if c.tripId.isEmpty { throw TripConfigError(field: "tripId", rule: "empty") }
        if !c.destLat.isFinite || !(c.destLat >= -90.0 && c.destLat <= 90.0) {
            throw TripConfigError(field: "destLat", rule: "out of range")
        }
        if !c.destLng.isFinite || !(c.destLng >= -180.0 && c.destLng < 180.0) {
            throw TripConfigError(field: "destLng", rule: "out of range")
        }
        if c.mode == .distance && c.distanceThresholdM == nil {
            throw TripConfigError(field: "distanceThresholdM", rule: "required")
        }
        if c.mode == .time && c.timeThresholdMin == nil { throw TripConfigError(field: "timeThresholdMin", rule: "required") }
        if let d = c.distanceThresholdM, !(d >= 200 && d <= 10000) {
            throw TripConfigError(field: "distanceThresholdM", rule: "out of range")
        }
        if let t = c.timeThresholdMin, !(t >= 5 && t <= 60) {
            throw TripConfigError(field: "timeThresholdMin", rule: "out of range")
        }
    }

    /// Step of an ENDED state: no change, no event; view computed from the state at its own clock.
    static func endedStep(_ s: EngineState) -> Step {
        let e = Estimator.estimate(s, now: s.nowMs)
        let view = ViewBuilder.buildView(s, e, predicted: nil, risk: false, wakeAtMs: nil)
        return Step(state: s, events: [], view: view)
    }
}

/// Mutable working copy for one Step (like T12 `StepWork`).
struct StepWork {
    var s: EngineState
    let now: Int64
    var events: [TripEvent] = []
    var fixAccepted = false
    var firstFix = false
    var e: Estimate? = nil
    var eComputed = false
    var predicted = Predicted.none
    var predictedComputed = false
    /// Policy at the start of the Step (T10.4 §4.8: step 9 folds its interval into policyIntervalAtLastFixS).
    let policyAtStart: SamplingPolicy?

    init(s: EngineState, now: Int64) {
        self.s = s
        self.now = now
        self.policyAtStart = s.policy
    }

    var p: EngineParams { s.params }

    // MARK: alarm helpers (T10 §3)

    mutating func markRing(_ reason: AlarmReason, ringAt: Int64, ringNow: Bool) {
        s.alarm.ringing = true
        s.alarm.lastReason = reason
        s.alarm.lastRingAtMs = TMath.max(s.alarm.lastRingAtMs ?? ringAt, ringAt)
        if s.alarm.atMs == nil {
            s.alarm.atMs = ringAt
            s.alarm.reason = reason
            s.alarm.source = ringNow ? .engine : .fallback
        }
    }

    mutating func appendAlarmPlaceholder(_ reason: AlarmReason, ringNow: Bool) {
        events.append(.alarm(.init(atMs: now, reason: reason, ringNow: ringNow, snoozeAllowed: false, distanceM: nil,
                                   etaS: nil, batteryPct: nil)))
    }

    /// Enter ALARMING/OVERSHOT with `Alarm(ringNow=true)` (C1: SUPERSEDED only if a target was set).
    mutating func raiseNow(_ reason: AlarmReason, to phase: TripPhase) {
        if s.fallback.targetAtMs != nil {
            events.append(.fallbackAlarmChanged(.init(atMs: now, fallbackAtMs: nil, cause: .superseded)))
        }
        s.fallback = .cleared
        markRing(reason, ringAt: now, ringNow: true)
        s.phase = phase
        appendAlarmPlaceholder(reason, ringNow: true)
    }

    /// Fallback alarm already rang elsewhere: `Alarm(ringNow=false)`, no SUPERSEDED.
    mutating func raiseFallback(_ reason: AlarmReason, ringAt: Int64) {
        s.fallback = .cleared
        markRing(reason, ringAt: ringAt, ringNow: false)
        s.phase = .alarming
        appendAlarmPlaceholder(reason, ringNow: false)
    }

    mutating func endTrip(_ reason: EndReason) {
        if s.fallback.targetAtMs != nil {
            events.append(.fallbackAlarmChanged(.init(atMs: now, fallbackAtMs: nil, cause: .tripEnded)))
        }
        s.fallback = .cleared
        s.alarm.ringing = false
        s.phase = .ended
        let outcome: TripOutcome
        if s.overshootAtMs != nil || reason == .alarmUnanswered {
            outcome = .missed
        } else if s.alarm.atMs != nil {
            outcome = s.alarm.snoozeCount >= 1 ? .snoozed : .onTime
        } else {
            outcome = .cancelled
        }
        s.ended = EndedState(outcome: outcome, endReason: reason, atMs: now)
        events.append(.tripEnded(.init(atMs: now, outcome: outcome, endReason: reason, summary: ViewBuilder.summary(s))))
    }

    // MARK: step 2

    mutating func applyInput(_ input: EngineInput) {
        switch input {
        case let .locationFix(f):
            applyFix(f)
        case .tick:
            break
        case let .batterySample(atMs, level, charging):
            BatteryRule.onBattery(&s, atMs: atMs, levelPct: level, charging: charging)
        case let .locationAvailability(_, cause):
            GpsMonitor.onAvailability(&s, now: now, cause: cause, events: &events)
        case let .fallbackScheduled(_, x, ok):
            if let t = s.fallback.targetAtMs, t == x {
                if ok {
                    s.fallback.status = .confirmed
                    s.fallback.confirmedAtMs = now
                } else {
                    s.fallback.status = .failed
                    s.fallback.confirmedAtMs = nil
                }
            }
        case let .fallbackFired(_, firedAtMs):
            let ringAt = TMath.min(firedAtMs, now)   // clampNow (C14)
            switch s.phase {
            case .acquiring, .tracking: raiseFallback(.fallback, ringAt: ringAt)
            case .snoozed: raiseFallback(.snoozeEnd, ringAt: ringAt)
            case .alarming, .overshot:
                s.alarm.ringing = true
                s.alarm.lastRingAtMs = TMath.max(s.alarm.lastRingAtMs ?? ringAt, ringAt)
            case .ended: break
            }
        case .alarmSilenced:
            if s.phase == .alarming || s.phase == .overshot { s.alarm.ringing = false }
        case let .userAction(_, action):
            applyUser(action)
        }
    }

    mutating func applyUser(_ action: UserActionKind) {
        switch action {
        case .dismiss:
            if s.phase == .alarming || s.phase == .snoozed || s.phase == .overshot {
                s.alarm.dismissedAtMs = now
                endTrip(.dismissed)
            }
        case .snooze:
            if s.phase == .alarming && s.alarm.snoozeCount < p.maxSnoozes {
                let until = now + TMath.ms(p.snoozeS)
                s.phase = .snoozed
                s.alarm.snoozeCount += 1
                s.alarm.snoozeUntilMs = until
                s.alarm.ringing = false
                let fbAt = until + TMath.ms(p.fallbackLagS)
                s.fallback = FallbackState(targetAtMs: fbAt, emittedAtMs: now, status: .requested, confirmedAtMs: nil,
                                           resync: false, near: false)
                events.append(.snoozed(.init(atMs: now, untilMs: until)))
                events.append(.fallbackAlarmChanged(.init(atMs: now, fallbackAtMs: fbAt, cause: .snooze)))
            }
        case .stopTrip:
            endTrip(.userStop)
        case .batteryMaxSaving, .batteryAlarmAt5, .batteryAlarmEarlier:
            BatteryRule.onChoice(&s, action)
        }
    }

    mutating func applyFix(_ f: LocationFix) {
        var rec = FixRec(fixAtMs: f.fixAtMs, lat: f.lat, lng: f.lng, accM: f.accuracyM, d: 0.0, groundSample: nil)
        var speed: Double? = nil
        if let v = f.speedMps, v.isFinite, !(v < 0) { speed = v }
        let wasFirst = s.last == nil
        let noRejectsSincePrev = s.rejects.isEmpty   // T10.5 round 3f: classifyFix clears `rejects` on ACCEPT
        switch FixFilter.classifyFix(&s, atMs: f.atMs, fix: &rec) {
        case .drop:
            s.droppedFixes += 1
            return
        case let .reanchor(d):
            rec.d = d
            s.recent = [rec]
            s.rejects = []
            s.last = rec
            s.dSmooth = d
            s.minD = d
            s.minDChord = false
            s.alarmedChordD = nil   // T10.7 round 2 (C31)
            s.last3 = [d]
            s.stopStartMs = nil
            s.stopAnchor = nil
        case let .accept(d):
            rec.d = d
            // T10.5 round 3/3b (§4.11): first in ACCEPT, from the state before this fix (gps, lostAfterS, last). A chord through
            // the destination lowers minD and ends the stop from before the gap (the vehicle went along the chord).
            // Round 3f: not after a fix rejected as IMPLAUSIBLE since L (`rejects` read before ACCEPT cleared it).
            // T10.7 (C30): also in ALARMING/SNOOZED (overshootAtMs == nil). T10.7 round 2 (C31): after the first alarm the chord
            // only proves "came near" (alarmedChordD); minD, minDChord and the stop are left alone, so "moved away > 1 km" is
            // measured from observed fixes.
            let notYet = (s.phase == .acquiring || s.phase == .tracking) && s.alarm.atMs == nil
            if noRejectsSincePrev, OvershootDetector.isGapFix(s, l: s.last, f: rec), let l = s.last,
               let dChord = OvershootDetector.chordClosest(l, rec, s.config) {
                if notYet {
                    s.stopStartMs = nil
                    s.stopAnchor = nil
                    if s.minD == nil || dChord < s.minD! {
                        s.minD = dChord
                        s.minDChord = true   // T10.5 round 3e
                    }
                } else if let a = s.alarmedChordD {
                    s.alarmedChordD = TMath.min(a, dChord)
                } else {
                    s.alarmedChordD = dChord
                }
            }
            if let last = s.last {
                let sample = SpeedEstimator.speedSample(last: last, f: rec, speedMps: speed, p)
                rec.groundSample = sample.groundSample
                SpeedEstimator.applyMotion(&s, last: last, f: rec, sample: sample)
            }
            FixFilter.updateRecent(&s, rec)
            s.last = rec
            OvershootDetector.updateMinDLast3(&s)
        }
        GpsMonitor.onFixReceived(&s, now: now, events: &events)
        s.policyIntervalAtLastFixS = s.policy?.intervalS ?? 0   // C2: before SamplingPlanner
        fixAccepted = true
        if wasFirst {
            firstFix = true
            if s.dStartM == nil { s.dStartM = s.dSmooth }
        }
        if s.phase == .acquiring { s.phase = .tracking }
    }

    // MARK: restore branch (T10 §7.2). Returns true when the Tick part must not run (DISMISSED).

    mutating func restoreBranch(_ info: RestoreInfo) -> Bool {
        let now = self.now
        func clampNow(_ x: Int64?) -> Int64? { x.map { TMath.min($0, now) } }
        let alarmed = s.alarm.atMs != nil
        let due = s.fallback.targetAtMs.map { $0 <= now } ?? false
        switch info.status {
        case .dismissed:
            let firedAt = clampNow(info.firedAtMs) ?? clampNow(s.fallback.targetAtMs) ?? now
            if !alarmed {
                markRing(.fallback, ringAt: firedAt, ringNow: false)
                appendAlarmPlaceholder(.fallback, ringNow: false)
            } else if s.phase == .snoozed {
                markRing(.snoozeEnd, ringAt: firedAt, ringNow: false)
                appendAlarmPlaceholder(.snoozeEnd, ringNow: false)
            }
            s.alarm.dismissedAtMs = TMath.max(s.alarm.atMs ?? now, clampNow(info.dismissedAtMs) ?? now)
            endTrip(.dismissed)
            return true
        case .rang:
            rangBranch(firedAt: clampNow(info.firedAtMs) ?? now, alarmed: alarmed)
        case .unknown:
            if due, let target = s.fallback.targetAtMs {
                rangBranch(firedAt: clampNow(info.firedAtMs) ?? target, alarmed: alarmed)
            }
        case .missing:
            if due && !alarmed {
                s.fallback = .cleared
                markRing(.fallbackMissed, ringAt: now, ringNow: true)
                s.phase = .alarming
                appendAlarmPlaceholder(.fallbackMissed, ringNow: true)
            } else if !alarmed {
                s.fallback = FallbackState(targetAtMs: nil, emittedAtMs: nil, status: .notSet, confirmedAtMs: nil,
                                           resync: true, near: false)
            } else if s.phase == .snoozed {
                if let until = s.alarm.snoozeUntilMs, now < until {
                    let at = until + TMath.ms(p.fallbackLagS)
                    s.fallback = FallbackState(targetAtMs: at, emittedAtMs: now, status: .requested, confirmedAtMs: nil,
                                               resync: false, near: false)
                    events.append(.fallbackAlarmChanged(.init(atMs: now, fallbackAtMs: at, cause: .resync)))
                } else {
                    s.fallback = .cleared
                }
            }
        case .pending:
            break
        }
        return false
    }

    mutating func rangBranch(firedAt: Int64, alarmed: Bool) {
        if !alarmed {
            raiseFallback(.fallback, ringAt: firedAt)
        } else if s.phase == .snoozed {
            raiseFallback(.snoozeEnd, ringAt: firedAt)
        }
    }

    // MARK: steps 3–9

    mutating func runFromStep3() {
        if s.phase == .ended { return }
        // 3. Alarm unanswered.
        if s.phase == .alarming || s.phase == .overshot, let l = s.alarm.lastRingAtMs,
           now - l >= TMath.ms(p.alarmMaxActiveS) {
            endTrip(.alarmUnanswered)
            return
        }
        // 4. GPS timeouts.
        GpsMonitor.onTime(&s, now: now, events: &events)
        // 5. Estimator (once per Step, C7).
        e = Estimator.estimate(s, now: now)
        eComputed = true
        if fixAccepted { Estimator.updateSlow(&s) }
        if firstFix { s.maxTripDurationS = ModeRules.maxTripDurationFromFirstFix(e, p) }
        // 6. Snooze end.
        if s.phase == .snoozed, let until = s.alarm.snoozeUntilMs, now >= until {
            raiseNow(.snoozeEnd, to: .alarming)
        }
        // 7. Overshoot.
        if fixAccepted && OvershootDetector.isOvershoot(s) {
            // T10.7 round 2 (C31): from the estimated closest point (nearD; = minD when no chord was taken after the alarm).
            let past = TMath.roundHalfUp((s.dSmooth ?? 0) - (OvershootDetector.nearD(s) ?? 0))
            s.overshootAtMs = now
            s.overshootPastM = past
            switch s.phase {
            case .alarming:
                if s.alarm.ringing { s.phase = .overshot } else { raiseNow(.overshoot, to: .overshot) }
            default:
                raiseNow(.overshoot, to: .overshot)
            }
            events.append(.overshoot(.init(atMs: now, pastM: past)))
        }
        // 8. T10.6 (3), C27: slow-vehicle passed-closest mark, on every Step with an accepted fix (ACCEPT/REANCHOR), in every phase.
        if fixAccepted { OvershootDetector.updatePassAnchor(&s, e) }
        // 8. Mode / GPS / battery / passed-closest / timeout; pre-alert.
        if (s.phase == .acquiring || s.phase == .tracking) && s.alarm.atMs == nil {
            if firstFix { s.preAlertArmed = !PreAlertRule.inZone(s, e) }
            let passed = fixAccepted && OvershootDetector.isPassedClosest(s, e)
            if let reason = ModeRules.alarmReason(s, e, now: now, passedClosest: passed) {
                raiseNow(reason, to: .alarming)
            } else if PreAlertRule.shouldPreAlert(s, e) {
                s.preAlertFired = true
                events.append(.preAlert(.init(atMs: now, distanceM: 0, etaS: nil)))
            }
        }
        predicted = ModeRules.predictedAlarmAt(s, e, now: now)
        predictedComputed = true
        // 9. Arrived · battery risk · SamplingPlanner · FallbackPlanner.
        if fixAccepted && !s.arrivedFired, let d = s.dSmooth, d <= Double(p.arrivedRadiusM) {
            s.arrivedFired = true
            events.append(.arrived(.init(atMs: now, distanceM: TMath.roundHalfUp(d))))
        }
        let risk = BatteryRule.riskOf(s, predictedNoBattery: predicted.noBattery, now: now)
        if risk.risk && !s.battery.riskEmitted && s.battery.choice == nil, let level = s.battery.levelPct {
            s.battery.riskEmitted = true
            events.append(.lowBatteryRisk(.init(atMs: now, levelPct: level,
                                                availableMin: TMath.roundHalfUp(TMath.max(0.0, risk.availableS) / 60.0),
                                                neededMin: TMath.roundHalfUp(risk.neededS / 60.0))))
        }
        if let tier = SamplingPlanner.targetTier(s, e, predicted: predicted.withBattery, now: now),
           case let policy = SamplingPlanner.policyFor(tier, p, maxSaving: s.battery.choice == .batteryMaxSaving), s.policy != policy {
            s.policy = policy
            events.append(.samplingPolicyChanged(.init(atMs: now, policy: policy)))
        }
        // T10.4 (GAP-2, §4.8, §4.12): lostAfterS never shrinks between two fixes, so c2 stays > now and Tick(now) stays silent (I14).
        s.policyIntervalAtLastFixS = TMath.max(s.policyIntervalAtLastFixS,
                                               TMath.max(policyAtStart?.intervalS ?? 0, s.policy?.intervalS ?? 0))
        if (s.phase == .acquiring || s.phase == .tracking) && s.alarm.atMs == nil {
            FallbackPlanner.planFallback(&s, e, predicted: predicted.withBattery, now: now, events: &events)
        }
    }

    // MARK: step 10

    mutating func finish() -> Step {
        if !eComputed { e = Estimator.estimate(s, now: now) }   // ENDED Steps: view from the ENDED state at now (C22)
        // C16 (T10.3): snoozeUntilMs is non-nil only while SNOOZED; every reader ran earlier in the Step.
        if s.phase != .snoozed && s.alarm.snoozeUntilMs != nil { s.alarm.snoozeUntilMs = nil }
        if !predictedComputed { predicted = ModeRules.predictedAlarmAt(s, e, now: now) }
        // Stable sort by T10 §2.3 rank (insertion sort keeps equal ranks in emission order).
        var sorted = events
        var i = 1
        while i < sorted.count {
            let x = sorted[i]
            var j = i - 1
            while j >= 0 && sorted[j].sortRank > x.sortRank {
                sorted[j + 1] = sorted[j]
                j -= 1
            }
            sorted[j + 1] = x
            i += 1
        }
        let risk = BatteryRule.riskOf(s, predictedNoBattery: predicted.noBattery, now: now).risk
        let wake = WakePlanner.wakeAt(s, wakeBasis: predicted.wakeBasis, wakeBattery: predicted.wakeBattery, now: now)
        let view = ViewBuilder.buildView(s, e, predicted: predicted.withBattery, risk: risk, wakeAtMs: wake)
        let snoozeAllowed = s.phase == .alarming && s.alarm.snoozeCount < p.maxSnoozes
        // C4: numeric event fields come from the view of the same Step.
        for k in 0..<sorted.count {
            switch sorted[k] {
            case let .alarm(a):
                sorted[k] = .alarm(.init(atMs: a.atMs, reason: a.reason, ringNow: a.ringNow, snoozeAllowed: snoozeAllowed,
                                         distanceM: view.distanceM, etaS: view.etaS, batteryPct: view.batteryPct))
            case let .preAlert(pa):
                sorted[k] = .preAlert(.init(atMs: pa.atMs, distanceM: view.distanceM ?? 0, etaS: view.etaS))
            default:
                break
            }
        }
        return Step(state: s, events: sorted, view: view)
    }
}
