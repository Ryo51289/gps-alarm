import Testing
@testable import Trip

/// Exact port of the Kotlin tester's `TesterT122Test` (T10.5 + vòng 2/3/3f; docs/test-reports/T12.2.md): same generator
/// (splitmix64 seeded `seed * golden + 0x7654321`, shared by reference like the Kotlin class), same draw order, builders and
/// platform model, so every run is the Kotlin run and `<report>/unit/t122-{a,b,c,d,e}*.txt` are byte-identical to the Kotlin files.
///  - (a) restore while GPS is lost, the first fix 0–150 s before the fallback (round-2 `soon` branch, urgent later shift).
///  - (b) / U115 the destination passed inside a tunnel (no TIMEOUT; alarm within 2 fix periods after the gap) + RK20 d variant.
///  - (c) GPS lost > 1 h with a changing true speed (T10.6, pinned). (d) no wake-up storm. (e) fuzz of the urgent-shift path.
/// Platform model (`Sim`): one OS fallback alarm per FallbackAlarmChanged(at), set before the old one is cancelled (after a lag);
/// FallbackScheduled(ok) right after; a fired OS alarm is FallbackFired and cancels the others; kill keeps the OS alarms.
@Suite("TesterT132Tests")
struct TesterT132Tests {
    static let S = KW.S
    static let p = EngineParams.defaults

