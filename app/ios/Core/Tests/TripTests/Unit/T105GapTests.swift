import Foundation
import Testing
@testable import Trip

/// Java `Double.toHexString` (U113 cross-check file).
func javaHex(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x < 0 ? "-Infinity" : "Infinity" }
    let sign = x.sign == .minus ? "-" : ""
    if x == 0 { return sign + "0x0.0p0" }
    let bits = x.bitPattern
    let frac = bits & 0x000F_FFFF_FFFF_FFFF
    let expBits = Int((bits >> 52) & 0x7FF)
    var h = String(frac, radix: 16)
    h = String(repeating: "0", count: 13 - h.count) + h
    while h.count > 1 && h.hasSuffix("0") { h.removeLast() }
    if expBits == 0 { return sign + "0x0." + h + "p-1022" }
    return sign + "0x1." + h + "p" + String(expBits - 1023)
}

/// splitmix64 seeded directly (Kotlin `T105GapTest.Mix`).
struct Mix {
    private var x: UInt64
    init(_ seed: Int64) { x = UInt64(bitPattern: seed) }

    mutating func next() -> UInt64 {
        x &+= 0x9E37_79B9_7F4A_7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func dbl(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * (Double(next() >> 11) / 9_007_199_254_740_992.0) }
}

/// `u114-gap.txt` lines from every U114 test (parallel tests; written sorted by tag so the file is deterministic).
final class GapLog: @unchecked Sendable {
    static let shared = GapLog()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func add(_ tag: String, _ line: String) {
        lock.lock()
        lines[tag] = line
        let text = lines.keys.sorted().map { lines[$0]! }.joined()
        lock.unlock()
        Report.shared.write("unit/u114-gap.txt", text)
    }
}

/// T10.5 round 3 – 3f (T10 "T10.5 vòng 3" … "vòng 3f"; port of Kotlin `unit/T105GapTest.kt`): the destination passed inside a
/// GPS gap. The chord between the fix before the gap and the first fix after it lowers minD (no immediate alarm, 3b); the usual
/// overshoot rule, or the `notCloser` term (3c, 3d) gated by `minDChord` (3e), rings; no chord fix after an IMPLAUSIBLE reject
/// (3f). U113 `chordClosest`, U114 the engine on the tester's / reviewer's builders, U116 (a) and U117 on the fixtures.
/// U115 is in `TesterT132Tests`, U116 (b) in `TesterT131Tests` (U111), U114 (ae), (af) in `TesterT132OvershootTests`.
@Suite("T105GapTests")
struct T105GapTests {
    static let S = KW.S
    static let n = KW.S + 3_600_000
    typealias LatLng = KW.LatLng

    /// Point `south` m south (negative = north) and `east` m east of the destination.
    static func pt(_ south: Double, _ east: Double = 0.0) -> LatLng {
        let p0 = KW.pointOnMeridian(south)
        return east == 0.0 ? p0 : KW.jitter(p0, east, 0.0)
    }

    static func rec(_ p: LatLng, _ at: Int64 = T105GapTests.n) -> FixRec { KW.rec(p, at: at) }

    static func kd(_ x: Double) -> String { KW.kd(x) }

    // MARK: - U113

    @Test("U113 chordClosest distance from the destination to the GPS-gap chord, only inside the segment (hex file for Kotlin)")
    func u113() throws {
        let c = KW.cfg()
        let n = Self.n
        // (g), (h) round 4: a vertical chord 1 500 m east ending at the foot of the perpendicular gives u == 1.0 exactly → excluded;
        // ending 0.1 mm past it gives u just below 1 → included.
        let east = 1_500.0 / KW.K   // cosDeg(0) == 1
        let lV = FixRec(fixAtMs: n, lat: -0.045, lng: KW.destLng + east, accM: 8.0, d: 1.0, groundSample: nil)
        let fFoot = FixRec(fixAtMs: n, lat: 0.0, lng: KW.destLng + east, accM: 8.0, d: 1.0, groundSample: nil)
        let fPast = FixRec(fixAtMs: n, lat: 1e-9, lng: KW.destLng + east, accM: 8.0, d: 1.0, groundSample: nil)
        let cases: [(String, FixRec, FixRec)] = [
            ("a", Self.rec(Self.pt(29_410.0)), Self.rec(Self.pt(-3_100.0))),
            ("b", Self.rec(Self.pt(5_000.0)), Self.rec(Self.pt(1_000.0))),
            ("c", Self.rec(Self.pt(3_000.0)), Self.rec(Self.pt(3_000.0))),
            ("d", Self.rec(Self.pt(5_000.0, 1_500.0)), Self.rec(Self.pt(-5_000.0, 1_500.0))),
            ("e", Self.rec(Self.pt(5_000.0, 200.0)), Self.rec(Self.pt(-5_000.0))),
            ("f", Self.rec(Self.pt(5_000.0)), FixRec(fixAtMs: n, lat: 0.01, lng: KW.destLng + 181.0, accM: 8.0, d: 1.0, groundSample: nil)),
            ("g", lV, fFoot),
            ("h", lV, fPast),
        ]
        var got: [String: Double?] = [:]
        var u: [String: Double?] = [:]
        for (k, l, f) in cases {
            got.updateValue(OvershootDetector.chordClosest(l, f, c), forKey: k)   // keeps nil values (subscript = nil removes)
            u.updateValue(OvershootDetector.chordProjection(l.lat, l.lng, f.lat, f.lng, c)?.u, forKey: k)
        }
        #expect(try #require(got["a"]!) <= 1.0, "a \(String(describing: got["a"]))")
        #expect(got["b"]! == nil, "b (u >= 1)")
        #expect(try #require(u["b"]!) >= 1.0)
        #expect(got["c"]! == nil, "c (len2 = 0)")
        #expect((try #require(got["d"]!) - 1_500.0).magnitude <= 1.0)
        #expect((try #require(got["e"]!) - 100.0).magnitude <= 1.0)
        #expect(got["f"]! == nil, "f (|Δlng| > 180)")
        #expect(u["g"]! == 1.0, "g u")
        #expect(got["g"]! == nil, "g (u == 1 excluded)")
        let uh = try #require(u["h"]!)
        #expect(uh < 1.0 && uh > 0.999999, "h u \(uh)")
        #expect((try #require(got["h"]!) - 1_500.0).magnitude <= 1.0)
        // Exact values for the Kotlin cross-check (same arithmetic and order, no FMA; u and the distance in hex).
        func hex(_ x: Double?) -> String { x.map { javaHex($0) + " " + Self.kd($0) } ?? "null" }
        Report.shared.write("unit/u113-chord.txt", cases.map { "\($0.0) u=\(hex(u[$0.0]!)) dChord=\(hex(got[$0.0]!))" }.joined(separator: "\n") + "\n")
    }

