import Testing
@testable import Trip

@Suite("OvershootDetectorTests")
struct OvershootDetectorTests {
    /// Fixes every 30 s at the given distances with a constant Doppler speed.
    static func run(_ ds: [Double], thr: Int = 1000, kmh: Double = 40, params: String? = nil, dt: Double = 30,
                    exactAt: Set<Int> = []) -> EngineDriver {
        var d = EngineDriver(.distance, thr: thr, params: params)
        for (i, x) in ds.enumerated() { d.fix(Double(i) * dt, d: x, spd: kmh / 3.6, exact: exactAt.contains(i)) }
        return d
    }

    static let approachTo300: [Double] = [3000, 2300, 1600, 900, 300]

    @Test("U34 alarmed (ringing), minD 300, then 400 → 800 → 1350 at 40 km/h → Overshoot(pastM 1050), no new Alarm; (b) DISTANCE 2000, minD 1500")
    func u34() {
        let d = Self.run(Self.approachTo300 + [400, 800, 1350])
        let all = d.allEvents()
        #expect(all.alarms.map(\.reason) == [.distance])
        #expect(d.events.compactMap { if case let .overshoot(o) = $0 { return o.pastM } else { return nil } } == [1050])
        #expect(d.view.phase == .overshot && d.view.overshootPastM == 1050)
        let b = Self.run([5000, 4000, 3000, 1500, 1800, 2200, 2500], thr: 2000)
        #expect(b.events.named("overshoot").count == 1)
    }

    @Test("U35 8 km/h, or not strictly increasing → no Overshoot; (b) fast boundary 5.0 m/s vs 18 km/h; (c) minD == nearRadius exactly")
    func u35() {
        #expect(Self.run(Self.approachTo300 + [400, 800, 1350], kmh: 8).allEvents().named("overshoot").isEmpty)
        #expect(Self.run(Self.approachTo300 + [400, 400, 1350]).allEvents().named("overshoot").isEmpty)
        #expect(Self.run(Self.approachTo300 + [400, 800, 1350], kmh: 18, params: #"{"overshootMinSpeedKmh": 18}"#)
            .allEvents().named("overshoot").isEmpty)
        #expect(5.0 * 3.6 == 18.0)
        #expect(Self.run(Self.approachTo300 + [400, 800, 1350], kmh: 5.01 * 3.6, params: #"{"overshootMinSpeedKmh": 18}"#)
            .allEvents().named("overshoot").count == 1)
        let exact = Self.run([3000, 2000, 1000.0, 1100, 1500, 2050], exactAt: [2])
        #expect(exact.state.minD == 1000.0)
        #expect(exact.allEvents().named("overshoot").isEmpty)
        #expect(Self.run([3000, 2000, 999.9, 1100, 1500, 2050]).allEvents().named("overshoot").count == 1)
    }

    @Test("U36 as U34 but DISMISS first → ENDED, no Overshoot")
    func u36() {
        var d = Self.run(Self.approachTo300)
        d.user(130, .dismiss)
        d.fix(150, d: 400, spd: 11.1); d.fix(180, d: 800, spd: 11.1); d.fix(210, d: 1350, spd: 11.1)
        #expect(d.view.phase == .ended && d.allEvents().named("overshoot").isEmpty)
    }

    @Test("U37 DISTANCE 500 not alarmed: 900, 800, 1100, 2000 (180 s) at 40 km/h → Alarm(OVERSHOOT) + Overshoot, phase OVERSHOT")
    func u37() {
        let d = Self.run([900, 800, 1100, 2000], thr: 500, dt: 180)
        #expect(d.events.alarms.map(\.reason) == [.overshoot] && d.events.named("overshoot").count == 1)
        #expect(d.view.phase == .overshot)
        #expect(d.events.first?.fixtureName == "alarm")
    }

    @Test("U38 d down to 290 → Arrived(290) once, phase unchanged")
    func u38() {
        let d = Self.run([2000, 1500, 1000, 600, 290, 250])
        let arrived = d.allEvents().compactMap { if case let .arrived(a) = $0 { return a.distanceM } else { return nil } }
        #expect(arrived == [290])
        #expect(d.steps[5].view.phase == d.steps[4].view.phase)
    }

    static func passed(_ ds: [Double], kmh: Double = 18) -> EngineDriver {
        var d = EngineDriver(.distance, thr: 1000)
        for (i, x) in ds.enumerated() { d.fix(Double(i) * 60, d: x, spd: kmh / 3.6) }
        return d
    }

    @Test("U77 PASSED_CLOSEST at 1850 (closest 1200, 18 km/h); negatives (minD 3100, 8 km/h, +500, not strict, already alarmed); R2-4")
    func u77() {
        let base: [Double] = [4000, 3400, 2800, 2200, 1600, 1200]
        let ok = Self.passed(base + [1300, 1600, 1850])
        #expect(ok.allEvents().alarms.map(\.reason) == [.passedClosest] && ok.events.alarms.count == 1)
        #expect(ok.view.phase == .alarming)
        #expect(Self.passed(base.map { $0 + 1900 } + [3200, 3500, 3750]).allEvents().alarms.isEmpty)
        #expect(Self.passed(base + [1300, 1600, 1850], kmh: 8).allEvents().alarms.isEmpty)
        #expect(Self.passed(base + [1300, 1500, 1700]).allEvents().alarms.isEmpty)
        #expect(Self.passed(base + [1300, 1300, 1850]).allEvents().alarms.isEmpty)
        var al = Self.passed(base + [1300])
        al.fired(420, firedAtMs: al.ms(420))
        al.fix(430, d: 1600, spd: 5); al.fix(490, d: 1850, spd: 5)
        #expect(al.allEvents().alarms.map(\.reason) == [.fallback])
        // R2-4: start 2500 and move away: no; later approach to 1800 then away → at 2800.
        let r = Self.passed([2500, 2600, 3000, 3800], kmh: 24)
        #expect(r.allEvents().alarms.isEmpty)
        let r2 = Self.passed([2500, 2600, 3000, 3800, 3000, 2400, 1800, 2000, 2400, 2800], kmh: 24)
        let alarms = r2.allEvents().alarms
        #expect(alarms.map(\.reason) == [.passedClosest] && r2.events.alarms.count == 1)
    }

    @Test("U78 (a) silenced then overshoot → Alarm(OVERSHOOT, ringNow) + Overshoot; (b) still ringing → only Overshoot; (c) ends 3600 s after Alarm(OVERSHOOT)")
    func u78() {
        var a = Self.run(Self.approachTo300)
        a.silenced(125)
        a.fix(150, d: 400, spd: 11.1); a.fix(180, d: 800, spd: 11.1); a.fix(210, d: 1350, spd: 11.1)
        #expect(a.events.alarms.map(\.reason) == [.overshoot] && a.events.alarms.first?.ringNow == true)
        #expect(a.events.named("overshoot").count == 1)
        let b = Self.run(Self.approachTo300 + [400, 800, 1350])
        #expect(b.events.alarms.isEmpty && b.events.named("overshoot").count == 1)
        a.tick(210 + 3599)
        #expect(a.events.named("tripEnded").isEmpty && a.view.phase == .overshot)
        a.tick(210 + 3600)
        #expect(a.events.compactMap(\.asEnded).first?.endReason == .alarmUnanswered)
    }
}

