import Testing
@testable import Trip

/// Exact port of the Kotlin tester's `TesterT122OvershootTest` (T12.2 retest, T10.5 vòng 3–3f): adversarial cases for the
/// overshoot rule `(increasing && fast) || (not alarmed && minDChord && notCloser)` and the GPS-gap chord on minD. Same generator
/// (splitmix64 seeded `seed * golden + 0x1357911`), same draw order and builders, so every run is the Kotlin run and the
/// `<report>/unit/t122-o*.txt`, `u114-ae.txt`, `u114-af.txt` files are byte-identical to the Kotlin ones.
/// A "wrong-wording" alarm = OVERSHOOT or PASSED_CLOSEST while the vehicle has not reached its closest point yet (y < 0).
@Suite("TesterT132OvershootTests")
struct TesterT132OvershootTests {
    static let S = KW.S
    static let p = EngineParams.defaults

    struct Rng {
        private var x: UInt64
        init(_ seed: Int64) { x = UInt64(bitPattern: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x1357911 }

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
        mutating func chance(_ q: Double) -> Bool { dbl() < q }
    }

    /// Piecewise-constant along-route speed (m/s, negative = reversing); route = meridian of the destination shifted offsetM east.
    struct Path {
        let y0: Double
        let offsetM: Double
        var segs: [(Int64, Double)] = []

        init(_ y0: Double, _ offsetM: Double) {
            self.y0 = y0
            self.offsetM = offsetM
        }

        func yAt(_ t: Int64) -> Double {
            var y = y0
            for i in segs.indices {
                let (s0, v) = segs[i]
                if s0 >= t { break }
                let s1 = i + 1 < segs.count ? Swift.min(segs[i + 1].0, t) : t
                y += v * Double(s1 - s0) / 1000.0
            }
            return y
        }

        func vAt(_ t: Int64) -> Double { segs.last { $0.0 <= t }?.1 ?? 0.0 }

        func dAt(_ t: Int64) -> Double {
            let y = yAt(t)
            return (y * y + offsetM * offsetM).squareRoot()
        }
    }

    struct Outcome {
        let alarm: TripEvent.Alarm?
        let y: Double
        let d: Double
        let steps: Int
        let wrong: Bool
    }

    /// Drives a trip until the first alarm or `horizonMs`; `forcedIntervalMs` nil = the policy interval; `fix` builds the fix at t
    /// (nil = dropped). Wrong wording: OVERSHOOT/PASSED_CLOSEST while y < 0 at the alarm.
    static func drive(_ config: TripConfig, _ path: Path, _ horizonMs: Int64, _ forcedIntervalMs: Int64?,
                      _ fix: (Int64, Step) -> LocationFix?) throws -> Outcome {
        var step = try TripEngine.start(config: config, params: p, nowMs: S)
        var nextFix = S + 1_000
        var n = 0
        while step.events.alarms.isEmpty && step.state.nowMs < horizonMs {
            n += 1
            if n >= 200_000 { break }
            if let wake = step.view.wakeAtMs, wake < nextFix {
                step = TripEngine.reduce(step.state, .tick(atMs: wake))
            } else {
                let t = nextFix
                nextFix = t + (forcedIntervalMs ?? Int64(step.view.samplingPolicy?.intervalS ?? 5) * 1000)
                guard let f = fix(t, step) else { continue }
                step = TripEngine.reduce(step.state, .locationFix(f))
            }
        }
        let a = step.events.alarms.first
        let t = step.state.nowMs
        let wrong = a != nil && (a!.reason == .overshoot || a!.reason == .passedClosest) && path.yAt(t) < 0.0
        return Outcome(alarm: a, y: path.yAt(t), d: path.dAt(t), steps: n, wrong: wrong)
    }

    static func fixAt(_ t: Int64, _ y: Double, _ east: Double, _ acc: Double, _ spd: Double?) -> LocationFix {
        let pt = KW.jitter(KW.pointOnMeridian(-y), east, 0.0)
        return LocationFix(atMs: t, fixAtMs: t, lat: pt.lat, lng: pt.lng, accuracyM: acc, speedMps: spd)
    }

