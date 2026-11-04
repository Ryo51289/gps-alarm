import Testing
@testable import Trip

/// Tester additions for T13.1 (Swift engine on T10.4; docs/test-reports/T13.1.md). Exact port of the Kotlin tester's
/// `TesterT121Test` (app/android/core-trip/src/test/kotlin/app/napstop/core/trip/unit/TesterT121Test.kt): same generator
/// (splitmix64 seeded `seed * golden + 0x1234567`), same draw order, same builders (`trackingState` = `t12TrackingState`), so
/// the random sets and trips are the Kotlin ones. Each test writes `<report>/unit/t131-*.txt` in the Kotlin `t121-*.txt` format
/// (Kotlin `Double.toString` via `kd`) so the two files can be compared byte for byte; since T13.2 (T10.5) the storm test is U106 a/b
/// (`u106-storm.txt`), the A10 tests are U107 and the Doze fuzz is U111 (`u111-doze-*.txt`), same names as Kotlin T12.2.
/// Question: "is there any situation where the engine does not wake the user on time?"
@Suite("TesterT131Tests")
struct TesterT131Tests {
    static let S = TesterT13Tests.S
    static let G = WakePlanner.wakeGuardMs

    /// Kotlin `TesterT121Test.Rng`.
    struct Rng {
        private var x: UInt64
        init(_ seed: Int64) { x = UInt64(bitPattern: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234567 }

        mutating func next() -> UInt64 {
            x &+= 0x9E37_79B9_7F4A_7C15
            var z = x
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ n: Int) -> Int { Int((next() >> 1) % UInt64(n)) }
        mutating func dbl() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
        mutating func dbl(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * dbl() }
        mutating func chance(_ p: Double) -> Bool { dbl() < p }
    }

    // MARK: - helpers (Kotlin formatting, builders)

    /// Kotlin/JVM `Double.toString`: plain in [1e-3, 1e7), otherwise `d.dddE±n`.
    static func kd(_ x: Double) -> String {
        if x == 0 { return x.sign == .minus ? "-0.0" : "0.0" }
        let a = x.magnitude
        let sign = x < 0 ? "-" : ""
        if a >= 1e-3 && a < 1e7 { return "\(x)" }
        let s = "\(a)"
        var mant = s
        var e = 0
        if let i = s.firstIndex(of: "e") {
            mant = String(s[..<i])
            e = Int(s[s.index(after: i)...].filter { $0 != "+" })!
        }
        var digits = Array(mant.filter { $0 != "." })
        var point = (mant.firstIndex(of: ".").map { mant.distance(from: mant.startIndex, to: $0) } ?? mant.count) + e
        while digits.first == "0" { digits.removeFirst(); point -= 1 }
        while digits.count > 1 && digits.last == "0" { digits.removeLast() }
        let rest = digits.count > 1 ? String(digits[1...]) : "0"
        return "\(sign)\(digits[0]).\(rest)E\(point - 1)"
    }

    static func opt(_ x: Int?) -> String { x.map { "\($0)" } ?? "null" }
    static func optKd(_ x: Int64?) -> String { x.map { kd(Double($0 &- S) / 1000.0) } ?? "null" }

    /// Kotlin `cfg(mode, thr, thrMin)`: destination (0, 106), TRAIN, pre-alert on; DISTANCE defaults to 1000 m, TIME to 15 min.
    static func cfg(_ mode: AlarmMode = .distance, thr: Int? = nil, thrMin: Int? = nil) -> TripConfig {
        TripConfig(tripId: "trip-1", destLat: 0.0, destLng: 106.0, mode: mode,
                   distanceThresholdM: thr ?? (mode == .distance ? 1000 : nil), timeThresholdMin: thrMin ?? (mode == .time ? 15 : nil),
                   preAlertEnabled: true, vehicleHint: .train)
    }

    static func preAlerts(_ s: Step) -> [TripEvent.PreAlert] {
        s.events.compactMap { if case let .preAlert(p) = $0 { return p } else { return nil } }
    }

    static func lostAtMs(_ st: EngineState) -> Int64 { S + TMath.ms(GpsMonitor.lostAfterS(st)) }

    /// Kotlin `i13`.
    static func i13(_ s: Step) -> String? {
        let w = s.view.wakeAtMs
        if s.view.phase == .ended { return w == nil ? nil : "I13 ENDED with wakeAt" }
        guard let w else { return "I13 wakeAt null in \(s.view.phase.jsonName)" }
        return w <= s.state.nowMs ? "I13 wakeAt \(w - s.state.nowMs) ms <= now in \(s.view.phase.jsonName)" : nil
    }

    /// Kotlin `i14` (events, state and view unchanged by Tick(now)).
    static func i14(_ s: Step) -> String? {
        if s.view.phase == .ended { return nil }
        let again = TripEngine.reduce(s.state, .tick(atMs: s.state.nowMs))
        if !again.events.isEmpty { return "I14 Tick(now) emitted \(again.events.map(\.fixtureName))" }
        if again.state != s.state { return "I14 Tick(now) changed the state" }
        if again.view != s.view { return "I14 Tick(now) changed the view" }
        return nil
    }

    // MARK: - A10: pre-alert during GPS loss (TIME / SMART)

    struct DozeRun {
        let lost: Step
        let wakes: [Step]
    }

