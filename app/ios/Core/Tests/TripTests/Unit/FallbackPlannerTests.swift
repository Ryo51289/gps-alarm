import Testing
@testable import Trip

/// Planner-only simulation (T10 "Kiểm tra F1/F2" model): ticks every 5 s, `predicted(t)` synthetic; the engine alarms
/// at the first tick with now ≥ predicted. Returns emissions (now, at) and per-tick fb.
struct FallbackSim {
    var fb = FallbackState.cleared
    var emissions: [(now: Int64, at: Int64)] = []
    var alarmAt: Int64? = nil
    var violations: [String] = []
    let p: EngineParams

    init(_ p: EngineParams = .defaults) { self.p = p }

    mutating func run(from start: Int64, until end: Int64, predicted: (Int64) -> Int64) {
        var now = start
        while now <= end {
            if let f = fb.targetAtMs, now >= f, alarmAt == nil { violations.append("fallback due at \(now) before engine") }
            let pr = predicted(now)
            if now >= pr { alarmAt = now; return }
            let target = FallbackPlanner.fallbackTarget(now: now, predicted: pr, predictedFb: pr, p)
            if let at = FallbackPlanner.nextFallbackAt(fb, target: target, predicted: pr, now: now, p) {
                if let prev = fb.targetAtMs, fb.status != .failed, now >= TMath.min(prev, pr) - Int64(p.fallbackQuietBeforeS) * 1000 {
                    violations.append("emission in quiet window at \(now)")
                }
                emissions.append((now, at))
                fb = FallbackState(targetAtMs: at, emittedAtMs: now, status: .requested, confirmedAtMs: nil, resync: false,
                                   near: TMath.toS(pr - now) <= Double(p.fallbackNearS))
            }
            if let f = fb.targetAtMs, now < TMath.min(f, pr) - Int64(p.fallbackQuietBeforeS) * 1000,
               TMath.toS(pr - now) <= Double(p.fallbackNearS), f < pr + 30_000 {
                violations.append("F2a: fb < predicted + 30 s at \(now)")
            }
            now += 5000
        }
    }
}

