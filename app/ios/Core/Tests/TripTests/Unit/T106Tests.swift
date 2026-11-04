import Foundation
import Testing
@testable import Trip

/// `t106-log.txt` lines from every T106 test (parallel tests; written sorted by tag so the file is deterministic).
final class T106Log: @unchecked Sendable {
    static let shared = T106Log()
    private let lock = NSLock()
    private var lines: [String: String] = [:]

    func add(_ tag: String, _ text: String) {
        lock.lock()
        lines[tag] = text
        let all = lines.keys.sorted().map { lines[$0]! }.joined()
        lock.unlock()
        Report.shared.write("unit/t106-log.txt", all)
    }
}

extension KDriver {
    /// Kotlin `EngineDriver(config, p)`: a trip started at S.
    init(start config: TripConfig, params: EngineParams = .defaults) {
        let s = try! TripEngine.start(config: config, params: params, nowMs: KW.S)
        self.init(from: s.state)
        steps = [s]
    }

    var last: Step { steps[steps.count - 1] }

    @discardableResult mutating func tick(_ t: Int) -> Step { feed(.tick(atMs: ms(t))) }

    @discardableResult mutating func avail(_ t: Int, _ c: AvailabilityCause) -> Step { feed(.locationAvailability(atMs: ms(t), cause: c)) }

    /// Kotlin `restore(t, info, roundTrip = true)`.
    @discardableResult
    mutating func restore(_ t: Int, _ info: RestoreInfo) -> Step {
        let st = try! TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(state))
        let s = TripEngine.restore(st, nowMs: ms(t), info: info)
        steps.append(s)
        state = s.state
        return s
    }
}

/// T10.6 (T10 mục cuối "T10.6" §7; port of Kotlin `unit/T106Test.kt`): "long loss" rule W (U119, U120), speed before
/// `established` while LOST (U122), slow-vehicle passed-closest net `passAnchorD` (U123 c–i; U123 a, b in `T105GapTests`), snapshot
/// key (U124). U121 is in `TesterT132Tests`, U125 in `TesterT132OvershootTests`, U126 in `TesterT131Tests` / `TesterT132Tests`.
@Suite("T106Tests")
struct T106Tests {
    static let S = KW.S

    /// U120 (b): measured (Kotlin T12.3).
    static let u120bAlarmMs: Int64 = 5_911_009
    /// U122 (a), (b): measured (Kotlin T12.3); designer by hand about 621 s / 4 126 s.
    static let u122aAlarmMs: Int64 = 620_000
    static let u122bAlarmMs: Int64 = 4_126_000
    /// U123 (h): measured (Kotlin T12.3).
    static let u123hAlarmS = 2_655

    static func estimateOf(_ s: EngineState) -> Estimate { Estimator.estimate(s, now: s.nowMs)! }

    static func hasGpsLost(_ s: Step) -> Bool { !s.events.compactMap(\.asGpsLost).isEmpty }

    static func firstAlarm(_ steps: [Step]) -> TripEvent.Alarm? { steps.flatMap(\.events).alarms.first }

    /// I13: wakeAtMs is nil only when ENDED, otherwise strictly after now.
    static func i13(_ s: Step, _ tag: String) {
        let w = s.view.wakeAtMs
        if s.view.phase == .ended {
            #expect(w == nil, "\(tag): I13 ENDED")
        } else {
            #expect(w != nil && w! > s.state.nowMs, "\(tag): I13 wakeAtMs \(String(describing: w)) not after now in \(s.view.phase.jsonName)")
        }
    }

    // MARK: - U119: lostLongAtS (pure)

    /// TRAIN (default), EMA ground/closing, gps LOST, the last fix at S, now = S + 60 s.
    static func lostState(_ d: Double, p: EngineParams = .defaults, hint: VehicleKind = .train, ground: Double? = 15.0,
                          closing: Double? = 12.5, gps: GpsStatus = .lost) -> EngineState {
        KW.trackingState(KW.cfg(hint: hint), p: p, now: S + 60_000, d: d, ground: ground, closing: closing, gps: gps, lastFixAt: S)
    }

    /// The pure function and the Step's estimate agree bit for bit.
    static func lla(_ s: EngineState) -> Double? {
        let e = estimateOf(s)
        let pure = Estimator.lostLongAtS(s, e)
        #expect(e.lostLongAtS?.bitPattern == pure?.bitPattern)
        return pure
    }