@Suite("SamplingPlannerTests")
struct SamplingPlannerTests {
    @Test("U39 tierOf with hysteresis; ACQUIRING / ALARMING → DENSE; not established → ≥ MEDIUM; emitted only on change")
    func u39() {
        let p = EngineParams.defaults
        #expect(SamplingPlanner.tierOf(4000, .sparse, p) == .sparse)
        #expect(SamplingPlanner.tierOf(4000, .medium, p) == .medium)
        #expect(SamplingPlanner.tierOf(3500, .sparse, p) == .medium)
        #expect(SamplingPlanner.tierOf(800, .sparse, p) == .dense)
        #expect(SamplingPlanner.tierOf(1100, .dense, p) == .dense)
        #expect(SamplingPlanner.tierOf(1200, .dense, p) == .medium)
        var s = EngineDriver().state
        #expect(SamplingPlanner.targetTier(s, nil, predicted: s.nowMs + 10_000_000, now: s.nowMs) == .dense)   // ACQUIRING
        s.phase = .alarming
        #expect(SamplingPlanner.targetTier(s, nil, predicted: nil, now: s.nowMs) == .dense)
        s.phase = .tracking; s.policy = SamplingPlanner.policyFor(.sparse, p, maxSaving: false)
        #expect(SamplingPlanner.targetTier(s, makeE(dNow: 1, v: 1, k: 1, established: false), predicted: s.nowMs + 10_000_000, now: s.nowMs) == .medium)
        var d = EngineDriver()
        d.drive(from: 0, d0: 200_000, v: 20, count: 60)
        let changes = d.allEvents().named("samplingPolicyChanged").count
        let distinctPolicies = Set(d.steps.compactMap { $0.view.samplingPolicy?.intervalS }).count
        #expect(changes >= distinctPolicies && changes <= 3)
    }