    /// Kotlin `lostDoze`: TRACKING DENSE, one fix at S, etaS at the fix = eta0; Tick at lostAfterS → GpsLost; then only
    /// Tick(view.wakeAtMs) until the Alarm.
    static func lostDoze(_ config: TripConfig, eta0: Double, ground: Double, closing: Double, slow: Bool, _ tag: String) -> DozeRun? {
        let d = (eta0 - 20.0) * closing
        // T10.6 §6: U107 loses GPS >= gpsLostLongS before the alarm and checks the A10 pre-alert rule, so W is off (U120 d: W on).
        let st = TesterT13Tests.t12TrackingState(config, d: d, ground: ground, closing: closing, slow: slow,
                                                 p: KW.params(#"{"gpsLostLongS": 0}"#))
        var e = TesterT13Tests.t12Driver(st)
        let lost = e.feed(.tick(atMs: lostAtMs(st)))
        guard !lost.events.compactMap(\.asGpsLost).isEmpty else {
            Issue.record(Comment(rawValue: "\(tag): no GpsLost at lostAfterS"))
            return nil
        }
        var wakes: [Step] = []
        var prev = lost
        while prev.events.alarms.isEmpty {
            if let f = i13(prev) {
                Issue.record(Comment(rawValue: "\(tag): \(f)"))
                return nil
            }
            prev = e.feed(.tick(atMs: prev.view.wakeAtMs!))
            wakes.append(prev)
            if wakes.count >= 499 {
                Issue.record(Comment(rawValue: "\(tag): no alarm after 499 wake-ups"))
                return nil
            }
        }
        // I5: at most one PreAlert over the trip, never at or after the Alarm (T10.5 U107).
        let all = [lost] + wakes
        let preIdx = all.indices.filter { !preAlerts(all[$0]).isEmpty }
        let alarmIdx = all.firstIndex { !$0.events.alarms.isEmpty } ?? -1
        #expect(preIdx.count <= 1 && preIdx.allSatisfy { $0 < alarmIdx }, "\(tag) I5: pre-alerts at \(preIdx), alarm at \(alarmIdx)")
        return DozeRun(lost: lost, wakes: wakes)
    }

    @Test("U107 a A10 (= T121): TIME/SMART pre-alert during GPS loss lands on the near-zone wake-up P − 599 s (etaS 1799), GPS_LOST at P + 1 s")
    func a10PreAlert() {
        var rng = Rng(10)
        let modes: [(String, TripConfig, Bool)] = [
            ("TIME 5", Self.cfg(.time, thrMin: 5), false),
            ("TIME 15", Self.cfg(.time, thrMin: 15), false),
            ("TIME 20", Self.cfg(.time, thrMin: 20), false),
            ("SMART", Self.cfg(.smart), false),
            ("SMART slow", Self.cfg(.smart), true),
        ]
        var log = ""
        var sets = 0
        for (name, config, slow) in modes {
            var sets0: [(Double, Double, Double)] = [slow ? (5_000.0, 3.0, 2.5) : (5_000.0, 15.0, 12.5)]
            for _ in 0..<30 {
                // SMART slow: closing > 2.12 m/s so slowDistM (2 500 m) is reached after etaS 1200 (P = lostAt, the A10 claim).
                let g = slow ? rng.dbl(2.6, 4.1) : rng.dbl(5.0, 30.0)
                let eta0 = rng.dbl(2_000.0, 20_000.0)
                let c = rng.dbl(slow ? Swift.max(0.6 * g, 2.2) : 0.6 * g, g)
                sets0.append((eta0, g, c))
            }
            for (eta0, g, c) in sets0 {
                let tag = "\(name) eta0=\(Self.kd(eta0)) ground=\(Self.kd(g)) closing=\(Self.kd(c))"
                guard let r = Self.lostDoze(config, eta0: eta0, ground: g, closing: c, slow: slow, tag),
                      let p0 = r.lost.view.predictedAlarmAtMs, let alarmStep = r.wakes.last else { continue }
                let pre = r.wakes.filter { !Self.preAlerts($0).isEmpty }
                #expect(pre.count == 1, "\(tag): pre-alert count \(pre.count)")
                guard pre.count == 1, alarmStep.events.alarms.count == 1 else {
                    Issue.record(Comment(rawValue: "\(tag): alarms \(alarmStep.events.alarms)"))
                    continue
                }
                let preStep = pre[0]
                let a = alarmStep.events.alarms[0]
                #expect(a.reason == .gpsLost, "\(tag)")
                #expect(a.ringNow, "\(tag)")
                #expect(preStep.state.nowMs < alarmStep.state.nowMs, "\(tag): pre-alert not before the alarm")
                let expect = p0 - 600_000 + Self.G
                #expect((expect - 1)...(expect + 1) ~= preStep.state.nowMs, "\(tag): pre-alert at \(preStep.state.nowMs - p0) ms vs P0")
                let eta = Self.preAlerts(preStep)[0].etaS ?? -1
                #expect((1799...1800).contains(eta), "\(tag): pre-alert etaS \(eta)")
                #expect((999...1001).contains(a.atMs - p0), "\(tag): alarm \(a.atMs - p0) ms after P0")
                log += "\(tag) lead=\((a.atMs - preStep.state.nowMs) / 1000) s etaS=\(eta)\n"
                sets += 1
            }
        }
        #expect(sets == 155)
        Report.shared.write("unit/t131-a10.txt", "sets=\(sets)\n\(log)")
    }

    /// U107 b–d, outside the A10 scope of T10.5 §2.2 (pinned numbers of the T12.1 tester): TIME 21–25 min, SMART slow closing
    /// < 2.12 m/s and DISTANCE. The pre-alert comes at the c8 wake-up 61 s before the alarm, or not at all (I5 allows).
    @Test("U107 b c d A10 outside the scope (= T121): TIME 21/25 and SMART slow 1.5 pre-alert 61 s before GPS_LOST; SMART slow 1.41 and DISTANCE none")
    func a10Outside() {
        var out = ""
        func measure(_ name: String, _ config: TripConfig, _ ground: Double, _ closing: Double, _ slow: Bool) -> [Double]? {
            guard let r = Self.lostDoze(config, eta0: 5_000.0, ground: ground, closing: closing, slow: slow, name),
                  let alarm = r.wakes.last, alarm.events.alarms.count == 1 else {
                Issue.record(Comment(rawValue: "\(name): no single alarm"))
                return nil
            }
            let a = alarm.events.alarms[0]
            #expect(a.ringNow && a.reason == .gpsLost, "\(name)")
            let leads = r.wakes.filter { !Self.preAlerts($0).isEmpty }.map { Double(alarm.state.nowMs - $0.state.nowMs) / 1000.0 }
            out += "\(name): alarm \(a.reason.jsonName) at etaS \(Self.opt(alarm.view.etaS)); pre-alert lead "
                + "[\(leads.map { Self.kd($0) }.joined(separator: ", "))] s; wake-ups \(r.wakes.count)\n"
            return leads
        }
        _ = measure("TIME 20 (claim, reference)", Self.cfg(.time, thrMin: 20), 15.0, 12.5, false)
        let t21 = measure("TIME 21", Self.cfg(.time, thrMin: 21), 15.0, 12.5, false)
        let t25 = measure("TIME 25", Self.cfg(.time, thrMin: 25), 15.0, 12.5, false)
        let slow15 = measure("SMART slow closing 1.5", Self.cfg(.smart), 1.8, 1.5, true)
        let slow141 = measure("SMART slow closing 1.41", Self.cfg(.smart), 1.69, 1.41, true)
        let dist = measure("DISTANCE 1000", Self.cfg(.distance, thr: 1000), 15.0, 12.5, false)
        Report.shared.write("unit/t131-a10-outside.txt", out)
        #expect(t21 == [61.0])
        #expect(t25 == [61.0])
        #expect(slow15 == [61.0])
        #expect(slow141 == [])
        #expect(dist == [])
    }

    // MARK: - early wake-up delivery (T10.4 §3.1 (2))

    @Test("T131 early Tick (= T121): a Tick delivered up to 998 ms before wakeAtMs still rings when GPS is lost (every mode, 14 361 probes)")
    func earlyTick() {
        var rng = Rng(31)
        let modes = [
            Self.cfg(.distance, thr: 200), Self.cfg(.distance, thr: 1000), Self.cfg(.distance, thr: 10_000),
            Self.cfg(.time, thrMin: 5), Self.cfg(.time, thrMin: 20), Self.cfg(.time, thrMin: 60), Self.cfg(.smart),
        ]
        var probes = 0
        var failures: [String] = []
        for config in modes {
            for slow in [false, true] {
                if slow && config.mode != .smart { continue }
                for i in 0..<60 {
                    let g = slow ? rng.dbl(0.8, 4.0) : rng.dbl(3.0, 35.0)
                    let c = rng.dbl(0.5 * g, g)
                    let d = rng.dbl(1_500.0, 150_000.0)
                    let guardV: [Double] = rng.chance(0.3) ? [c * rng.dbl(1.0, 1.6)] : []
                    let st = TesterT13Tests.t12TrackingState(config, d: d, ground: g, closing: c, slow: slow, cvGuard: guardV)
                    var e = TesterT13Tests.t12Driver(st)
                    var s = e.feed(.tick(atMs: Self.lostAtMs(st)))
                    let tag = "\(config.mode.jsonName) thr=\(Self.opt(config.distanceThresholdM))/\(Self.opt(config.timeThresholdMin)) slow=\(slow) #\(i)"
                    var n = 0
                    while s.events.alarms.isEmpty {
                        guard let p = s.view.predictedAlarmAtMs, let w = s.view.wakeAtMs else {
                            failures.append("\(tag): predicted/wakeAt nil")
                            break
                        }
                        let earlies: [Int64] = [998, Int64(rng.int(999)), 0]
                        for early in earlies {
                            let at = p + Self.G - early
                            if at < s.state.nowMs { continue }
                            let r = TripEngine.reduce(s.state, .tick(atMs: at))
                            let al = r.events.alarms
                            if al.count != 1 || !al[0].ringNow || al[0].reason == .fallback {
                                failures.append("\(tag): Tick \(early) ms early (P + \(Self.G - early) ms) did not ring: \(al)")
                            }
                            probes += 1
                        }
                        s = e.feed(.tick(atMs: w))
                        n += 1
                        if n >= 499 {
                            failures.append("\(tag): no alarm after 499 wake-ups")
                            break
                        }
                    }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10))")
        #expect(probes > 1_000)
        Report.shared.write("unit/t131-early.txt", "probes=\(probes)\n")
    }

    @Test("T131 GPS OK, no new fix (= T121): dead reckoning wake-up at P + 1 s rings the mode alarm before c2 (240 sets)")
    func gpsOkNoFix() {
        var rng = Rng(32)
        var n = 0
        var out = ""
        for config in [Self.cfg(.distance, thr: 500), Self.cfg(.time, thrMin: 10), Self.cfg(.smart)] {
            for _ in 0..<80 {
                let g = rng.dbl(5.0, 35.0)
                let c = rng.dbl(0.6 * g, g)
                // Boundary 5–55 s after the fix (DENSE: lostAfterS = 60 s).
                let x = rng.dbl(5.0, 55.0)
                let d: Double
                switch config.mode {
                case .distance: d = 500.0 + c * x
                case .time: d = (600.0 - 20.0 + x) * c
                case .smart:
                    let a = 1000.0 + c * x, b = (600.0 - 20.0 + x) * c
                    d = a > b ? a : b
                }
                var e = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(config, d: d, ground: g, closing: c))
                var s = e.feed(.tick(atMs: Self.S + 1_000))
                #expect(s.view.gps == .ok)
                var wakes = 0
                while s.events.alarms.isEmpty, wakes < 49, let w = s.view.wakeAtMs {
                    s = e.feed(.tick(atMs: w))
                    wakes += 1
                }
                guard s.events.alarms.count == 1 else {
                    Issue.record(Comment(rawValue: "\(config.mode.jsonName) x=\(x): no single alarm after \(wakes) wake-ups"))
                    continue
                }
                let a = s.events.alarms[0]
                #expect(a.reason != .gpsLost && a.reason != .fallback && a.ringNow, "\(a.reason)")
                #expect(s.view.gps == .ok, "rang before c2")
                let bound = Int64((x * 1000.0).rounded(.up)) + Self.G + 1
                #expect(a.atMs - Self.S <= bound, "late: \(a.atMs - Self.S) vs boundary \(x * 1000)")
                out += "\(config.mode.jsonName) \(a.reason.jsonName) at \(a.atMs - Self.S) ms, boundary \(Self.kd(x * 1000.0)) ms, wakes \(wakes)\n"
                n += 1
            }
        }
        #expect(n == 240)
        Report.shared.write("unit/t131-gpsok.txt", "sets=\(n)\n\(out)")
    }

    // MARK: - U106 a/b: no wake-up storm (GPS OK + stopped; designer note #1 of the T12.1 report, fixed by T10.5)

    /// U106 (a), (b) (T10 mục T10.5 §6; was the storm characterisation). GPS OK, the last fix is STATIONARY: dNow = dSmooth, so
    /// predicted = now + T slides with now. Before T10.5 a wake-up every 1 499 ms (40 / 60 / 360 before c2; 794 in a 20-minute
    /// SPARSE stop). T10.5: c3/c4 come from wakeBasisAt (= deadlineAt while sliding), so the only wake-up left is c2.
    @Test("U106 a b (= T121): GPS OK and stopped with T just above a boundary asks for no wake-up storm (1 Tick to GpsLost; 0 in a 20-min stop)")
    func storm() {
        var out = ""
        let tiers: [(SamplingTier, Int, Int64)] = [(.dense, 600, 60_000), (.medium, 900, 90_000), (.sparse, 3600, 540_000)]
        for (tier, b, expectWake) in tiers {
            // DISTANCE 1000, cvDr = 12.5: T = (d − 1000)/12.5 = B + 0.5 s.
            let d = 1000.0 + 12.5 * (Double(b) + 0.5)
            var e = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(Self.cfg(), d: d, inStop: true, tier: tier))
            var s = e.feed(.tick(atMs: Self.S + 1))
            #expect(Self.i13(s) == nil)
            #expect(s.view.wakeAtMs == Self.S + expectWake, "\(tier.jsonName): wakeAtMs after Tick(S + 1)")
            var wakes = 0
            while s.view.gps == .ok && s.events.alarms.isEmpty {
                s = e.feed(.tick(atMs: s.view.wakeAtMs!))
                #expect(Self.i13(s) == nil, "\(tier.jsonName)")
                wakes += 1
                if wakes > 5_000 { break }
            }
            out += "tier \(tier.jsonName) B=\(b): \(wakes) wake-up Tick(s) until GpsLost at \(Self.kd(Double(s.state.nowMs - Self.S) / 1000.0)) s "
                + "(before T10.5: 40/60/360)\n"
            #expect(wakes == 1, "\(tier.jsonName): wake-up Ticks until GpsLost")
            let lost = s.events.compactMap(\.asGpsLost)
            #expect(lost.count == 1 && lost.first?.cause == .noFixTimeout)
            let alarm = s.events.alarms
            if tier == .sparse {
                #expect(alarm.isEmpty, "SPARSE: only GpsLost")
            } else {
                // etaS 640.5 / 910.5 < gpsLostAlarmEtaS 1 200.
                #expect(alarm.count == 1 && alarm.first?.reason == .gpsLost && alarm.first?.ringNow == true, "\(tier.jsonName): \(alarm)")
            }
        }
        // (b) Stationary fixes every 180 s for a 20-minute SPARSE stop; a wake-up Tick only when it comes before the next fix.
        let d = 1000.0 + 12.5 * 3600.5
        var e = TesterT13Tests.t12Driver(TesterT13Tests.t12TrackingState(Self.cfg(), d: d, inStop: true, tier: .sparse))
        var s = e.feed(.tick(atMs: Self.S + 1))
        var ticks = 0
        var nextFix = Self.S + 180_000
        while s.state.nowMs < Self.S + 1_200_000 {
            let w = s.view.wakeAtMs!
            if nextFix <= w {
                let t = (nextFix - Self.S) / 1000
                let at = Self.S + t * 1000
                s = e.feed(.locationFix(LocationFix(atMs: at, fixAtMs: at, lat: 0.0 - d / Geo.kMetresPerDegLat, lng: 106.0,
                                                    accuracyM: 8.0, speedMps: 0.0)))
                nextFix += 180_000
            } else {
                ticks += 1
                s = e.feed(.tick(atMs: w))
            }
            #expect(Self.i13(s) == nil)
            #expect(s.view.gps == .ok)
            #expect(s.events.alarms.isEmpty)
        }
        out += "SPARSE B=3600, stopped 1 200 s with a stationary fix every 180 s: \(ticks) wake-up Ticks (before T10.5: 794)\n"
        #expect(ticks == 0, "U106 b: wake-up Ticks during the stop")
        Report.shared.write("unit/u106-storm.txt", out)
    }

    // MARK: - Doze platform fuzz (Kotlin `dozeTrip`)

    struct Truth {
        let d0: Double
        let base: Double
        var segs: [(Double, Double)] = []   // (startS, speed m/s)

        init(_ r: inout Rng, d0: Double) {
            self.d0 = d0
            base = r.dbl(3.0, 35.0)
            var t = 0.0
            while t < 200_000.0 {
                let moveS = r.dbl(300.0, 3_600.0)
                segs.append((t, base * r.dbl(0.7, 1.3)))
                t += moveS
                if r.chance(0.3) {
                    segs.append((t, 0.0))
                    t += r.dbl(30.0, 1_500.0)
                }
            }
        }

        func dAt(_ tS: Double) -> Double {
            var d = d0
            for i in segs.indices {
                let (s0, v) = segs[i]
                if s0 >= tS { break }
                let s1 = i + 1 < segs.count ? Swift.min(segs[i + 1].0, tS) : tS
                d -= v * (s1 - s0)
            }
            return d
        }

        func speedAt(_ tS: Double) -> Double { segs.last { $0.0 <= tS }!.1 }
    }

    final class FuzzStats {
        var trips = 0
        var steps = 0
        var probes = 0
        var firstBy: [String: Int] = [:]
        var violations: [String: Int] = [:]
        var firstViolation: [String: String] = [:]
        var kills = 0
        var minWakeGapMs = Int64.max
        var maxWakesIn9Min = 0
        var dozeTickAlarms = 0
        var dozeTickAlarmsWithin9Min = 0
        var ties = 0
        var lateVsTruth: [Double] = []
        var lateCases: [(Double, String)] = []
        var fbAfterInfo: [String] = []
        /// T10.5: urgent later shifts (I4 exception) emitted in the fuzz.
        var urgentShifts = 0
        /// T10.5: `fallback (new info after planning)` first alarms: predicted at the last Step before it fired − F, s.
        var earlyS: [Double] = []
        /// T10.5 round 2: fallback-first planned on unchanged information while the engine believes it is stopped with <= Q to the
        /// boundary, by the truth speed at the ring (< stationarySpeedMps: really stopped).
        var believedStopReal: [String] = []
        var believedStopMoving: [String] = []
        /// U116 (b): OVERSHOOT / PASSED_CLOSEST using a minD from the GPS-gap chord.
        var gapTriggers = 0
        var gapLines: [String] = []
        /// U126 (T10.6): first alarms due to the "long loss" term W alone; true seconds to the destination at them (< 0: after).
        var longLostAlarms = 0
        var longLostRemainingS: [Double] = []
        /// U126: per-seed lines for the seeds of the review (55, 433, 787).
        var seedLines: [String] = []
        /// U126 (after T12.3, D5): DISTANCE cases late > 1 800 s, (late, line).
        var lateLines: [(Double, String)] = []
        var lastFirstKey = ""

        func v(_ kind: String, _ at: @autoclosure () -> String) {
            violations[kind, default: 0] += 1
            if firstViolation[kind] == nil { firstViolation[kind] = at() }
        }

        func first(_ k: String) {
            lastFirstKey = k
            firstBy[k, default: 0] += 1
        }

        /// Kotlin `sortedMapOf<String, *>().toString()`.
        static func map<V>(_ m: [String: V]) -> String { "{" + m.keys.sorted().map { "\($0)=\(m[$0]!)" }.joined(separator: ", ") + "}" }
    }

    enum Variant: Int {
        case noFix = 0, withFixes, fromStart
        var name: String { ["DOZE_NO_FIX", "DOZE_WITH_FIXES", "DOZE_FROM_START"][rawValue] }
    }

    /// T10.5 U111: the last Step that carried new information (fix, battery sample, restore): its now, the fallback in force before
    /// it, the predicted time after it and whether it moved the fallback later.
    struct InfoStep {
        let t: Int64
        let fBefore: Int64?
        let statusBefore: FallbackStatus
        let predicted: Int64?
        let movedLater: Bool
    }

    static func infoStep(_ t: Int64, _ s0: EngineState, _ step: Step) -> InfoStep {
        let f = s0.fallback.targetAtMs
        let moved = f != nil && step.events.fallbacks.contains { ($0.fallbackAtMs ?? .min) > f! }
        return InfoStep(t: t, fBefore: f, statusBefore: s0.fallback.status, predicted: step.view.predictedAlarmAtMs, movedLater: moved)
    }

    /// Kotlin `AlarmReason.name` / "Overshoot" list of the Alarm and Overshoot events of a Step, as Kotlin `List.toString()`.
    static func passKinds(_ events: [TripEvent]) -> String {
        var k: [String] = []
        for e in events {
            if case let .alarm(a) = e { k.append(a.reason.jsonName) }
            if case .overshoot = e { k.append("Overshoot") }
        }
        return KW.klist(k)
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func dozeTrip(_ seed: Int64, _ variant: Variant, okP: Double, killP: Double, battery: Bool, _ st: FuzzStats,
                         params: EngineParams = .defaults) throws {
        var r = Rng(seed &* 7919 &+ Int64(variant.rawValue))
        let mode = AlarmMode.allCases[r.int(3)]
        let thr: Int? = mode == .distance || r.chance(0.3) ? 200 + r.int(9801) : nil
        let thrMin: Int? = mode == .time || (mode != .distance && r.chance(0.3)) ? 5 + r.int(56) : nil
        let preAlert = r.chance(0.7)
        let hint = VehicleKind.allCases[r.int(4)]
        let config = TripConfig(tripId: "doze-\(seed)", destLat: 0.0, destLng: 106.0, mode: mode, distanceThresholdM: thr,
                                timeThresholdMin: thrMin, preAlertEnabled: preAlert, vehicleHint: hint)
        let d0 = r.dbl(3_000.0, 600_000.0)
        let truth = Truth(&r, d0: d0)
        var step = try TripEngine.start(config: config, params: params, nowMs: S)
        let tripTag = "seed=\(seed) \(variant.name) mode=\(mode.jsonName) thr=\(opt(thr))/\(opt(thrMin)) d0=\(Int(truth.d0))"
        let dozeAtS = variant == .fromStart ? r.dbl(0.0, 300.0) : r.dbl(0.0, 1.0) * truth.d0 / truth.base
        let gapA = r.chance(0.5) ? r.dbl(0.0, 1.2) * truth.d0 / truth.base : Double.greatestFiniteMagnitude
        let gapB = gapA + r.dbl(60.0, 7_200.0)
        let withFixInDoze = variant == .withFixes
        let fixInDozeP = r.dbl(0.2, 0.9)
        var killAt: Int64? = r.chance(killP) ? S + Int64(r.dbl(0.0, 1.5) * truth.d0 / truth.base * 1000.0) : nil
        var lastFixAt = S - 1_000_000
        var lastInfoAt = S   // last input that may move predicted: fix, battery, restore
        var lastInfoKind = "start"
        var lastInfo: InfoStep? = nil
        var chordMinD: Double? = nil   // U116 (b): last dChord of the trip
        let p = params
        var batteryAt = S
        var level = 20 + r.int(81)
        let drainPerH = r.dbl(1.0, 12.0)
        var rang = false
        var guardN = 0
        var prevWakeTicks: [Int64] = []
        func deadline(_ s: EngineState) -> Int64 { s.startedAtMs + TMath.ms(s.maxTripDurationS) + TMath.ms(s.params.fallbackLagS) }
        var everDead = false
        // U126 classes: states after every Step (DISTANCE trips) and the harness death intervals [kill, restart).
        var states: [EngineState] = []
        if mode == .distance { states.append(step.state) }
        var deadIntervals: [(Int64, Int64)] = []

        func inGap(_ tMs: Int64) -> Bool {
            let ts = Double(tMs - S) / 1000.0
            return ts >= gapA && ts < gapB
        }

        func check(_ prev: Step, _ s: Step, _ label: @escaping () -> String) {
            if mode == .distance { states.append(s.state) }
            st.steps += 1
            let at = { "\(tripTag) t=\(kd(Double(s.state.nowMs - S) / 1000.0)) after \(label())" }
            if !Runner.finite(s.state) { st.v("finite", at()) }
            // I4 (T10.5 wording) and the urgent-later-shift counter.
            for x in s.events.fallbacks where x.cause == .eta {
                switch Checks.quietEmission(prev.view, s.view, x, s.state.params) {
                case false?: st.v("I4", at())
                case true?: st.urgentShifts += 1
                case nil: break
                }
            }
            if let m = i13(s) {
                var k = m
                if let r = k.firstRange(of: " in ") { k = String(k[..<r.lowerBound]) }
                if let r = k.firstRange(of: " ms") { k = String(k[..<r.lowerBound]) }
                st.v(k, at())
            }
            if let m = i14(s) { st.v(String(m.prefix(40)), at()) }
            if s.view.phase != .ended {
                // Restore PENDING at the state's own now behaves as Tick(now) (T10.4 §8).
                let rp = TripEngine.restore(s.state, nowMs: s.state.nowMs, info: RestoreInfo(status: .pending))
                if !rp.events.isEmpty || rp.state != s.state { st.v("restore PENDING at now not silent", at()) }
                // Tick at wakeAtMs: rings / ends, or re-arms strictly later.
                if let w = s.view.wakeAtMs {
                    let rr = TripEngine.reduce(s.state, .tick(atMs: w))
                    st.probes += 1
                    let ok = !rr.events.alarms.isEmpty || rr.state.phase == .ended || (rr.view.wakeAtMs ?? .min) > w
                        || rr.state.phase != s.state.phase
                    if !ok { st.v("Tick(wakeAt) neither rings nor re-arms later", at()) }
                }
                let ph = s.view.phase
                if (ph == .acquiring || ph == .tracking) && s.state.fallback.targetAtMs == nil && s.state.fallback.status != .notSet {
                    st.v("active fb status without target", at())
                }
            }
            if prev.state.alarm.atMs != nil && prev.state.alarm.atMs != s.state.alarm.atMs { st.v("first alarm time changed", at()) }
        }

        while step.state.phase != .ended {
            guardN += 1
            if guardN > 60_000 {
                st.v("no end after 60 000 events", tripTag)
                break
            }
            let s0 = step.state
            let now = s0.nowMs
            let awake = Double(now - S) / 1000.0 < dozeAtS
            let interval = Int64(step.view.samplingPolicy?.intervalS ?? 5) * 1000
            let wake = step.view.wakeAtMs
            let fb: Int64? = s0.fallback.status == .confirmed ? s0.fallback.targetAtMs : nil
            var nextFix: Int64?
            if awake {
                nextFix = Swift.max(lastFixAt + interval, now + 1)
            } else if withFixInDoze, let w = wake, r.chance(fixInDozeP) {
                nextFix = w   // a fix right at the wake-up (FGS location while the CPU is up)
            }
            if let nf = nextFix, inGap(nf) { nextFix = nil }
            let nextBattery: Int64? = battery ? batteryAt + 600_000 : nil
            let candidates = [wake, fb.map { Swift.max($0, now) }, nextFix, nextBattery, killAt.map { Swift.max($0, now) }].compactMap { $0 }
            guard let t = candidates.min() else {
                st.v("nothing will ever run again", "\(tripTag) phase=\(s0.phase.jsonName)")
                break
            }
            if !rang && t > deadline(s0) && !everDead { st.v("silent past deadline + fallbackLag", tripTag) }
            if let w = wake, let f = fb, w == f { st.ties += 1 }
            let prev = step
            let label: () -> String
            if let k = killAt, t == Swift.max(k, now) {
                // Process death. Restart after a random delay, or when the OS fallback fires (it starts the app).
                st.kills += 1
                everDead = true
                let delay = Int64(r.dbl(1.0, 7_200.0) * 1000.0)
                var restartAt = t + delay
                let info: RestoreInfo
                if let f = fb, f <= restartAt {
                    restartAt = Swift.max(f, t)
                    info = RestoreInfo(status: .rang, firedAtMs: f)
                } else {
                    switch r.int(10) {
                    case 0: info = RestoreInfo(status: .missing)
                    case 1: info = RestoreInfo(status: .unknown)
                    default: info = RestoreInfo(status: .pending)
                    }
                }
                deadIntervals.append((t, restartAt))
                killAt = r.chance(0.3) ? restartAt + Int64(r.dbl(60.0, 7_200.0) * 1000.0) : nil
                let snap = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s0))
                step = TripEngine.restore(snap, nowMs: restartAt, info: info)
                lastInfoAt = restartAt
                lastInfoKind = "restore"
                lastInfo = infoStep(restartAt, s0, step)
                label = { "RESTORE \(info.status.jsonName)" }
                if !rang, let a = step.events.alarms.first {
                    rang = true
                    st.first("restore \(info.status.jsonName) " + a.reason.jsonName)
                    noteU126(st, seed, tripTag, config, truth, restartAt, step)
                }
            } else {
                let viaFb = fb != nil && t == Swift.max(fb!, now) && (wake == nil || fb! < wake!)
                let input: EngineInput
                if viaFb {
                    input = .fallbackFired(atMs: t, firedAtMs: fb!)
                } else if t == nextFix {
                    let ts = Double(t - S) / 1000.0
                    let d = truth.dAt(ts)
                    var dd = d.magnitude
                    let acc = r.chance(0.1) ? r.dbl(60.0, 400.0) : r.dbl(4.0, 30.0)
                    if r.chance(0.03) { dd += r.dbl(-2_000.0, 4_000.0) }   // GPS jump
                    // TestGeo.jitter(TestGeo.pointOnMeridian(DEST, ±dd), east, 0.0) with DEST = (0, 106).
                    let lat0 = 0.0 - (d < 0 ? -dd : dd) / Geo.kMetresPerDegLat
                    let east = r.dbl(-15.0, 15.0)
                    let lat = lat0 + 0.0 / Geo.kMetresPerDegLat
                    let lng = 106.0 + east / (Geo.kMetresPerDegLat * Geo.cosDeg(lat0))
                    let spd: Double? = r.chance(0.3) ? nil : truth.speedAt(ts) * r.dbl(0.9, 1.1)
                    lastFixAt = t
                    lastInfoAt = t
                    lastInfoKind = "fix"
                    input = .locationFix(LocationFix(atMs: t, fixAtMs: t - Int64(r.int(1_500)), lat: lat, lng: lng, accuracyM: acc,
                                                     speedMps: spd))
                } else if t == wake {
                    input = .tick(atMs: t)
                } else {
                    batteryAt = t
                    level = Swift.max(1, level - Swift.max(0, Int(drainPerH / 6.0 + r.dbl(-0.5, 0.5))))
                    lastInfoAt = t
                    let charging = r.chance(0.1)
                    lastInfoKind = "battery(charging=\(charging))"
                    input = .batterySample(atMs: t, levelPct: level, charging: charging)
                }
                var isTick = false
                if case .tick = input { isTick = true }
                var gapFromPrevWake = Int64.max
                if isTick && !awake {
                    // Wake-up Ticks while the CPU sleeps (Doze): gap to the previous one, and how many in any 9-minute window
                    // (Android allows one setExactAndAllowWhileIdle per ~9 min in Doze: RK17).
                    if let last = prevWakeTicks.last { gapFromPrevWake = t - last }
                    prevWakeTicks.append(t)
                    while prevWakeTicks[0] < t - 540_000 { prevWakeTicks.removeFirst() }
                    st.maxWakesIn9Min = Swift.max(st.maxWakesIn9Min, prevWakeTicks.count)
                    if gapFromPrevWake != .max { st.minWakeGapMs = Swift.min(st.minWakeGapMs, gapFromPrevWake) }
                }
                step = TripEngine.reduce(s0, input)
                label = { "\(input)" }
                if case let .locationFix(lf) = input {
                    // U116 (b) (round 3b): an OVERSHOOT / PASSED_CLOSEST that uses a minD from the GPS-gap chord must not come
                    // before the vehicle really passed the destination.
                    if let dc = GapProbe.of(s0, lf, step)?.dChord { chordMinD = dc }
                    let passEv = step.events.contains { e in
                        if case .overshoot = e { return true }
                        if case let .alarm(a) = e { return a.reason == .overshoot || a.reason == .passedClosest }
                        return false
                    }
                    if let cm = chordMinD, passEv, step.state.minD == cm {
                        st.gapTriggers += 1
                        let dTruth = truth.dAt(Double(t - S) / 1000.0)
                        st.gapLines.append("\(tripTag) t=\(kd(Double(t - S) / 1000.0)) truthD=\(KW.ki(dTruth)) chordMinD=\(kd(cm)) "
                                           + passKinds(step.events))
                        if dTruth > 0.0 { st.v("chord minD used before the destination was passed", st.gapLines.last!) }
                    }
                }
                switch input {
                case .locationFix, .batterySample: lastInfo = infoStep(t, s0, step)
                default: break
                }
                if !rang, let a = step.events.alarms.first {
                    rang = true
                    noteU126(st, seed, tripTag, config, truth, t, step)
                    if viaFb {
                        // Engine-first: a fallback planned after the last new information (pure dead reckoning since then)
                        // must never beat the engine's own wake-up alarm.
                        let emitted = s0.fallback.emittedAtMs ?? .min
                        let pv = prev.view.predictedAlarmAtMs
                        let detail = "\(tripTag) t=\(kd(Double(t - S) / 1000.0)) emitted=\(kd(Double(emitted &- S) / 1000.0)) "
                            + "engineP=\(optKd(pv)) engineWake=\(optKd(prev.view.wakeAtMs)) "
                            + "gps=\(prev.view.gps.jsonName) stopped=\(prev.state.stopStartMs != nil)"
                        // T10 "T10.5" (a) + "T10.5 vòng 2" (2): the engine believes it is stopped (GPS OK, stop in progress) with
                        // predicted − now <= Q: K1 forbids moving the fallback and the forecast slides with now. Not a violation
                        // while the fallback rings no later than predicted (previous Step) + (fallbackLagS + fallbackNearSlackS)
                        // + 1 s (T10.5 round 3 §11); split by the truth speed at the ring.
                        let believedStop = prev.view.gps == .ok && prev.state.stopStartMs != nil && pv != nil
                            && pv! - prev.state.nowMs <= TMath.ms(p.fallbackQuietBeforeS)
                        if emitted >= lastInfoAt && believedStop {
                            let v = truth.speedAt(Double(t - S) / 1000.0)
                            let moving = v >= p.stationarySpeedMps
                            let bound = pv! + TMath.ms(p.fallbackLagS + p.fallbackNearSlackS) + 1000
                            let line = "\(detail) truthSpeed=\(kd(v)) \(moving ? "moving" : "stopped") ring-P=\(kd(Double(t - pv!) / 1000.0)) s"
                            if t > bound {
                                st.v("believed-stop fallback later than predicted + fallbackLag + fallbackNearSlack + 1 s", line)
                            }
                            st.first("fallback (pure DR, engine believes stopped, <= Q to the boundary) \(a.reason.jsonName)")
                            if moving { st.believedStopMoving.append(line) } else { st.believedStopReal.append(line) }
                        } else if emitted >= lastInfoAt {
                            st.v("first alarm from OS fallback though planned on unchanged information", detail)
                            st.first("fallback (pure DR) \(a.reason.jsonName)")
                        } else {
                            st.first("fallback (new info after planning) \(a.reason.jsonName)")
                            let q = TMath.ms(p.fallbackQuietBeforeS)
                            // T10.5 U111: the last new information could rescue it (F − t >= minLead, predicted − t > Q,
                            // predicted >= F), so that Step must have moved the fallback later.
                            let f = fb!
                            if let li = lastInfo, li.fBefore == f, li.statusBefore != .failed, let lp = li.predicted,
                               f - li.t >= TMath.ms(p.fallbackMinLeadS), lp - li.t > q, lp >= f, !li.movedLater {
                                st.v("eligible for the urgent later shift but not rescued", "\(tripTag) t=\(kd(Double(t - S) / 1000.0))")
                            }
                            if let pp = prev.view.predictedAlarmAtMs { st.earlyS.append(Double(pp - t) / 1000.0) }
                            st.fbAfterInfo.append(
                                "\(tripTag) F=\(kd(Double(t - S) / 1000.0)) emitted=\(kd(Double(emitted &- S) / 1000.0)) lastInfo=\(lastInfoKind)@"
                                    + "\(kd(Double(lastInfoAt - S) / 1000.0)) F-tInfo=\(kd(Double(f - lastInfoAt) / 1000.0)) "
                                    + "engineP=\(optKd(prev.view.predictedAlarmAtMs)) "
                                    + "early=\(prev.view.predictedAlarmAtMs.map { kd(Double($0 - t) / 1000.0) } ?? "null") "
                                    + "engineWake=\(optKd(prev.view.wakeAtMs)) gps=\(prev.view.gps.jsonName) "
                                    + "stopped=\(prev.state.stopStartMs != nil)")
                        }
                    } else {
                        st.first((awake ? "awake " : "doze ") + (a.ringNow ? "engine " : "noRing ") + a.reason.jsonName)
                        if isTick && !awake {
                            st.dozeTickAlarms += 1
                            if gapFromPrevWake < 540_000 { st.dozeTickAlarmsWithin9Min += 1 }
                        }
                        if !a.ringNow { st.v("engine alarm without ringNow", tripTag) }
                    }
                    if mode == .distance {
                        // Truth at the first alarm: distance left vs threshold (positive = rang before reaching the threshold).
                        let thrD = Double(config.distanceThresholdM!)
                        let tS = Double(t - S) / 1000.0
                        st.lateVsTruth.append(truth.dAt(tS) - thrD)
                        if truth.dAt(tS) < thrD {
                            var lo = 0.0
                            var hi = tS
                            for _ in 0..<60 {
                                let m = (lo + hi) / 2
                                if truth.dAt(m) > thrD { lo = m } else { hi = m }
                            }
                            let cross = S + Int64(hi * 1000)
                            let lateS = Double(t - cross) / 1000.0
                            if lateS > 1_800.0 {
                                let dead = deadIntervals.contains { cross >= $0.0 && cross < $0.1 }
                                let before = states.last { $0.nowMs <= cross }
                                st.lateLines.append((lateS, LongLoss.lateCaseLine(
                                    tag: tripTag, hint: config.vehicleHint, lateS: lateS, first: st.lastFirstKey, dead: dead,
                                    crossMs: cross, thrM: thrD, st: before) { ms in truth.dAt(Double(ms - S) / 1000.0) }))
                            }
                            st.lateCases.append((Double(t - cross) / 1000.0,
                                                 "\(tripTag) late \(kd(Double(t - cross) / 1000.0)) s reason \(a.reason.jsonName) gapAtCross=\(inGap(cross)) "
                                                     + "dozeAt=\(Int(dozeAtS)) s cross=\((cross - S) / 1000) s everDead=\(everDead) "
                                                     + "fixesInDozeP=\(kd(withFixInDoze ? fixInDozeP : 0.0)) "
                                                     + "speedAtCross=\(kd(truth.speedAt(Double(cross - S) / 1000.0))) base=\(kd(truth.base))"))
                        }
                    }
                }
            }
            check(prev, step, label)
            // Platform: confirm the requested fallback alarm (ok with probability okP).
            if let fbEvent = step.events.fallbacks.last, let fbAt = fbEvent.fallbackAtMs, step.state.phase != .ended {
                let prev2 = step
                step = TripEngine.reduce(step.state, .fallbackScheduled(atMs: step.state.nowMs, fallbackAtMs: fbAt, ok: r.chance(okP)))
                check(prev2, step) { "FallbackScheduled" }
                if !step.events.alarms.isEmpty { st.v("FallbackScheduled at now produced an alarm", tripTag) }
            }
            // Nobody answers: alarms stop after alarmMaxActiveS (c6) and the trip ends MISSED.
        }
        if !rang { st.v("trip ended without any alarm", tripTag) }
        st.trips += 1
    }