    @Test("U119 lostLongAtS the long-loss mark W of C25 (a)–(h), hex printed for the Kotlin comparison")
    func u119() throws {
        var out = ""
        // (a) T122 c builder, L = 3 600 / 7 200 / 10 800.
        for (l, want) in [(3_600, 2_784.8), (7_200, 5_435.7), (10_800, 8_086.6)] {
            let x = try #require(Self.lla(Self.lostState(12.5 * (1_180.0 + Double(l)))))
            #expect((x - want).magnitude <= 0.1, "a L=\(l): \(x)")
            out += "a L=\(l): \(KW.kd(x)) \(javaHex(x))\n"
        }
        // (b) hint BUS: cvH = cvDr, thS 7 200, earlyS 1 650.
        let b = try #require(Self.lla(Self.lostState(12.5 * 8_380.0, hint: .bus)))
        #expect((b - 5_550.0).magnitude <= 1e-9, "b: \(b)")
        // (c) dSmooth 15 000: the floor gpsLostLongS.
        let c = try #require(Self.lla(Self.lostState(15_000.0)))
        #expect(c == 1_800.0, "c")
        // (d) gpsLostLongS 0: off.
        #expect(Self.lla(Self.lostState(12.5 * 8_380.0, p: KW.params(#"{"gpsLostLongS": 0}"#))) == nil, "d")
        // (e) no hint floor, L = 7 200.
        let e = try #require(Self.lla(Self.lostState(12.5 * 8_380.0, p: KW.params(#"{"gpsLostLongHintFactor": 0}"#))))
        #expect((e - 5_550.0).magnitude <= 1e-9, "e: \(e)")
        // (f) ground 0, cvGuard empty (cvDr 0), dSmooth 50 000: the TRAIN floor alone.
        let fs = Self.lostState(50_000.0, ground: 0.0, closing: 0.0)
        #expect(Self.estimateOf(fs).cvDr == 0.0)
        let f = try #require(Self.lla(fs))
        #expect((f - 2_210.45).magnitude <= 0.01, "f: \(f)")
        // (g) as (f) without the floor: cvH 0 → nil.
        #expect(Self.lla(Self.lostState(50_000.0, p: KW.params(#"{"gpsLostLongHintFactor": 0}"#), ground: 0.0, closing: 0.0)) == nil, "g")
        // (h) gps OK → nil.
        #expect(Self.lla(Self.lostState(12.5 * 8_380.0, gps: .ok)) == nil, "h")
        out += "b: \(javaHex(b))\nc: \(javaHex(c))\ne: \(javaHex(e))\nf: \(KW.kd(f)) \(javaHex(f))\n"
        Report.shared.write("unit/u119-lostlong.txt", out)
    }

    // MARK: - U120: W through reduce

    struct DozeOut {
        let steps: [Step]
        let alarm: Step
    }

    /// Only Tick(view.wakeAtMs) until a Step with an Alarm; I13 at every Step. nil when the next wake-up is at or after `until`.
    static func doze(_ e: inout KDriver, _ tag: String, until: Int64 = .max, max: Int = 2_000) -> DozeOut? {
        var out: [Step] = []
        if e.steps.isEmpty { out.append(e.tick(0)) }
        while true {
            i13(e.last, tag)
            guard let w = e.view.wakeAtMs else {
                Issue.record("\(tag): no wake-up")
                return nil
            }
            if w >= until { return nil }
            let s = e.tickMs(w)
            out.append(s)
            if !s.events.alarms.isEmpty {
                i13(s, tag)
                return DozeOut(steps: out, alarm: s)
            }
            if out.count >= max {
                Issue.record("\(tag): no alarm after \(max) wake-ups")
                return nil
            }
        }
    }

    static func t122c(_ lossS: Int, _ p: EngineParams = .defaults) -> KDriver {
        var e = KDriver(from: KW.trackingState(KW.cfg(.distance, thr: 1000), p: p, d: 12.5 * (1_180.0 + Double(lossS)), tier: .dense))
        e.tick(0)
        return e
    }

