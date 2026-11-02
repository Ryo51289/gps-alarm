import Testing
@testable import Trip

/// T10.4 (T10 mục cuối "T10.4" §7.1): wakeGuardMs on the wake-up candidates (GAP-1) and lostAfterS that never shrinks between
/// two fixes (GAP-2). Mirror of T12 `WakeGuardT104Test` (U101, U103, U104). U99 / U100 replace the tester pins in
/// `TesterT13Tests`, U102 is in `WakePlannerTests`, U105 in `FuzzT104Tests`.
@Suite("WakeGuardT104Tests")
struct WakeGuardT104Tests {
    static let S = TesterT13Tests.S

    /// I13 (T10.4): not ENDED ⇒ wakeAtMs ≠ nil and > now; ENDED ⇒ nil. Returns a failure message or nil.
    static func i13(_ s: Step) -> String? {
        guard let w = s.view.wakeAtMs else { return s.view.phase == .ended ? nil : "I13 wakeAtMs nil in \(s.view.phase.jsonName)" }
        if s.view.phase == .ended { return "I13 wakeAtMs set while ENDED" }
        return w > s.state.nowMs ? nil : "I13 wakeAtMs \(w - s.state.nowMs) ms from now"
    }

    /// I14 (T10.4): reduce(s, Tick(s.nowMs)) emits nothing and returns an equal state and view. Returns a failure message or nil.
    static func i14(_ s: Step) -> String? {
        let again = TripEngine.reduce(s.state, .tick(atMs: s.state.nowMs))
        if !again.events.isEmpty { return "I14 events \(again.events.map(\.fixtureName))" }
        if again.state != s.state { return "I14 state changed" }
        if again.view != s.view { return "I14 view changed" }
        return nil
    }

    /// Doze loop: only Tick(view.wakeAtMs) until a Step has an Alarm. Returns (wake time − start, Step) per wake-up; I13 and
    /// strictly increasing wake-ups are checked at every Step.
    static func doze(_ e: inout EngineDriver, _ tag: String, max: Int = 2_000) -> [(Int64, Step)] {
        var out: [(Int64, Step)] = []
        var prev = Int64.min
        while true {
            if let f = i13(e.last) { Issue.record(Comment(rawValue: "\(tag): \(f)")); return out }
            let w = e.view.wakeAtMs!
            if w <= prev { Issue.record(Comment(rawValue: "\(tag): wake-ups not strictly increasing")); return out }
            prev = w
            let s = e.feed(.tick(atMs: w))
            out.append((w - e.startMs, s))
            if !s.events.alarms.isEmpty {
                if let f = i13(s) { Issue.record(Comment(rawValue: "\(tag): \(f)")) }
                return out
            }
            if out.count >= max { Issue.record(Comment(rawValue: "\(tag): no alarm after \(max) wake-ups")); return out }
        }
    }

    static func c2(_ s: EngineState) -> Int64 { s.last!.fixAtMs + TMath.ms(GpsMonitor.lostAfterS(s)) }

    // MARK: - U101