    /// U126: true time of arrival (dAt <= 0), s from S; nil when not within 200 000 s.
    static func arrivalS(_ truth: Truth) -> Double? {
        if truth.dAt(200_000.0) > 0.0 { return nil }
        var lo = 0.0
        var hi = 200_000.0
        for _ in 0..<60 {
            let m = (lo + hi) / 2
            if truth.dAt(m) > 0.0 { lo = m } else { hi = m }
        }
        return hi
    }

    /// U126: the seeds of review T12.2 round 2.
    static let u126Seeds: Set<Int64> = [55, 433, 787]

    /// U126 (T10.6): statistics of the first alarm of a trip (`t` its time, `step` the Step that raised it).
    static func noteU126(_ st: FuzzStats, _ seed: Int64, _ tripTag: String, _ config: TripConfig, _ truth: Truth, _ t: Int64,
                         _ step: Step) {
        guard let a = step.events.alarms.first else { return }
        let ts = Double(t - S) / 1000.0
        let arr = arrivalS(truth)
        let info = a.reason == .gpsLost ? LongLoss.lostAlarmInfo(step.state) : nil
        if info?.longLostOnly == true {
            st.longLostAlarms += 1
            if let arr { st.longLostRemainingS.append(arr - ts) }
        }
        if u126Seeds.contains(seed) {
            var lateTxt = "-"
            if config.mode == .distance, let thrI = config.distanceThresholdM {
                let thr = Double(thrI)
                var lo = 0.0
                var hi = 200_000.0
                if truth.dAt(hi) <= thr {
                    for _ in 0..<60 {
                        let m = (lo + hi) / 2
                        if truth.dAt(m) > thr { lo = m } else { hi = m }
                    }
                    lateTxt = KW.jf(ts - hi, 0)
                }
            }
            let e = Estimator.estimate(step.state, now: step.state.nowMs)
            st.seedLines.append("\(tripTag) hint=\(config.vehicleHint.jsonName): \(a.reason.jsonName) at \(KW.ki(ts)) s; vs DISTANCE crossing "
                                + "\(lateTxt) s (+ late); true remaining \(arr.map { String(KW.ki($0 - ts)) } ?? "null") s; "
                                + "cvDr \(e.map { KW.jf($0.cvDr, 2) } ?? "null"); preV \(info?.preV ?? false); "
                                + "W alone \(info?.longLostOnly ?? false)")
        }
    }