    final class Rng {
        private var x: UInt64
        init(_ seed: Int64) { x = UInt64(bitPattern: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x7654321 }

        func next() -> UInt64 {
            x &+= 0x9E37_79B9_7F4A_7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        func int(_ n: Int) -> Int { Int((next() >> 1) % UInt64(n)) }
        func dbl() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
        func dbl(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * dbl() }
        func chance(_ q: Double) -> Bool { dbl() < q }
    }

    /// Signed distance to the destination (negative = past it) under a piecewise-constant closing speed; times absolute ms.
    final class Truth {
        let d0: Double
        let t0: Int64
        var segs: [(Int64, Double)] = []

        init(_ d0: Double, _ t0: Int64) {
            self.d0 = d0
            self.t0 = t0
        }

        func dAt(_ t: Int64) -> Double {
            var d = d0
            for i in segs.indices {
                let (s0, v) = segs[i]
                if s0 >= t { break }
                let s1 = i + 1 < segs.count ? Swift.min(segs[i + 1].0, t) : t
                d -= v * Double(s1 - s0) / 1000.0
            }
            return d
        }

        func speedAt(_ t: Int64) -> Double { segs.last { $0.0 <= t }?.1 ?? 0.0 }

        /// First ms at which dAt <= x (binary search up to `until`), or nil.
        func crossAt(_ x: Double, _ until: Int64) -> Int64? {
            if dAt(until) > x { return nil }
            var lo = t0
            var hi = until
            while hi - lo > 1 {
                let m = (lo + hi) / 2
                if dAt(m) > x { lo = m } else { hi = m }
            }
            return hi
        }
    }

    static func fixAt(_ t: Int64, _ d: Double, acc: Double = 8.0, spd: Double? = nil, ageMs: Int64 = 0, eastM: Double = 0.0) -> LocationFix {
        let p0 = KW.pointOnMeridian(d)
        let pt = eastM == 0.0 ? p0 : KW.jitter(p0, eastM, 0.0)
        return LocationFix(atMs: t, fixAtMs: t - ageMs, lat: pt.lat, lng: pt.lng, accuracyM: acc, speedMps: spd)
    }

    static func kd(_ x: Double) -> String { KW.kd(x) }
    static func rel(_ t: Int64) -> String { kd(Double(t - S) / 1000.0) }
    static func reason(_ a: TripEvent.Alarm?) -> String { a?.reason.jsonName ?? "null" }

    /// Kotlin `input.javaClass.simpleName`.
    static func simpleName(_ x: EngineInput) -> String {
        switch x {
        case .locationFix: "LocationFix"
        case .tick: "Tick"
        case .batterySample: "BatterySample"
        case .locationAvailability: "LocationAvailability"
        case .fallbackScheduled: "FallbackScheduled"
        case .fallbackFired: "FallbackFired"
        case .alarmSilenced: "AlarmSilenced"
        case .userAction: "UserAction"
        }
    }

    final class OsAlarm {
        let at: Int64
        var cancelAt: Int64 = .max
        var cancelCause: FallbackCause? = nil
        init(_ at: Int64) { self.at = at }
    }

    struct LastInfo {
        let t: Int64
        let fBefore: Int64?
        let statusBefore: FallbackStatus
        let predictedAfter: Int64?
        let moved: Bool
    }

    /// Engine + platform model with checks at every Step (see the suite comment).
    final class Sim {
        var step: Step
        let tag: String
        let rng: Rng
        let okP: Double
        let cancelLagMaxMs: Int64
        var records: [StepRecord] = []
        var viol: [String] = []
        var os: [OsAlarm] = []
        var engineRinging = false
        var osRinging = false
        var alarms: [(TripEvent.Alarm, String)] = []
        var allEvents: [TripEvent] = []
        var osFired = 0
        var raceFired = 0
        var supersedeRaces: [String] = []
        var urgent = 0
        var soonShifts = 0
        var dead = false
        var steps = 0
        var lastInput = "start"
        var truthSpeed: ((Int64) -> Double)? = nil
        var believedStopOverLag: [String] = []
        var lastInfo: LastInfo? = nil
        var osFirstKinds: [String: Int] = [:]
        var osFirstEarly: [Double] = []
        /// U126: the state after the Step of the first Alarm.
        var firstAlarmState: EngineState? = nil
        /// U126 classes: states after every Step; harness death intervals [kill, restart).
        var states: [EngineState] = []
        var deadIntervals: [(Int64, Int64)] = []
        private var killedAt: Int64? = nil

        init(_ start: Step, _ tag: String, _ rng: Rng, okP: Double = 1.0, cancelLagMaxMs: Int64 = 0) {
            self.step = start
            self.tag = tag
            self.rng = rng
            self.okP = okP
            self.cancelLagMaxMs = cancelLagMaxMs
            afterStep(nil, start, "start", nil)
        }

        var now: Int64 { step.state.nowMs }
        var ended: Bool { step.state.phase == .ended }
        var p: EngineParams { TesterT132Tests.p }

        func nextOs() -> OsAlarm? { os.filter { $0.at < $0.cancelAt }.min { $0.at < $1.at } }

        func v(_ msg: String) {
            if viol.count < 20 { viol.append("\(tag) t=\(rel(now)) after \(lastInput): \(msg)") }
        }

        @discardableResult
        func feed(_ input: EngineInput, _ label: String? = nil) -> Step {
            precondition(!dead)
            let prev = step
            let s = TripEngine.reduce(prev.state, input)
            switch input {
            case .locationFix, .batterySample: noteInfo(prev, s)
            default: break
            }
            return afterStep(prev, s, label ?? simpleName(input), input)
        }

        /// The OS fallback alarm `a` fires; delivered as FallbackFired unless the process is dead.
        func fireOs(_ a: OsAlarm) {
            os.removeAll { $0 === a }
            osFired += 1
            if a.cancelAt != .max { raceFired += 1 }
            if engineRinging || osRinging {
                let c = a.cancelCause
                if c == .superseded || c == .tripEnded {
                    supersedeRaces.append("\(tag) t=\(rel(now)) F=\(rel(a.at)) cause=\(c!.jsonName)")
                } else {
                    v("double ring: OS fallback at \(rel(a.at)) fires while \(engineRinging ? "the engine" : "an OS") alarm rings "
                      + "(race cause \(c?.jsonName ?? "null"))")
                }
            }
            osRinging = true
            os.removeAll()   // obligation 5
            if !dead && alarms.isEmpty { classifyOsFirst(a.at) }
            if !dead { feed(.fallbackFired(atMs: Swift.max(now, a.at), firedAtMs: a.at), "FallbackFired(\(rel(a.at)))") }
        }

        private func classifyOsFirst(_ f: Int64) {
            let li = lastInfo
            let q = TMath.ms(p.fallbackQuietBeforeS)
            if let li, li.fBefore == f, li.statusBefore != .failed, let pA = li.predictedAfter,
               f - li.t >= TMath.ms(p.fallbackMinLeadS), pA - li.t > q, pA >= f, !li.moved {
                v("eligible for the urgent later shift but not rescued (info at \(rel(li.t)), F \(rel(f)), P \(rel(pA)))")
            }
            let pv = step.view.predictedAlarmAtMs
            let believedStop = step.view.gps == .ok && step.state.stopStartMs != nil && pv != nil && pv! - now <= q
            let k: String
            if believedStop { k = "believedStop<=Q" }
            else if let li, li.t > (step.state.fallback.emittedAtMs ?? .min) { k = "newInfoAfterPlanning" }
            else { k = "plannedOnSameInfo" }
            osFirstKinds[k, default: 0] += 1
            if let pv { osFirstEarly.append(Double(pv - f) / 1000.0) }
            let ts = truthSpeed.map { kd($0(f)) } ?? "null"
            if believedStop && f > pv! + TMath.ms(p.fallbackLagS) + 1000 {
                believedStopOverLag.append("\(rel(f)): F-P=\(kd(Double(f - pv!) / 1000.0)) s truthSpeed=\(ts)")
            }
            if believedStop && f > pv! + TMath.ms(p.fallbackLagS + p.fallbackNearSlackS) + 1000 {
                v("believed-stop fallback later than predicted + lag + slack + 1 s: F=\(rel(f)) P(prev)=\(rel(pv!)) F-P=\(kd(Double(f - pv!) / 1000.0)) s "
                  + "emitted=\(step.state.fallback.emittedAtMs.map(rel) ?? "null") truthSpeed=\(ts)")
            }
        }

        private func noteInfo(_ prev: Step, _ s: Step) {
            let f = prev.state.fallback.targetAtMs
            let moved = f != nil && s.events.fallbacks.contains { ($0.fallbackAtMs ?? .min) > f! }
            lastInfo = LastInfo(t: s.state.nowMs, fBefore: f, statusBefore: prev.state.fallback.status,
                                predictedAfter: s.view.predictedAlarmAtMs, moved: moved)
        }

        /// Key of the first alarm as in the firstAlarm table of FuzzStats.
        func firstKey() -> String {
            guard let f = alarms.first else { return "none" }
            let src = f.1.hasPrefix("FallbackFired") ? "os" : (f.1.hasPrefix("RESTORE") ? "restore" : "engine")
            return "\(src) \(f.0.reason.jsonName)"
        }

        func kill(_ atMs: Int64? = nil) {
            killedAt = atMs ?? step.state.nowMs
            dead = true
            engineRinging = false   // the engine ring dies with the process (AlarmRingService is T16)
        }

        /// Restart at `at`: RANG if an OS alarm fired while dead, else `info`.
        @discardableResult
        func restart(_ at: Int64, _ info: FallbackRestoreStatus) throws -> Step {
            precondition(dead)
            let f = nextOs()
            let prev = step
            let t: Int64
            let ri: RestoreInfo
            if let f, f.at <= at {
                fireOs(f)
                t = Swift.max(f.at, prev.state.nowMs)
                ri = RestoreInfo(status: .rang, firedAtMs: f.at)
            } else {
                if info == .missing { os.removeAll() }
                t = at
                ri = RestoreInfo(status: info)
            }
            dead = false
            if let k = killedAt { deadIntervals.append((k, t)) }
            killedAt = nil
            let snap = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(prev.state))
            let s = TripEngine.restore(snap, nowMs: t, info: ri)
            noteInfo(prev, s)
            return afterStep(prev, s, "RESTORE \(ri.status.jsonName)", nil)
        }

        @discardableResult
        func afterStep(_ prev: Step?, _ s: Step, _ label: String, _ input: EngineInput?) -> Step {
            step = s
            steps += 1
            states.append(s.state)
            lastInput = label
            records.append(StepRecord(t: Int((s.state.nowMs - S) / 1000), input: input.map { .input($0, fixIndex: nil) } ?? .start,
                                      events: s.events, view: s.view, v: ""))
            allEvents += s.events
            if !Runner.finite(s.state) { v("non-finite double in state") }
            // I14 and restore PENDING at now: silent, same state.
            if s.view.phase != .ended {
                let again = TripEngine.reduce(s.state, .tick(atMs: s.state.nowMs))
                if !again.events.isEmpty || again.state != s.state || again.view != s.view { v("I14 Tick(now) not silent") }
                let rp = TripEngine.restore(s.state, nowMs: s.state.nowMs, info: RestoreInfo(status: .pending))
                if !rp.events.isEmpty || rp.state != s.state { v("restore PENDING at now not silent") }
                if let w = s.view.wakeAtMs {
                    let rr = TripEngine.reduce(s.state, .tick(atMs: w))
                    let ok = !rr.events.alarms.isEmpty || rr.state.phase != s.state.phase || (rr.view.wakeAtMs ?? .min) > w
                    if !ok { v("Tick(wakeAt) neither rings nor re-arms later") }
                }
            }
            for e in s.events {
                switch e {
                case let .alarm(a):
                    if alarms.isEmpty { firstAlarmState = s.state }
                    alarms.append((a, label))
                    if a.ringNow {
                        if osRinging { v("double ring: engine Alarm(\(a.reason.jsonName), ringNow) while the OS fallback rings") }
                        if engineRinging { v("double ring: engine Alarm(\(a.reason.jsonName), ringNow) while the engine rings") }
                        engineRinging = true
                    }
                case let .fallbackAlarmChanged(x):
                    guard x.cause == .eta, let prev else { break }
                    let q = Checks.quietEmission(prev.view, s.view, x, s.state.params)
                    if q == true { urgent += 1 }
                    if q == false { v("I4 ETA emission inside the quiet window") }
                    let pf = prev.state.fallback
                    let cur = pf.targetAtMs
                    let at = x.fallbackAtMs
                    let pr = s.view.predictedAlarmAtMs
                    let nowS = s.state.nowMs
                    let far = pr != nil && pr! - nowS > TMath.ms(p.fallbackNearS)
                    let soon = q == nil && far && cur != nil && at != nil && at! > cur! && pf.status != .failed
                        && cur! - nowS <= TMath.ms(p.fallbackQuietBeforeS + p.fallbackMinIntervalS)
                        && nowS - (pf.emittedAtMs ?? nowS) < TMath.ms(p.fallbackMinIntervalS)
                    if soon { soonShifts += 1 }
                    // Every ETA emission is fallbackTarget of the end-of-Step state (planFallback is the last step): exactly for the
                    // urgent later shift, the round-2 far-zone shift and the far zone; near zone: target .. target + slack.
                    if let pr, let at {
                        let st = s.state
                        let est = Estimator.estimate(st, now: st.nowMs)
                        let target = FallbackPlanner.fallbackTarget(
                            now: st.nowMs, predicted: pr, predictedFb: FallbackPlanner.fallbackPredictedAt(st, est, predicted: pr, now: st.nowMs),
                            st.params)
                        let slackMs = TMath.ms(p.fallbackNearSlackS)
                        let exact = q == true || soon || far || cur == nil
                        if target == nil || (exact && at != target!) || (!exact && (at < target! || at > target! + slackMs)) {
                            v("ETA emission at \(rel(at)) vs fallbackTarget \(target.map(rel) ?? "null") (urgent=\(q == true) soon=\(soon) far=\(far))")
                        }
                    }
                case .tripEnded:
                    engineRinging = false
                    osRinging = false
                default:
                    break
                }
            }
            // Platform reaction: set the new OS alarm first, cancel the old one after a lag; then FallbackScheduled.
            for e in s.events {
                guard case let .fallbackAlarmChanged(x) = e else { continue }
                let lag: Int64 = cancelLagMaxMs > 0 ? Int64(rng.int(Int(cancelLagMaxMs) + 1)) : 0
                for a in os where a.cancelAt == .max {
                    a.cancelAt = s.state.nowMs + lag
                    a.cancelCause = x.cause
                }
                os.removeAll { $0.cancelAt <= s.state.nowMs }
                if let at = x.fallbackAtMs, s.state.phase != .ended {
                    let ok = rng.chance(okP)
                    if ok { os.append(OsAlarm(at)) }
                    let prev2 = step
                    let r = TripEngine.reduce(prev2.state, .fallbackScheduled(atMs: prev2.state.nowMs, fallbackAtMs: at, ok: ok))
                    afterStep(prev2, r, "FallbackScheduled(\(rel(at)), \(ok))", nil)
                    if !r.events.alarms.isEmpty { v("FallbackScheduled produced an alarm") }
                }
            }
            if s.events.contains(where: { if case .tripEnded = $0 { return true } else { return false } }) { os.removeAll() }
            return s
        }

        /// Harness invariants over the whole trip (I1–I7, I10–I13, C16), one alarm, no double ring.
        func finish() -> [String] {
            var out = viol
            out += Checks.invariants(records, p).prefix(10)
            if alarms.count > 1 { out.append("\(tag): \(alarms.count) alarms \(KW.klist(alarms.map { $0.0.reason.jsonName }))") }
            return out
        }

        /// Delivers the earliest of: OS fallback, wake-up Tick, `nextFix`; false when nothing is due before `until`.
        func advance(_ until: Int64, _ nextFix: Int64? = nil, _ fix: ((Int64) -> LocationFix)? = nil) -> Bool {
            if ended { return false }
            let f = nextOs()
            let fAt = f.map { Swift.max($0.at, now) }
            let wake = step.view.wakeAtMs
            guard let t = [fAt, wake, nextFix].compactMap({ $0 }).min() else { return false }
            if t >= until { return false }
            if let fAt, t == fAt, wake == nil || fAt < wake! {
                fireOs(f!)
            } else if let nf = nextFix, t == nf {
                feed(.locationFix(fix!(t)), "fix")
            } else {
                feed(.tick(atMs: t), "Tick")
            }
            return true
        }
    }

    static func interval(_ s: Step) -> Int64 { Int64(s.view.samplingPolicy?.intervalS ?? 5) * 1000 }

    // MARK: - (a) restore while GPS lost, first fix 0–150 s before F

    struct ResultA {
        let line: String
        let viol: [String]
    }