    static let modes: [(String, TripConfig)] = [
        ("D200", KW.cfg(.distance, thr: 200)), ("D500", KW.cfg(.distance, thr: 500)),
        ("D800", KW.cfg(.distance, thr: 800)), ("D1000", KW.cfg(.distance, thr: 1000)),
        ("D2000", KW.cfg(.distance, thr: 2000)), ("T5", KW.cfg(.time, thrMin: 5)),
        ("T15", KW.cfg(.time, thrMin: 15)), ("SMART", KW.cfg(.smart)),
    ]

    static func kd(_ x: Double) -> String { KW.kd(x) }
    static func ki(_ x: Double) -> Int { KW.ki(x) }
    static func reason(_ a: TripEvent.Alarm?) -> String { a?.reason.jsonName ?? "null" }
    static func iv(_ x: Int64?) -> String { x.map { String($0 / 1000) } ?? "policy" }

    static let pinnedO1 = 14              // = HEAD (T12.1), run-by-run (T12.2 round 8)
    static let pinnedO2 = 0
    static let pinnedO3 = 0
    static let pinnedO4 = "silentCrawl=8 wrongReverse=18"   // = HEAD (crawl: T10.6 known; reverse: PASSED_CLOSEST, RK10)
    static let pinnedO1C = 43             // T10.5 vòng 3f, RK20 c (2 304 runs)
    static let pinnedO1B = 0              // = HEAD
    static let pinnedO1Repro = "DISTANCE ringNow=true at d=480 m (y=-480)"   // = HEAD

    // MARK: - O1: stuck in traffic before the destination + outlier fix(es)

    static func jam(_ config: TripConfig, _ jamY: Double, _ crawl: Double, _ doppler: Bool, _ delta: Double, _ outliers: Int,
                    _ interval: Int64?, dropFirst: Bool = false) throws -> Outcome {
        var path = Path(-20_000.0, 0.0)
        let tJam = S + KW.kl((20_000.0 + jamY) / 12.0 * 1000.0)
        path.segs.append((S, 12.0))
        path.segs.append((tJam, crawl))
        path.segs.append((tJam + 1_200_000, 12.0))
        var r = Rng(KW.kl(jamY) &* 31 &+ KW.kl(delta))
        let outAt = tJam + 300_000
        var outLeft = outliers
        let path0 = path
        return try drive(config, path, S + 6 * 3_600_000, interval) { t, _ in
            let y = path0.yAt(t)
            let spd: Double? = doppler ? path0.vAt(t).magnitude : nil
            if t >= outAt && outLeft > 0 {
                outLeft -= 1
                // O1c (T10.5 vòng 3f): the first outlier never arrives (dropped by the platform) instead of being rejected.
                if dropFirst && outLeft == outliers - 1 { return nil }
                return fixAt(t, y + delta, r.dbl(-8.0, 8.0), 15.0, spd)
            }
            let yy = y + r.dbl(-8.0, 8.0)
            return fixAt(t, yy, r.dbl(-8.0, 8.0), 10.0, spd)
        }
    }

    @Test("T132 O1 (= T122 O1) stuck in traffic before the destination with an outlier fix: wrong-wording OVERSHOOT count = HEAD (14)")
    func o1() throws {
        var out = ""
        var wrong: [String] = []
        var runs = 0
        for (name, config) in Self.modes {
            for jamY in [-1_200.0, -1_500.0, -1_900.0, -2_500.0] {
                for crawl in [0.0, 0.3] { for doppler in [true, false] { for delta in [1_100.0, 1_500.0, 2_000.0] {
                    for outliers in [0, 1, 2] { for interval in [nil, 30_000, 180_000] as [Int64?] {
                        let o = try Self.jam(config, jamY, crawl, doppler, delta, outliers, interval)
                        runs += 1
                        let line = "\(name) jamY=\(Int(jamY)) crawl=\(Self.kd(crawl)) doppler=\(doppler) delta=\(Int(delta)) outliers=\(outliers) "
                            + "interval=\(Self.iv(interval)): \(Self.reason(o.alarm)) at y=\(Self.ki(o.y)) d=\(Self.ki(o.d))"
                        out += line + "\n"
                        if o.wrong { wrong.append(line) }
                    } }
                } } }
            }
        }
        Report.shared.write("unit/t122-o1-jam-outlier.txt", "runs=\(runs) wrongWording=\(wrong.count)\n\(wrong.joined(separator: "\n"))\n\nall:\n\(out)")
        // Without outliers the rule must never fire before the destination.
        #expect(!wrong.contains { $0.contains("outliers=0") }, "\(wrong.filter { $0.contains("outliers=0") }.prefix(5))")
        #expect(wrong.count == Self.pinnedO1)
    }