    @Test("U120 a c f the long-loss rule rings GPS_LOST at lostLongAt + 1 s from a wake-up Tick, constant prediction, off is T12.2")
    func u120acf() throws {
        // (a) T122 c, L = 7 200, Doze loop, no fix.
        var a = Self.t122c(7_200)
        let raOpt = Self.doze(&a, "U120 a")
        let ra = try #require(raOpt)
        let lostIdx = try #require(ra.steps.firstIndex { Self.hasGpsLost($0) })
        let lostStep = ra.steps[lostIdx]
        // The designer's first table said S + 60 s; the first Tick(S) moves the policy to SPARSE, so lostAfterS = 540 s
        // (T10.4 GAP-2, D2). lostLongAt counts from the last fix, so the alarm time does not depend on it.
        #expect(lostStep.state.nowMs == Self.S + 540_000, "a: GpsLost (T10.4 GAP-2: SPARSE after the first Tick)")
        let lla = try #require(Self.estimateOf(lostStep.state).lostLongAtS)
        #expect((lla - 5_435.72).magnitude <= 0.01, "a: \(lla)")
        let p = Self.S + TMath.floorMs(lla)
        for st in ra.steps[lostIdx...] where st.events.alarms.isEmpty {
            #expect(st.view.predictedAlarmAtMs == p, "a: predicted at \(st.state.nowMs - Self.S)")
        }
        let alarms = ra.alarm.events.alarms
        #expect(alarms.count == 1 && alarms.first?.reason == .gpsLost && alarms.first?.ringNow == true, "a: \(alarms)")
        #expect(alarms.first?.atMs == p + 1_000, "a: Tick c3 = predicted + 1 s (T10.5: S + 7 201 000)")
        // (c) gpsLostLongS 0: the T12.2 sequence (alarm S + 7 201 000, predicted S + 7 200 000 from GpsLost).
        var c = Self.t122c(7_200, KW.params(#"{"gpsLostLongS": 0}"#))
        let rcOpt = Self.doze(&c, "U120 c")
        let rc = try #require(rcOpt)
        let lostC = try #require(rc.steps.first { Self.hasGpsLost($0) })
        #expect(lostC.view.predictedAlarmAtMs == Self.S + 7_200_000)
        #expect(Self.firstAlarm(rc.steps)?.atMs == Self.S + 7_201_000)
        #expect(Self.firstAlarm(rc.steps)?.reason == .gpsLost)
        // (f) as (a), the loss comes from LocationAvailability(PERMISSION_REVOKED) at S + 1 s.
        var f = Self.t122c(7_200)
        let lf = f.avail(1, .permissionRevoked)
        #expect(lf.events.compactMap(\.asGpsLost).map(\.cause) == [.permissionRevoked])
        #expect(lf.view.predictedAlarmAtMs == p)
        let rfOpt = Self.doze(&f, "U120 f")
        let rf = try #require(rfOpt)
        #expect(Self.firstAlarm(rf.steps)?.atMs == p + 1_000)
        #expect(Self.firstAlarm(rf.steps)?.reason == .gpsLost)
        let fAt = Self.firstAlarm(rf.steps).map { KW.kd(Double($0.atMs - Self.S) / 1000.0) } ?? "null"
        T106Log.shared.add("U120 a", "U120 a: lostLongAtS \(KW.kd(lla)) alarm \(KW.kd(Double(alarms.first!.atMs - Self.S) / 1000.0)) s; "
                           + "c: 7201 s; f: \(fAt) s\n")
    }

    @Test("U120 b a fix in the middle of the loss recomputes lostLongAt from the new fix (pinned)")
    func u120b() throws {
        var e = Self.t122c(7_200)
        let before = Self.doze(&e, "U120 b before", until: Self.S + 1_799_000)
        #expect(before == nil)
        let dr = 12.5 * (1_180.0 + 7_200.0) - 12.5 * 1_799.0
        let fx = e.fix(1_799, dr, spd: 15.0)
        #expect(fx.view.gps == .ok)
        Self.i13(fx, "U120 b fix")
        let rOpt = Self.doze(&e, "U120 b after")
        let r = try #require(rOpt)
        let lost = try #require(r.steps.first { Self.hasGpsLost($0) })
        let lla = try #require(Self.estimateOf(lost.state).lostLongAtS)
        let lastFix = try #require(lost.state.last).fixAtMs
        let p = lastFix + TMath.floorMs(lla)
        #expect(lastFix == Self.S + 1_799_000)
        #expect(lost.view.predictedAlarmAtMs == p, "b: lostLongAt from the new fix")
        let a = try #require(Self.firstAlarm(r.steps))
        #expect(a.reason == .gpsLost)
        #expect(a.atMs == p + 1_000)
        #expect(a.atMs - Self.S == Self.u120bAlarmMs, "b: first alarm (pinned)")
    }

    @Test("U120 d e the A10 builder rings before the pre-alert zone, a zero-speed state rings by the hint floor")
    func u120de() throws {
        // (d) lostDoze of U107 (a) with the defaults: first set of every mode.
        let modes: [(String, TripConfig, Bool)] = [
            ("TIME 5", KW.cfg(.time, thrMin: 5), false),
            ("TIME 15", KW.cfg(.time, thrMin: 15), false),
            ("TIME 20", KW.cfg(.time, thrMin: 20), false),
            ("SMART", KW.cfg(.smart), false),
            ("SMART slow", KW.cfg(.smart), true),
        ]
        var log = ""
        for (name, config, slow) in modes {
            let (g, c) = slow ? (3.0, 2.5) : (15.0, 12.5)
            let st = KW.trackingState(config, d: (5_000.0 - 20.0) * c, ground: g, closing: c, slow: slow)
            var e = KDriver(from: st)
            let lost = e.tickMs(Self.S + TMath.ms(GpsMonitor.lostAfterS(st)))
            #expect(Self.hasGpsLost(lost), "\(name)")
            let lla = try #require(Self.estimateOf(lost.state).lostLongAtS)
            let rOpt = Self.doze(&e, "U120 d \(name)")
            let r = try #require(rOpt)
            #expect(e.steps.allSatisfy { TesterT131Tests.preAlerts($0).isEmpty }, "\(name): PreAlert (I5)")
            let a = Self.firstAlarm(r.steps)
            #expect(a?.reason == .gpsLost, "\(name)")
            #expect(a?.atMs == Self.S + TMath.floorMs(lla) + 1_000, "\(name)")
            log += "U120 d \(name): lostLongAtS \(KW.kd(lla))\n"
        }
        T106Log.shared.add("U120 d", log)
        // (e) ground 0, cvGuard empty, dSmooth 50 000, TRAIN: T10.5 rang only TIMEOUT.
        var e = KDriver(from: KW.trackingState(d: 50_000.0, ground: 0.0, closing: 0.0))
        let rOpt = Self.doze(&e, "U120 e")
        let r = try #require(rOpt)
        let lostE = try #require(r.steps.first { Self.hasGpsLost($0) })
        let lla = try #require(Self.estimateOf(lostE.state).lostLongAtS)
        #expect((lla - 2_210.45).magnitude <= 0.01, "e: \(lla)")
        let a = Self.firstAlarm(r.steps)
        #expect(a?.reason == .gpsLost)
        #expect(a?.atMs == Self.S + TMath.floorMs(lla) + 1_000, "e")
    }

    @Test("U120 g a snapshot round trip and restore PENDING in the middle of the loss gives the uninterrupted event sequence")
    func u120g() throws {
        func eventsOf(_ steps: [Step]) -> [TripEvent] { steps.flatMap(\.events) }
        // Reference: the same wake-ups plus a plain Tick at S + 3 000 s (restore PENDING is Tick(now) after the restore branch).
        var a = Self.t122c(7_200)
        let aBefore = Self.doze(&a, "U120 g ref before", until: Self.S + 3_000_000)
        #expect(aBefore == nil)
        a.tick(3_000)
        let raOpt = Self.doze(&a, "U120 g ref after")
        let ra = try #require(raOpt)
        var g = Self.t122c(7_200)
        let gBefore = Self.doze(&g, "U120 g before", until: Self.S + 3_000_000)
        #expect(gBefore == nil)
        g.restore(3_000, RestoreInfo(status: .pending))
        let rgOpt = Self.doze(&g, "U120 g after")
        let rg = try #require(rgOpt)
        #expect(eventsOf(a.steps) == eventsOf(g.steps), "g: events differ from the uninterrupted run")
        #expect(a.steps.map(\.view) == g.steps.map(\.view), "g: views differ")
        // Same alarm as without the extra Step: lostLongAt + 1 s.
        let lostG = try #require(g.steps.first { Self.hasGpsLost($0) })
        let lla = try #require(Self.estimateOf(lostG.state).lostLongAtS)
        #expect(Self.firstAlarm(rg.steps)?.atMs == Self.S + TMath.floorMs(lla) + 1_000)
        #expect(Self.firstAlarm(ra.steps) == Self.firstAlarm(rg.steps))
    }

    // MARK: - U122: speed before `established` while LOST (C26)

    /// Not established (movingTimeS 60, movingSamples 2), hint BUS, dSmooth 30 000, the fix at S.
    static func preState(_ ground: Double?, _ p: EngineParams = .defaults) -> EngineState {
        var s = KW.trackingState(KW.cfg(hint: .bus), p: p, d: 30_000.0, ground: ground, closing: nil, established: false)
        s.movingTimeS = 60.0
        s.movingSamples = 2
        return s
    }

    @Test("U122 preV lifts dead reckoning to the measured ground speed while LOST before established (a)–(e)")
    func u122() throws {
        // (a) ground 20: lift, cvDr 20/1.2, GPS_LOST at about N + 621 s (T10.5: N + 5 301 s).
        var a = KDriver(from: Self.preState(20.0))
        let raOpt = Self.doze(&a, "U122 a")
        let ra = try #require(raOpt)
        let lostA = try #require(ra.steps.first { Self.hasGpsLost($0) })
        let ea = Self.estimateOf(lostA.state)
        #expect(!ea.established)
        #expect(ea.lift, "a lift")
        #expect(ea.cvDr == 20.0 / 1.2)
        #expect(ea.vDr == (20.0 / 1.2) * 1.2)
        let aa = try #require(Self.firstAlarm(ra.steps))
        #expect(aa.reason == .gpsLost)
        #expect(aa.atMs - Self.S == Self.u122aAlarmMs, "a: pinned")
        #expect((Double(aa.atMs - Self.S) / 1000.0 - 621.0).magnitude <= 5.0)
        // (b) ground 4: preV 3.33 < hint 4.63, no lift; W rings at about N + 4 126 s.
        var b = KDriver(from: Self.preState(4.0))
        let rbOpt = Self.doze(&b, "U122 b")
        let rb = try #require(rbOpt)
        let lostB = try #require(rb.steps.first { Self.hasGpsLost($0) })
        #expect(!Self.estimateOf(lostB.state).lift, "b lift")
        let ab = try #require(Self.firstAlarm(rb.steps))
        #expect(ab.reason == .gpsLost)
        #expect(ab.atMs - Self.S == Self.u122bAlarmMs, "b: pinned")
        #expect((Double(ab.atMs - Self.S) / 1000.0 - 4_126.0).magnitude <= 5.0)
        // (c) as (a), GPS still OK at N + 30 s: v = hint, no lift.
        var cd = KDriver(from: Self.preState(20.0))
        let c = cd.tick(30)
        #expect(c.view.gps == .ok)
        let ec = Self.estimateOf(c.state)
        #expect(!ec.lift)
        #expect(ec.v == 20.0 / 3.6)
        // (d) lostSpeedGuardUpdates 0, (e) ground nil: no lift.
        for (tag, st) in [("d", Self.preState(20.0, KW.params(#"{"lostSpeedGuardUpdates": 0}"#))), ("e", Self.preState(nil))] {
            var x = KDriver(from: st)
            let rOpt = Self.doze(&x, "U122 \(tag)")
            let r = try #require(rOpt)
            let lost = try #require(r.steps.first { Self.hasGpsLost($0) })
            #expect(!Self.estimateOf(lost.state).lift, "\(tag) lift")
        }
        T106Log.shared.add("U122", "U122 a \(KW.kd(Double(aa.atMs - Self.S) / 1000.0)) s, b \(KW.kd(Double(ab.atMs - Self.S) / 1000.0)) s\n")
    }

    // MARK: - U123 c–i: slow-vehicle net (C27)

    struct Fx {
        let y: Double
        let east: Double
        let acc: Double
        var spd: Double? = nil
    }

    /// stand() of U114 generalised: route along the meridian `east` m east of the destination, start 3 km south (y = 3 000), y
    /// decreasing northwards; `y(t)` gives the position at t; `fix(k, t, y)` the delivered fix (nil = none) every `everyS` s.
    /// Returns every Step (t, Step) until the first Alarm or `maxS`.
    static func pass(_ config: TripConfig, _ east: Double, _ v: Double, _ everyS: Int, _ y: (Int) -> Double, maxS: Int = 7_200,
                     params: EngineParams = .defaults, fix: ((Int, Int, Double) -> Fx?)? = nil) -> [(Int, Step)] {
        let p0 = KW.jitter(KW.pointOnMeridian(3_000.0), east, 0.0)
        let d0 = KW.distToDest(p0)
        let l = FixRec(fixAtMs: S, lat: p0.lat, lng: p0.lng, accM: 8.0, d: d0, groundSample: nil)
        let base = KW.trackingState(config, p: params, now: S, d: d0, ground: v, closing: v * 0.95, lastFixAt: S)
        var st = KW.withLast(base, l, dStartPlus: 5_000.0)
        var out: [(Int, Step)] = []
        var t = 0
        var k = 0
        while t < maxS {
            t += everyS
            k += 1
            let yy = y(t)
            let moving = (yy - y(t - everyS)).magnitude > 0.0
            let fOpt: Fx? = fix != nil ? fix!(k, t, yy) : Fx(y: yy, east: east, acc: 8.0)
            guard let f = fOpt else { continue }
            let pt = KW.jitter(KW.pointOnMeridian(f.y), f.east, 0.0)
            let at = S + Int64(t) * 1000
            let s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: pt.lat, lng: pt.lng, accuracyM: f.acc,
                                                                   speedMps: f.spd ?? (moving ? v : 0.0))))
            st = s.state
            out.append((t, s))
            if !s.events.alarms.isEmpty { break }
        }
        return out
    }

    /// (p) geometry: 2 m/s, stops `stopNorth` m north of the closest point.
    static func yStop(_ stopNorth: Double, _ v: Double = 2.0) -> (Int) -> Double { { t in Swift.max(3_000.0 - v * Double(t), -stopNorth) } }

    static func yForD(_ d: Double, _ east: Double = 800.0) -> Double { -(d * d - east * east).squareRoot() }

    static func alarmOf(_ steps: [(Int, Step)]) -> (Int, TripEvent.Alarm)? {
        for (t, s) in steps { if let a = s.events.alarms.first { return (t, a) } }
        return nil
    }

    @Test("U123 c d d2 poor fixes never set the mark, the mark comes with the first good fix")
    func u123cdd2() throws {
        // (c) U114 x, y (O1 repro) are unchanged with the defaults (T10.6 on): DISTANCE at 780 s / 480 m (pinned there).
        let d500 = KW.cfg(.distance, thr: 500)
        // (d) as (p), every fix acc 80: no good fix, no mark, silent.
        let d = Self.pass(d500, 800.0, 2.0, 5, Self.yStop(2_000.0)) { _, _, yy in Fx(y: yy, east: 800.0, acc: 80.0) }
        #expect(Self.alarmOf(d) == nil, "d: silent")
        #expect(d.allSatisfy { $0.1.state.passAnchorD == nil }, "d: no mark")
        // (d2) acc 80 until 1 800 m north of the closest point, then acc 8 (no stop: interpretation noted in T12.md).
        let d2 = Self.pass(d500, 800.0, 2.0, 5, Self.yStop(10_000.0)) { _, _, yy in Fx(y: yy, east: 800.0, acc: yy > -1_800.0 ? 80.0 : 8.0) }
        let firstGood = try #require(d2.firstIndex { $0.1.state.last!.accM <= 50.0 })
        #expect(d2[..<firstGood].allSatisfy { $0.1.state.passAnchorD == nil }, "d2: mark before the first good fix")
        let g = d2[firstGood].1.state
        #expect(g.passAnchorD != nil && g.dSmooth == g.passAnchorD, "d2: mark = dSmooth at the first good fix")
        let (ta, a) = try #require(Self.alarmOf(d2))
        #expect(a.reason == .passedClosest)
        let ia = try #require(d2.firstIndex { $0.0 == ta })
        let sa = d2[ia].1.state
        let sp = d2[ia - 1].1.state
        #expect(sa.last3[1] - sa.passAnchorD! >= 300.0, "d2: rang without two fixes 300 m above the mark")
        #expect(sp.last3.count < 3 || sp.passAnchorD == nil || sp.last3[1] - sp.passAnchorD! < 300.0 || !(sp.last3[1] < sp.last3[2]),
                "d2: should have rung earlier")
        T106Log.shared.add("U123 d2", "U123 d2: mark \(KW.kdOpt(g.passAnchorD)) at \(d2[firstGood].0) s, PASSED_CLOSEST at \(ta) s\n")
    }

    @Test("U123 e f one fix away from a parked vehicle does not ring, two consecutive ones do")
    func u123ef() throws {
        let d500 = KW.cfg(.distance, thr: 500)
        let stopY = Self.yForD(1_450.0)
        func run(_ outliers: [Int: Double]) -> [(Int, Step)] {
            Self.pass(d500, 800.0, 2.0, 30, { t in Swift.max(3_000.0 - 2.0 * Double(t), stopY) }) { k, _, yy in
                if let o = outliers[k] { return Fx(y: Self.yForD(o), east: 800.0, acc: 15.0, spd: 0.0) }
                return Fx(y: yy, east: 800.0, acc: 8.0, spd: yy > stopY ? 2.0 : 0.0)
            }
        }
        // Parked from k ≈ 140 (t ≈ 4 200 s); outliers at k = 160 (and 161).
        let base = run([:])
        #expect(Self.alarmOf(base) == nil, "e base: silent")
        let mark = try #require(base.last?.1.state.passAnchorD)
        #expect(1_450.0 - mark < 300.0, "e: parked less than 300 m above the mark (\(mark))")
        let e = run([160: 1_950.0])
        #expect(Self.alarmOf(e) == nil, "e: one fix 500 m away rang")
        let f = run([160: 1_850.0, 161: 1_900.0])
        let (tf, af) = try #require(Self.alarmOf(f))
        #expect(af.reason == .passedClosest, "f")
        #expect(tf == 161 * 30, "f: at the second fix away")
        #expect(f.allSatisfy { KW.overshoots($0.1.events).isEmpty })
        T106Log.shared.add("U123 e", "U123 e: mark \(KW.kd(mark)); f: PASSED_CLOSEST at \(tf) s\n")
    }

    @Test("U123 g a REANCHOR clears the mark")
    func u123g() throws {
        let d500 = KW.cfg(.distance, thr: 500)
        // Mark set (about 1 300 m), then three fixes 5 km south at +5, +20, +35 s: IMPLAUSIBLE, IMPLAUSIBLE, REANCHOR.
        let base = Self.pass(d500, 800.0, 2.0, 5, Self.yStop(2_000.0), maxS: 2_100)
        let lastBase = try #require(base.last)
        let st0 = lastBase.1.state
        #expect(st0.passAnchorD != nil, "g: mark set")
        var st = st0
        let tl = lastBase.0
        let far = KW.jitter(KW.pointOnMeridian(5_000.0), 800.0, 0.0)
        var steps: [Step] = []
        for dt in [5, 20, 35] {
            let at = Self.S + Int64(tl + dt) * 1000
            let s = TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: far.lat, lng: far.lng, accuracyM: 8.0,
                                                                   speedMps: 2.0)))
            st = s.state
            steps.append(s)
        }
        #expect(steps[0].state.passAnchorD == st0.passAnchorD, "g: a dropped fix keeps the mark")
        #expect(steps[1].state.passAnchorD == st0.passAnchorD, "g: a dropped fix keeps the mark")
        let re = steps[2].state
        #expect(re.last?.d == re.minD, "g: REANCHOR")
        #expect(re.passAnchorD == nil, "g: mark after REANCHOR")
    }

    @Test("U123 h the mark is the minimum seen, turning back does not ring, moving away again does (pinned)")
    func u123h() throws {
        let d500 = KW.cfg(.distance, thr: 500)
        // Forward at 2 m/s to d = 1 550 (poor fixes until then, so the mark comes late), 5 min back at 0.9 m/s, forward again.
        let y1 = Self.yForD(1_550.0)
        let t1 = KW.ki((3_000.0 - y1) / 2.0)
        let y: (Int) -> Double = { t in
            if t <= t1 { return 3_000.0 - 2.0 * Double(t) }
            if t <= t1 + 300 { return 3_000.0 - 2.0 * Double(t1) + 0.9 * Double(t - t1) }
            return 3_000.0 - 2.0 * Double(t1) + 0.9 * 300.0 - 2.0 * Double(t - t1 - 300)
        }
        let steps = Self.pass(d500, 800.0, 2.0, 5, y) { _, t, yy in
            Fx(y: yy, east: 800.0, acc: t < t1 ? 80.0 : 8.0, spd: (t1 + 1)...(t1 + 300) ~= t ? 0.9 : 2.0)
        }
        let (ta, a) = try #require(Self.alarmOf(steps))
        #expect(a.reason == .passedClosest)
        #expect(ta > t1 + 300, "h: rang at \(ta) s while turning back")
        // The mark only goes down while it exists, and equals the minimum dSmooth of the good fixes since it was set.
        var seen: Double? = nil
        var first: Double? = nil
        for (_, s) in steps {
            guard let m = s.state.passAnchorD else {
                seen = nil
                continue
            }
            let ds = s.state.dSmooth!
            let good = s.state.last!.accM <= 50.0
            if let sn = seen { seen = good ? Swift.min(sn, ds) : sn } else { seen = ds }
            #expect(seen == m, "h: mark is not the minimum seen")
            if first == nil { first = m }
        }
        let atAlarm = try #require(steps.last).1.state
        let markAtAlarm = try #require(atAlarm.passAnchorD)
        let firstMark = try #require(first)
        #expect(markAtAlarm < firstMark - 100.0, "h: the turn back lowered the mark (\(firstMark) → \(markAtAlarm))")
        #expect(atAlarm.last3[1] - markAtAlarm >= 300.0)
        #expect(ta == Self.u123hAlarmS, "h: pinned")
        T106Log.shared.add("U123 h", "U123 h: first mark \(KW.kd(firstMark)), mark at alarm \(KW.kd(markAtAlarm)), PASSED_CLOSEST at \(ta) s\n")
    }

    @Test("U123 i a fake minD from one outlier then a parked vehicle with GNSS jitter never rings, 400 runs")
    func u123i() {
        // The designer's first row said DISTANCE 500; with minD lowered to 400 m by the outlier, dSmooth = 400 <= 500 rings DISTANCE at
        // the outlier itself, so the net is never reached. DISTANCE 200 keeps the geometry (standing 1 500 m, fake minD 400 m)
        // without a mode alarm (D3, accepted by the designer).
        let config = KW.cfg(.distance, thr: 200)
        var rings = 0
        var maxRise = -Double.infinity
        var bad: [String] = []
        var runs = 0
        for seed in Int64(1)...200 {
            for every in [5, 30] {
                var r = Mix(seed &* 1_000_003 &+ Int64(every))
                var e = KDriver(start: config)
                let tStand = KW.ki((20_000.0 - 1_500.0) / 12.0)
                var t = 0
                var outlierDone = false
                var minDAfter: Double? = nil
                while t < tStand + 1_800 {
                    t += every
                    let standing = t >= tStand
                    let d = standing ? 1_500.0 : 20_000.0 - 12.0 * Double(t)
                    let outT = tStand + 300
                    let s: Step
                    if standing && !outlierDone && t >= outT {
                        outlierDone = true
                        s = e.fix(t, 400.0, acc: 15.0, spd: 0.0)
                        minDAfter = s.state.minD
                    } else if standing && every == 5 && !outlierDone && t > outT - 30 {
                        continue   // 25 s without a fix before the outlier so that it is plausible (as O1c)
                    } else if standing {
                        let dd = d + r.dbl(-50.0, 50.0)
                        let east = r.dbl(-50.0, 50.0)
                        s = e.fix(t, dd, acc: 50.0, spd: 0.0, eastM: east)
                    } else {
                        s = e.fix(t, d, spd: 12.0)
                    }
                    let st = s.state
                    if let m = st.passAnchorD, st.last3.count == 3 { maxRise = Swift.max(maxRise, st.last3[1] - m) }
                    let pass = !KW.overshoots(s.events).isEmpty
                        || s.events.alarms.contains { $0.reason == .passedClosest || $0.reason == .overshoot }
                    if pass {
                        rings += 1
                        bad.append("seed \(seed) every \(every) t=\(t) \(s.events)")
                        break
                    }
                    if !s.events.alarms.isEmpty {
                        rings += 1
                        bad.append("seed \(seed) every \(every) t=\(t) other alarm \(s.events.alarms)")
                        break
                    }
                }
                #expect(((minDAfter ?? 0.0) - 400.0).magnitude <= 1.0, "i: the outlier lowered minD (seed \(seed) every \(every): \(String(describing: minDAfter)))")
                runs += 1
            }
        }
        Report.shared.write("unit/u123-i-jitter.txt",
                            "runs=\(runs) rings=\(rings) max(last3[1] - passAnchorD)=\(maxRise.isFinite ? KW.kd(maxRise) : "-Infinity")\n\(bad.prefix(20).joined(separator: "\n"))\n")
        #expect(runs == 400)
        #expect(rings == 0, "\(bad.prefix(5).joined(separator: "\n"))")
    }

    // MARK: - U124: snapshot key (C28)

    @Test("U124 passAnchorD is written right after minDChord, round-trips, a missing key reads nil and a wrong type fails")
    func u124() throws {
        let anchors: [Double?] = [nil, 1_304.25, 0.1, Double.leastNonzeroMagnitude]
        for anchor in anchors {
            var st = KW.trackingState()
            st.minD = 1234.5
            st.minDChord = true
            st.passAnchorD = anchor
            let json = TripEngine.encodeSnapshot(st)
            // Swift writes the shortest round-trip digits (`description`); Kotlin writes `Double.toString` (5e-324 → 4.9E-324).
            let lit = anchor.map { "\($0)" } ?? "null"
            #expect(json.contains("\"minDChord\":true,\"passAnchorD\":\(lit),\"last3\""), "\(json)")
            #expect(try TripEngine.decodeSnapshot(json) == st)
            let without = json.replacingOccurrences(of: ",\"passAnchorD\":\(lit)", with: "")
            #expect(!without.contains("passAnchorD"))
            var expected = st
            expected.passAnchorD = nil
            #expect(try TripEngine.decodeSnapshot(without) == expected)
            for wrong in ["\"1\"", "true"] {
                let w = json.replacingOccurrences(of: "\"passAnchorD\":\(lit)", with: "\"passAnchorD\":\(wrong)")
                #expect(throws: SnapshotError(rule: "passAnchorD invalid")) { try TripEngine.decodeSnapshot(w) }
            }
        }
    }
}