    static func scenarioA(_ lossSpeed: Double, _ y: Int, _ x: Double, _ status: FallbackRestoreStatus, _ doze: Bool,
                          _ seed: Int64) throws -> ResultA? {
        let config = KW.cfg(.distance, thr: 1000, hint: .train)
        let truth = Truth(120_000.0, S)
        truth.segs.append((S, 25.0))
        let lossAt = S + 900_000
        truth.segs.append((lossAt, lossSpeed))
        let rng = Rng(seed)
        let tag = "A loss=\(kd(lossSpeed)) y=\(y) x=\(kd(x)) \(status.jsonName) doze=\(doze)"
        let sim = Sim(try TripEngine.start(config: config, params: p, nowMs: S), tag, rng)
        var lastFix = S
        while true {
            let nf = Swift.max(lastFix + interval(sim.step), sim.now + 1)
            if nf >= lossAt { break }
            if !sim.advance(lossAt, nf, { t in lastFix = t; return fixAt(t, truth.dAt(t), spd: 25.0) }) { break }
        }
        while !sim.allEvents.contains(where: { if case .gpsLost = $0 { return true } else { return false } }) && sim.advance(.max) {}
        guard let pDr = sim.step.view.predictedAlarmAtMs else { return nil }
        let killAt = pDr - 700_000
        while sim.advance(killAt) {}
        if !sim.alarms.isEmpty { return nil }
        sim.kill()
        let tr = pDr - Int64(y) * 1000
        let fOld = sim.nextOs()?.at
        try sim.restart(tr, status)
        if !sim.alarms.isEmpty {
            return ResultA(line: "\(tag): restore rang \(sim.alarms[0].0.reason.jsonName) (F old \(fOld.map { kd(Double($0 - pDr) / 1000.0) } ?? "null") vs P)",
                           viol: sim.finish())
        }
        guard let f = sim.step.state.fallback.targetAtMs else { return nil }
        let tf = Swift.max(sim.now + 1, f - KW.kl(x * 1000.0))
        while sim.advance(tf) {}
        if !sim.alarms.isEmpty {
            // F = P + 30 s: a fix later than P + 1 s comes after the engine's own c3 alarm (GPS_LOST, ringNow).
            let a = sim.alarms[0].0
            var v = sim.finish()
            if !a.ringNow || a.reason != .gpsLost { v.append("\(tag): rang before the fix with \(a)") }
            return ResultA(line: "\(tag): rang before the fix \(a.reason.jsonName) ringNow=\(a.ringNow)", viol: v)
        }
        truth.segs.append((tf + 120_000, 25.0))
        let fBefore = sim.step.state.fallback.targetAtMs!
        let emittedBefore = sim.step.state.fallback.emittedAtMs!
        let fixStep = sim.feed(.locationFix(fixAt(tf, truth.dAt(tf), spd: lossSpeed)), "first fix")
        lastFix = tf
        let facs = fixStep.events.fallbacks
        let fac = facs.count == 1 ? facs[0] : nil
        let pNew = fixStep.view.predictedAlarmAtMs
        var guardN = 0
        while !sim.ended {
            guardN += 1
            if guardN >= 200_000 { break }
            let nf: Int64? = doze ? nil : Swift.max(lastFix + interval(sim.step), sim.now + 1)
            let wake = sim.step.view.wakeAtMs
            let fixFn = { (t: Int64) -> LocationFix in lastFix = t; return fixAt(t, truth.dAt(t), spd: truth.speedAt(t)) }
            if doze, let w = wake, rng.chance(0.5), (sim.nextOs()?.at ?? .max) > w {
                sim.feed(.locationFix(fixFn(w)), "fix@wake")
                continue
            }
            if !sim.advance(.max, nf, fixFn) { break }
        }
        let first = sim.alarms.first
        let cross = truth.crossAt(1000.0, S + 48 * 3_600_000)
        let firstAt = first?.0.atMs
        let facTxt = fac.map { "\($0.cause.jsonName)@+\($0.fallbackAtMs.map { a in kd(Double(a - tf) / 1000.0) } ?? "null")" } ?? "null"
        let lateTxt = firstAt != nil && cross != nil ? kd(Double(firstAt! - cross!) / 1000.0) : "null"
        let line = "\(tag): F-tRestore=\(kd(Double(fBefore - tr) / 1000.0)) fix at F-\(kd(Double(fBefore - tf) / 1000.0)) s "
            + "(now-emitted \(kd(Double(tf - emittedBefore) / 1000.0)) s) "
            + "Pnew-t=\(pNew.map { kd(Double($0 - tf) / 1000.0) } ?? "null") fac=\(facTxt) "
            + "first=\(reason(first?.0))/\(first.map { String($0.0.ringNow) } ?? "null") via \(first?.1 ?? "null") late-vs-cross=\(lateTxt) s "
            + "osFired=\(sim.osFired) urgent=\(sim.urgent) soon=\(sim.soonShifts)"
        var viol = sim.finish()
        if first == nil { viol.append("\(tag): no alarm") }
        let lead = fBefore - tf
        // The OS fallback never rings first: the fallback is moved later (at this Step, or at a later Step when the round-2 rule
        // does not apply yet: F − now > 90 s and the last emission < fallbackMinIntervalS ago) and the engine rings first.
        let mustMoveNow = lead >= TMath.ms(p.fallbackMinLeadS)
            && (lead <= TMath.ms(p.fallbackQuietBeforeS + p.fallbackMinIntervalS) || tf - emittedBefore >= TMath.ms(p.fallbackMinIntervalS))
        if mustMoveNow && (fac == nil || fac!.cause != .eta || (fac!.fallbackAtMs ?? 0) < tf + TMath.ms(p.fallbackNearS)) {
            viol.append("\(tag): not moved later at the fix Step: \(String(describing: fac))")
        }
        if !mustMoveNow && fac != nil { viol.append("\(tag): moved although not allowed yet: \(String(describing: fac))") }
        if let f0 = first, !f0.0.ringNow || f0.0.reason == .fallback { viol.append("\(tag): first alarm \(f0.0) via \(f0.1)") }
        return ResultA(line: line, viol: viol)
    }

    @Test("T132 a (= T122 a) restore while GPS lost then the first fix 0 to 150 s before the fallback: one alarm, no double ring, moved later")
    func a() throws {
        var out = ""
        var viol: [String] = []
        var runs = 0
        var moved = 0
        var seed: Int64 = 1
        for status in [FallbackRestoreStatus.pending, .unknown, .missing] {
            for lossSpeed in [0.0, 6.0] { for y in [35, 60, 90, 120] { for doze in [false, true] {
                for x in [150.0, 120.0, 91.0, 90.0, 89.0, 75.0, 63.0, 60.0, 45.0, 33.0, 31.0, 30.0, 29.0, 20.0, 10.0, 9.999, 5.0, 1.0] {
                    if x > Double(y + 30) { continue }
                    let sd = seed
                    seed += 1
                    guard let r = try Self.scenarioA(lossSpeed, y, x, status, doze, sd) else { continue }
                    runs += 1
                    if r.line.contains("fac=ETA") { moved += 1 }
                    out += r.line + "\n"
                    viol += r.viol
                }
            } } }
        }
        Report.shared.write("unit/t122-a-restore.txt", "runs=\(runs) moved=\(moved)\nviolations=\(KW.klist(Array(viol.prefix(40))))\n\(out)")
        #expect(runs >= 300, "runs \(runs)")
        #expect(viol.isEmpty, "violations \(viol.prefix(10))")
    }

    // MARK: - (b) destination passed inside a tunnel / U115

    struct ResultB {
        let key: String
        let line: String
        let viol: [String]
        let reason: AlarmReason?
        let lateS: Double?
        let gapFixAtMs: Int64?
        let firstAtMs: Int64?
        let awake: Bool
        let periodMs: Int64?
    }