    @Test("U62 tierOf(null, MEDIUM) = MEDIUM; lost at DENSE with T = 5000 keeps DENSE")
    func u62() {
        let p = EngineParams.defaults
        #expect(SamplingPlanner.tierOf(nil, .medium, p) == .medium)
        var s = EngineDriver().state
        s.phase = .tracking; s.gps = .lost; s.policy = SamplingPlanner.policyFor(.dense, p, maxSaving: false)
        #expect(SamplingPlanner.targetTier(s, makeE(dNow: 1, v: 1, k: 1), predicted: s.nowMs + 5_000_000, now: s.nowMs) == .dense)
    }
}

@Suite("WakePlannerTests")
struct WakePlannerTests {
    static func base() -> EngineState { EngineDriver(startMs: 0).state }

    @Test("U70 wakeAt (a)–(h): acquire, NEVER_ACQUIRED, OK, LOST, SNOOZED, ALARMING, FAILED (c7), ENDED")
    func u70() {
        let p = EngineParams.defaults
        var a = EngineDriver(startMs: 0)
        #expect(a.view.wakeAtMs == 120_000)
        a.tick(120)
        #expect(a.events.compactMap(\.asGpsLost).first?.cause == .neverAcquired)
        var b = a.state
        b.fallback = .cleared   // U70 (a)–(f), (h) are specified with fb.targetAtMs = null (T10.2 round 2)
        #expect(WakePlanner.wakeAt(b, predicted: a.view.predictedAlarmAtMs, now: 120_000) == 13_800_000)
        var c = Self.base()
        c.phase = .tracking; c.gps = .ok
        c.last = FixRec(fixAtMs: 1_000_000, lat: 0, lng: 0, accM: 8, d: 1, groundSample: nil)
        c.policy = SamplingPlanner.policyFor(.dense, p, maxSaving: false); c.policyIntervalAtLastFixS = 5
        #expect(WakePlanner.wakeAt(c, predicted: 2_000_000, now: 1_000_000) == 1_060_000)
        var g = c
        g.fallback = FallbackState(targetAtMs: 2_030_000, emittedAtMs: 980_000, status: .failed, confirmedAtMs: nil, resync: false, near: false)
        #expect(WakePlanner.wakeAt(g, predicted: 2_000_000, now: 1_000_000) == 1_040_000)
        var dd = c
        dd.gps = .lost
        #expect(WakePlanner.wakeAt(dd, predicted: 3_000_000, now: 1_500_000) == 2_100_000)
        var e = c
        e.phase = .snoozed; e.alarm.snoozeUntilMs = 1_030_000; e.gps = .lost
        #expect(WakePlanner.wakeAt(e, predicted: nil, now: 1_000_000) == 1_030_000)
        var f = c
        f.phase = .alarming; f.gps = .lost; f.alarm.lastRingAtMs = 900_000
        #expect(WakePlanner.wakeAt(f, predicted: nil, now: 1_000_000) == 4_500_000)
        var h = c
        h.phase = .ended
        #expect(WakePlanner.wakeAt(h, predicted: nil, now: 1_000_000) == nil)
    }

    @Test("U70 (i) SNOOZED + fb FAILED: c7 is still a candidate (C13)")
    func u70i() {
        var s = Self.base()
        s.phase = .snoozed; s.gps = .lost; s.alarm.snoozeUntilMs = 2_000_000
        s.fallback = FallbackState(targetAtMs: 2_030_000, emittedAtMs: 980_000, status: .failed, confirmedAtMs: nil, resync: false, near: false)
        #expect(WakePlanner.wakeAt(s, predicted: nil, now: 1_000_000) == 1_040_000)
    }

    @Test("U96 c8: lost TRACKING, predicted N + 2 000 000: fb N + 700 000 → N + 610 000; fb N + 1 950 000 → c4 N + 1 100 000; ALARMING no c8")
    func u96() {
        let n: Int64 = 50_000_000
        var s = Self.base()
        s.phase = .tracking; s.gps = .lost
        s.fallback = FallbackState(targetAtMs: n + 700_000, emittedAtMs: n, status: .confirmed, confirmedAtMs: n, resync: false, near: false)
        #expect(WakePlanner.wakeAt(s, predicted: n + 2_000_000, now: n) == n + 610_000)
        s.fallback.targetAtMs = n + 1_950_000
        #expect(WakePlanner.wakeAt(s, predicted: n + 2_000_000, now: n) == n + 1_100_000)
        s.phase = .alarming; s.fallback = .cleared; s.alarm.lastRingAtMs = n
        #expect(WakePlanner.wakeAt(s, predicted: nil, now: n) == n + 3_600_000)
    }
}
