import Testing
@testable import Trip

/// T10.5 (T10 mục cuối "T10.5" §6; port of Kotlin `unit/T105Test.kt`): wakeBasisAt / wakeBatteryAt (U106 c–g), the urgent later
/// shift of the fallback in the quiet window (U108, U109), the harness I4 wording + counter (U110) and the round-2 far-zone rule
/// (U112). U106 a/b, U107 and U111 are in `TesterT131Tests`.
@Suite("T105Tests")
struct T105Tests {
    static let p = EngineParams.defaults
    static let S = KW.S
    static let n = KW.S + 3_600_000

    // MARK: - U106 c–g

    /// TRACKING, GPS OK, last fix at n, now = n, policyIntervalAtLastFixS 600 (c2 = n + 1 800 000), no fallback.
    static func okState() -> EngineState {
        KW.trackingState(KW.cfg(), now: n, d: 200_000.0, lastFixAt: n, tier: .sparse, policyAtFix: 600)
    }

    @Test("U106 c d e f wakeAt takes c3 from min(wakeBasisAt, wakeBatteryAt), near-zone and c4 from wakeBasisAt only")
    func u106cdef() {
        let s = Self.okState()
        let n = Self.n
        #expect(GpsMonitor.lostAfterS(s) == 1_800)   // c2 = n + 1 800 000
        func w(_ b: Int64, _ bat: Int64?) -> Int64? { WakePlanner.wakeAt(s, wakeBasis: b, wakeBattery: bat, now: s.nowMs) }
        // (c) sliding: basis = deadline far away; T10.4 with the sliding predicted n + 900 500 gave n + 1 500.
        #expect(w(n + 20_000_000, nil) == n + 1_800_000)
        // (d) not sliding, no battery: as T10.4.
        #expect(w(n + 900_500, nil) == n + 1_500)
        // (e) c4 from deadlineAt.
        #expect(w(n + 1_000_000, nil) == n + 101_000)
        // (f) c3 from the battery forecast; c4 / near-zone from wakeBasisAt (n + 2 101 000, n + 2 401 000), not from the battery.
        #expect(w(n + 3_000_000, n + 950_000) == n + 951_000)
        #expect(w(n + 950_000, nil) == n + 51_000)   // T10.4 with predicted = battery n + 950 000
    }

    @Test("U106 g wakeBasisAt is deadlineAt when sliding or without estimate, predictedNoBattery otherwise, nil when alarmed")
    func u106g() throws {
        let n = Self.n
        func deadline(_ s: EngineState) -> Int64 { s.startedAtMs + TMath.ms(s.maxTripDurationS) }
        func work(_ s: EngineState) -> Estimate? { Estimator.estimate(s, now: s.nowMs) }
        var battery = BatteryState.initial
        battery.levelPct = 40
        battery.armed = true
        // (i) TRACKING, GPS OK, stop in progress: modeAt slides with now, so the basis is the deadline (the view keeps predicted).
        let i = KW.trackingState(KW.cfg(), now: n, d: 20_000.0, lastFixAt: n - 20_000, inStop: true, battery: battery)
        let ei = work(i)
        let pi = ModeRules.predictedAlarmAt(i, ei, now: i.nowMs)
        #expect(ModeRules.wakeBasisAt(i, ei, now: i.nowMs) == deadline(i))
        #expect(pi.wakeBasis == deadline(i))
        #expect(pi.wakeBattery != nil)
        #expect(try #require(pi.withBattery) < deadline(i))   // the view's predictedAlarmAt is unchanged (not the deadline)
        // (ii) GPS OK, moving.
        var ii = i
        ii.stopStartMs = nil
        ii.stopAnchor = nil
        let eii = work(ii)
        #expect(ModeRules.wakeBasisAt(ii, eii, now: n) == ModeRules.predictedAlarmAt(ii, eii, now: n).noBattery)
        #expect(try #require(ModeRules.wakeBasisAt(ii, eii, now: n)) < deadline(ii))
        // (iii) GPS LOST with stopStartMs != nil: dead reckoning, fixed between inputs.
        let iii = KW.trackingState(KW.cfg(), now: n, d: 20_000.0, gps: .lost, lastFixAt: n - 70_000, inStop: true)
        let eiii = work(iii)
        #expect(ModeRules.wakeBasisAt(iii, eiii, now: n) == ModeRules.predictedAlarmAt(iii, eiii, now: n).noBattery)
        #expect(try #require(ModeRules.wakeBasisAt(iii, eiii, now: n)) < deadline(iii))
        // (iv) ACQUIRING without a fix: no estimate.
        let iv = try TripEngine.start(config: KW.cfg(), params: Self.p, nowMs: Self.S).state
        let eiv = work(iv)
        #expect(eiv == nil)
        #expect(ModeRules.wakeBasisAt(iv, eiv, now: iv.nowMs) == deadline(iv))
        #expect(ModeRules.predictedAlarmAt(iv, eiv, now: iv.nowMs).wakeBattery == nil)
        // (v) ALARMING.
        var v = i
        v.phase = .alarming
        v.alarm = .empty
        v.alarm.atMs = n - 1_000
        v.alarm.lastRingAtMs = n - 1_000
        let ev = work(v)
        #expect(ModeRules.wakeBasisAt(v, ev, now: n) == nil)
        #expect(ModeRules.predictedAlarmAt(v, ev, now: n).wakeBattery == nil)
    }