    static func runDozeFuzz(_ name: String, _ seeds: ClosedRange<Int64>, _ variant: Variant, okP: Double, killP: Double,
                            battery: Bool, params: EngineParams = .defaults, write: Bool = true) throws -> FuzzStats {
        let st = FuzzStats()
        for seed in seeds { try dozeTrip(seed, variant, okP: okP, killP: killP, battery: battery, st, params: params) }
        if !write { return st }
        let late = st.lateVsTruth.sorted()
        let lateTxt = late.isEmpty ? "-" : "min \(Int(late[0])) m, p05 \(Int(late[late.count / 20])) m, median \(Int(late[late.count / 2])) m, "
            + "rang after passing the threshold: \(late.filter { $0 < 0 }.count)/\(late.count)"
        // Kotlin sortedByDescending (stable): ties keep insertion order.
        let lateSorted = st.lateCases.enumerated().sorted { $0.element.0 != $1.element.0 ? $0.element.0 > $1.element.0 : $0.offset < $1.offset }
        let early = st.earlyS.sorted()
        let fbNewInfo = st.firstBy.filter { $0.key.hasPrefix("fallback (new info after planning)") }.values.reduce(0, +)
        // T10.5 round 2: DISTANCE lateness vs truth (threshold crossing → first alarm) of the trips that rang after the threshold.
        let lateS = st.lateCases.map(\.0).sorted()
        func q(_ f: Double) -> Double { lateS[Swift.min(lateS.count - 1, Int(f * Double(lateS.count)))] }
        let lateSTxt = lateS.isEmpty ? "-" : "n \(lateS.count), p50 \(kd(q(0.5))) s, p90 \(kd(q(0.9))) s, max \(kd(lateS.last!)) s"
        let warn = st.believedStopMoving.count > 3 ? "WARNING: believed-stop moving > 3, report to the designer\n" : ""
        let earlyTxt = early.isEmpty ? "-" : "median \(kd(early[early.count / 2])) max \(kd(early.last!))"
        var text = "trips=\(st.trips) steps=\(st.steps) probes=\(st.probes) kills=\(st.kills) ties=\(st.ties)\n"
        text += "urgentLaterShifts=\(st.urgentShifts) fallbackNewInfoAfterPlanning=\(fbNewInfo) earlyVsPredictedS: \(earlyTxt)\n"
        text += "believedStopFallbackFirst: stopped=\(st.believedStopReal.count) moving=\(st.believedStopMoving.count)\n" + warn
        text += "chordMinDPassAlarms=\(st.gapTriggers)" + st.gapLines.map { "\n  \($0)" }.joined() + "\n"
        text += "DISTANCE late vs truth (crossing → first alarm, rang after the threshold): \(lateSTxt)\n"
        text += "firstAlarm=\(FuzzStats.map(st.firstBy))\nviolations=\(FuzzStats.map(st.violations))\nfirst=\(FuzzStats.map(st.firstViolation))\n"
        text += "minGapBetweenDozeWakeTicksMs=\(st.minWakeGapMs) maxDozeWakeTicksIn9Min=\(st.maxWakesIn9Min) "
            + "firstAlarmFromDozeTick=\(st.dozeTickAlarms) ofWhichWithin9MinOfPreviousWake=\(st.dozeTickAlarmsWithin9Min)\n"
        text += "DISTANCE truth at first alarm (d − thr): \(lateTxt)\n"
        text += lateSorted.prefix(25).map(\.element.1).joined(separator: "\n") + "\n"
        text += "fallback first after new information:\n" + st.fbAfterInfo.joined(separator: "\n") + "\n"
        text += "fallback first, engine believes stopped with <= Q to the boundary (not a violation within P + lag + 1 s):\n"
            + (st.believedStopReal + st.believedStopMoving).joined(separator: "\n") + "\n"
        Report.shared.write("unit/u111-doze-\(name).txt", text)
        return st
    }