    /// O1c (T10.5 vòng 3f, RK20 c, recorded): the first outlier never arrives (not in `rejects`), the next one(s) are outliers.
    @Test("T132 O1c (= T122 O1c) first outlier dropped by the platform instead of rejected: wrong-wording count (RK20 c)")
    func o1c() throws {
        var out = ""
        var wrong: [String] = []
        var runs = 0
        for (name, config) in Self.modes {
            for jamY in [-1_200.0, -1_500.0, -1_900.0, -2_500.0] {
                for crawl in [0.0, 0.3] { for doppler in [true, false] { for delta in [1_100.0, 1_500.0, 2_000.0] {
                    for outliers in [2, 3] { for interval in [nil, 30_000, 180_000] as [Int64?] {
                        let o = try Self.jam(config, jamY, crawl, doppler, delta, outliers, interval, dropFirst: true)
                        runs += 1
                        let line = "\(name) jamY=\(Int(jamY)) crawl=\(Self.kd(crawl)) doppler=\(doppler) delta=\(Int(delta)) "
                            + "outliers=\(outliers)(first dropped) interval=\(Self.iv(interval)): \(Self.reason(o.alarm)) at y=\(Self.ki(o.y)) d=\(Self.ki(o.d))"
                        out += line + "\n"
                        if o.wrong { wrong.append(line) }
                    } }
                } } }
            }
        }
        Report.shared.write("unit/t122-o1c-dropped-outlier.txt", "runs=\(runs) wrongWording=\(wrong.count)\n\(wrong.joined(separator: "\n"))\n\nall:\n\(out)")
        #expect(wrong.count == Self.pinnedO1C)
    }

    /// O1b: stop-and-go traffic (60 s at `crawl`, 120 s stopped) for 40 min with the engine's own sampling policy; one outlier fix
    /// `delta` m closer 60 s into a stopped phase after `outlierAfterS` s of jam.
    static func stopAndGo(_ config: TripConfig, _ jamY: Double, _ crawl: Double, _ delta: Double, _ outlierAfterS: Int,
                          _ vApproach: Double) throws -> (Outcome, Int?) {
        let y0 = vApproach >= 5.0 ? -20_000.0 : jamY - 2_000.0
        var path = Path(y0, 0.0)
        let tJam = S + KW.kl((jamY - y0) / vApproach * 1000.0)
        path.segs.append((S, vApproach))
        var t = tJam
        while t < tJam + 2_400_000 {
            path.segs.append((t, crawl))
            path.segs.append((t + 60_000, 0.0))
            t += 180_000
        }
        path.segs.append((t, 12.0))
        var r = Rng(KW.kl(jamY) &+ KW.kl(delta) &+ Int64(outlierAfterS))
        let k = (Int64(outlierAfterS) * 1000) / 180_000
        let outAt = tJam + k * 180_000 + 120_000
        var done = false
        var intervalAtOutlier: Int? = nil
        let path0 = path
        let o = try drive(config, path, S + 6 * 3_600_000, nil) { at, st in
            let y = path0.yAt(at)
            let spd = path0.vAt(at).magnitude
            if !done && at >= outAt && path0.vAt(at) == 0.0 {
                done = true
                intervalAtOutlier = st.view.samplingPolicy?.intervalS
                return fixAt(at, y + delta, r.dbl(-8.0, 8.0), 15.0, spd)
            }
            let yy = y + r.dbl(-8.0, 8.0)
            return fixAt(at, yy, r.dbl(-8.0, 8.0), 10.0, spd)
        }
        return (o, intervalAtOutlier)
    }