@Suite("FallbackPlannerTests")
struct FallbackPlannerTests {
    static let old = EngineDriver.params(#"{"fallbackEarlyFrac": 0.1, "fallbackEarlyMaxS": 1800, "fallbackHintSpeedFactor": 0}"#)
    static let P: Int64 = 36_000_000   // 10:00:00

    @Test("U40 fallbackTarget (predictedFb = predicted): far zone early part, near zone P + 30 s, lead floor, T10 override")
    func u40() {
        let now: Int64 = 1_000_000_000, p = EngineParams.defaults
        func tg(_ t: Int64, _ prm: EngineParams = .defaults) -> Int64 {
            FallbackPlanner.fallbackTarget(now: now, predicted: now + t * 1000, predictedFb: now + t * 1000, prm)!
        }
        let P = { (t: Int64) in now + t * 1000 }
        #expect(tg(20_000) == P(20_000) - 3_570_000)
        #expect(tg(3600) == P(3600) - 720_000)
        #expect(tg(1000) == P(1000) - 70_000)
        for t: Int64 in [600, 300, 60] { #expect(tg(t) == P(t) + 30_000) }
        #expect(tg(0) == now + 30_000)
        #expect(tg(0, EngineDriver.params(#"{"fallbackLagS": 10, "fallbackMinLeadS": 20}"#)) == now + 20_000)
        #expect(tg(20_000, Self.old) == P(20_000) - 1_770_000)
        #expect(tg(3600, Self.old) == P(3600) - 270_000)
        _ = p
    }

    static func fb(_ target: Int64, emitted: Int64, status: FallbackStatus = .confirmed, near: Bool = false) -> FallbackState {
        FallbackState(targetAtMs: target, emittedAtMs: emitted, status: status, confirmedAtMs: nil, resync: false, near: near)
    }

    @Test("U41 fb = now + 25 s: quiet window blocks any change except the T10.5 urgent later shift (+120 s with predicted > now + 30 s)")
    func u41() {
        let now: Int64 = 10_000_000, p = EngineParams.defaults
        let f = now + 25_000
        let fb = Self.fb(f, emitted: now - 100_000)
        for pred in [now + 2_000_000, now + 300_000] {
            #expect(FallbackPlanner.nextFallbackAt(fb, target: f - 120_000, predicted: pred, now: now, p) == nil, "earlier, pred \(pred - now)")
            // T10.5 (§4.10, U108 a): later by >= fallbackMinShiftS while predicted − now > 30 s and F − now >= 10 s is the urgent
            // later shift (before T10.5: null).
            #expect(FallbackPlanner.nextFallbackAt(fb, target: f + 120_000, predicted: pred, now: now, p) == f + 120_000,
                    "later, pred \(pred - now)")
        }
        // K1: the engine itself is about to ring (predicted − now <= 30 s): any change stays blocked.
        for pred in [now + 30_000, now + 20_000] {
            for delta: Int64 in [-120_000, 120_000] {
                #expect(FallbackPlanner.nextFallbackAt(fb, target: f + delta, predicted: pred, now: now, p) == nil)
            }
        }
    }

    @Test("U42 far zone: shift 20 s null; earlier 40 s now; later 40 s after 30 s null / 61 s target; FAILED 59 / 60 s (even in quiet)")
    func u42() {
        let now: Int64 = 10_000_000, p = EngineParams.defaults, pred = now + 2_000_000, x = now + 1_500_000
        func next(_ t: Int64, emittedAgo: Int64, status: FallbackStatus = .confirmed, cur: Int64 = x) -> Int64? {
            FallbackPlanner.nextFallbackAt(Self.fb(cur, emitted: now - emittedAgo, status: status), target: t, predicted: pred, now: now, p)
        }
        #expect(next(x + 20_000, emittedAgo: 600_000) == nil)
        #expect(next(x - 40_000, emittedAgo: 1_000) == x - 40_000)
        #expect(next(x + 40_000, emittedAgo: 30_000) == nil)
        #expect(next(x + 40_000, emittedAgo: 61_000) == x + 40_000)
        #expect(next(x, emittedAgo: 59_000, status: .failed) == nil)
        #expect(next(x, emittedAgo: 60_000, status: .failed) == x)
        #expect(next(now + 30_000, emittedAgo: 60_000, status: .failed, cur: now + 10_000) == now + 30_000)
    }

    @Test("U43 TRACKING with a target, then Alarm(ringNow) → FallbackAlarmChanged(null, SUPERSEDED) once, no ETA afterwards")
    func u43() {
        var d = EngineDriver()
        d.drive(from: 0, d0: 3000, v: 15, count: 40)
        let all = d.allEvents()
        let firstAlarm = d.steps.firstIndex { !$0.events.alarms.isEmpty }!
        #expect(d.steps[firstAlarm].events.fallbacks == [TripEvent.FallbackAlarmChanged(atMs: d.steps[firstAlarm].view.atMs, fallbackAtMs: nil, cause: .superseded)])
        #expect(d.allEvents(from: firstAlarm + 1).fallbacks.isEmpty)
        #expect(all.fallbacks.filter { $0.cause == .superseded }.count == 1)
    }

    @Test("U73 F1 (a) 20 phases from P − 3600 s → final P + 30 s; (b) 09:30 run: 11 emissions (T10: 5); (c) start in the near zone")
    func u73() {
        for i in 0..<20 {
            var s = FallbackSim()
            s.run(from: Self.P - 3_600_000 + Int64(i) * 250, until: Self.P + 60_000) { _ in Self.P }
            #expect(s.emissions.last?.at == Self.P + 30_000 && s.violations.isEmpty, "phase \(i)")
        }
        var b = FallbackSim()
        b.run(from: Self.P - 1_800_000, until: Self.P) { _ in Self.P }
        let wantNow = (0..<10).map { Self.P - 1_800_000 + Int64($0) * 120_000 } + [Self.P - 600_000]
        let wantAt = (0..<10).map { Self.P - 270_000 + Int64($0) * 30_000 } + [Self.P + 30_000]
        #expect(b.emissions.map(\.now) == wantNow && b.emissions.map(\.at) == wantAt)
        var o = FallbackSim(Self.old)
        o.run(from: Self.P - 1_800_000, until: Self.P) { _ in Self.P }
        #expect(o.emissions.map(\.now) == [0, 300, 600, 900, 1200].map { Self.P - 1_800_000 + Int64($0) * 1000 })
        #expect(o.emissions.map(\.at) == [-90, -60, -30, 0, 30].map { Self.P + Int64($0) * 1000 })
        for t: Int64 in [700, 600, 300, 100, 40, 31, 30, 20] {
            var c = FallbackSim()
            c.run(from: Self.P - t * 1000, until: Self.P) { _ in Self.P }
            #expect(c.emissions.last?.at == Self.P + 30_000 && c.violations.isEmpty, "T = \(t)")
        }
    }

    @Test("U74 F2 (a) ±20 → 1 emission; (b) ±40 → 7; (c) ±20 then P − 100 → 2; (d) drift → 17 + 1 (P + 660)")
    func u74() {
        let start = Self.P - 1_800_000, t955 = Self.P - 300_000
        func alt(_ a: Int64) -> (Int64) -> Int64 {
            { now in now < t955 ? Self.P : (((now - t955) / 5000) % 2 == 0 ? Self.P + a : Self.P - a) }
        }
        var a = FallbackSim(); a.run(from: start, until: Self.P + 120_000, predicted: alt(20_000))
        let ea = a.emissions.filter { $0.now >= t955 }
        #expect(ea.map(\.at) == [Self.P + 80_000] && a.alarmAt == Self.P - 15_000 && a.violations.isEmpty)
        var b = FallbackSim(); b.run(from: start, until: Self.P + 120_000, predicted: alt(40_000))
        let eb = b.emissions.filter { $0.now >= t955 }
        let tb: [Int64] = [0, 65, 70, 135, 140, 205, 210].map { t955 + $0 * 1000 }
        #expect(eb.map(\.now) == tb)
        #expect(eb.map(\.at) == [100, 50, 100, 50, 100, 50, 100].map { Self.P + Int64($0) * 1000 })
        #expect(b.alarmAt == Self.P - 35_000 && b.violations.isEmpty)
        var c = FallbackSim()
        c.run(from: start, until: Self.P + 120_000) { now in now < t955 + 60_000 ? alt(20_000)(now) : Self.P - 100_000 }
        let ec = c.emissions.filter { $0.now >= t955 }
        #expect(ec.map(\.at) == [Self.P + 80_000, Self.P - 10_000] && ec.last?.now == t955 + 60_000)
        #expect(c.alarmAt == Self.P - 100_000 && c.violations.isEmpty)
        let d0 = Self.P - 500_000, d1 = Self.P + 100_000
        var d = FallbackSim()
        d.run(from: start, until: Self.P + 700_000) { now in now < d0 ? Self.P : (now < d1 ? now + 500_000 : Self.P + 600_000) }
        let inDrift = d.emissions.filter { $0.now >= d0 && $0.now < d1 }
        #expect(inDrift.count == 17)
        #expect(zip(inDrift.dropFirst(), inDrift).allSatisfy { $0.now - $1.now == 35_000 })
        #expect(d.emissions.last.map { $0.now == d1 && $0.at == Self.P + 660_000 } == true)
        #expect(d.alarmAt == Self.P + 600_000 && d.violations.isEmpty)
    }

    @Test("U87 near zone T = 300: raise to X / X + 30 s (near); lower only ≥ 30 s above the upper edge and ≥ 60 s after the last emission")
    func u87() {
        let now: Int64 = 100_000_000, p = EngineParams.defaults, pred = now + 300_000, x = pred + 30_000
        func next(_ cur: Int64, near: Bool = false, ago: Int64 = 600_000) -> Int64? {
            FallbackPlanner.nextFallbackAt(Self.fb(cur, emitted: now - ago, near: near), target: x, predicted: pred, now: now, p)
        }
        #expect(FallbackPlanner.fallbackTarget(now: now, predicted: pred, predictedFb: pred, p) == x)
        #expect(next(x - 1) == x)
        #expect(next(x - 1, near: true) == x + 30_000)
        #expect(next(x + 89_999) == nil)
        #expect(next(x + 90_000, ago: 59_999) == nil)
        #expect(next(x + 90_000, ago: 60_000) == x + 60_000)
        #expect(next(x) == nil && next(x + 60_000) == nil)
        // (f) fb.near after an emission, and false after every clear.
        var d = EngineDriver()
        d.drive(from: 0, d0: 8000, v: 15, count: 60)
        for st in d.steps where !st.events.fallbacks.isEmpty {
            let f = st.events.fallbacks[0]
            if f.fallbackAtMs != nil && f.cause == .eta, let pr = st.view.predictedAlarmAtMs {
                #expect(st.state.fallback.near == (TMath.toS(pr - st.view.atMs) <= 600))
            } else if f.fallbackAtMs == nil {
                #expect(!st.state.fallback.near)
            }
        }
    }

    /// State + estimate for U93 (hint TRAIN, established v, k = 1.2, dNow 50 000, GPS OK).
    static func u93(_ mode: AlarmMode = .distance, thrMin: Int? = nil, v: Double = 12, params: String? = nil, lost: Bool = false)
        -> (EngineState, Estimate, Int64) {
        var d = EngineDriver(mode, thr: mode == .distance ? 1000 : nil, thrMin: thrMin, hint: .train, params: params)
        d.fix(0, d: 300_000)
        var s = d.state
        s.maxTripDurationS = 172_800
        if lost { s.gps = .lost }
        return (s, makeE(dNow: 50_000, v: v, k: 1.2), s.nowMs)
    }

    static func chain(_ s: EngineState, _ e: Estimate?, _ n: Int64) -> (Int64?, Int64?, Int64?) {
        let pr = ModeRules.predictedAlarmAt(s, e, now: n).withBattery
        let pfb = FallbackPlanner.fallbackPredictedAt(s, e, predicted: pr, now: n)
        return (pr, pfb, FallbackPlanner.fallbackTarget(now: n, predicted: pr, predictedFb: pfb, s.params))
    }

    @Test("U93 fallbackPredictedAt / fallbackTarget: TRAIN floor wins (a), loses (b), disabled (c), TIME (d), LOST (e), no fix (f)")
    func u93() {
        var (s, e, n) = Self.u93()
        var r = Self.chain(s, e, n)
        #expect(r.0 == n + 4_900_000 && r.1 == n + 3_848_727 && r.2 == n + 3_066_546)
        (s, e, n) = Self.u93(v: 18)
        r = Self.chain(s, e, n)
        #expect(r.1 == r.0 && r.0 == n + 3_266_666 && r.2 == n + 2_630_000)
        (s, e, n) = Self.u93(params: #"{"fallbackHintSpeedFactor": 0}"#)
        r = Self.chain(s, e, n)
        #expect(r.1 == r.0 && r.2 == n + 3_855_000)
        (s, e, n) = Self.u93(.time, thrMin: 15)
        #expect(approx(e.etaS, 5020, 1e-9))
        r = Self.chain(s, e, n)
        #expect(r.0 == n + 4_120_000 && r.1 == n + 3_047_272 && r.2 == n + 2_465_454)
        (s, e, n) = Self.u93(lost: true)
        r = Self.chain(s, e, n)
        #expect(r.0 == n + 3_820_000 && r.1 == n + 2_747_272)
        let fresh = EngineDriver(hint: .train)
        r = Self.chain(fresh.state, nil, fresh.state.nowMs)
        #expect(r.1 == r.0 && r.0 == fresh.startMs + 14_400_000)
    }

    @Test("U94 TIME 30, far floor now + 600 s at N; no emission N+5…N+15 s; N + 20 s first near-zone Step → N + 650 000 (T10.3); TIME alarm first")
    func u94() {
        // Fix distances are 25 m (one sample) ahead so that medianHi of the 3 recent fixes gives dNow = 12 000 − 5 (t − N).
        // Start far enough that neither the hint ETA nor the EMA ETA reaches 1800 s before N.
        var d = EngineDriver(.time, thr: nil, thrMin: 30, hint: .train)
        d.drive(from: 0, d0: 24_975, v: 6, k: 1.2, count: 520, exact: true)
        #expect(d.allEvents().alarms.isEmpty)
        d.state.fallback = .cleared
        let n = d.ms(2600)
        d.fix(2600, d: 11_975, spd: 6, exact: true)
        #expect(d.state.dSmooth == 12_000)
        #expect(approx(d.estimate!.etaS, 2420, 1e-9))
        #expect(d.view.predictedAlarmAtMs == n + 620_000)
        #expect(d.events.fallbacks == [TripEvent.FallbackAlarmChanged(atMs: n, fallbackAtMs: n + 600_000, cause: .eta)])
        var alarmT: Double? = nil
        for i in 1...130 {
            let t = 2600 + Double(i) * 5
            d.fix(t, d: 11_975 - 25 * Double(i), spd: 6, exact: true)
            // T10.3 corrected row: N + 5 … N + 15 s far zone, no emission (floor shift 5–15 s < 30 s); N + 20 s is the first
            // near-zone Step (T = 600 ≤ fallbackNearS) → raise to exactly P + 30 s = N + 650 000; nothing after that.
            if i < 4 {
                #expect(d.events.fallbacks.isEmpty, "i = \(i)")
                #expect(((d.view.predictedAlarmAtMs ?? 0) - (n + 620_000)).magnitude <= 1)
                #expect((d.state.fallback.targetAtMs ?? 0) - d.state.nowMs >= 585_000)
            }
            if i == 4 {
                #expect(d.events.fallbacks.count == 1)
                #expect(d.events.fallbacks.first.flatMap(\.fallbackAtMs).map { ($0 - (n + 650_000)).magnitude <= 1 } == true)
            }
            if i > 4 && d.events.alarms.isEmpty { #expect(d.events.fallbacks.isEmpty, "i = \(i)") }
            if !d.events.alarms.isEmpty { alarmT = t; break }
        }
        #expect(d.allEvents().alarms.first?.reason == .time)
        #expect(alarmT.map { (d.ms($0) - (n + 620_000)).magnitude <= 5000 } == true)
    }

    @Test("U95 F3 sweep: constant speed 2…20 m/s, TRAIN and COACH: far-zone margin ≥ 540 s, no quiet ETA, no early fallback, final P + 30 s")
    func u95() {
        for hint in [VehicleKind.train, .coach] {
            for c in [2.0, 5, 8, 12, 15, 20] {
                var d = EngineDriver(.distance, thr: 1000, hint: hint)
                var fbOs: Int64? = d.view.fallbackAtMs
                var lastFix: Double? = nil, t = 0.0
                var firstAlarm: TripEvent.Alarm? = nil, lastPredBefore: Int64? = nil, lastEmitBefore: Int64? = nil
                var farEmits: [Int64] = []
                let cvHint = Estimator.expectedSpeedMps(hint, .defaults) / 1.2
                while t <= 20_000 && firstAlarm == nil {
                    // Fix cadence = the engine's own sampling policy (SPARSE 180 s when T > 3600, MEDIUM 30 s when T > 900,
                    // DENSE 5 s after; hysteresis as §4.12), so GPS never times out between fixes.
                    let cadence = Double(d.view.samplingPolicy?.intervalS ?? 5)
                    if let f = fbOs, d.ms(t) >= f { Issue.record("c=\(c) \(hint): fallback due at \(t) before engine"); break }
                    let prevView = d.view
                    if lastFix == nil || t - lastFix! >= cadence {
                        d.fix(t, d: 60_000 - c * t, spd: c); lastFix = t
                    } else if Int(t) % 60 == 0 {
                        d.tick(t)
                    } else { t += 5; continue }
                    for f in d.events.fallbacks {
                        if f.cause == .eta, let prevT = prevView.fallbackAtMs, prevView.fallbackStatus != .failed,
                           let p2 = d.view.predictedAlarmAtMs, d.ms(t) >= TMath.min(prevT, p2) - 30_000 {
                            Issue.record("c=\(c) \(hint): I4 at \(t)")
                        }
                        fbOs = f.fallbackAtMs
                        if d.events.alarms.isEmpty { lastEmitBefore = f.fallbackAtMs }
                        if let p2 = d.view.predictedAlarmAtMs, p2 - d.ms(t) > 600_000 { farEmits.append(d.ms(t)) }
                    }
                    if let a = d.events.alarms.first { firstAlarm = a; break }
                    lastPredBefore = d.view.predictedAlarmAtMs
                    if let p2 = d.view.predictedAlarmAtMs, p2 - d.ms(t) > 600_000, !d.state.fallback.near, let tg = d.state.fallback.targetAtMs {
                        #expect(tg - d.ms(t) >= 540_000, "c=\(c) \(hint) t=\(t)")
                    }
                    if c >= cvHint, let e = d.estimate {
                        let p0 = ModeRules.predictedAlarmAt(d.state, e, now: d.state.nowMs).withBattery
                        #expect(FallbackPlanner.fallbackPredictedAt(d.state, e, predicted: p0, now: d.state.nowMs) == p0)
                    }
                    t += 5
                }
                guard let a = firstAlarm else { Issue.record("c=\(c) \(hint): no alarm"); continue }
                #expect(a.ringNow)
                if c == 2 {
                    #expect(a.reason == .timeout && a.atMs == d.ms(14_400))
                    #expect(lastEmitBefore == d.ms(14_430))
                } else {
                    #expect(a.reason == .distance)
                    #expect(lastEmitBefore.map { ($0 - (lastPredBefore ?? 0) - 30_000).magnitude <= 1 } == true, "c=\(c) \(hint)")
                }
                let gaps = zip(farEmits.dropFirst(), farEmits).map { ($1 - d.startMs, $0 - $1) }.filter { $0.1 < 60_000 }
                #expect(gaps.isEmpty, "c = \(c) \(hint): far emissions closer than 60 s: \(gaps.prefix(5))")
            }
        }
    }

    @Test("U97 (b) 1 000 random (now, predicted, E) with the T10 override: bit-identical to the T10.1 expression")
    func u97b() {
        var rng = SplitMix64(97)
        for i in 0..<1000 {
            let modes: [AlarmMode] = [.distance, .time, .smart]
            let mode = modes[i % 3]
            var d = EngineDriver(mode, thr: mode == .distance ? 1000 : nil, thrMin: 15,
                                 params: #"{"fallbackEarlyFrac": 0.1, "fallbackEarlyMaxS": 1800, "fallbackHintSpeedFactor": 0}"#)
            d.fix(0, d: 300_000)
            var s = d.state
            s.slow = rng.nextInt(2) == 0
            if rng.nextInt(3) == 0 { s.gps = .lost }
            let now = s.nowMs + Int64(rng.nextInt(1_000_000))
            let predicted = now + Int64(rng.nextDouble() * 172_800_000)
            let e = makeE(dNow: rng.nextDouble() * 1_200_000, v: 1, k: 1, cvDr: 1e-9 + rng.nextDouble() * 40)
            let pfb = FallbackPlanner.fallbackPredictedAt(s, e, predicted: predicted, now: now)
            let got = FallbackPlanner.fallbackTarget(now: now, predicted: predicted, predictedFb: pfb, s.params)!
            let t = TMath.max(0.0, TMath.toS(predicted - now))
            let want = TMath.max(now + 10_000, TMath.max(predicted, now) + 30_000 - TMath.floorMs(TMath.min(1800.0, 0.1 * TMath.max(0.0, t - 600))))
            #expect(got == want, "i = \(i)")
        }
    }
}