    static func scenarioB(_ config: TripConfig, _ past: Double, _ x: Double, _ awake: Bool, _ fromStart: Bool,
                          implausibleInGap: Bool = false) throws -> ResultB {
        let thrTxt = config.distanceThresholdM.map(String.init) ?? config.timeThresholdMin.map(String.init) ?? ""
        let key = "\(config.mode.jsonName)\(thrTxt) fromStart=\(fromStart) awake=\(awake) past=\(KW.ki(past)) x=\(KW.ki(x))"
        let sim: Sim
        if fromStart {
            sim = Sim(try TripEngine.start(config: config, params: p, nowMs: S), "B \(key)", Rng(7))
            var lastFix = S
            let gapStart = S + 3_000_000   // 60 km − 10 m/s · 3 000 s = 30 km
            while true {
                let nf = Swift.max(lastFix + interval(sim.step), sim.now + 1)
                if nf > gapStart { break }
                if !sim.advance(.max, nf, { t in lastFix = t; return fixAt(t, 60_000.0 - 10.0 * Double(t - S) / 1000.0, spd: 10.0) }) { break }
            }
            precondition(sim.alarms.isEmpty)
        } else {
            let st = KW.trackingState(config, d: 30_000.0, ground: 10.0, closing: 10.0, tier: .dense)
            sim = Sim(TripEngine.reduce(st, .tick(atMs: S)), "B \(key)", Rng(7))
        }
        let d0 = sim.step.state.dSmooth!
        let fixAt0 = sim.step.state.last!.fixAtMs
        while !sim.allEvents.contains(where: { if case .gpsLost = $0 { return true } else { return false } }) && sim.alarms.isEmpty
            && sim.advance(.max) {}
        // U115 variant (T10.5 vòng 3f, RK20 d): one jump fix rejected as IMPLAUSIBLE right after the gap began (500 km away).
        if implausibleInGap && sim.alarms.isEmpty { sim.feed(.locationFix(fixAt(sim.now + 1_000, 500_000.0, spd: 10.0)), "implausible in gap") }
        let pDr = sim.step.view.predictedAlarmAtMs
        let f = (pDr ?? 0) + TMath.ms(p.fallbackLagS)
        let tf = f - KW.kl(x * 1000.0)
        while sim.advance(tf) {}
        let v2 = (d0 + past) / (Double(tf - fixAt0) / 1000.0)
        let truth = Truth(d0, fixAt0)
        truth.segs.append((fixAt0, v2))
        var lastFix = tf
        let rangBefore = !sim.alarms.isEmpty
        var periodMs: Int64? = nil
        if !rangBefore {
            sim.feed(.locationFix(fixAt(tf, truth.dAt(tf), spd: v2)), "first fix")
            periodMs = interval(sim.step)
            var guardN = 0
            while !sim.ended {
                guardN += 1
                if guardN >= 100_000 { break }
                let nf: Int64? = awake ? Swift.max(lastFix + interval(sim.step), sim.now + 1) : nil
                if !sim.advance(.max, nf, { t in lastFix = t; return fixAt(t, truth.dAt(t), spd: v2) }) { break }
            }
        }
        let first = sim.alarms.first?.0
        let thrD = config.mode == .distance ? Double(config.distanceThresholdM!) : 1000.0
        let cross = truth.crossAt(thrD, tf)!
        let late = first.map { Double($0.atMs - cross) / 1000.0 }
        let line = "\(key): v=\(KW.jf(v2, 2)) m/s, F=\(rel(f)) fix at \(rel(tf)) cross(\(KW.ki(thrD)) m)=\(rel(cross)) "
            + "dest=\(rel(truth.crossAt(0.0, tf)!)); \(rangBefore ? "rang before the fix; " : "")first=\(reason(first))/\(first.map { String($0.ringNow) } ?? "null") "
            + "at \(first.map { rel($0.atMs) } ?? "null") late-vs-cross=\(late.map(kd) ?? "null") s (no fix after the gap: GPS_LOST at P+1, late "
            + "\(kd(Double(pDr! + 1000 - cross) / 1000.0)) s) "
            + "maxTripS=\(sim.step.state.maxTripDurationS) urgent=\(sim.urgent) soon=\(sim.soonShifts) osFired=\(sim.osFired)"
        return ResultB(key: key, line: line, viol: sim.finish() + (first == nil ? ["B \(key): no alarm"] : []), reason: first?.reason,
                       lateS: late, gapFixAtMs: rangBefore ? nil : tf, firstAtMs: first?.atMs, awake: awake, periodMs: periodMs)
    }

    static let u115Periods: Int64 = 2         // T10.5 vòng 3c
    static let u115VariantTimeout = 3         // RK20 d, measured in T12.2 round 8

    static let configsB: [TripConfig] = [KW.cfg(.distance, thr: 1000), KW.cfg(.time, thrMin: 15), KW.cfg(.smart)]

    @Test("U115 (= T122 b tunnel) destination passed inside a tunnel, first fix <= 90 s before the fallback: no TIMEOUT, alarm <= 2 fix periods after the gap")
    func u115() throws {
        var out = ""
        var viol: [String] = []
        var late: [String] = []
        var afterFix: [String] = []
        var afterFixS: [Double: Int] = [:]
        var timeouts = 0
        for config in Self.configsB { for fromStart in [false, true] { for awake in [true, false] {
            for past in [300.0, 1_000.0, 2_000.0, 2_900.0, 3_100.0, 3_500.0, 5_000.0, 10_000.0] {
                for x in [90.0, 60.0, 31.0, 29.0, 20.0, 10.0] {
                    if config.mode != .distance && (!fromStart || x == 60.0 || x == 20.0) { continue }
                    let r = try Self.scenarioB(config, past, x, awake, fromStart)
                    out += r.line + "\n"
                    viol += r.viol
                    if r.reason == .timeout { timeouts += 1 }
                    if (r.lateS ?? .greatestFiniteMagnitude) > 900.0 {
                        late.append("\(r.key) \(r.reason?.jsonName ?? "null") +\(r.lateS.map { String(KW.kl($0)) } ?? "null") s")
                    }
                    if let gf = r.gapFixAtMs, r.awake {
                        let after = (r.firstAtMs ?? .max) - gf
                        afterFixS[Double(after) / 1000.0, default: 0] += 1
                        if after > Self.u115Periods * r.periodMs! + 1_000 {
                            afterFix.append("\(r.key) \(r.reason?.jsonName ?? "null") at fix + \(Self.kd(Double(after) / 1000.0)) s")
                        }
                    }
                }
            }
        } } }
        let afterTxt = "{" + afterFixS.keys.sorted().map { "\(Self.kd($0))=\(afterFixS[$0]!)" }.joined(separator: ", ") + "}"
        Report.shared.write("unit/t122-b-tunnel.txt",
                            "violations=\(KW.klist(Array(viol.prefix(40))))\nTIMEOUT=\(timeouts)\nawake runs, first alarm − first fix after the gap (s → runs): \(afterTxt)\n"
                                + "over the bound (\(afterFix.count)): \(KW.klist(afterFix))\n"
                                + "late > 900 s after the crossing (\(late.count)):\n\(late.joined(separator: "\n"))\n\n\(out)")
        #expect(viol.isEmpty, "violations \(viol.prefix(10))")
        #expect(timeouts == 0, "TIMEOUT runs (before T10.5 round 3: 32)")
        #expect(afterFix.isEmpty, "\(afterFix)")
        #expect(late.isEmpty, "\(late)")
    }

    @Test("U115 variant (= T122, RK20 d): one IMPLAUSIBLE fix inside the gap in 10 % of runs, TIMEOUT count recorded (3 of 32)")
    func u115Variant() throws {
        var out = ""
        var viol: [String] = []
        var reasons: [String: Int] = [:]
        var timeouts = 0
        var runs = 0
        var idx = 0
        for config in Self.configsB { for fromStart in [false, true] { for awake in [true, false] {
            for past in [300.0, 1_000.0, 2_000.0, 2_900.0, 3_100.0, 3_500.0, 5_000.0, 10_000.0] {
                for x in [90.0, 60.0, 31.0, 29.0, 20.0, 10.0] {
                    if config.mode != .distance && (!fromStart || x == 60.0 || x == 20.0) { continue }
                    let i = idx
                    idx += 1
                    if i % 10 != 0 { continue }
                    let r = try Self.scenarioB(config, past, x, awake, fromStart, implausibleInGap: true)
                    runs += 1
                    out += r.line + "\n"
                    viol += r.viol
                    reasons[r.reason?.jsonName ?? "null", default: 0] += 1
                    if r.reason == .timeout { timeouts += 1 }
                }
            }
        } } }
        Report.shared.write("unit/t122-b-tunnel-implausible.txt",
                            "runs=\(runs) TIMEOUT=\(timeouts) firstAlarm=\(KW.kmap(reasons)) violations=\(KW.klist(Array(viol.prefix(40))))\n\n\(out)")
        #expect(viol.isEmpty, "violations \(viol.prefix(10))")
        #expect(runs == 32)
        #expect(timeouts == Self.u115VariantTimeout, "RK20 d: TIMEOUT runs of the variant")
    }

    @Test("T132 b repro (= T122): passed the destination in a GPS gap, first fix 29 s before F and 3.1 km beyond → OVERSHOOT 10 s after the fix")
    func bRepro() {
        let n = Self.S
        let config = KW.cfg(.distance, thr: 1000)
        let dr = 11_800.0 + 10.0 * 1_761.0
        let st = KW.trackingState(config, now: n - 1_000, startedAt: n - 3_000_000, d: dr, ground: 10.0, closing: 10.0, gps: .lost,
                                  lastFixAt: n - 1_761_000, tier: .dense, maxTripS: 14_400,
                                  fallback: FallbackState(targetAtMs: n + 29_000, emittedAtMs: n - 600_000, status: .confirmed,
                                                          confirmedAtMs: n - 599_000, resync: false, near: true))
        var e = KDriver(from: st)
        let first = e.feed(.locationFix(Self.fixAt(n, -3_100.0, spd: 18.0)))
        let facs = first.events.fallbacks
        let fac = facs.count == 1 ? facs[0] : nil
        var s = first
        var t = n
        while s.events.alarms.isEmpty && t < n + 4 * 3_600_000 {
            t += Int64(s.view.samplingPolicy?.intervalS ?? 5) * 1000
            s = e.feed(.locationFix(Self.fixAt(t, -3_100.0 - 18.0 * Double(t - n) / 1000.0, spd: 18.0)))
        }
        let a = e.events().alarms.first
        let got = "gps=\(first.view.gps.jsonName) predicted-now=\(first.view.predictedAlarmAtMs.map { String(($0 - n) / 1000) } ?? "null") s "
            + "fac=\(fac?.cause.jsonName ?? "null")@\(fac?.fallbackAtMs.map { String(($0 - n) / 1000) } ?? "null") s; "
            + "first alarm \(Self.reason(a)) at \(a.map { String(($0.atMs - n) / 1000) } ?? "null") s after the fix"
        Report.shared.write("unit/t122-b-repro.txt", got + "\n")
        #expect(got == "gps=OK predicted-now=210 s fac=ETA@240 s; first alarm OVERSHOOT at 10 s after the fix")
    }