    @Test("T132 O1b (= T122 O1b) stop-and-go traffic with the engine's own sampling policy and one outlier fix: 0 wrong wording")
    func o1b() throws {
        var out = ""
        var wrong: [String] = []
        var runs = 0
        for (name, config) in Self.modes {
            for jamY in [-1_200.0, -1_500.0, -1_900.0, -2_500.0] {
                for crawl in [1.2, 1.5, 2.5] { for delta in [1_100.0, 1_300.0, 1_500.0] { for after in [600, 1_200, 1_800] {
                    for vA in [12.0, 1.3] {
                        let (o, iv) = try Self.stopAndGo(config, jamY, crawl, delta, after, vA)
                        runs += 1
                        let line = "\(name) vApproach=\(Self.kd(vA)) jamY=\(Int(jamY)) crawl=\(Self.kd(crawl)) delta=\(Int(delta)) "
                            + "outlierAfter=\(after) s intervalAtOutlier=\(iv.map(String.init) ?? "null"): \(Self.reason(o.alarm)) "
                            + "at y=\(Self.ki(o.y)) d=\(Self.ki(o.d))"
                        out += line + "\n"
                        if o.wrong { wrong.append(line) }
                    }
                } } }
            }
        }
        Report.shared.write("unit/t122-o1b-stopgo.txt", "runs=\(runs) wrongWording=\(wrong.count)\n\(wrong.joined(separator: "\n"))\n\nall:\n\(out)")
        #expect(wrong.count == Self.pinnedO1B)
    }

    @Test("T132 O1 repro (= T122): stopped 1.9 km before the destination, one outlier fix at 800 m, fixes every 30 s → DISTANCE at 480 m")
    func o1Repro() throws {
        let o = try Self.jam(KW.cfg(.distance, thr: 500), -1_900.0, 0.0, true, 1_100.0, 1, 30_000)
        let got = "\(Self.reason(o.alarm)) ringNow=\(o.alarm.map { String($0.ringNow) } ?? "null") at d=\(Self.ki(o.d)) m (y=\(Self.ki(o.y)))"
        Report.shared.write("unit/t122-o1-repro.txt", got + "\n")
        #expect(got == Self.pinnedO1Repro)
    }

    // MARK: - O2: normal approach, GPS jitter, sparse fixes (fuzz)

    @Test("T132 O2 (= T122 O2) normal approach fuzz: jitter, sparse fixes, off-route destination, rare outliers; wrong wording only with outliers")
    func o2() throws {
        var out = ""
        var byCause: [String: Int] = [:]
        var firsts: [String: Int] = [:]
        var lateAfterPass: [Double] = []
        var runs = 0
        for seed in Int64(1)...3_000 {
            var r = Rng(seed)
            let (name, config) = Self.modes[r.int(Self.modes.count)]
            let v = r.dbl(2.0, 30.0)
            let offset = r.chance(0.4) ? 0.0 : r.dbl(50.0, 900.0)
            var path = Path(-r.dbl(5_000.0, 30_000.0), offset)
            path.segs.append((Self.S, v))
            let acc = r.dbl(5.0, 60.0)
            let noDoppler = r.chance(0.3)
            let forced = ([nil, nil, 30_000, 60_000, 180_000] as [Int64?])[r.int(5)]
            let drop = r.dbl(0.0, 0.5)
            let outlierP = r.chance(0.5) ? 0.0 : 0.02
            var outliers = 0
            let path0 = path
            let o = try Self.drive(config, path, Self.S + 8 * 3_600_000, forced) { t, _ in
                if r.chance(drop) { return nil }
                let y = path0.yAt(t)
                let spd: Double? = noDoppler ? nil : path0.vAt(t).magnitude * r.dbl(0.9, 1.1)
                if r.chance(outlierP) {
                    outliers += 1
                    let yy = y + r.dbl(-2_000.0, 2_000.0)
                    let ee = offset + r.dbl(-300.0, 300.0)
                    return Self.fixAt(t, yy, ee, r.dbl(10.0, 30.0), spd)
                }
                let yy = y + r.dbl(-acc, acc)
                let ee = offset + r.dbl(-acc, acc)
                return Self.fixAt(t, yy, ee, acc, spd)
            }
            runs += 1
            let k = Self.reason(o.alarm)
            firsts[k, default: 0] += 1
            if o.y > 0 { lateAfterPass.append(o.y / v) }
            if o.wrong {
                let cause = outliers > 0 ? "with outliers" : (forced != nil ? "sparse, no outlier" : "policy, no outlier")
                byCause[cause, default: 0] += 1
                out += "seed=\(seed) \(name) v=\(KW.jf(v, 1)) offset=\(Self.ki(offset)) acc=\(Self.ki(acc)) forced=\(forced.map(String.init) ?? "null") "
                    + "drop=\(KW.jf(drop, 2)) noDoppler=\(noDoppler) outliers=\(outliers): \(Self.reason(o.alarm)) at y=\(Self.ki(o.y)) d=\(Self.ki(o.d))\n"
            }
        }
        let l = lateAfterPass.sorted()
        let tail = l.isEmpty ? "" : ", p50 \(Self.ki(l[l.count / 2])), p90 \(Self.ki(l[(l.count * 9) / 10])), max \(Self.ki(l.last!))"
        Report.shared.write("unit/t122-o2-approach.txt", "runs=\(runs) firstAlarm=\(KW.kmap(firsts)) wrongWording=\(KW.kmap(byCause))\n"
                            + "rang after the closest point (s after it): n \(l.count)\(tail)\n\(out)")
        #expect(byCause.keys.allSatisfy { $0 == "with outliers" }, "wrong wording without an outlier: \(byCause)\n\(out)")
        #expect((byCause["with outliers"] ?? 0) == Self.pinnedO2)
    }