    @Test("U111 a Doze fuzz (= T121): no fix in Doze, fallback always scheduled OK, no kill → engine always rings first (700 trips)")
    func dozeNoFixOk() throws {
        let st = try Self.runDozeFuzz("nofix-ok", 1...700, .noFix, okP: 1.0, killP: 0.0, battery: false)
        #expect(st.steps > 100_000, "too small: \(st.steps)")
        #expect(st.violations.isEmpty, "violations \(st.violations) first \(st.firstViolation)")
        #expect(!st.firstBy.keys.contains { $0.hasPrefix("fallback") }, "first alarms: \(st.firstBy)")
    }

    @Test("U111 b Doze fuzz (= T121): from trip start, random FallbackScheduled failures (15 %) and kills/restores (50 %) → invariants, liveness")
    func dozeFromStart() throws {
        let st = try Self.runDozeFuzz("fromstart", 1...700, .fromStart, okP: 0.85, killP: 0.5, battery: true)
        #expect(st.violations.isEmpty, "violations \(st.violations) first \(st.firstViolation)")
    }

    @Test("U111 c Doze fuzz (= T121): fixes at wake-ups, battery, FallbackScheduled failures, kills/restores → invariants, liveness, urgent later shift")
    func dozeWithFixes() throws {
        let st = try Self.runDozeFuzz("withfix", 1...700, .withFixes, okP: 0.85, killP: 0.4, battery: true)
        #expect(st.violations.isEmpty, "violations \(st.violations) first \(st.firstViolation)")
    }