    // MARK: - (c) GPS lost > 1 h, changing speed (T10.6: U121)

    struct CRes {
        let line: String
        let lateS: Int64
        let lostLongAtS: Double?
    }

    /// T10.6 (U121): with W on (`params` gpsLostLongS > 0) the line gets a `lostLongAtS` column.
    static func scenarioC(_ lossS: Int, _ m: Double, _ mode: AlarmMode, _ params: EngineParams = TesterT132Tests.p) -> CRes {
        let config = mode == .distance ? KW.cfg(.distance, thr: 1000) : KW.cfg(mode)
        let d = 12.5 * (1180.0 + Double(lossS))
        let st = KW.trackingState(config, p: params, d: d, tier: .dense)
        let truth = Truth(d, S)
        let r = Rng(433)
        var t = S
        while t < S + 48 * 3_600_000 {
            truth.segs.append((t, 12.5 * m * (r.chance(0.5) ? 1.3 : 0.7)))
            t += 600_000
        }
        let sim = Sim(TripEngine.reduce(st, .tick(atMs: S)), "C", Rng(1))
        while sim.alarms.isEmpty && sim.advance(.max) {}
        let a = sim.alarms[0].0
        let dest = truth.crossAt(0.0, S + 48 * 3_600_000)!
        // Instant the true remaining time to the destination is 1 200 s.
        var lo = S
        var hi = dest
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if dest - mid > 1_200_000 { lo = mid } else { hi = mid }
        }
        let ideal = hi
        let cross = truth.crossAt(1000.0, dest)!
        // Hypothetical etaMinS rule (10 s grid from GpsLost).
        var etaMinAt: Int64? = nil
        var probe = S + 60_000
        while probe < a.atMs + 3_600_000 {
            let s1 = TripEngine.reduce(st, .tick(atMs: probe)).state
            if let em = Estimator.estimate(s1, now: s1.nowMs)?.etaMinS, em < Double(p.gpsLostAlarmEtaS) {
                etaMinAt = probe
                break
            }
            probe += 10_000
        }
        let s60 = TripEngine.reduce(st, .tick(atMs: S + 60_000)).state
        let lostLong = Estimator.estimate(s60, now: s60.nowMs)!.lostLongAtS
        let v = sim.finish()
        #expect(v.isEmpty, "\(v)")
        let late = (a.atMs - ideal) / 1000
        let line = "loss=\(lossS)s m=\(kd(m)) \(mode.jsonName): alarm \(a.reason.jsonName) at \((a.atMs - S) / 1000) s; "
            + "late vs trueRemaining1200 \(late) s; true remaining at alarm \((dest - a.atMs) / 1000) s; "
            + "late vs cross1000 \((a.atMs - cross) / 1000) s; etaMinS<1200 rule would ring at \(etaMinAt.map { String(($0 - S) / 1000) } ?? "null") s "
            + "(late vs trueRemaining1200 \(etaMinAt.map { String(($0 - ideal) / 1000) } ?? "null") s)"
            + (params.gpsLostLongS > 0 ? "; lostLongAtS \(lostLong.map { KW.jf($0, 1) } ?? "null")" : "")
        return CRes(line: line, lateS: late, lostLongAtS: lostLong)
    }

    static func tableC(_ params: EngineParams) -> [CRes] {
        var rows: [CRes] = []
        for lossS in [3_600, 7_200, 10_800] { for m in [0.7, 1.0, 1.15, 1.3, 1.5] { rows.append(scenarioC(lossS, m, .distance, params)) } }
        rows.append(scenarioC(7_200, 1.3, .time, params))
        rows.append(scenarioC(7_200, 1.3, .smart, params))
        return rows
    }

    /// U121: measured with W on (Kotlin T12.3); DISTANCE rows within ± 5 s of T10 "T10.6" §1.4 column "W, Q12 A".
    static let pinnedU121 = """
    loss=3600s m=0.7 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -3712 s; true remaining at alarm 4912 s; late vs cross1000 -4748 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -3717 s); lostLongAtS 2784.8
    loss=3600s m=1.0 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -1352 s; true remaining at alarm 2552 s; late vs cross1000 -2491 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -1358 s); lostLongAtS 2784.8
    loss=3600s m=1.15 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -873 s; true remaining at alarm 2073 s; late vs cross1000 -2019 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -878 s); lostLongAtS 2784.8
    loss=3600s m=1.3 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -504 s; true remaining at alarm 1704 s; late vs cross1000 -1656 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -509 s); lostLongAtS 2784.8
    loss=3600s m=1.5 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -127 s; true remaining at alarm 1327 s; late vs cross1000 -1285 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -132 s); lostLongAtS 2784.8
    loss=7200s m=0.7 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -6172 s; true remaining at alarm 7372 s; late vs cross1000 -7284 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -5948 s); lostLongAtS 5435.7
    loss=7200s m=1.0 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -2763 s; true remaining at alarm 3963 s; late vs cross1000 -3848 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -2540 s); lostLongAtS 5435.7
    loss=7200s m=1.15 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -1460 s; true remaining at alarm 2660 s; late vs cross1000 -2607 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -1237 s); lostLongAtS 5435.7
    loss=7200s m=1.3 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -514 s; true remaining at alarm 1714 s; late vs cross1000 -1627 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s); lostLongAtS 5435.7
    loss=7200s m=1.5 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 400 s; true remaining at alarm 799 s; late vs cross1000 -758 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 624 s); lostLongAtS 5435.7
    loss=10800s m=0.7 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -8989 s; true remaining at alarm 10189 s; late vs cross1000 -10026 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -8537 s); lostLongAtS 8086.6
    loss=10800s m=1.0 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -3527 s; true remaining at alarm 4727 s; late vs cross1000 -4666 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -3075 s); lostLongAtS 8086.6
    loss=10800s m=1.15 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -2048 s; true remaining at alarm 3248 s; late vs cross1000 -3195 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -1596 s); lostLongAtS 8086.6
    loss=10800s m=1.3 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -1124 s; true remaining at alarm 2324 s; late vs cross1000 -2276 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -671 s); lostLongAtS 8086.6
    loss=10800s m=1.5 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 449 s; true remaining at alarm 750 s; late vs cross1000 -674 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 901 s); lostLongAtS 8086.6
    loss=7200s m=1.3 TIME: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -514 s; true remaining at alarm 1714 s; late vs cross1000 -1627 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s); lostLongAtS 5435.7
    loss=7200s m=1.3 SMART: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -514 s; true remaining at alarm 1714 s; late vs cross1000 -1627 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s); lostLongAtS 5435.7
    """

    static let pinnedC = """
    loss=3600s m=0.7 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 -2896 s; true remaining at alarm 4096 s; late vs cross1000 -3933 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -3717 s)
    loss=3600s m=1.0 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 -537 s; true remaining at alarm 1737 s; late vs cross1000 -1675 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -1358 s)
    loss=3600s m=1.15 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 -57 s; true remaining at alarm 1257 s; late vs cross1000 -1204 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -878 s)
    loss=3600s m=1.3 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 311 s; true remaining at alarm 888 s; late vs cross1000 -841 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -509 s)
    loss=3600s m=1.5 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 688 s; true remaining at alarm 511 s; late vs cross1000 -470 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -132 s)
    loss=7200s m=0.7 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 -4407 s; true remaining at alarm 5607 s; late vs cross1000 -5519 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -5948 s)
    loss=7200s m=1.0 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 -999 s; true remaining at alarm 2199 s; late vs cross1000 -2084 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -2540 s)
    loss=7200s m=1.15 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 303 s; true remaining at alarm 896 s; late vs cross1000 -843 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -1237 s)
    loss=7200s m=1.3 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 1249 s; true remaining at alarm -49 s; late vs cross1000 137 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s)
    loss=7200s m=1.5 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 2165 s; true remaining at alarm -965 s; late vs cross1000 1006 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 624 s)
    loss=10800s m=0.7 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 -6276 s; true remaining at alarm 7476 s; late vs cross1000 -7313 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -8537 s)
    loss=10800s m=1.0 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 -814 s; true remaining at alarm 2014 s; late vs cross1000 -1952 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -3075 s)
    loss=10800s m=1.15 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 664 s; true remaining at alarm 535 s; late vs cross1000 -481 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -1596 s)
    loss=10800s m=1.3 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 1589 s; true remaining at alarm -389 s; late vs cross1000 436 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -671 s)
    loss=10800s m=1.5 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 3162 s; true remaining at alarm -1962 s; late vs cross1000 2039 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 901 s)
    loss=7200s m=1.3 TIME: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 1249 s; true remaining at alarm -49 s; late vs cross1000 137 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s)
    loss=7200s m=1.3 SMART: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 1249 s; true remaining at alarm -49 s; late vs cross1000 137 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s)
    """