    // MARK: - O3: covered station before the destination, alternating sources

    @Test("T132 O3 (= T122 O3) stopped in a covered station before the destination, coordinates alternating between two sources")
    func o3() throws {
        var out = ""
        var wrong: [String] = []
        var runs = 0
        for (name, config) in Self.modes {
            for ds in [600.0, 900.0, 1_200.0, 1_500.0, 2_500.0] {
                for delta in [30.0, 300.0, 1_100.0, -1_100.0] { for acc in [20.0, 80.0] { for interval in [nil, 30_000] as [Int64?] {
                    var path = Path(-20_000.0, 0.0)
                    let tStop = Self.S + KW.kl((20_000.0 - ds) / 12.0 * 1000.0)
                    path.segs.append((Self.S, 12.0))
                    path.segs.append((tStop, 0.0))
                    path.segs.append((tStop + 900_000, 12.0))
                    var k = 0
                    let path0 = path
                    let o = try Self.drive(config, path, Self.S + 4 * 3_600_000, interval) { t, _ in
                        let y = path0.yAt(t)
                        let inStation = t >= tStop && t < tStop + 900_000
                        var alt = false
                        if inStation {
                            alt = k % 2 == 1
                            k += 1
                        }
                        return Self.fixAt(t, alt ? y + delta : y, 0.0, inStation ? acc : 8.0, inStation ? nil : 12.0)
                    }
                    runs += 1
                    let line = "\(name) ds=\(Int(ds)) delta=\(Int(delta)) acc=\(Int(acc)) interval=\(Self.iv(interval)): "
                        + "\(Self.reason(o.alarm)) at y=\(Self.ki(o.y)) d=\(Self.ki(o.d))"
                    out += line + "\n"
                    if o.wrong { wrong.append(line) }
                } } }
            }
        }
        Report.shared.write("unit/t122-o3-station.txt", "runs=\(runs) wrongWording=\(wrong.count)\n\(wrong.joined(separator: "\n"))\n\nall:\n\(out)")
        #expect(wrong.count == Self.pinnedO3)
    }

    // MARK: - O4: slow crawl away after the pass, vehicle reversing before it