    // MARK: - U108

    static func fb(_ f: Int64, _ status: FallbackStatus = .confirmed, emittedAt: Int64 = T105Tests.n - 5_000, near: Bool = true) -> FallbackState {
        FallbackState(targetAtMs: f, emittedAtMs: emittedAt, status: status, confirmedAtMs: status == .confirmed ? emittedAt + 500 : nil,
                      resync: false, near: near)
    }

    static func next(_ fb: FallbackState, _ target: Int64, _ predicted: Int64, _ now: Int64, _ p: EngineParams = T105Tests.p) -> Int64? {
        FallbackPlanner.nextFallbackAt(fb, target: target, predicted: predicted, now: now, p)
    }

    @Test("U108 nextFallbackAt urgent later shift inside the quiet window (K1, K2 bounds, min shift, far zone, FAILED, emit)")
    func u108() {
        let n = Self.n
        // (a)
        #expect(Self.next(Self.fb(n + 29_000), n + 430_000, n + 400_000, n) == n + 430_000)
        // (b) K1: now >= predicted − Q blocks; one ms later it does not.
        #expect(Self.next(Self.fb(n + 29_000), n + 60_000, n + 30_000, n) == nil)
        #expect(Self.next(Self.fb(n + 29_000), n + 60_001, n + 30_001, n) == n + 60_001)
        // (c) K2: F − now >= fallbackMinLeadS.
        #expect(Self.next(Self.fb(n + 9_999), n + 430_000, n + 400_000, n) == nil)
        #expect(Self.next(Self.fb(n + 10_000), n + 430_000, n + 400_000, n) == n + 430_000)
        // (d) shift below fallbackMinShiftS (override 60 s).
        #expect(Self.next(Self.fb(n + 29_000), n + 61_000, n + 31_000, n, KW.params("{\"fallbackMinShiftS\": 60}")) == nil)
        // (e) far zone, last emission 5 s ago: fallbackMinIntervalS is skipped.
        #expect(Self.next(Self.fb(n + 29_000), n + 1_512_500, n + 2_000_000, n) == n + 1_512_500)
        // (f) FAILED: the retry branch as before (60 s since the emission).
        #expect(Self.next(Self.fb(n + 29_000, .failed, emittedAt: n - 60_000), n + 430_000, n + 400_000, n) == n + 430_000)
        #expect(Self.next(Self.fb(n + 29_000, .failed, emittedAt: n - 59_999), n + 430_000, n + 400_000, n) == nil)
        // (g) emit, then a Step 5 s later with the same predicted: nothing.
        var s = KW.trackingState(KW.cfg(), now: n, lastFixAt: n, fallback: Self.fb(n + 29_000))
        var events: [TripEvent] = []
        FallbackPlanner.planFallback(&s, nil, predicted: n + 400_000, now: n, events: &events)
        #expect(events == [.fallbackAlarmChanged(.init(atMs: n, fallbackAtMs: n + 430_000, cause: .eta))])
        #expect(s.fallback == FallbackState(targetAtMs: n + 430_000, emittedAtMs: n, status: .requested, confirmedAtMs: nil,
                                            resync: false, near: true))
        #expect(Self.next(s.fallback, n + 430_000, n + 400_000, n + 5_000) == nil)
        s.nowMs = n + 5_000
        FallbackPlanner.planFallback(&s, nil, predicted: n + 400_000, now: n + 5_000, events: &events)
        #expect(events.count == 1)
    }

    // MARK: - U109

    /// Fixes from `first` s: stationary (d 8 000, speed 0) every 5 s to 700 s, then moving at 12.5 m/s every 5 s. Before every
    /// input the OS fallback fires if view.fallbackAtMs has come (simple osSim). Returns the Step with the first Alarm.
    static func run109(_ e: inout KDriver, _ first: Int) -> Step {
        var t = first
        var guardN = 0
        var s = e.fix(t, 8_000.0, spd: 0.8)
        while s.events.alarms.isEmpty {
            t += 5
            if let f = s.view.fallbackAtMs, f <= S + Int64(t) * 1000 {
                s = e.feed(.fallbackFired(atMs: f, firedAtMs: f))
                break
            }
            s = t <= 700 ? e.fix(t, 8_000.0, spd: 0.0) : e.fix(t, 8_000.0 - 12.5 * Double(t - 700), spd: 12.5)
            guardN += 1
            if guardN >= 1_000 { break }
        }
        return s
    }

    static func state109() -> EngineState {
        KW.trackingState(KW.cfg(), d: 8_500.0, tier: .dense,
                         fallback: FallbackState(targetAtMs: S + 630_000, emittedAtMs: S, status: .confirmed, confirmedAtMs: S + 500,
                                                 resync: false, near: true))
    }

    @Test("U109 a a fix in the quiet window showing a stop moves the fallback later and the engine rings first")
    func u109a() throws {
        let st = Self.state109()
        let before = TripEngine.reduce(st, .tick(atMs: Self.S)).view   // I14: same state, the previous Step's view
        #expect(before.predictedAlarmAtMs == Self.S + 600_000)
        var e = KDriver(from: st)
        let s0 = e.fix(601, 8_000.0, spd: 0.8)
        #expect(s0.events.alarms.isEmpty)
        #expect(s0.state.stopStartMs != nil, "inStop")
        #expect(s0.view.predictedAlarmAtMs == Self.S + 1_161_000)
        let facs = s0.events.fallbacks
        #expect(facs == [.init(atMs: Self.S + 601_000, fallbackAtMs: Self.S + 1_191_000, cause: .eta)])
        let fac = try #require(facs.first)
        #expect(Checks.quietEmission(before, s0.view, fac, st.params) == true, "I4 (T10.5): urgent later shift")
        // Then: the engine rings DISTANCE first, the fallback never comes before it.
        var e2 = KDriver(from: st)
        let last = Self.run109(&e2, 601)
        let a = try #require(last.events.alarms.first)
        #expect(last.events.alarms.count == 1)
        #expect(a.reason == .distance && a.ringNow, "first alarm \(a.reason) at \(a.atMs - Self.S) ms")
    }

    @Test("U109 b with only 9 s left the fallback stays and rings early (pinned remainder)")
    func u109b() throws {
        var e = KDriver(from: Self.state109())
        let s0 = e.fix(621, 8_000.0, spd: 0.8)
        #expect(s0.events.fallbacks.isEmpty)
        var e2 = KDriver(from: Self.state109())
        let last = Self.run109(&e2, 621)
        let a = try #require(last.events.alarms.first)
        #expect(a.reason == .fallback)
        #expect(!a.ringNow)
        #expect(a.atMs == Self.S + 630_000)
    }

    @Test("U109 c a charging battery sample removing batteryAt inside the quiet window moves the fallback to the far zone")
    func u109c() throws {
        let n = Self.n
        var bat = BatteryState.initial
        bat.levelPct = 6
        bat.armed = true
        let st = KW.trackingState(KW.cfg(), now: n, d: 50_000.0, lastFixAt: n, battery: bat,
                                  fallback: FallbackState(targetAtMs: n + 25_000, emittedAtMs: n - 600_000, status: .confirmed,
                                                          confirmedAtMs: n - 599_000, resync: false, near: false))
        let s = TripEngine.reduce(st, .batterySample(atMs: n, levelPct: 6, charging: true))
        #expect(s.events.alarms.isEmpty)
        #expect(s.events.fallbacks.count == 1)
        let fac = try #require(s.events.fallbacks.first)
        #expect(fac.cause == .eta)
        let at = try #require(fac.fallbackAtMs)
        #expect(at >= n + 600_000, "at \(at - n)")
    }

    // MARK: - U110

    static func run110(_ prevTarget: Int64, _ predicted: Int64, _ newTarget: Int64) -> [StepRecord] {
        let n = Self.n
        let v = TripEngine.reduce(KW.trackingState(KW.cfg(), now: n, lastFixAt: n), .tick(atMs: n)).view
        let prev = KW.view(v, atMs: n - 5_000, fallbackAtMs: .some(prevTarget), fallbackStatus: .confirmed, wakeAtMs: .some(n + 60_000))
        let cur = KW.view(v, atMs: n, predictedAlarmAtMs: .some(predicted), fallbackAtMs: .some(newTarget), fallbackStatus: .requested,
                          wakeAtMs: .some(n + 60_000))
        return [
            StepRecord(t: 0, input: .start, events: [], view: prev, v: ""),
            StepRecord(t: 5, input: .input(.tick(atMs: n), fixIndex: nil),
                       events: [.fallbackAlarmChanged(.init(atMs: n, fallbackAtMs: newTarget, cause: .eta))], view: cur, v: ""),
        ]
    }

    @Test("U110 harness I4 accepts the urgent later shift and counts it, rejects the K2, K1 and min-shift cases")
    func u110() {
        let n = Self.n, p = Self.p
        let a = Self.run110(n + 29_000, n + 400_000, n + 430_000)
        #expect(Checks.invariants(a, p).isEmpty)
        let u = Checks.urgentShifts(a, p)
        #expect(u.count == 1)
        #expect(u.map { [$0.prevTarget, $0.newTarget ?? -1, $0.predicted] } == [[n + 29_000, n + 430_000, n + 400_000]])
        let b = Checks.invariants(Self.run110(n + 9_000, n + 400_000, n + 430_000), p)
        #expect(b.count == 1 && b[0].hasPrefix("I4"), "\(b)")
        let c = Checks.invariants(Self.run110(n + 29_000, n + 20_000, n + 430_000), p)
        #expect(c.count == 1 && c[0].hasPrefix("I4"), "\(c)")
        // (d) T10.5 round 2 (review nit #5): a later shift below fallbackMinShiftS inside the quiet window is an I4 violation;
        // exactly fallbackMinShiftS is the exception.
        let d = Checks.invariants(Self.run110(n + 29_000, n + 400_000, n + 58_000), p)
        #expect(d.count == 1 && d[0].hasPrefix("I4"), "\(d)")
        #expect(Checks.invariants(Self.run110(n + 29_000, n + 400_000, n + 59_000), p).isEmpty)
    }

    // MARK: - U112 (T10.5 round 2)

    @Test("U112 a b far-zone later shift is immediate when the alarm already set is within Q + minInterval")
    func u112ab() {
        let n = Self.n
        func f(_ at: Int64) -> FallbackState { Self.fb(at, emittedAt: n - 1) }
        // (a) emitted 1 ms ago: the once-a-minute limit is lifted when F − now <= 90 s (before round 2: nil all three).
        #expect(Self.next(f(n + 63_000), n + 1_500_000, n + 2_000_000, n) == n + 1_500_000)
        #expect(Self.next(f(n + 90_000), n + 1_500_000, n + 2_000_000, n) == n + 1_500_000)
        #expect(Self.next(f(n + 90_001), n + 1_500_000, n + 2_000_000, n) == nil)
        // (b) earlier shift, the old branch (|40 000 − 63 000| < fallbackMinShiftS → nil; an earlier shift by >= 30 s at once).
        #expect(Self.next(f(n + 63_000), n + 40_000, n + 2_000_000, n) == nil)
        #expect(Self.next(f(n + 63_000), n + 33_000, n + 2_000_000, n) == n + 33_000)
    }

    static func check112(_ atS: Int64) throws {
        let n = Self.n
        let st = KW.trackingState(KW.cfg(), now: n, d: 9_000.0, gps: .lost, lastFixAt: n - 600_000, tier: .dense,
                                  fallback: FallbackState(targetAtMs: n + 63_000, emittedAtMs: n - 1, status: .confirmed, confirmedAtMs: n,
                                                          resync: false, near: true))
        let pt = KW.pointOnMeridian(9_000.0)
        let s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: n + atS * 1000, fixAtMs: n + atS * 1000, lat: pt.lat, lng: pt.lng,
                                                               accuracyM: 8.0, speedMps: 0.0)))
        #expect(KW.hasRecovered(s), "GpsRecovered")
        #expect(s.events.alarms.isEmpty)
        #expect(s.view.predictedAlarmAtMs == n + atS * 1000 + 640_000)
        #expect(s.events.fallbacks.count == 1)
        let fac = try #require(s.events.fallbacks.first)
        #expect(fac.cause == .eta)
        let at = try #require(fac.fallbackAtMs)
        #expect(at >= n + atS * 1000 + 600_000, "at \(at - n)")
    }

    @Test("U112 c d seed 746 pattern: a fix after a GPS loss showing the vehicle far moves a near fallback 63 s or 33 s away")
    func u112cd() throws {
        try Self.check112(0)    // (c)
        try Self.check112(30)   // (d)
    }
}