    @Test("U101 T10.4 §4.8: policyIntervalAtLastFixS is the longest interval in force since the last fix was requested")
    func u101() {
        // (a) DENSE (field 5), a fix whose predicted is far (T > 1 125 s) → MEDIUM: field 30, c2 = fix + 90 s.
        var a = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(d: 30_000, tier: .dense))
        #expect(a.state.policyIntervalAtLastFixS == 5)
        let sa = TesterT13Tests.t12Fix(&a, 5, 30_000.0 - 62.5)
        #expect(sa.view.samplingPolicy?.tier == .medium)
        #expect(sa.state.policyIntervalAtLastFixS == 30)
        #expect(Self.c2(sa.state) == Self.S + 95_000)
        #expect(sa.view.wakeAtMs == Self.S + 95_000)
        // (b) SPARSE (field 180), MAX_SAVING (360), then ALARM_EARLIER (back to 180): field keeps 360 → GpsLost at 1 080 s.
        func b() -> EngineDriver {
            var e = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(d: 100_000, tier: .sparse))
            #expect(e.state.policyIntervalAtLastFixS == 180)
            #expect(e.user(10, .batteryMaxSaving).state.policyIntervalAtLastFixS == 360)
            let s20 = e.user(20, .batteryAlarmEarlier)
            #expect(s20.view.samplingPolicy?.intervalS == 180)
            #expect(s20.state.policyIntervalAtLastFixS == 360)
            return e
        }
        var eb = b()
        #expect(eb.tick(1079).events.compactMap(\.asGpsLost).isEmpty)   // before T10.4: GpsLost at 540 s
        #expect(eb.tick(1080).events.compactMap(\.asGpsLost) == [.init(atMs: Self.S + 1_080_000, cause: .noFixTimeout, lastFixAgeS: 1080)])
        // (c) A fix resets the field to the policy at the start of its Step.
        var ec = b()
        let sc = TesterT13Tests.t12Fix(&ec, 1000, 100_000.0 - 12_500.0)
        #expect(sc.state.last?.fixAtMs == Self.S + 1_000_000)
        #expect(sc.state.policyIntervalAtLastFixS == 180)
        #expect(Self.c2(sc.state) == Self.S + 1_540_000)
        #expect((sc.view.wakeAtMs ?? .max) <= Self.S + 1_540_000)
        // (d) FallbackFired while SPARSE → ALARMING, DENSE: field stays 180, c2 kept, I14.
        var ed = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(d: 100_000, tier: .sparse))
        let sd = ed.fired(100, firedAtMs: Self.S + 100_000)
        #expect(sd.view.phase == .alarming && sd.view.samplingPolicy?.tier == .dense)
        #expect(sd.state.policyIntervalAtLastFixS == 180)
        let wd = sd.view.wakeAtMs ?? .min
        #expect(wd <= Self.S + 540_000 && wd > sd.state.nowMs)
        #expect(Self.i14(sd) == nil)
        // (e) start: DENSE requested at once, field 5.
        let st = try? TripEngine.start(config: TesterT13Tests.t12Config(), params: .defaults, nowMs: Self.S)
        #expect(st?.state.policyIntervalAtLastFixS == 5)
    }

    // MARK: - U103 (P08 in a unit test)

    struct ModeCase: Sendable {
        let name: String
        let config: TripConfig
        let slow: Bool
    }

    static func cfg(_ mode: AlarmMode, thr: Int? = nil, thrMin: Int? = nil) -> TripConfig {
        TripConfig(tripId: "trip-1", destLat: 0.0, destLng: 106.0, mode: mode, distanceThresholdM: thr, timeThresholdMin: thrMin,
                   preAlertEnabled: true, vehicleHint: .train)
    }

    static let modes: [ModeCase] = [
        ModeCase(name: "DISTANCE 500", config: cfg(.distance, thr: 500), slow: false),
        ModeCase(name: "DISTANCE 1000", config: cfg(.distance, thr: 1000), slow: false),
        ModeCase(name: "DISTANCE 10000", config: cfg(.distance, thr: 10_000), slow: false),
        ModeCase(name: "TIME 5", config: cfg(.time, thrMin: 5), slow: false),
        ModeCase(name: "TIME 15", config: cfg(.time, thrMin: 15), slow: false),
        ModeCase(name: "TIME 20", config: cfg(.time, thrMin: 20), slow: false),
        ModeCase(name: "TIME 30", config: cfg(.time, thrMin: 30), slow: false),
        ModeCase(name: "SMART", config: cfg(.smart), slow: false),
        ModeCase(name: "SMART slow", config: cfg(.smart), slow: true),
    ]

    /// One set: lost GPS at lostAfterS, then the Doze loop. Returns true when the alarm came at the GpsLost Step itself.
    static func p08Set(_ m: ModeCase, d: Double, ground: Double, closing: Double, guardV: [Double], tag: String) -> Bool {
        let st0 = TesterT13Tests.t12TrackingState(m.config, d: d, ground: ground, closing: closing, slow: m.slow, cvGuard: guardV)
        var e = TesterT13Tests.t12Driver(st0)
        let lostAt = Self.S + TMath.ms(GpsMonitor.lostAfterS(st0))
        let lost = e.feed(.tick(atMs: lostAt))
        #expect(!lost.events.compactMap(\.asGpsLost).isEmpty, "\(tag): no GpsLost at lostAfterS")
        #expect(i13(lost) == nil, "\(tag)")
        if !lost.events.alarms.isEmpty { return true }
        guard let p0 = lost.view.predictedAlarmAtMs else {
            Issue.record(Comment(rawValue: "\(tag): no predictedAlarmAtMs"))
            return false
        }
        let wakes = doze(&e, tag)
        guard let ringStep = wakes.last?.1, let a = ringStep.events.alarms.first else { return false }
        let prevView = wakes.count >= 2 ? wakes[wakes.count - 2].1.view : lost.view
        #expect(ringStep.events.alarms.count == 1 && a.ringNow, "\(tag): ringNow")
        #expect(a.reason != .fallback && a.reason != .fallbackMissed, "\(tag): \(a.reason)")
        #expect(a.atMs >= p0 + 999 && a.atMs <= p0 + 1001, "\(tag): alarm at \(a.atMs - p0) ms after P0")
        if let fb = prevView.fallbackAtMs {
            #expect(a.atMs <= fb - 28_000, "\(tag): alarm \(a.atMs - fb) ms vs fallback")
        } else {
            Issue.record(Comment(rawValue: "\(tag): no fallback before the alarm"))
        }
        return false
    }

    @Test("U103 P08: GPS lost and only wake-up Ticks: every mode rings 1 s after the predicted time, before the fallback")
    func u103() {
        var rng = SplitMix64(103)   // same generator and seed as Kotlin U103 → same 468 sets
        func dbl(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * rng.nextDouble() }
        var sets = 0
        var immediate: [String] = []
        let round = (d: 46_000.0, g: 15.0, c: 12.5)
        for m in Self.modes {
            var all: [(String, (Double, Double, Double))] = [("(i)", (round.d, round.g, round.c))]
            for i in 0..<50 {
                let g = dbl(3.0, 30.0)
                let d = dbl(3_000.0, 120_000.0)
                let c = dbl(0.6 * g, g)
                all.append(("(ii) #\(i)", (d, g, c)))
            }
            for (label, x) in all {
                let ground = m.slow && label == "(i)" ? 3.0 : x.1
                let closing = m.slow && label == "(i)" ? 2.5 : x.2
                let tag = "\(m.name) \(label) d=\(x.0) ground=\(ground) closing=\(closing)"
                if Self.p08Set(m, d: x.0, ground: ground, closing: closing, guardV: [], tag: tag) { immediate.append(tag) }
                sets += 1
            }
            // (iii) lifted: cvGuard above closingV.
            let tag = "\(m.name) (iii) lift"
            if Self.p08Set(m, d: round.d, ground: round.g, closing: round.c, guardV: [1.3 * round.c], tag: tag) { immediate.append(tag) }
            sets += 1
        }
        #expect(sets == 9 * 52)
        #expect(immediate.count < sets / 2, "too many sets alarm at the GpsLost Step: \(immediate.count)/\(sets)")
        Report.shared.write("unit/u103.txt", "sets=\(sets) alarmAtGpsLostStep=\(immediate.count)\n" + immediate.joined(separator: "\n") + "\n")
    }

    // MARK: - U104 (I14 on states from real Steps)

    @Test("U104 I14: Tick at the state's own now emits nothing and changes nothing (start, ACQUIRING, TRACKING, FAILED, SNOOZED, ALARMING, OVERSHOT, restore)")
    func u104() throws {
        var cases: [(String, Step)] = []
        cases.append(("start", try TripEngine.start(config: TesterT13Tests.t12Config(), params: .defaults, nowMs: Self.S)))
        var acq = EngineDriver(startMs: Self.S)
        let neverAcquired = acq.tick(120)
        #expect(neverAcquired.events.compactMap(\.asGpsLost).map(\.cause) == [.neverAcquired])
        cases.append(("ACQUIRING after NEVER_ACQUIRED", neverAcquired))
        let tiers: [(SamplingTier, Double)] = [(.sparse, 100_000), (.medium, 30_000), (.dense, 8_000)]
        for (tier, d) in tiers {
            var e = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(d: d, tier: tier))
            let s = TesterT13Tests.t12Fix(&e, 5, d - 62.5)
            #expect(s.view.samplingPolicy?.tier == tier)
            cases.append(("TRACKING OK \(tier)", s))
        }
        var lostE = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(d: 50_000))
        let lost = lostE.tick(60)
        #expect(lost.view.gps == .lost)
        cases.append(("TRACKING LOST", lost))
        var shortened = TesterT13Tests.lostTrip(3700)
        cases.append(("policy shortened (U100)", shortened.tick(100)))
        var failed = EngineDriver(startMs: Self.S)
        failed.fix(0, d: 50_000)
        let fbFailed = failed.scheduled(1, failed.state.fallback.targetAtMs!, ok: false)
        #expect(fbFailed.state.fallback.status == .failed)
        cases.append(("fb FAILED", fbFailed))
        func alarmed() -> EngineDriver {
            var e = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(d: 900, inStop: true))
            e.tick(0)
            return e
        }
        let ringing = alarmed()
        #expect(ringing.view.phase == .alarming)
        cases.append(("ALARMING", ringing.last))
        var sn = alarmed()
        let snoozed = sn.user(0, .snooze)
        #expect(snoozed.view.phase == .snoozed)
        cases.append(("SNOOZED", snoozed))
        var ov = EngineDriver(.distance, thr: 1000, startMs: Self.S)
        var t = 0.0
        for d in [3000.0, 2300, 1600, 900, 300, 400, 800, 1350] {
            ov.fix(t, d: d, spd: 40 / 3.6)
            t += 60
        }
        #expect(ov.view.phase == .overshot)
        cases.append(("OVERSHOT", ov.last))
        func tracking() -> EngineDriver {
            var e = EngineDriver(startMs: Self.S)
            e.fix(0, d: 50_000)
            return e
        }
        let target = tracking().state.fallback.targetAtMs!
        let after = Double((target - Self.S) / 1000 + 1)
        // Like Kotlin `EngineDriver.restore` (roundTrip = true): the restored state goes through encodeSnapshot / decodeSnapshot.
        func restored(_ t: Double, _ info: RestoreInfo) throws -> Step {
            let e = tracking()
            let st = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(e.state))
            return TripEngine.restore(st, nowMs: e.ms(t), info: info)
        }
        cases.append(("restore RANG", try restored(after, RestoreInfo(status: .rang, firedAtMs: target))))
        cases.append(("restore MISSING", try restored(10, RestoreInfo(status: .missing))))
        cases.append(("restore PENDING", try restored(10, RestoreInfo(status: .pending))))
        for (name, s) in cases {
            #expect(s.view.phase != .ended, "\(name)")
            #expect(Self.i13(s) == nil, "\(name): \(Self.i13(s) ?? "")")
            #expect(Self.i14(s) == nil, "\(name): \(Self.i14(s) ?? "")")
        }
    }
}