    @Test("T132 O4 (= T122 O4) slow crawl away after an off-route pass and a vehicle reversing before the destination")
    func o4() throws {
        var out = ""
        var wrongReverse = 0
        var silentCrawl = 0
        for (name, config) in Self.modes {
            // (i) off-route destination 600 m from the road, slow pass then crawl away at 0.5–2.7 m/s for 2 h.
            for crawl in [0.5, 1.0, 2.0, 2.7] {
                var path = Path(-3_000.0, 600.0)
                path.segs.append((Self.S, crawl))
                var r = Rng(KW.kl(crawl) + 7)
                let path0 = path
                let o = try Self.drive(config, path, Self.S + 2 * 3_600_000, nil) { t, _ in
                    let yy = path0.yAt(t) + r.dbl(-8.0, 8.0)
                    let ee = 600.0 + r.dbl(-8.0, 8.0)
                    return Self.fixAt(t, yy, ee, 10.0, crawl)
                }
                if o.alarm == nil { silentCrawl += 1 }
                out += "crawl \(name) offset=600 v=\(Self.kd(crawl)): \(Self.reason(o.alarm)) at y=\(Self.ki(o.y)) d=\(Self.ki(o.d)) "
                    + "(\(Self.kd((o.y + 3_000.0) / crawl / 60.0)) min)\n"
            }
            // (ii) approach to R before the destination, reverse 1.5 km, then forward again to the destination.
            for rr in [700.0, 900.0, 1_500.0] {
                for vRev in [5.0, 12.0] {
                    var path = Path(-15_000.0, 0.0)
                    let t1 = Self.S + KW.kl((15_000.0 - rr) / 12.0 * 1000.0)
                    path.segs.append((Self.S, 12.0))
                    path.segs.append((t1, -vRev))
                    path.segs.append((t1 + KW.kl(1_500.0 / vRev * 1000.0), 12.0))
                    var r = Rng(KW.kl(rr) + KW.kl(vRev))
                    let path0 = path
                    let o = try Self.drive(config, path, Self.S + 3 * 3_600_000, nil) { t, _ in
                        let yy = path0.yAt(t) + r.dbl(-8.0, 8.0)
                        let ee = r.dbl(-8.0, 8.0)
                        return Self.fixAt(t, yy, ee, 10.0, path0.vAt(t).magnitude)
                    }
                    if o.wrong { wrongReverse += 1 }
                    out += "reverse \(name) R=\(Int(rr)) vRev=\(Self.kd(vRev)): \(Self.reason(o.alarm)) at y=\(Self.ki(o.y)) d=\(Self.ki(o.d))"
                        + "\(o.wrong ? "  <- wrong wording" : "")\n"
                }
            }
        }
        Report.shared.write("unit/t122-o4-crawl-reverse.txt", "silentCrawl=\(silentCrawl) wrongReverse=\(wrongReverse)\n\(out)")
        #expect("silentCrawl=\(silentCrawl) wrongReverse=\(wrongReverse)" == Self.pinnedO4)
    }

    // MARK: - U114 (ae), (af): the two minDChord branches (review vòng 7 #1)

    /// GPS LOST since n − gapS s, last fix L at `lSouth` m south / `east` m east, DISTANCE `thr`, DENSE, established 10 m/s.
    static func gapState(_ thr: Int, _ lSouth: Double, _ east: Double, gapS: Int = 1_761) -> EngineState {
        let n = S + 3_600_000
        let st = KW.trackingState(KW.cfg(.distance, thr: thr), now: n - 1_000, startedAt: n - 3_000_000, d: lSouth, ground: 10.0,
                                  closing: 10.0, gps: .lost, lastFixAt: n - Int64(gapS) * 1000, tier: .dense, maxTripS: 14_400)
        let p0 = KW.jitter(KW.pointOnMeridian(lSouth), east, 0.0)
        let l = FixRec(fixAtMs: n - Int64(gapS) * 1000, lat: p0.lat, lng: p0.lng, accM: 8.0, d: KW.distToDest(p0), groundSample: nil)
        return KW.withLast(st, l)
    }

    static func fixN(_ s: EngineState, _ at: Int64, _ south: Double, _ east: Double, _ spd: Double?) -> Step {
        TripEngine.reduce(s, .locationFix(fixAt(at, -south, east, 8.0, spd)))
    }