    @Test("U113 (support) javaHex = Java Double.toHexString")
    func javaHexFormat() {
        #expect(javaHex(1.0) == "0x1.0p0" && javaHex(0.0) == "0x0.0p0" && javaHex(-0.0) == "-0x0.0p0" && javaHex(1.25) == "0x1.4p0")
        #expect(javaHex(0.5) == "0x1.0p-1" && javaHex(1500.0004619388117) == "0x1.770007918305bp10")
        #expect(javaHex(Double.leastNonzeroMagnitude) == "0x0.0000000000001p-1022")
    }

    // MARK: - U114 (T10.5 round 3b) builders

    /// The tester's repro builder (TesterT122Test `T122 b repro`): GPS lost since n − gapS s, DR still 11.8 km out at 10 m/s.
    static func reproState(_ config: TripConfig = KW.cfg(.distance, thr: 1000), east: Double = 0.0, gapS: Int = 1_761) -> EngineState {
        let dr = 11_800.0 + 10.0 * Double(gapS)
        let st = KW.trackingState(config, now: n - 1_000, startedAt: n - 3_000_000, d: dr, ground: 10.0, closing: 10.0, gps: .lost,
                                  lastFixAt: n - Int64(gapS) * 1000, tier: .dense, maxTripS: 14_400,
                                  fallback: FallbackState(targetAtMs: n + 29_000, emittedAtMs: n - 600_000, status: .confirmed,
                                                          confirmedAtMs: n - 599_000, resync: false, near: true))
        if east == 0.0 { return st }
        return KW.withLast(st, Self.rec(Self.pt(dr, east), n - Int64(gapS) * 1000))
    }