    /// U121 (T10.6 (1), flipped from the tester's `T122 c`): same 17 runs with the "long loss" rule W on (defaults, Q12 = A).
    /// DISTANCE lateness vs "true remaining 1 200 s" = T10 "T10.6" §1.4 column "W, Q12 A" (± 5 s), every row <= +460 s, TIME/SMART
    /// at (2 h, 1.3) = DISTANCE. With gpsLostLongS = 0 the old pinned table `pinnedC` (T12.2) comes back unchanged.
    @Test("U121 GPS lost for more than 1 h with a changing true speed: the long-loss rule W bounds the GPS_LOST lateness (T122 c flipped)")
    func c() {
        let rows = Self.tableC(Self.p)
        let txt = rows.map(\.line).joined(separator: "\n")
        Report.shared.write("unit/t122-c-longloss.txt", txt + "\n")
        let handW: [Int64] = [-3711, -1352, -872, -504, -127, -6171, -2763, -1461, -515, 401, -8988, -3526, -2048, -1123, 450]
        for (i, want) in handW.enumerated() { #expect((rows[i].lateS - want).magnitude <= 5, "row \(i): \(rows[i].lateS) vs hand \(want)") }
        #expect(rows.allSatisfy { $0.lateS <= 460 }, "\(txt)")
        #expect(rows[8].lateS == rows[15].lateS && rows[8].lateS == rows[16].lateS)
        for (i, l) in [2784.8, 5435.7, 8086.6].enumerated() { #expect(approx(rows[i * 5].lostLongAtS, l, 0.1), "row \(i * 5)") }
        #expect(txt == Self.pinnedU121)
        // W off: the T12.2 table, line for line.
        let off = Self.tableC(KW.params(#"{"gpsLostLongS": 0}"#)).map(\.line).joined(separator: "\n")
        #expect(off == Self.pinnedC)
    }

    // MARK: - (d) wake-up storm regression, with a battery forecast

    /// Battery state whose batteryAt − now at `now` is `leadS` (+ < 1 ms), level `level`, not charging, armed.
    static func batteryWithLead(_ now: Int64, _ level: Int, _ leadS: Double) -> BatteryState {
        let rate = Double(level - p.lowBatteryAlarmPct) * 3600.0 / leadS   // %/h
        let drop = Swift.max(1, KW.ki((rate * Double(p.batteryMinRateWindowS) / 3600.0).rounded(.up)) + 1)
        let windowMs = KW.kl((Double(drop) * 3_600_000.0 / rate).rounded(.toNearestOrAwayFromZero))
        return BatteryState(levelPct: level, charging: false, segT0: now - windowMs, segL0: level + drop, armed: true, riskEmitted: true,
                            choice: nil, choicePct: nil)
    }

    struct StormResult {
        let wakes: Int
        let minGapMs: Int64
        let line: String
    }

    static func storm(_ tier: SamplingTier, _ b: Int, stopped: Bool, battery: Bool, leadS: Double, fixEveryS: Int, horizonS: Int) -> StormResult {
        let d = 1000.0 + 12.5 * (Double(b) + 0.5)
        let bat = battery ? batteryWithLead(S, 40, leadS) : .initial
        let st = KW.trackingState(KW.cfg(), d: d, inStop: stopped, tier: tier, battery: bat)
        let lead0 = ModeRules.batteryAt(st, now: st.nowMs).map { Double($0 - S) / 1000.0 }
        let sim = Sim(TripEngine.reduce(st, .tick(atMs: S + 1)), "D", Rng(3))
        var wakes = 0
        var lastWake: Int64? = nil
        var minGap = Int64.max
        var nextFix: Int64? = fixEveryS > 0 ? S + Int64(fixEveryS) * 1000 : nil
        let end = S + Int64(horizonS) * 1000
        while !sim.ended && sim.now < end {
            guard let wake = sim.step.view.wakeAtMs else { break }
            if !sim.alarms.isEmpty { break }
            if let nf = nextFix, nf <= wake {
                let t = nf
                let dd = stopped ? d : d - 12.5 * Double(t - S) / 1000.0
                sim.feed(.locationFix(fixAt(t, dd, spd: stopped ? 0.0 : 15.0)), "fix")
                nextFix = t + (stopped ? Int64(fixEveryS) * 1000 : interval(sim.step))   // moving: fixes follow the policy
            } else {
                if wake >= end { break }
                sim.feed(.tick(atMs: wake), "wake")
                wakes += 1
                if let lw = lastWake { minGap = Swift.min(minGap, wake - lw) }
                lastWake = wake
            }
        }
        let v = sim.finish()
        #expect(v.isEmpty, "\(v)")
        let line = "tier=\(tier.jsonName) B=\(b) stopped=\(stopped) battery=\(battery) lead0=\(KW.kdOpt(lead0)) s fixEvery=\(fixEveryS) s "
            + "horizon=\(horizonS) s: wake Ticks=\(wakes) minGap=\(minGap == .max ? "-" : "\(kd(Double(minGap) / 1000.0)) s") "
            + "alarms=\(KW.klist(sim.alarms.map { $0.0.reason.jsonName })) gps=\(sim.step.view.gps.jsonName)"
        return StormResult(wakes: wakes, minGapMs: minGap, line: line)
    }

    @Test("T132 d (= T122 d) no wake-up storm at tier boundaries with GPS OK, with and without a sliding battery forecast")
    func d() {
        var out = ""
        var bad: [String] = []
        func expect(_ ok: Bool, _ line: String) {
            out += (ok ? "" : "FAIL ") + line + "\n"
            if !ok { bad.append(line) }
        }
        for (tier, b) in [(SamplingTier.dense, 600), (.medium, 900), (.sparse, 3600)] {
            for battery in [false, true] {
                for leadS in battery ? [Double(b) + 0.5, Double(b) + 5.0, 20_000.0] : [0.0] {
                    let every = tier == .dense ? 5 : (tier == .medium ? 30 : 180)
                    let a = Self.storm(tier, b, stopped: true, battery: battery, leadS: leadS, fixEveryS: every, horizonS: 1_200)
                    expect(a.wakes == 0, a.line)
                    let z = Self.storm(tier, b, stopped: true, battery: battery, leadS: leadS, fixEveryS: 0, horizonS: 3_600)
                    expect(z.wakes <= 8 && (z.wakes < 2 || z.minGapMs >= 10_000), z.line)
                    let mv = Self.storm(tier, b, stopped: false, battery: battery, leadS: leadS, fixEveryS: every, horizonS: 1_200)
                    expect(mv.wakes <= 6 && (mv.wakes < 2 || mv.minGapMs >= 1_000), mv.line)
                }
            }
        }
        // Moving, GPS OK then lost (Doze, no fix), the battery forecast is the smallest component and slides (no BatterySample).
        for leadS in [600.5, 900.5, 3600.5, 120.0, 30.0] {
            let r = Self.storm(.sparse, 20_000, stopped: false, battery: true, leadS: leadS, fixEveryS: 0, horizonS: 3_600)
            expect(r.wakes < 2 || r.minGapMs >= 10_000, "far mode forecast: " + r.line)
        }
        Report.shared.write("unit/t122-d-storm.txt", out)
        #expect(bad.isEmpty, "\(bad.joined(separator: "\n"))")
    }

    // MARK: - (e) fuzz

    final class FuzzStats {
        var trips = 0
        var steps = 0
        var urgent = 0
        var soon = 0
        var osFired = 0
        var raceFired = 0
        var kills = 0
        var first: [String: Int] = [:]
        var viol: [String] = []
        var violTrips = 0
        var lateCross: [Double] = []
        var supersedeRaces: [String] = []
        var wrongWording: [String] = []
        var osFirstKinds: [String: Int] = [:]
        var osFirstEarly: [Double] = []
        var believedStopOverLag: [String] = []
        /// U126 (after T12.3, D5): DISTANCE cases late > 1 800 s, (late, line).
        var lateLines: [(Double, String)] = []
        /// U126 (T10.6): first alarms due to the "long loss" term W alone; true seconds to the destination at them (< 0: after).
        var longLost = 0
        var longLostRemaining: [Double] = []

        func add(_ sim: Sim) {
            trips += 1
            steps += sim.steps
            urgent += sim.urgent
            soon += sim.soonShifts
            osFired += sim.osFired
            raceFired += sim.raceFired
            supersedeRaces += sim.supersedeRaces
            for (k, n) in sim.osFirstKinds { osFirstKinds[k, default: 0] += n }
            osFirstEarly += sim.osFirstEarly
            believedStopOverLag += sim.believedStopOverLag.map { "\(sim.tag) \($0)" }
            let f = sim.alarms.first
            let k = sim.firstKey()
            first[k, default: 0] += 1
            let v = sim.finish() + (f == nil ? ["\(sim.tag): trip without alarm"] : [])
            if !v.isEmpty { violTrips += 1 }
            if viol.count < 30 { viol += v.prefix(3) }
        }

        func text(_ name: String) -> String {
            let l = lateCross.sorted()
            let lt = l.isEmpty ? "-"
                : "n \(l.count), p50 \(kd(l[l.count / 2])), p90 \(kd(l[Swift.min(l.count - 1, Int(Double(l.count) * 0.9))])), max \(kd(l.last!))"
            let e = osFirstEarly.sorted()
            let et = e.isEmpty ? "-" : "min \(kd(e.first!)) p50 \(kd(e[e.count / 2])) max \(kd(e.last!))"
            return "\(name): trips=\(trips) steps=\(steps) urgentLaterShifts=\(urgent) farZoneSoonShifts=\(soon) osFallbackFired=\(osFired) "
                + "(after a cancel request: \(raceFired)) kills=\(kills) violatingTrips=\(violTrips)\nfirstAlarm=\(KW.kmap(first))\n"
                + "OVERSHOOT/PASSED_CLOSEST first while the truth has not passed the destination: \(wrongWording.count) \(KW.klist(wrongWording))\n"
                + "believed-stop OS fallback later than P(prev Step) + lag + 1 s (U111 bound; within the hold band): "
                + "\(believedStopOverLag.count) \(KW.klist(believedStopOverLag))\n"
                + "OS fallback first while alive, by kind: \(KW.kmap(osFirstKinds)); predicted(prev Step) − F, s: \(et)\n"
                + "DISTANCE late vs truth crossing (rang after the threshold, s): \(lt)\nviolations=\(KW.klist(viol))\n"
        }
    }

    static func randomFix(_ r: Rng, _ t: Int64, _ truth: Truth, jump: (Double, Double), accBad: (Double, Double), accGood: (Double, Double)) -> LocationFix {
        let dd = truth.dAt(t)
        var dist = dd.magnitude
        if r.chance(0.03) { dist += r.dbl(jump.0, jump.1) }
        let acc = r.chance(0.1) ? r.dbl(accBad.0, accBad.1) : r.dbl(accGood.0, accGood.1)
        let spd: Double? = r.chance(0.3) ? nil : truth.speedAt(t) * r.dbl(0.9, 1.1)
        let age = Int64(r.int(1_500))
        let east = r.dbl(-15.0, 15.0)
        return fixAt(t, dd < 0 ? -dist : dist, acc: acc, spd: spd, ageMs: age, eastM: east)
    }

    static func randomConfig(_ r: Rng, _ id: String, extraThr: Bool) -> TripConfig {
        let mode = AlarmMode.allCases[r.int(3)]
        let thr: Int? = mode == .distance || (extraThr && r.chance(0.3)) ? 200 + r.int(9801) : nil
        let thrMin: Int? = mode == .time || (extraThr && mode != .distance && r.chance(0.3)) ? 5 + r.int(56) : nil
        let preAlert = r.chance(0.7)
        let hint = VehicleKind.allCases[r.int(4)]
        return TripConfig(tripId: id, destLat: KW.destLat, destLng: KW.destLng, mode: mode, distanceThresholdM: thr,
                          timeThresholdMin: thrMin, preAlertEnabled: preAlert, vehicleHint: hint)
    }

    static func thrTag(_ c: TripConfig) -> String {
        "\(c.mode.jsonName) thr=\(c.distanceThresholdM.map(String.init) ?? "null")/\(c.timeThresholdMin.map(String.init) ?? "null")"
    }

    /// U126 (after T12.3, D5): a DISTANCE first alarm more than 1 800 s after the threshold crossing, one classified line.
    static func noteLate(_ sim: Sim, _ truth: Truth, _ config: TripConfig, _ a: TripEvent.Alarm, _ cross: Int64, _ st: FuzzStats) {
        let lateS = Double(a.atMs - cross) / 1000.0
        if lateS <= 1_800.0 { return }
        let dead = sim.deadIntervals.contains { cross >= $0.0 && cross < $0.1 }
        st.lateLines.append((lateS, LongLoss.lateCaseLine(
            tag: sim.tag, hint: config.vehicleHint, lateS: lateS, first: sim.firstKey(), dead: dead, crossMs: cross,
            thrM: Double(config.distanceThresholdM!), st: sim.states.last { $0.nowMs <= cross }) { ms in truth.dAt(ms) }))
    }

    /// U126: a first GPS_LOST alarm due to W alone, and the true time left to the destination at it.
    static func noteLongLost(_ sim: Sim, _ truth: Truth, _ st: FuzzStats) {
        guard let a = sim.alarms.first?.0, let state = sim.firstAlarmState else { return }
        if a.reason != .gpsLost || !LongLoss.lostAlarmInfo(state).longLostOnly { return }
        st.longLost += 1
        if let arr = truth.crossAt(0.0, S + 60 * 3_600_000) { st.longLostRemaining.append(Double(arr - a.atMs) / 1000.0) }
    }

    /// (e1) Approach with a real stop placed around the predicted alarm boundary (P0 ± 90 s), stop 20–1 500 s, then a new speed.
    static func stopNearAlarm(_ seed: Int64, _ st: FuzzStats, _ params: EngineParams = TesterT132Tests.p) throws {
        let r = Rng(seed)
        let config = randomConfig(r, "e1-\(seed)", extraThr: false)
        let mode = config.mode
        let c = r.dbl(4.0, 30.0)
        let g = c * r.dbl(1.0, 1.4)
        let d0 = r.dbl(8_000.0, 60_000.0)
        let s0 = KW.trackingState(config, p: params, d: d0, ground: g, closing: c, slow: mode == .smart && g * 3.6 < Double(p.smartSlowSpeedKmh),
                                  tier: .dense)
        let sim = Sim(TripEngine.reduce(s0, .tick(atMs: S)), "e1 seed=\(seed) \(thrTag(config))", r, okP: 0.9, cancelLagMaxMs: 5_000)
        guard let p0 = sim.step.view.predictedAlarmAtMs else { return }
        let truth = Truth(d0, S)
        truth.segs.append((S, c))
        let stopAt = p0 + Int64(r.int(180_000)) - 90_000
        truth.segs.append((stopAt, 0.0))
        let resume = stopAt + KW.kl(r.dbl(20.0, 1_500.0) * 1000.0)
        truth.segs.append((resume, c * r.dbl(0.5, 1.5)))
        sim.truthSpeed = { truth.speedAt($0) }
        let fixP = r.dbl(0.3, 1.0)
        // Doze (60 %): from some time before the stop, a fix only at a wake-up Tick (probability fixInDozeP), as U111 withfix.
        let dozeAt = r.chance(0.6) ? stopAt - Int64(r.int(1_800_000)) : Int64.max
        let fixInDozeP = r.dbl(0.2, 0.9)
        var lastFix = S
        var guardN = 0
        let killAt: Int64? = r.chance(0.2) ? stopAt + Int64(r.int(120_000)) - 60_000 : nil
        var killed = false
        var nf: Int64? = nil
        while !sim.ended {
            guardN += 1
            if guardN >= 50_000 { break }
            if let k = killAt, !killed, sim.alarms.isEmpty {
                let nextAny = [sim.step.view.wakeAtMs, sim.nextOs()?.at, nf].compactMap { $0 }.min() ?? .max
                if nextAny >= k {
                    killed = true
                    sim.kill(k)
                    st.kills += 1
                    let statuses = FallbackRestoreStatus.allCases.filter { $0 != .dismissed && $0 != .rang }
                    let at = Swift.max(k, sim.now) + Int64(r.int(300_000)) + 1_000
                    try sim.restart(at, statuses[r.int(statuses.count)])
                    nf = nil
                    continue
                }
            }
            if sim.now >= dozeAt {
                let w = sim.step.view.wakeAtMs
                nf = w != nil && r.chance(fixInDozeP) ? w : nil
            } else if nf == nil || nf! <= sim.now {
                var x = Swift.max(lastFix + interval(sim.step), sim.now + 1)
                while !r.chance(fixP) { x += interval(sim.step) }
                nf = x
            }
            let ok = sim.advance(.max, nf) { t in
                lastFix = t
                return randomFix(r, t, truth, jump: (-1_000.0, 3_000.0), accBad: (60.0, 300.0), accGood: (4.0, 25.0))
            }
            if !ok { break }
        }
        if let a = sim.alarms.first?.0, a.reason == .overshoot || a.reason == .passedClosest, truth.dAt(a.atMs) > 0.0 {
            st.wrongWording.append("\(sim.tag) \(a.reason.jsonName) at truth d=\(KW.ki(truth.dAt(a.atMs))) m")
        }
        if config.mode == .distance, let f = sim.alarms.first?.0,
           let cross = truth.crossAt(Double(config.distanceThresholdM!), S + 48 * 3_600_000), f.atMs > cross {
            st.lateCross.append(Double(f.atMs - cross) / 1000.0)
            noteLate(sim, truth, config, f, cross, st)
        }
        noteLongLost(sim, truth, st)
        st.add(sim)
    }

    /// (e2) Doze trips (model of U111 `withfix`, own generator).
    static func dozeTrip(_ seed: Int64, _ st: FuzzStats, _ params: EngineParams = TesterT132Tests.p) throws {
        let r = Rng(seed)
        let config = randomConfig(r, "e2-\(seed)", extraThr: true)
        let d0 = r.dbl(3_000.0, 300_000.0)
        let base = r.dbl(3.0, 35.0)
        let truth = Truth(d0, S)
        var t = S
        while t < S + 60 * 3_600_000 {
            truth.segs.append((t, base * r.dbl(0.7, 1.3)))
            t += KW.kl(r.dbl(300.0, 3_600.0) * 1000.0)
            if r.chance(0.3) {
                truth.segs.append((t, 0.0))
                t += KW.kl(r.dbl(30.0, 1_500.0) * 1000.0)
            }
        }
        let tripS = d0 / base
        let dozeAt = S + KW.kl(r.dbl(0.0, 1.0) * tripS * 1000.0)
        let gapA: Int64 = r.chance(0.5) ? S + KW.kl(r.dbl(0.0, 1.2) * tripS * 1000.0) : .max
        let gapB: Int64 = gapA == .max ? gapA : gapA + KW.kl(r.dbl(60.0, 7_200.0) * 1000.0)
        let fixInDozeP = r.dbl(0.2, 0.9)
        var killAt: Int64? = nil
        if r.chance(0.4) {
            if gapA != .max && r.chance(0.33) {
                killAt = gapA + KW.kl(r.dbl(0.0, 1.0) * Double(gapB - gapA))
            } else {
                killAt = S + KW.kl(r.dbl(0.0, 1.5) * tripS * 1000.0)
            }
        }
        let sim = Sim(try TripEngine.start(config: config, params: params, nowMs: S), "e2 seed=\(seed) \(thrTag(config)) d0=\(KW.ki(d0))", r,
                      okP: 0.85, cancelLagMaxMs: 5_000)
        var lastFix = S - 1_000_000
        var batteryAtT = S
        var level = 20 + r.int(81)
        let drainPerH = r.dbl(1.0, 12.0)
        var guardN = 0
        func inGap(_ x: Int64) -> Bool { x >= gapA && x < gapB }
        while !sim.ended {
            guardN += 1
            if guardN >= 60_000 { break }
            let now = sim.now
            let awake = now < dozeAt
            let wake = sim.step.view.wakeAtMs
            var nf: Int64?
            if awake { nf = Swift.max(lastFix + interval(sim.step), now + 1) } else if let w = wake, r.chance(fixInDozeP) { nf = w } else { nf = nil }
            if let x = nf, inGap(x) { nf = nil }
            let nb = batteryAtT + 600_000
            let osAt = sim.nextOs().map { Swift.max($0.at, now) }
            let x = [wake, osAt, nf, nb, killAt.map { Swift.max($0, now) }].compactMap { $0 }.min()!
            if let k = killAt, x == Swift.max(k, now) {
                sim.kill(x)
                st.kills += 1
                let restartAt = x + KW.kl(r.dbl(1.0, 7_200.0) * 1000.0)
                let status: FallbackRestoreStatus
                switch r.int(10) {
                case 0: status = .missing
                case 1: status = .unknown
                default: status = .pending
                }
                killAt = r.chance(0.3) ? restartAt + KW.kl(r.dbl(60.0, 7_200.0) * 1000.0) : nil
                try sim.restart(restartAt, status)
                continue
            }
            if let o = osAt, x == o, wake == nil || o < wake! {
                sim.fireOs(sim.nextOs()!)
            } else if let f = nf, x == f {
                lastFix = x
                sim.feed(.locationFix(randomFix(r, x, truth, jump: (-2_000.0, 4_000.0), accBad: (60.0, 400.0), accGood: (4.0, 30.0))), "fix")
            } else if let w = wake, x == w {
                sim.feed(.tick(atMs: x), "Tick")
            } else {
                batteryAtT = x
                level = Swift.max(1, level - Swift.max(0, KW.ki(drainPerH / 6.0 + r.dbl(-0.5, 0.5))))
                sim.feed(.batterySample(atMs: x, levelPct: level, charging: r.chance(0.1)), "battery")
            }
        }
        if let a = sim.alarms.first?.0, a.reason == .overshoot || a.reason == .passedClosest, truth.dAt(a.atMs) > 0.0 {
            st.wrongWording.append("\(sim.tag) \(a.reason.jsonName) at truth d=\(KW.ki(truth.dAt(a.atMs))) m")
        }
        if config.mode == .distance, let f = sim.alarms.first?.0,
           let cross = truth.crossAt(Double(config.distanceThresholdM!), S + 60 * 3_600_000), f.atMs > cross {
            st.lateCross.append(Double(f.atMs - cross) / 1000.0)
            noteLate(sim, truth, config, f, cross, st)
        }
        noteLongLost(sim, truth, st)
        st.add(sim)
    }

    @Test("T132 e (= T122 e) fuzz of the urgent later shift path: no double ring, one alarm, I1–I7 I10–I14 at every Step, emissions = fallbackTarget")
    func e() throws {
        let e1 = FuzzStats()
        for seed in Int64(1)...6_000 { try Self.stopNearAlarm(seed, e1) }
        let e2 = FuzzStats()
        for seed in Int64(10_001)...12_000 { try Self.dozeTrip(seed, e2) }
        Report.shared.write("unit/t122-e-fuzz.txt", e1.text("e1 stop near the alarm boundary") + "\n" + e2.text("e2 Doze with fixes at wake-ups, kills"))
        #expect(e1.urgent + e2.urgent >= 150, "the fuzz exercises the urgent later shift: \(e1.urgent) + \(e2.urgent)")
        #expect(e1.viol.isEmpty && e2.viol.isEmpty, "e1 \(e1.viol.prefix(5))\ne2 \(e2.viol.prefix(5))")
        // U125 (T10.6): no OVERSHOOT / PASSED_CLOSEST before the truth passed the destination.
        #expect(e1.wrongWording.isEmpty && e2.wrongWording.isEmpty, "e1 \(e1.wrongWording.prefix(5))\ne2 \(e2.wrongWording.prefix(5))")
    }

    /// U126 b (T10.6, statistics): e1 / e2 with T10.6 off and on. Gate (T10.6 on): no violation, an alarm on every trip, no
    /// wrong-wording OVERSHOOT / PASSED_CLOSEST. Written to u126-longloss-t122.txt (byte-identical to Kotlin): DISTANCE lateness vs
    /// the threshold crossing, each case late > 1 800 s classified, first alarms due to W alone and the true time left at them.
    @Test("U126 b e1 e2 fuzz lateness off vs T10.6, late > 1800 s classes and long-loss alarms")
    func u126b() throws {
        let off = LongLoss.offParams
        let e1Off = FuzzStats()
        for seed in Int64(1)...6_000 { try Self.stopNearAlarm(seed, e1Off, off) }
        let e2Off = FuzzStats()
        for seed in Int64(10_001)...12_000 { try Self.dozeTrip(seed, e2Off, off) }
        let e1 = FuzzStats()
        for seed in Int64(1)...6_000 { try Self.stopNearAlarm(seed, e1) }
        let e2 = FuzzStats()
        for seed in Int64(10_001)...12_000 { try Self.dozeTrip(seed, e2) }
        let q = LongLoss.quantiles
        var out = "# U126 b (T10.6) e1 / e2 of TesterT122Test: off (gpsLostLongS 0, passedClosestSlowRiseM 0; preV on) -> T10.6\n"
        for (name, a, b) in [("e1", e1Off, e1), ("e2", e2Off, e2)] {
            out += "\n## \(name)\nDISTANCE late vs truth crossing (s): off \(q(a.lateCross)) -> T10.6 \(q(b.lateCross))\n"
            out += "late > 1800 s: off \(a.lateCross.filter { $0 > 1_800.0 }.count) -> T10.6 \(b.lateCross.filter { $0 > 1_800.0 }.count)\n"
            // Kotlin sortedByDescending (stable): ties keep insertion order. Printed only, no gate (class ? → báo designer).
            let sortedLate = b.lateLines.enumerated().sorted { $0.element.0 != $1.element.0 ? $0.element.0 > $1.element.0 : $0.offset < $1.offset }
            for x in sortedLate { out += x.element.1 + "\n" }
            out += "first alarms due to W alone: \(b.longLost); true time left at them (s): \(q(b.longLostRemaining)); after arrival: "
                + "\(b.longLostRemaining.filter { $0 < 0.0 }.count)\nfirstAlarm off \(KW.kmap(a.first))\nfirstAlarm T10.6 \(KW.kmap(b.first))\n"
                + "violatingTrips off \(a.violTrips) -> T10.6 \(b.violTrips); wrong wording \(a.wrongWording.count) -> \(b.wrongWording.count)\n"
        }
        Report.shared.write("unit/u126-longloss-t122.txt", out)
        #expect(e1.viol.isEmpty && e2.viol.isEmpty, "e1 \(e1.viol.prefix(5))\ne2 \(e2.viol.prefix(5))")
        #expect(e1.wrongWording.isEmpty && e2.wrongWording.isEmpty)
    }
}