    /// U114 (ae): the chord fix sets the flag (minD ≈ 0, 3 100 m beyond); three fixes 600 m beyond are rejected as IMPLAUSIBLE and
    /// the third REANCHORs: minD = 600, flag false. The vehicle then crawls away at 2 m/s to 1 800 m and stands 2 min: no
    /// OVERSHOOT (T12.1 rule). Control without the jumps: the chord flag stays and the same crawl rings OVERSHOOT.
    @Test("U114 ae a REANCHOR below 1 km after a chord fix clears the flag, no OVERSHOOT on a slow crawl away and stop")
    func u114ae() throws {
        let n = Self.S + 3_600_000
        func run(_ jumps: Bool) -> ([Step], Step?) {
            var out: [Step] = []
            var s = Self.fixN(Self.gapState(200, 11_800.0 + 10.0 * 1_761.0, 0.0), n, -3_100.0, 0.0, 0.0)
            out.append(s)
            #expect(s.state.minDChord && s.state.minD! <= 1.0, "ae chord fix: flag \(s.state.minDChord) minD \(String(describing: s.state.minD))")
            var reanchor: Step? = nil
            var t = n
            var y = 3_100.0
            if jumps {
                for dt: Int64 in [5_000, 20_000, 35_000] {
                    s = Self.fixN(s.state, n + dt, -600.0, 0.0, 2.0)
                    out.append(s)
                }
                reanchor = s
                t = n + 35_000
                y = 600.0
            }
            // Crawl away north at 2 m/s every 5 s up to 1 800 m beyond, then stand 2 min (Doppler 0).
            while !out.contains(where: { !$0.events.alarms.isEmpty }) && t < n + 1_200_000 {
                t += 5_000
                let standing = y >= 1_800.0
                if !standing { y += 10.0 }
                s = Self.fixN(s.state, t, -y, 0.0, standing ? 0.0 : 2.0)
                out.append(s)
                if standing && t > n + 1_200_000 { break }
                if standing && out.filter({ $0.state.stopStartMs != nil }).count > 24 { break }
            }
            return (out, reanchor)
        }
        let (steps, re0) = run(true)
        let re = try #require(re0)
        #expect(!re.state.minDChord && (re.state.minD! - 600.0).magnitude <= 1.0, "ae REANCHOR: flag \(re.state.minDChord) minD \(String(describing: re.state.minD))")
        #expect(!steps.flatMap(\.events).alarms.contains { $0.reason == .overshoot }, "ae: OVERSHOOT after a REANCHOR")
        let reIdx = try #require(steps.firstIndex { $0.state == re.state && $0.events == re.events })
        #expect(steps[reIdx...].allSatisfy { !$0.state.minDChord }, "ae: flag set again after the REANCHOR")
        let (control, _) = run(false)
        let ca = control.flatMap(\.events).alarms.first
        #expect(ca?.reason == .overshoot, "ae control (chord flag kept)")
        Report.shared.write("unit/u114-ae.txt", "ae: reanchor minD=\(KW.kdOpt(re.state.minD)) flag=\(re.state.minDChord); first alarm "
                            + "\(Self.reason(steps.flatMap(\.events).alarms.first)); control \(Self.reason(ca))\n")
    }

    /// U114 (af): observed minD 900 m (no chord, flag false), GPS lost, then the chord passes at 950 m > minD: minD stays 900, the
    /// flag stays false; the vehicle stands: no OVERSHOOT. Control without the observed minD: the chord sets the flag, OVERSHOOT.
    @Test("U114 af a chord farther than the observed minD keeps the flag false, no OVERSHOOT when standing after the gap")
    func u114af() throws {
        let n = Self.S + 3_600_000
        func run(_ observed: Bool) -> [Step] {
            var st = Self.gapState(200, 29_410.0, 950.0)
            if observed {
                st.minD = 900.0
                st.minDChord = false
            }
            var out: [Step] = []
            var s = Self.fixN(st, n, -3_000.0, 950.0, 0.0)
            out.append(s)
            for i in 1...24 {
                if !s.events.alarms.isEmpty { break }
                s = Self.fixN(s.state, n + 5_000 * Int64(i), -3_000.0, 950.0, 0.0)
                out.append(s)
            }
            return out
        }
        let steps = run(true)
        let first = steps[0].state
        #expect(!first.minDChord && first.minD == 900.0, "af chord fix: flag \(first.minDChord) minD \(String(describing: first.minD))")
        #expect(steps.allSatisfy { !$0.state.minDChord }, "af: flag set")
        #expect(!steps.flatMap(\.events).alarms.contains { $0.reason == .overshoot }, "af: OVERSHOOT")
        let control = run(false)
        #expect(control[0].state.minDChord && (control[0].state.minD! - 950.0).magnitude <= 2.0, "af control chord \(String(describing: control[0].state.minD))")
        let ca = control.flatMap(\.events).alarms.first
        #expect(ca?.reason == .overshoot, "af control (flag set by the chord)")
        Report.shared.write("unit/u114-af.txt", "af: chord fix minD=\(KW.kdOpt(first.minD)) flag=\(first.minDChord); first alarm "
                            + "\(Self.reason(steps.flatMap(\.events).alarms.first)); control \(Self.reason(ca))\n")
    }
}