    @Test("U111 d Doze fuzz (= T121): no fix in Doze with battery, FallbackScheduled failures, kills/restores (seeds 701–1400)")
    func dozeNoFixMixed() throws {
        let st = try Self.runDozeFuzz("nofix-mixed", 701...1400, .noFix, okP: 0.85, killP: 0.4, battery: true)
        #expect(st.violations.isEmpty, "violations \(st.violations) first \(st.firstViolation)")
    }

    /// Designer note #3 of the T12.1 report, fixed by T10.5 (urgent later shift, §4.10): before T10.5 the fix 29 s before F inside
    /// the quiet window (seed 26, DOZE_WITH_FIXES) left the OS fallback to ring first at 11 698.544 s while the engine predicted
    /// 13 685.193 s. Flipped: the fallback is moved later at that fix, so the first alarm no longer comes from the fallback.
    @Test("T131 seed 26 (= T121 note #3, flipped by T10.5): the fix 29 s before F moves the fallback later; first alarm not from the fallback")
    func seed26EarlyFallback() throws {
        let st = FuzzStats()
        try Self.dozeTrip(26, .withFixes, okP: 0.85, killP: 0.4, battery: true, st)
        #expect(st.violations.isEmpty, "\(st.violations)")
        #expect(st.firstBy.keys.allSatisfy { !$0.hasPrefix("fallback") }, "\(st.firstBy)")
        #expect(st.fbAfterInfo.isEmpty, "\(st.fbAfterInfo)")
        #expect(st.urgentShifts >= 1, "urgent later shifts \(st.urgentShifts)")
    }