    static func fix(_ st: EngineState, _ south: Double, east: Double = 0.0, at: Int64 = T105GapTests.n, spd: Double? = 18.0) -> Step {
        let p = pt(south, east)
        return TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: 8.0, speedMps: spd)))
    }

    /// One fix of a sequence: time, metres south (negative = north), metres east, Doppler speed.
    struct Fx {
        let at: Int64
        let south: Double
        let east: Double
        let spd: Double?
    }

    /// Feeds `fixes` from `st` until the first Alarm (inclusive); returns every Step.
    static func drive(_ st: EngineState, _ fixes: [Fx]) -> [Step] {
        var out: [Step] = []
        var s = st
        for f in fixes {
            let step = fix(s, f.south, east: f.east, at: f.at, spd: f.spd)
            out.append(step)
            s = step.state
            if !step.events.alarms.isEmpty { break }
        }
        return out
    }

    /// Fixes every 5 s from n, moving away north from `past` m beyond the destination at `v` m/s (0 = standing).
    static func away(_ past: Double, _ v: Double, count: Int = 40, east: Double = 0.0, firstSpd: Double?? = nil) -> [Fx] {
        (0..<count).map { i in
            Fx(at: n + 5_000 * Int64(i), south: -(past + v * 5.0 * Double(i)), east: east, spd: i == 0 ? (firstSpd ?? v) : v)
        }
    }

    static func firstAlarm(_ steps: [Step]) -> (Int64, TripEvent.Alarm)? {
        for s in steps { if let a = s.events.alarms.first { return (s.state.nowMs, a) } }
        return nil
    }

    static func note(_ tag: String, _ steps: [Step]) {
        let a = firstAlarm(steps)
        let o = KW.overshoots(steps.flatMap(\.events)).first
        GapLog.shared.add(tag, "\(tag): first alarm \(a?.1.reason.jsonName ?? "null") at n+\(a.map { kd(Double($0.0 - n) / 1000.0) } ?? "null") s "
                          + "pastM=\(o.map { String($0.pastM) } ?? "null") minD after first fix=\(KW.kdOpt(steps.first?.state.minD))\n")
    }

    static func assertAlarm(_ steps: [Step], _ reason: AlarmReason, _ atMs: Int64, _ tag: String,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        note(tag, steps)
        guard let fa = firstAlarm(steps) else {
            Issue.record(Comment(rawValue: "\(tag): no alarm"), sourceLocation: sourceLocation)
            return
        }
        let (t, a) = fa
        #expect(a.reason == reason, "\(tag)", sourceLocation: sourceLocation)
        #expect(a.ringNow, "\(tag)", sourceLocation: sourceLocation)
        #expect(t == atMs, "\(tag): alarm at n+\(Double(t - n) / 1000.0) s", sourceLocation: sourceLocation)
    }

    // MARK: - U114 (a)–(m)

    @Test("U114 a a2 a3 b passed the destination in a GPS gap, OVERSHOOT once moving away is confirmed or the vehicle stands")
    func u114a() throws {
        let n = Self.n
        // (a) 3 100 m beyond, moving away at 18 m/s: no alarm at the first fix, minD from the chord; OVERSHOOT at the 3rd fix.
        let a = Self.drive(Self.reproState(), Self.away(3_100.0, 18.0))
        let a0 = try #require(a.first)
        #expect(a0.events.alarms.isEmpty, "a first fix \(a0.events)")
        #expect(KW.hasRecovered(a0))
        #expect(try #require(a0.state.minD) <= 1.0)
        #expect(a0.state.stopStartMs == nil)
        Self.assertAlarm(a, .overshoot, n + 10_000, "a")
        let oa = KW.overshoots(a.last!.events)
        #expect(oa.count == 1 && oa.first?.pastM == 3_190, "a pastM \(oa)")
        #expect(a.last!.state.phase == .overshot)
        // (a2) standing after the gap: first fix UNKNOWN (Δt 1 761 s > maxSpeedSampleGapS 900), the stationary one after it stands.
        Self.assertAlarm(Self.drive(Self.reproState(), Self.away(3_100.0, 0.0, firstSpd: 0.0)), .overshoot, n + 5_000, "a2")
        // (a3) as (a2) with a 600 s gap: the first fix (Doppler 0) is STATIONARY already.
        Self.assertAlarm(Self.drive(Self.reproState(gapS: 600), Self.away(3_100.0, 0.0, firstSpd: 0.0)), .overshoot, n, "a3")
        // (b) 2 000 m beyond, moving away.
        Self.assertAlarm(Self.drive(Self.reproState(), Self.away(2_000.0, 18.0)), .overshoot, n + 10_000, "b")
    }

    @Test("U114 c d e 300 m beyond rings DISTANCE, TIME and SMART their mode reason, off-route PASSED_CLOSEST once moving away")
    func u114cde() throws {
        let n = Self.n
        Self.assertAlarm(Self.drive(Self.reproState(), Self.away(300.0, 18.0)), .distance, n, "c")
        Self.assertAlarm(Self.drive(Self.reproState(KW.cfg(.time, thrMin: 15)), Self.away(3_100.0, 18.0)), .time, n, "d TIME 15")
        Self.assertAlarm(Self.drive(Self.reproState(KW.cfg(.smart)), Self.away(3_100.0, 18.0)), .smartTime, n, "d SMART")
        // (e) the route passes 1 500 m east of the destination.
        let e = Self.drive(Self.reproState(east: 1_500.0), Self.away(4_000.0, 18.0, east: 1_500.0))
        #expect((try #require(e.first?.state.minD) - 1_500.0).magnitude <= 1.0)
        Self.assertAlarm(e, .passedClosest, n + 20_000, "e")
        #expect(KW.overshoots(e.flatMap(\.events)).isEmpty, "e")
    }

    @Test("U114 f g h no gap, already alarmed, not yet passed")
    func u114fgh() throws {
        let n = Self.n
        // (f) not a gap (GPS OK, previous fix 30 s ago at 600 m): the usual rule, no interpolation through 0.
        let f0 = KW.trackingState(KW.cfg(.distance, thr: 1000), now: n - 30_000, d: 600.0, ground: 18.0, closing: 18.0, lastFixAt: n - 30_000)
        let f = Self.fix(f0, -300.0)
        #expect(try #require(f.state.minD) >= 299.0)
        #expect(f.events.alarms.map(\.reason) == [.distance], "f")
        // (g) already alarmed (GPS_LOST while lost): no new Alarm, minD not lowered by the chord.
        var g0 = Self.reproState()
        g0.phase = .alarming
        g0.alarm = .empty
        g0.alarm.atMs = n - 60_000
        g0.alarm.reason = .gpsLost
        g0.alarm.source = .engine
        g0.alarm.lastRingAtMs = n - 60_000
        g0.alarm.ringing = true
        g0.fallback = .cleared
        let g = Self.fix(g0, -3_100.0)
        #expect(g.events.alarms.isEmpty, "g \(g.events)")
        #expect(try #require(g.state.minD) >= 3_000.0)
        // (h) not yet passed: 5 000 m on the same side (seed 26 pattern): no alarm, the urgent later shift as U109.
        let h = Self.fix(Self.reproState(), 5_000.0, spd: 0.8)
        #expect(h.events.alarms.isEmpty, "h \(h.events)")
        #expect(h.events.fallbacks.count == 1)
        let fac = try #require(h.events.fallbacks.first)
        #expect(fac.cause == .eta)
        #expect(try #require(fac.fallbackAtMs) > n + 29_000)
    }

    /// The reviewer's bypass base (RvRk20Test): fix before the gap 20 km south, 700 s gap, near fallback at n + 400 s.
    static func bypassState() -> EngineState {
        let lp = pt(20_000.0)
        let ld = KW.distToDest(lp)
        let base = KW.trackingState(KW.cfg(.distance, thr: 1000), now: n - 1_000, startedAt: n - 3_000_000, d: ld, ground: 10.0,
                                    closing: 10.0, gps: .lost, lastFixAt: n - 700_000, tier: .dense, maxTripS: 14_400,
                                    fallback: FallbackState(targetAtMs: n + 400_000, emittedAtMs: n - 600_000, status: .confirmed,
                                                            confirmedAtMs: n - 599_000, resync: false, near: false))
        let l = FixRec(fixAtMs: n - 700_000, lat: lp.lat, lng: lp.lng, accM: 8.0, d: ld, groundSample: nil)
        return KW.withLast(base, l)
    }

    /// U114 (i): the reviewer's RK20 case: first fix 2 km north and 0.5 km east (the chord passes 0.4 km from the destination),
    /// then the vehicle keeps APPROACHING at 10 m/s. Round 3b: no OVERSHOOT, DISTANCE when dSmooth <= 1 000.
    @Test("U114 i bypass entering from the far side is not an overshoot, DISTANCE rings at 1 km")
    func u114i() throws {
        let n = Self.n
        let d0 = (2_000.0 * 2_000.0 + 500.0 * 500.0).squareRoot()
        let fixes = (0..<200).map { i -> Fx in
            let r = TMath.max(0.0, 1.0 - 10.0 * 5.0 * Double(i) / d0)
            return Fx(at: n + 5_000 * Int64(i), south: -2_000.0 * r, east: 500.0 * r, spd: i == 0 ? 30.0 : 10.0)
        }
        let steps = Self.drive(Self.bypassState(), fixes)
        Self.note("i", steps)
        #expect(KW.overshoots(steps.flatMap(\.events)).isEmpty, "i: no Overshoot")
        let (t, a) = try #require(Self.firstAlarm(steps))
        #expect(a.reason == .distance, "i")
        let atAlarm = try #require(steps.last?.state.dSmooth)
        #expect(atAlarm <= 1_000.0 && atAlarm > 900.0, "i: DISTANCE at dSmooth \(atAlarm) (n+\(Double(t - n) / 1000.0) s)")
    }

    /// U114 (j) (RK20 b): passed in the gap, first fix 3 100 m beyond, then creeping away at 2 m/s → OVERSHOOT at the 3rd fix.
    @Test("U114 j creeping away after the gap rings OVERSHOOT at the 3rd fix (round 3c)")
    func u114j() throws {
        let n = Self.n
        let creep = (0..<120).map { i in Fx(at: n + 5_000 * Int64(i), south: -(3_100.0 + 2.0 * 5.0 * Double(i)), east: 0.0, spd: 2.0) }
        let endS = 3_100.0 + 2.0 * 5.0 * 119.0
        let stand = (1...10).map { i in Fx(at: n + 5_000 * Int64(119 + i), south: -endS, east: 0.0, spd: 0.0) }
        let steps = Self.drive(Self.reproState(), creep + stand)
        Self.note("j", steps)
        let (t, a) = try #require(Self.firstAlarm(steps))
        #expect(a.reason == .overshoot, "j")
        #expect(t == n + 10_000, "j: 3rd fix")
    }

    /// U114 (k): GPS still OK — no Tick during the gap; only `Δt ≥ lostAfterS` makes the fix after it a gap fix.
    @Test("U114 k gps still OK with no Tick during the gap, moving away rings OVERSHOOT (time term of gapFix)")
    func u114k() throws {
        var st = Self.reproState()
        st.gps = .ok
        st.gpsLostAtMs = nil
        st.nowMs = Self.n - 1_761_000
        #expect(GpsMonitor.lostAfterS(st) == 60)
        let steps = Self.drive(st, Self.away(3_100.0, 18.0))
        #expect(!KW.hasRecovered(steps[0]), "k: no GpsRecovered (gps was OK)")
        #expect(try #require(steps[0].state.minD) <= 1.0)
        Self.assertAlarm(steps, .overshoot, Self.n + 10_000, "k")
    }

    /// U114 (l): LOST because location services were turned off, fixes closer than lostAfterS (SPARSE 540 s, Δt 300 s).
    @Test("U114 l gps LOST from location services off with fixes less than lostAfterS apart still lowers minD by the chord")
    func u114l() throws {
        let n = Self.n
        let st = KW.trackingState(KW.cfg(.distance, thr: 1000), now: n - 300_000, startedAt: n - 3_000_000, d: 7_000.0, ground: 5.0,
                                  closing: 5.0, lastFixAt: n - 300_000, tier: .sparse, maxTripS: 14_400)
        #expect(GpsMonitor.lostAfterS(st) == 540)
        let off = TripEngine.reduce(st, .locationAvailability(atMs: n - 290_000, cause: .servicesOff))
        #expect(off.state.gps == .lost)
        #expect(off.events.alarms.isEmpty, "l: no GPS_LOST alarm yet (DR etaS > 1 200) \(off.events)")
        let steps = Self.drive(off.state, Self.away(2_000.0, 30.0))
        #expect(KW.hasRecovered(steps[0]), "l GpsRecovered")
        #expect(try #require(steps[0].state.minD) <= 1.0)
        Self.assertAlarm(steps, .overshoot, n + 10_000, "l")
    }

    /// U114 (m): a stop in progress at the fix before the gap ends at the chord fix (stopStartMs/stopAnchor cleared).
    @Test("U114 m a stop from before the gap does not count as standing at the first fix after it")
    func u114m() throws {
        let l = try #require(Self.reproState().last)
        var st = Self.reproState()
        st.stopStartMs = l.fixAtMs - 60_000
        st.stopAnchor = l
        let steps = Self.drive(st, Self.away(3_100.0, 18.0))
        #expect(steps[0].events.alarms.isEmpty, "m first fix \(steps[0].events)")
        #expect(steps[0].state.stopStartMs == nil, "m stop cleared")
        Self.assertAlarm(steps, .overshoot, Self.n + 10_000, "m")
    }

    // MARK: - U114 (n)–(x) (T10.5 round 3c / 3d)

    struct ParkResult {
        let atMs: Int64?
        let reason: AlarmReason?
        let fixNo: Int
        let minD: Double?
    }

    /// The reviewer's RvParkTest runner: repro builder with a `gapS` gap, then a fix every 5 s from n at pos(k) = (south, east),
    /// accuracy `acc`, Doppler `spd`; the OS fallback fires when due. Until the first Alarm or `maxS`.
    static func park(_ gapS: Int, _ acc: Double, _ spd: Double?, maxS: Int = 4 * 3600, config: TripConfig = KW.cfg(.distance, thr: 1000),
                     _ pos: (Int) -> (Double, Double)) -> ParkResult {
        var st = reproState(config, gapS: gapS)
        var s: Step? = nil
        var k = 0
        var t = 0
        while t < maxS {
            let at = n + Int64(t) * 1000
            if let s0 = s, let f = s0.view.fallbackAtMs, f <= at {
                s = TripEngine.reduce(st, .fallbackFired(atMs: f, firedAtMs: f))
            } else {
                let (south, east) = pos(k)
                let p = pt(south, east)
                s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: acc, speedMps: spd)))
                k += 1
                t += 5
            }
            st = s!.state
            if let a = s!.events.alarms.first { return ParkResult(atMs: a.atMs, reason: a.reason, fixNo: k, minD: st.minD) }
            if st.phase == .ended { break }
        }
        return ParkResult(atMs: nil, reason: nil, fixNo: k, minD: st.minD)
    }

    static func assertPark(_ r: ParkResult, _ fixNo: Int, _ tag: String, sourceLocation: SourceLocation = #_sourceLocation) {
        GapLog.shared.add(tag, "\(tag): first alarm \(r.reason?.jsonName ?? "null") at n+\(r.atMs.map { kd(Double($0 - n) / 1000.0) } ?? "null") s "
                          + "(fix #\(r.fixNo)) minD=\(KW.kdOpt(r.minD))\n")
        #expect(r.reason == .overshoot, "\(tag)", sourceLocation: sourceLocation)
        #expect(r.fixNo == fixNo, "\(tag) fix number", sourceLocation: sourceLocation)
        #expect(r.atMs == n + 5_000 * Int64(fixNo - 1), "\(tag)", sourceLocation: sourceLocation)
    }

    /// U114 (n): the "not yet alarmed" gate. ALARMING, the alarm already stopped ringing, minD 300, the vehicle stands 1 400 m
    /// beyond: no re-ring from the `notCloser` term; the trip ends MISSED after alarmMaxActiveS as before.
    @Test("U114 n after an alarm stopped ringing a parked vehicle does not re-ring by notCloser, the trip ends after alarmMaxActiveS")
    func u114n() {
        let n = Self.n
        let p = Self.pt(-1_400.0)
        let f0 = FixRec(fixAtMs: n, lat: p.lat, lng: p.lng, accM: 8.0, d: 1_400.0, groundSample: nil)
        var st = KW.trackingState(KW.cfg(.distance, thr: 1000), now: n, d: 1_400.0, lastFixAt: n, minD: 300.0)
        st.last = f0
        st.recent = [f0]
        st.dSmooth = 1_400.0
        st.last3 = [1_400.0, 1_400.0]
        st.phase = .alarming
        st.alarm = .empty
        st.alarm.atMs = n - 60_000
        st.alarm.reason = .distance
        st.alarm.source = .engine
        st.alarm.lastRingAtMs = n - 60_000
        st.alarm.ringing = false
        st.fallback = .cleared
        var events: [TripEvent] = []
        for i in 1...120 {
            let at = n + Int64(i) * 5_000
            let s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: 8.0, speedMps: 0.0)))
            events += s.events
            st = s.state
        }
        #expect(events.alarms.isEmpty && KW.overshoots(events).isEmpty, "n: \(events)")
        let end = TripEngine.reduce(st, .tick(atMs: n - 60_000 + TMath.ms(st.params.alarmMaxActiveS)))
        let te = end.events.compactMap(\.asEnded)
        #expect(te.count == 1 && te.first?.endReason == .alarmUnanswered)
    }

    /// The reviewer's RvStandTest runner (no GPS gap): passing an off-route destination slowly, then standing `stopNorth` north.
    /// T10.6: `params` (default: the T10 §5 defaults).
    static func stand(_ config: TripConfig, _ east: Double, _ v: Double, stopNorth: Double = 1_600.0,
                      params: EngineParams = .defaults) -> (Int, Step)? {
        let p0 = KW.jitter(KW.pointOnMeridian(3_000.0), east, 0.0)
        let d0 = KW.distToDest(p0)
        let l = FixRec(fixAtMs: S, lat: p0.lat, lng: p0.lng, accM: 8.0, d: d0, groundSample: nil)
        let base = KW.trackingState(config, p: params, now: S, d: d0, ground: v, closing: v * 0.95, lastFixAt: S)
        var st = KW.withLast(base, l, dStartPlus: 5_000.0)
        var y = 3_000.0
        var t = 0
        while t < 7_200 {
            t += 5
            let moving = y > -stopNorth
            if moving { y -= v * 5.0 }
            let p = KW.jitter(KW.pointOnMeridian(y), east, 0.0)
            let at = S + Int64(t) * 1000
            let s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: 8.0,
                                                                   speedMps: moving ? v : 0.0)))
            st = s.state
            #expect(!st.minDChord, "no GPS gap: minDChord stays false")
            if !s.events.alarms.isEmpty { return (t, s) }
        }
        return nil
    }

    /// U123 (a): measured (Kotlin T12.3), within ± 5 s of the designer's hand values 1 720 / 2 210 / 2 210 s.
    static let u123O = 1720
    static let u123P = 2210
    static let u123P2 = 2210

    /// U123 (a) (T10.6 (3), flipped from U114 o, p, p2): a slow pass (< 10 km/h) of an off-route destination without a GPS gap
    /// rings PASSED_CLOSEST from the slow-vehicle net (designer by hand: o 1 720 s, p 2 210 s, p2 2 210 s, ± 5 s), never OVERSHOOT.
    /// U123 (b): passedClosestSlowRiseM = 0 is the T12.2 rule (silent for 2 h).
    @Test("U123 a b a slow pass of an off-route destination rings PASSED_CLOSEST from the slow-vehicle net, off is silent (U114 o p p2)")
    func u123ab() {
        func check(_ tag: String, _ r: (Int, Step)?, _ hand: Int, _ pinned: Int) {
            guard let r else { Issue.record("\(tag): silent"); return }
            let a = r.1.events.alarms
            #expect(a.count == 1 && a.first?.reason == .passedClosest && a.first?.ringNow == true, "\(tag): \(a)")
            #expect(KW.overshoots(r.1.events).isEmpty, "\(tag): Overshoot")
            #expect((r.0 - hand).magnitude <= 5, "\(tag): at \(r.0) s, hand \(hand) s")
            #expect(r.0 == pinned, "\(tag): pinned (Kotlin T12.3)")
        }
        // (o) TIME 5, 2.5 m/s, destination 600 m off the route (RvStandTest).
        let o = Self.stand(KW.cfg(.time, thrMin: 5), 600.0, 2.5)
        check("o", o, 1720, Self.u123O)
        // (p) DISTANCE 500, 2 m/s, destination 800 m off the route, standing 2 km north (1 354 m past the nearest point).
        let pp = Self.stand(KW.cfg(.distance, thr: 500), 800.0, 2.0, stopNorth: 2_000.0)
        check("p", pp, 2210, Self.u123P)
        // (p2) the RvStandTest geometry (standing 1.6 km north, 989 m past the nearest point 800 m off the route).
        let p2 = Self.stand(KW.cfg(.distance, thr: 500), 800.0, 2.0)
        check("p2", p2, 2210, Self.u123P2)
        // (b) the net off: the T12.2 rule, silent for 2 h.
        let off = KW.params(#"{"passedClosestSlowRiseM": 0}"#)
        #expect(Self.stand(KW.cfg(.time, thrMin: 5), 600.0, 2.5, params: off) == nil, "b o")
        #expect(Self.stand(KW.cfg(.distance, thr: 500), 800.0, 2.0, stopNorth: 2_000.0, params: off) == nil, "b p")
        #expect(Self.stand(KW.cfg(.distance, thr: 500), 800.0, 2.0, params: off) == nil, "b p2")
        Report.shared.write("unit/u123-a.txt", "o \(o.map { String($0.0) } ?? "null") s, p \(pp.map { String($0.0) } ?? "null") s, "
                            + "p2 \(p2.map { String($0.0) } ?? "null") s (hand 1720 / 2210 / 2210)
")
    }

    @Test("U114 q r s u parked after the gap with poor fixes, repeated or alternating coordinates, or crawling away rings OVERSHOOT at the 3rd fix")
    func u114qrsu() {
        Self.assertPark(Self.park(1_761, 80.0, nil) { _ in (-3_100.0, 0.0) }, 3, "q gap 1761")
        Self.assertPark(Self.park(600, 80.0, nil) { _ in (-3_100.0, 0.0) }, 3, "q gap 600 (P9)")
        Self.assertPark(Self.park(1_761, 60.0, 0.0) { _ in (-3_100.0, 0.0) }, 3, "r (P11)")
        Self.assertPark(Self.park(1_761, 80.0, nil) { k in (k % 2 == 0 ? -3_100.0 : -3_130.0, 0.0) }, 3, "s")
        Self.assertPark(Self.park(1_761, 8.0, 2.0) { k in (-(3_100.0 + 2.0 * 5.0 * Double(k)), 0.0) }, 3, "u")
    }

    @Test("U114 t parked after the gap with random jitter of 20 m, 200 deterministic sets ring OVERSHOOT within 120 s")
    func u114t() {
        var lat: [Double] = []
        var bad: [String] = []
        for seed in Int64(1)...200 {
            var r = Mix(seed &* 1_000_003)
            let res = Self.park(1_761, 80.0, nil, maxS: 3_600) { _ in
                let south = -(3_100.0 + r.dbl(-20.0, 20.0))
                let east = r.dbl(-20.0, 20.0)
                return (south, east)
            }
            let after = res.atMs.map { Double($0 - Self.n) / 1000.0 }
            if res.reason != .overshoot || after == nil || after! > 120.0 {
                bad.append("seed \(seed): \(res.reason?.jsonName ?? "null") at \(after.map(Self.kd) ?? "null") s")
            }
            if let a = after { lat.append(a) }
        }
        lat.sort()
        let dist = lat.isEmpty ? "-" : "n \(lat.count), p50 \(Self.kd(lat[lat.count / 2])) s, p90 \(Self.kd(lat[(lat.count * 9) / 10])) s, "
            + "max \(Self.kd(lat.last!)) s"
        var hist: [Double: Int] = [:]
        for x in lat { hist[x, default: 0] += 1 }
        let histTxt = "{" + hist.keys.sorted().map { "\(Self.kd($0))=\(hist[$0]!)" }.joined(separator: ", ") + "}"
        Report.shared.write("unit/u114-t-jitter.txt", "\(dist)\nafter first fix (s → sets): \(histTxt)\nover 120 s: \(KW.klist(bad))\n")
        #expect(bad.isEmpty, "U114 t: \(bad.prefix(10))")
    }

    /// U114 (x) (round 3d, RvOutlierTest row 1): normal tracking, DISTANCE 500, 2 m/s straight to the destination, a fix every 30 s;
    /// the 2nd fix is an outlier at 800 m (accepted) while the vehicle is at 1 940 m: DISTANCE at 780 s, no OVERSHOOT.
    @Test("U114 x one outlier fix lowering minD during a normal approach does not ring OVERSHOOT (round 3d)")
    func u114x() throws {
        let start = 2_060.0
        let p0 = KW.pointOnMeridian(start)
        let l = FixRec(fixAtMs: Self.S, lat: p0.lat, lng: p0.lng, accM: 8.0, d: start, groundSample: nil)
        let base = KW.trackingState(KW.cfg(.distance, thr: 500), now: Self.S, d: start, ground: 2.0, closing: 2.0, lastFixAt: Self.S)
        var st = KW.withLast(base, l, dStartPlus: 5_000.0)
        var y = start
        var t = 0
        var k = 0
        var first: (Int, Step)? = nil
        var events: [TripEvent] = []
        while y > 0 && t < 7_200 && first == nil {
            t += 30
            k += 1
            y -= 2.0 * 30.0
            let rep = k == 2 ? 800.0 : y
            let p = KW.pointOnMeridian(rep)
            let at = Self.S + Int64(t) * 1000
            let s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: k == 2 ? 10.0 : 8.0,
                                                                   speedMps: k == 2 ? nil : 2.0)))
            st = s.state
            events += s.events
            if k == 2 { #expect((st.minD! - 800.0).magnitude <= 1.0, "x: the outlier was accepted (minD \(String(describing: st.minD)))") }
            if !s.events.alarms.isEmpty { first = (t, s) }
        }
        let (ta, sa) = try #require(first)
        GapLog.shared.add("x", "x: first alarm \(sa.events.alarms[0].reason.jsonName) at t=\(ta) s\n")
        #expect(KW.overshoots(events).isEmpty, "x: no Overshoot")
        #expect(sa.events.alarms.map(\.reason) == [.distance], "x")
        #expect(ta == 780, "x: DISTANCE at 780 s")
    }

    /// U114 (w) (round 3c table row "turns back"): passed in the gap, then drives back to the destination.
    @Test("U114 w passed in the gap then turning back towards the destination rings DISTANCE at 1 km, no overshoot")
    func u114w() throws {
        let fixes = (0..<100).map { i in
            Fx(at: Self.n + 5_000 * Int64(i), south: -TMath.max(0.0, 3_100.0 - 18.0 * 5.0 * Double(i)), east: 0.0, spd: 18.0)
        }
        let steps = Self.drive(Self.reproState(), fixes)
        Self.note("w", steps)
        #expect(KW.overshoots(steps.flatMap(\.events)).isEmpty, "w: no Overshoot")
        let (_, a) = try #require(Self.firstAlarm(steps))
        #expect(a.reason == .distance, "w")
        #expect(try #require(steps.last?.state.dSmooth) <= 1_000.0)
    }

    /// U114 (v) (RK20 a, pinned accepted risk): the bypass case of (i), but after the first fix the vehicle stands 2 minutes before
    /// driving on: OVERSHOOT with the wrong wording.
    @Test("U114 v bypass entering from the far side then standing rings a wrong-wording OVERSHOOT (RK20 a, accepted)")
    func u114v() throws {
        let n = Self.n
        let d0 = (2_000.0 * 2_000.0 + 500.0 * 500.0).squareRoot()
        let standFixes = (0..<24).map { i in Fx(at: n + 5_000 * Int64(i), south: -2_000.0, east: 500.0, spd: i == 0 ? 30.0 : 0.0) }
        let driveFixes = (0..<100).map { i -> Fx in
            let r = TMath.max(0.0, 1.0 - 10.0 * 5.0 * Double(i + 1) / d0)
            return Fx(at: n + 120_000 + 5_000 * Int64(i), south: -2_000.0 * r, east: 500.0 * r, spd: 10.0)
        }
        let steps = Self.drive(Self.bypassState(), standFixes + driveFixes)
        Self.note("v", steps)
        let (t, a) = try #require(Self.firstAlarm(steps))
        #expect(a.reason == .overshoot, "v: accepted wrong-wording OVERSHOOT")
        #expect(t == n + 5_000 || t == n + 10_000, "v: at n+\(Double(t - n) / 1000.0) s (fix 2–3)")
    }

    // MARK: - U114 (y), (z), (aa), (ab)–(ad) (T10.5 round 3e, 3f)

    struct JamResult {
        let step: Step
        let d: Double
        let rejected: Int
        let minDs: [Double]
    }

    /// Normal tracking (no GPS gap), the tester's O1 shape: approach at 12 m/s from 20 km, at `jamD` m before the destination the
    /// vehicle stops (or crawls `crawl` m/s) for 20 min, then drives on; fixes every 30 s, noise ±8 m, Ticks at wakeAtMs in
    /// between; 300 s into the jam `outliers` outlier fix(es) `delta` m closer (acc 15). Until the first Alarm.
    static func jam(_ config: TripConfig, _ jamD: Double, _ crawl: Double, _ delta: Double, outliers: Int = 1) throws -> JamResult {
        var rejected = 0
        var minDs: [Double] = []
        var r = Mix(KW.kl(jamD) &* 31 &+ KW.kl(delta))
        let tJam = S + KW.kl((20_000.0 - jamD) / 12.0 * 1000.0)
        func yAt(_ t: Int64) -> Double {
            if t <= tJam { return -20_000.0 + 12.0 * Double(t - S) / 1000.0 }
            if t <= tJam + 1_200_000 { return -jamD + crawl * Double(t - tJam) / 1000.0 }
            return -jamD + crawl * 1_200.0 + 12.0 * Double(t - tJam - 1_200_000) / 1000.0
        }
        func vAt(_ t: Int64) -> Double { t <= tJam ? 12.0 : (t <= tJam + 1_200_000 ? crawl : 12.0) }
        var step = try TripEngine.start(config: config, params: .defaults, nowMs: S)
        var nextFix = S + 1_000
        var outLeft = outliers
        var guardN = 0
        while step.events.alarms.isEmpty {
            guardN += 1
            if guardN >= 100_000 { break }
            #expect(!step.state.minDChord, "minDChord must stay false without a GPS gap (t=\(Double(step.state.nowMs - S) / 1000.0))")
            if let wake = step.view.wakeAtMs, wake < nextFix {
                step = TripEngine.reduce(step.state, .tick(atMs: wake))
            } else {
                let t = nextFix
                nextFix = t + 30_000
                let y = yAt(t)
                let outlier = outLeft > 0 && t >= tJam + 300_000
                if outlier { outLeft -= 1 }
                let south = outlier ? -(y + delta) : -(y + r.dbl(-8.0, 8.0))
                let p = KW.jitter(KW.pointOnMeridian(south), r.dbl(-8.0, 8.0), 0.0)
                let s1 = TripEngine.reduce(step.state, .locationFix(LocationFix(atMs: t, fixAtMs: t, lat: p.lat, lng: p.lng,
                                                                                accuracyM: outlier ? 15.0 : 10.0, speedMps: vAt(t))))
                if s1.state.droppedFixes > step.state.droppedFixes { rejected += 1 }
                if let m = s1.state.minD { minDs.append(m) }
                step = s1
            }
        }
        #expect(!step.state.minDChord)
        return JamResult(step: step, d: yAt(step.state.nowMs).magnitude, rejected: rejected, minDs: minDs)
    }

    @Test("U114 y z normal tracking, stuck before the destination with one outlier fix, is the T12.1 rule (no OVERSHOOT)")
    func u114yz() throws {
        // (y) the tester's O1 repro (R2-1): DISTANCE 500, stopped at 1 900 m, outlier at 800 m.
        let y = try Self.jam(KW.cfg(.distance, thr: 500), 1_900.0, 0.0, 1_100.0)
        let ay = y.step.events.alarms
        GapLog.shared.add("y", "y: first alarm \(ay.first?.reason.jsonName ?? "null") at truth d=\(KW.ki(y.d)) m\n")
        #expect(ay.map(\.reason) == [.distance], "y")
        #expect((400.0...500.0).contains(y.d), "y: DISTANCE at d=\(y.d) (T12.1: 480 m)")
        // (z) TIME 5, crawling 0.3 m/s (lag-2 true after 3 fixes).
        let z = try Self.jam(KW.cfg(.time, thrMin: 5), 1_900.0, 0.3, 1_100.0)
        let az = z.step.events.alarms
        GapLog.shared.add("z", "z: first alarm \(az.first?.reason.jsonName ?? "null") at truth d=\(KW.ki(z.d)) m\n")
        #expect(az.count == 1 && az[0].reason != .overshoot && !KW.hasOvershoot(z.step), "z: \(az)")
    }

    @Test("U114 aa the chord flag survives parking jitter and is cleared by an observed fix closer than the chord")
    func u114aa() throws {
        let n = Self.n
        // (i) chord minD ≈ 0, then parked 3.1 km beyond with ±50 m jitter, Doppler 0: the flag stays, OVERSHOOT as U114 a2.
        var r = Mix(114_027)
        var fixes: [Fx] = []
        for i in 0..<40 {
            let south = -(3_100.0 + r.dbl(-50.0, 50.0))
            let east = r.dbl(-50.0, 50.0)
            fixes.append(Fx(at: n + 5_000 * Int64(i), south: south, east: east, spd: 0.0))
        }
        let i1 = Self.drive(Self.reproState(), fixes)
        let flagKept = i1.allSatisfy { $0.state.minDChord }
        #expect(flagKept, "aa (i): flag kept")
        let (t1, a1) = try #require(Self.firstAlarm(i1))
        GapLog.shared.add("aa1", "aa (i): \(a1.reason.jsonName) at n+\(Self.kd(Double(t1 - n) / 1000.0)) s\n")
        #expect(a1.reason == .overshoot)
        #expect(t1 <= n + 10_000, "aa (i) at n+\(Double(t1 - n) / 1000.0) s")
        // (ii) chord 400 m east of the destination (dChord ≈ 400), the vehicle turns back and drives straight to the destination:
        // the first observed dSmooth < dChord clears the flag; no OVERSHOOT. DISTANCE 200 so the vehicle gets below dChord first.
        let l = Self.rec(Self.pt(29_410.0, 400.0), n - 1_761_000)
        let st = KW.withLast(Self.reproState(KW.cfg(.distance, thr: 200)), l)
        let len = (3_100.0 * 3_100.0 + 400.0 * 400.0).squareRoot()
        let back = (0..<200).map { i -> Fx in
            let rr = TMath.max(0.0, 1.0 - 15.0 * 5.0 * Double(i) / len)
            return Fx(at: n + 5_000 * Int64(i), south: -3_100.0 * rr, east: 400.0 * rr, spd: 15.0)
        }
        let ii = Self.drive(st, back)
        let firstMinD = try #require(ii.first?.state.minD)
        #expect((firstMinD - 400.0).magnitude <= 2.0 && ii[0].state.minDChord, "aa (ii) chord \(firstMinD)")
        let cleared = ii.firstIndex { !$0.state.minDChord } ?? -1
        #expect(cleared > 0 && ii[cleared].state.dSmooth! < firstMinD + 1e-9, "aa (ii) cleared at \(cleared)")
        #expect(KW.overshoots(ii.flatMap(\.events)).isEmpty, "aa (ii) no Overshoot")
        let (t2, a2) = try #require(Self.firstAlarm(ii))
        GapLog.shared.add("aa2", "aa (ii): flag cleared at fix \(cleared + 1), first alarm \(a2.reason.jsonName) at n+\(Self.kd(Double(t2 - n) / 1000.0)) s\n")
        #expect(a2.reason == .distance)
        #expect(try #require(ii.last?.state.dSmooth) <= 200.0)
    }

    /// U114 (ab) (round 3f, the coder's O1 repro): D500, fixes every 30 s, stopped at 1 200 m, two outliers 2 km closer: outlier 1
    /// rejected (IMPLAUSIBLE), outlier 2 accepted with Δt = 60 s = lostAfterS: with `rejects` non-empty neither accepted fix is a
    /// chord fix; minDChord stays false, no OVERSHOOT, DISTANCE as on HEAD (T12.1).
    @Test("U114 ab an outlier accepted after a rejected one is not a GPS-gap chord fix (round 3f)")
    func u114ab() throws {
        let j = try Self.jam(KW.cfg(.distance, thr: 500), 1_200.0, 0.0, 2_000.0, outliers: 2)
        let a = j.step.events.alarms
        let firstLow = j.minDs.first { $0 < 1_100.0 }
        GapLog.shared.add("ab", "ab: first alarm \(a.first?.reason.jsonName ?? "null") at truth d=\(KW.ki(j.d)) m, rejected fixes \(j.rejected), "
                          + "minD after the outliers \(firstLow.map { String(KW.ki($0)) } ?? "null")\n")
        #expect(j.rejected >= 2, "ab: outlier 1 and the next true fix rejected (\(j.rejected))")
        let low = try #require(firstLow)
        #expect((low - 800.0).magnitude <= 20.0, "ab: outlier 2 accepted, minD \(low) (not a chord ≈ 0)")
        #expect(a.map(\.reason) == [.distance], "ab")
        #expect((400.0...500.0).contains(j.d), "ab: DISTANCE at d=\(j.d) (HEAD: 488 m)")
    }

    /// U114 (ac) (round 3f): one STALE fix (age 90 s) and one INACCURATE fix (acc 1 500 m) inside the gap are DROPped but not
    /// IMPLAUSIBLE: `rejects` stays empty, the first fix after the gap is still a chord fix.
    @Test("U114 ac STALE and INACCURATE fixes inside the gap keep the chord fix")
    func u114ac() throws {
        let n = Self.n
        var st = Self.reproState()
        let p1 = Self.pt(20_000.0)
        let stale = TripEngine.reduce(st, .locationFix(LocationFix(atMs: n - 600_000, fixAtMs: n - 690_000, lat: p1.lat, lng: p1.lng,
                                                                   accuracyM: 8.0, speedMps: 10.0)))
        #expect(stale.state.droppedFixes == st.droppedFixes + 1, "ac: STALE dropped")
        st = stale.state
        let inacc = TripEngine.reduce(st, .locationFix(LocationFix(atMs: n - 300_000, fixAtMs: n - 300_000, lat: p1.lat, lng: p1.lng,
                                                                   accuracyM: 1_500.0, speedMps: 10.0)))
        #expect(inacc.state.droppedFixes == st.droppedFixes + 1, "ac: INACCURATE dropped")
        st = inacc.state
        #expect(st.rejects.isEmpty)
        let steps = Self.drive(st, Self.away(3_100.0, 18.0))
        #expect(steps[0].state.minDChord && steps[0].state.minD! <= 1.0, "ac: chord fix (minD \(String(describing: steps[0].state.minD)))")
        Self.assertAlarm(steps, .overshoot, n + 10_000, "ac")
    }

    /// U114 (ad) (round 3f, RK20 d, pinned): one jump fix rejected as IMPLAUSIBLE inside the gap: the first fix after the gap is
    /// not a chord fix (T12.1 rule: minD 3 100 m, nothing to ring while moving away), silent for the hour driven here.
    @Test("U114 ad one IMPLAUSIBLE fix inside the gap makes the first fix after it a plain fix (T12.1 rule, pinned)")
    func u114ad() throws {
        let n = Self.n
        let p1 = Self.pt(500_000.0)
        let jump = TripEngine.reduce(Self.reproState(), .locationFix(LocationFix(atMs: n - 1_000_000, fixAtMs: n - 1_000_000, lat: p1.lat,
                                                                                 lng: p1.lng, accuracyM: 8.0, speedMps: 10.0)))
        #expect(jump.state.rejects.count == 1, "ad: IMPLAUSIBLE kept in rejects")
        let steps = Self.drive(jump.state, Self.away(3_100.0, 18.0, count: 720))
        Self.note("ad", steps)
        #expect(steps.allSatisfy { !$0.state.minDChord }, "ad: no chord fix")
        #expect((try #require(steps.first?.state.minD) - 3_100.0).magnitude <= 1.0)
        #expect(Self.firstAlarm(steps) == nil, "ad: pinned silent for 1 h (RK20 d)")
    }

    // MARK: - U116 a, U117 (fixture main runs)

    @Test("U116 a the GPS-gap chord never goes through a fixture destination (u outside 0 to 1 at every GpsRecovered Step)")
    func u116a() async {
        let outs = await FixtureMainRuns.all.value
        let probes = outs.flatMap { o in o.gapProbes.map { (o, $0) } }
        let traces = Set(probes.map { $0.0.traceId }).sorted()
        let lines = probes.map { (o, g) in
            "\(o.run) t=\(Self.kd(Double(g.atMs - o.startMs) / 1000.0)) recovered=\(g.recovered) gapFix=\(g.gapFix) u=\(KW.kdOpt(g.u)) "
                + "chord=\(KW.kdOpt(g.chordM)) dChord=\(KW.kdOpt(g.dChord)) standingTerm=\(g.standingTerm)"
        }.joined(separator: "\n")
        Report.shared.write("unit/u116-gap.txt", "traces=\(KW.klist(traces)) probes=\(probes.count)\n\(lines)\n")
        #expect(probes.contains { $0.1.recovered }, "no GpsRecovered Step on the fixtures?")
        #expect(traces.count >= 5, "traces with probes: \(traces)")
        let hit = probes.filter { $0.1.dChord != nil }
        #expect(hit.isEmpty, "chord through the destination on fixtures: \(hit.prefix(10).map { $0.0.run })")
    }

    @Test("U117 the notCloser term of the overshoot rule never holds on a fixture run without an earlier GPS-gap chord")
    func u117() async {
        let outs = await FixtureMainRuns.all.value
        var bad: [String] = []
        var standing = 0
        for o in outs {
            var chordSeen = false
            let sorted = o.gapProbes.enumerated().sorted { $0.element.atMs != $1.element.atMs ? $0.element.atMs < $1.element.atMs : $0.offset < $1.offset }
            for (_, g) in sorted {
                if g.dChord != nil { chordSeen = true }
                if g.standingTerm {
                    standing += 1
                    if !chordSeen { bad.append("\(o.run) t=\(Self.kd(Double(g.atMs - o.startMs) / 1000.0))") }
                }
            }
        }
        Report.shared.write("unit/u117-standing.txt", "standingTerm=\(standing) withoutChord=\(bad.count)\n\(bad.joined(separator: "\n"))\n")
        #expect(bad.isEmpty, "standing term without a chord: \(bad.prefix(10))")
    }
}