    /// U126 (T10.6 (1)(2)(4), statistics): the four Doze fuzzes of U111 with T10.6 off and on (defaults). Gate: no violation and an
    /// alarm on every trip with T10.6 on (as U111). Written to u126-longloss.txt (byte-identical to Kotlin): DISTANCE lateness vs
    /// truth off → T10.6, each DISTANCE case late > 1 800 s classified dead / short / fast / ?, first alarms due to W alone and the
    /// true time left to the destination at them, the review seeds 55, 433 (withfix), 787 (nofix-mixed).
    @Test("U126 a Doze fuzz lateness off vs T10.6, long-loss alarms, late > 1800 s classes and the review seeds")
    func u126a() throws {
        let runs: [(String, ClosedRange<Int64>, Variant, Double, Double, Bool)] = [
            ("nofix-ok", 1...700, .noFix, 1.0, 0.0, false),
            ("fromstart", 1...700, .fromStart, 0.85, 0.5, true),
            ("withfix", 1...700, .withFixes, 0.85, 0.4, true),
            ("nofix-mixed", 701...1400, .noFix, 0.85, 0.4, true),
        ]
        var out = "# U126 (T10.6) Doze fuzz of U111: off (gpsLostLongS 0, passedClosestSlowRiseM 0; preV on) -> T10.6 (defaults)\n"
        var bad: [String] = []
        for (name, seeds, variant, okP, killP, battery) in runs {
            let off = try Self.runDozeFuzz(name, seeds, variant, okP: okP, killP: killP, battery: battery, params: LongLoss.offParams,
                                           write: false)
            let on = try Self.runDozeFuzz(name, seeds, variant, okP: okP, killP: killP, battery: battery, write: false)
            if !on.violations.isEmpty { bad.append("\(name): \(FuzzStats.map(on.violations)) \(FuzzStats.map(on.firstViolation))") }
            let lateOff = off.lateCases.map(\.0)
            let lateOn = on.lateCases.map(\.0)
            out += "\n## \(name)\n"
            out += "DISTANCE late vs truth (s, rang after the threshold): off \(LongLoss.quantiles(lateOff)) -> T10.6 "
                + "\(LongLoss.quantiles(lateOn))\n"
            out += "late > 1800 s: off \(lateOff.filter { $0 > 1_800.0 }.count) -> T10.6 \(lateOn.filter { $0 > 1_800.0 }.count)\n"
            // Kotlin sortedByDescending (stable): ties keep insertion order.
            let sortedLate = on.lateLines.enumerated().sorted { $0.element.0 != $1.element.0 ? $0.element.0 > $1.element.0 : $0.offset < $1.offset }
            for x in sortedLate { out += x.element.1 + "\n" }   // printed only, no gate (class ? → báo designer)
            out += "first alarms due to W alone: \(on.longLostAlarms); true time left at them (s): \(LongLoss.quantiles(on.longLostRemainingS)); "
                + "after arrival: \(on.longLostRemainingS.filter { $0 < 0.0 }.count)\n"
            out += "firstAlarm off \(FuzzStats.map(off.firstBy))\nfirstAlarm T10.6 \(FuzzStats.map(on.firstBy))\n"
            for l in off.seedLines { out += "seed off " + l + "\n" }
            for l in on.seedLines { out += "seed T10.6 " + l + "\n" }
        }
        Report.shared.write("unit/u126-longloss.txt", out)
        #expect(bad.isEmpty, "\(bad.joined(separator: "\n"))")
    }

    @Test("T131 kd = Kotlin Double.toString on the shapes used in the t121 files")
    func kdFormat() {
        #expect(Self.kd(61.0) == "61.0" && Self.kd(0.0) == "0.0" && Self.kd(5207.133922771423) == "5207.133922771423")
        #expect(Self.kd(0.001) == "0.001" && Self.kd(5.0e-4) == "5.0E-4" && Self.kd(1.0e7) == "1.0E7" && Self.kd(-1.25e-5) == "-1.25E-5")
        #expect(Self.kd(12_345_678.5) == "1.23456785E7" && Self.kd(9_999_999.0) == "9999999.0")
    }
}
