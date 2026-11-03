import Testing
@testable import Trip

/// Tester T13.2 (docs/test-reports/T13.2.md): Kotlin ↔ Swift parity checks added in BOTH engines with identical inputs (mirror of
/// app/android/core-trip/src/test/kotlin/app/napstop/core/trip/unit/TesterT132ParityTest.kt). Every test writes
/// `<report>/unit/t132p-*.txt` in the Kotlin format; the Kotlin files must be byte-identical.
///  - Review T13.2 minor #1: chordProjection bits pinned (U113 cases + chords with Δlng ≠ 0 and destLat ≠ 0).
///  - Review T13.2 minor #2: the round-3d guard of `notCloser` kept alive after round 3e.
///  - Snapshot `minDChord`: round trip, missing / null / string / number / duplicate key, restore paths.
///  - Parity fuzz: per-Step transcript with a hash of the snapshot (Doubles canonicalised by bit pattern).
@Suite("TesterT132ParityTests")
struct TesterT132ParityTests {
    static let S = KW.S
    static let n = KW.S + 3_600_000

    static func bits(_ x: Double?) -> String {
        guard let x else { return "null" }
        let h = String(x.bitPattern, radix: 16)
        return String(repeating: "0", count: 16 - h.count) + h
    }

    static func kd(_ x: Double?) -> String { x.map { KW.kd($0) } ?? "null" }
    static func ks<T>(_ x: T?) -> String { x.map { "\($0)" } ?? "null" }

    static func pt(_ south: Double, _ east: Double = 0.0) -> KW.LatLng {
        let p0 = KW.pointOnMeridian(south)
        return east == 0.0 ? p0 : KW.jitter(p0, east, 0.0)
    }

    static func rec(_ p: KW.LatLng) -> FixRec { KW.rec(p, at: n) }

    static func raw(_ lat: Double, _ lng: Double) -> FixRec { FixRec(fixAtMs: n, lat: lat, lng: lng, accM: 8.0, d: 1.0, groundSample: nil) }

    static func dest(_ lat: Double, _ lng: Double) -> TripConfig {
        TripConfig(tripId: "trip-1", destLat: lat, destLng: lng, mode: .distance, distanceThresholdM: 1000, timeThresholdMin: nil,
                   preAlertEnabled: true, vehicleHint: .train)
    }

    // MARK: - (1) chordProjection bits (review minor #1)

    /// Kotlin bits (JDK 17, T12.2 engine `bb8248d`); the Kotlin mirror pins the same string.
    static let pinnedChord = [
        "a u=3fecf2d97e62bf09 dist=0000000000000000 closest=0000000000000000\n",
        "b u=3ff4000000000000 dist=0000000000000000 closest=null\n",
        "c u=null dist=null closest=null\n",
        "d u=3fe0000000000000 dist=409770007918305b closest=409770007918305b\n",
        "e u=3fe001a34350e41a dist=4058feb8ec2ab14e closest=4058feb8ec2ab14e\n",
        "f u=null dist=null closest=null\n",
        "g u=3ff0000000000000 dist=40976ffffffff428 closest=null\n",
        "h u=3feffffff411cd14 dist=40976ffffffff428 closest=40976ffffffff428\n",
        "i u=3fe69d6c196f69fa dist=40a0ee53f81b2d8b closest=40a0ee53f81b2d8b\n",
        "j u=3fe1eb4d8fbfc400 dist=40b09237d523077a closest=40b09237d523077a\n",
        "k u=3fe23f11e7be4d3f dist=409302f7bb7c3470 closest=409302f7bb7c3470\n",
        "l u=3fe123b05308a4a3 dist=409ec287f5a0d2a0 closest=409ec287f5a0d2a0\n",
        "m u=3fdc7955ee25ea19 dist=401174ca7dfaa036 closest=401174ca7dfaa036\n",
        "n u=3fda287f442db822 dist=408cf693820526de closest=408cf693820526de\n",
    ].joined()

    @Test("T132P chord bits pinned for the U113 cases and chords with dLng != 0 and destLat != 0 (= Kotlin)")
    func chordBits() {
        let east = 1_500.0 / KW.K
        let c0 = KW.cfg()
        let lV = FixRec(fixAtMs: Self.n, lat: -0.045, lng: KW.destLng + east, accM: 8.0, d: 1.0, groundSample: nil)
        let cases: [(String, TripConfig, FixRec, FixRec)] = [
            ("a", c0, Self.rec(Self.pt(29_410.0)), Self.rec(Self.pt(-3_100.0))),
            ("b", c0, Self.rec(Self.pt(5_000.0)), Self.rec(Self.pt(1_000.0))),
            ("c", c0, Self.rec(Self.pt(3_000.0)), Self.rec(Self.pt(3_000.0))),
            ("d", c0, Self.rec(Self.pt(5_000.0, 1_500.0)), Self.rec(Self.pt(-5_000.0, 1_500.0))),
            ("e", c0, Self.rec(Self.pt(5_000.0, 200.0)), Self.rec(Self.pt(-5_000.0))),
            ("f", c0, Self.rec(Self.pt(5_000.0)), FixRec(fixAtMs: Self.n, lat: 0.01, lng: KW.destLng + 181.0, accM: 8.0, d: 1.0, groundSample: nil)),
            ("g", c0, lV, FixRec(fixAtMs: Self.n, lat: 0.0, lng: KW.destLng + east, accM: 8.0, d: 1.0, groundSample: nil)),
            ("h", c0, lV, FixRec(fixAtMs: Self.n, lat: 1e-9, lng: KW.destLng + east, accM: 8.0, d: 1.0, groundSample: nil)),
            ("i", Self.dest(21.0, 105.8), Self.raw(20.90, 105.70), Self.raw(21.02, 105.86)),
            ("j", Self.dest(21.0, 105.8), Self.raw(21.30, 105.95), Self.raw(20.80, 105.62)),
            ("k", Self.dest(-33.9, 151.2), Self.raw(-34.05, 151.05), Self.raw(-33.80, 151.33)),
            ("l", Self.dest(59.9, 10.75), Self.raw(59.70, 10.40), Self.raw(60.05, 11.10)),
            ("m", Self.dest(21.0, 105.8), Self.raw(21.0005, 105.7990), Self.raw(20.9993, 105.8012)),
            ("n", Self.dest(-45.25, -170.5), Self.raw(-45.40, -170.20), Self.raw(-45.05, -170.95)),
        ]
        let text = cases.map { k, c, l, f in
            let p = OvershootDetector.chordProjection(l.lat, l.lng, f.lat, f.lng, c)
            return "\(k) u=\(Self.bits(p?.u)) dist=\(Self.bits(p?.distM)) closest=\(Self.bits(OvershootDetector.chordClosest(l, f, c)))\n"
        }.joined()
        Report.shared.write("unit/t132p-chord.txt", text)
        #expect(text == Self.pinnedChord)
    }

    // MARK: - (2) round-3d guard after round 3e (review minor #2)

    /// U114 (i) builder: fix before the gap 20 km south, 700 s gap, GPS LOST.
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

    /// Kotlin `names(step)`.
    static func names(_ s: Step) -> String {
        "[" + s.events.map { e -> String in
            switch e {
            case let .alarm(a): return "alarm:\(a.reason.jsonName):\(a.ringNow)"
            case let .overshoot(o): return "overshoot:\(o.pastM)"
            case let .gpsLost(g): return "gpsLost:\(g.cause.jsonName)"
            case let .fallbackAlarmChanged(f): return "fallbackAlarmChanged:\(Self.ks(f.fallbackAtMs.map { $0 - Self.S })):\(f.cause.jsonName)"
            default: return e.fixtureName
            }
        }.joined(separator: ",") + "]"
    }

    static func guardRun(_ outlierM: Double, _ tag: String, _ log: inout String) -> [Step] {
        let d0 = (2_000.0 * 2_000.0 + 500.0 * 500.0).squareRoot()
        var s = bypassState()
        var out: [Step] = []
        for i in 0..<20 {
            let r = d0 - 150.0 * Double(i) - (i == 1 ? outlierM : 0.0)
            let k = r / d0
            let p = pt(-2_000.0 * k, 500.0 * k)
            let at = n + 30_000 * Int64(i)
            let step = TripEngine.reduce(s, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: 8.0, speedMps: 5.0)))
            out.append(step)
            s = step.state
            log += "\(tag) \(i) t=\((at - n) / 1000) d=\(kd(s.dSmooth)) minD=\(kd(s.minD)) chord=\(s.minDChord) "
                + "last3=[\(s.last3.map { KW.kd($0) }.joined(separator: ", "))] stop=\(s.stopStartMs != nil) ev=\(names(step))\n"
            if !step.events.alarms.isEmpty { break }
        }
        return out
    }

    @Test("T132P round-3d guard still blocks a wrong-wording OVERSHOOT after a chord when one accepted outlier fakes lag-2 (= Kotlin)")
    func guard3d() throws {
        var log = ""
        let g = Self.guardRun(600.0, "guard600", &log)
        let m0 = try #require(g[0].state.minD)
        #expect(g[0].state.minDChord && m0 > 400.0 && m0 < 500.0, "chord fix: \(m0)")
        let s3 = g[3].state
        let l3 = s3.last3
        let minD = try #require(s3.minD)
        // Every other condition of the standing term holds at fix 3: only the guard blocks.
        #expect(s3.minDChord && s3.stopStartMs == nil && l3.count == 3 && l3[2] >= l3[0], "fix 3 state \(l3)")
        #expect(try #require(s3.dSmooth) - minD >= 1_000.0 && minD < 1_000.0)
        #expect(try #require(l3.min()) - minD < 1_000.0)
        #expect(!g.contains { KW.hasOvershoot($0) }, "no Overshoot")
        let a = try #require(g.last?.events.alarms.first)
        #expect(a.reason == .distance && a.ringNow && (g.last?.state.dSmooth ?? .infinity) <= 1_000.0)
        // Control (measured, pinned): an outlier only 400 m closer passes the guard → wrong-wording OVERSHOOT at fix 3 (RK20 a family).
        let c = Self.guardRun(400.0, "control400", &log)
        Report.shared.write("unit/t132p-guard3d.txt", log)
        #expect(c.last?.events.alarms.first?.reason == .overshoot)
        #expect(c.last?.state.nowMs == Self.n + 90_000)
    }

    // MARK: - (3) snapshot minDChord: adversarial decode, restore paths

    static func reproState() -> EngineState {
        KW.trackingState(KW.cfg(.distance, thr: 1000), now: n - 1_000, startedAt: n - 3_000_000, d: 11_800.0 + 10.0 * 1_761, ground: 10.0,
                         closing: 10.0, gps: .lost, lastFixAt: n - 1_761_000, tier: .dense, maxTripS: 14_400,
                         fallback: FallbackState(targetAtMs: n + 29_000, emittedAtMs: n - 600_000, status: .confirmed,
                                                 confirmedAtMs: n - 599_000, resync: false, near: true))
    }

    static func fixAt(_ st: EngineState, _ south: Double, _ at: Int64, _ spd: Double?) -> Step {
        let p = pt(south)
        return TripEngine.reduce(st, .locationFix(LocationFix(atMs: at, fixAtMs: at, lat: p.lat, lng: p.lng, accuracyM: 8.0, speedMps: spd)))
    }

    static func replace(_ s: String, _ a: String, _ b: String) -> String { s.split(separator: a, omittingEmptySubsequences: false).joined(separator: b) }

    @Test("T132P snapshot minDChord adversarial decode and restore paths (= Kotlin)")
    func snapshotAdversarial() throws {
        var out = ""
        let st = Self.fixAt(Self.reproState(), -3_100.0, Self.n, 0.0).state
        #expect(st.minDChord, "chord flag")
        let enc = TripEngine.encodeSnapshot(st)
        out += "enc \(enc)\n"
        let key = "\"minDChord\":true"
        var moved = Self.replace(enc, key + ",", "")
        moved.removeLast()
        moved += ",\"minDChord\":true}"
        let variants: [(String, String)] = [
            ("orig", enc),
            ("missing", Self.replace(enc, key + ",", "")),
            ("false", Self.replace(enc, key, "\"minDChord\":false")),
            ("null", Self.replace(enc, key, "\"minDChord\":null")),
            ("string", Self.replace(enc, key, "\"minDChord\":\"true\"")),
            ("number", Self.replace(enc, key, "\"minDChord\":1")),
            ("upper", Self.replace(enc, key, "\"minDChord\":TRUE")),
            ("spaces", Self.replace(enc, key, "\"minDChord\" : true")),
            ("moved", moved),
            ("dupFalseAfter", Self.replace(enc, key, key + ",\"minDChord\":false")),
            ("dupTrueAfter", Self.replace(enc, key, "\"minDChord\":false," + key)),
            ("array", Self.replace(enc, key, "\"minDChord\":[true]")),
        ]
        var decoded: [String: EngineState] = [:]
        for (name, json) in variants {
            do {
                let d = try TripEngine.decodeSnapshot(json)
                decoded[name] = d
                out += "\(name) ok flag=\(d.minDChord) sameState=\(d == st) reEnc=\(TripEngine.encodeSnapshot(d) == enc)\n"
            } catch {
                out += "\(name) error \(error)\n"
            }
        }
        let target = st.fallback.targetAtMs
        let infos: [(String, RestoreInfo)] = [
            ("PENDING", RestoreInfo(status: .pending)),
            ("MISSING", RestoreInfo(status: .missing)),
            ("UNKNOWN", RestoreInfo(status: .unknown)),
            ("RANG", RestoreInfo(status: .rang, firedAtMs: target ?? Self.n)),
            ("DISMISSED", RestoreInfo(status: .dismissed, firedAtMs: target ?? Self.n, dismissedAtMs: Self.n + 2_000)),
        ]
        for src in ["orig", "missing"] {
            let base = try #require(decoded[src])
            for (iname, info) in infos {
                let r = TripEngine.restore(base, nowMs: Self.n + 2_000, info: info)
                var s = r.state
                let line = "restore \(src) \(iname) ev=\(Self.names(r)) ph=\(r.view.phase.jsonName) flag=\(s.minDChord)"
                var first: String? = r.events.alarms.isEmpty ? nil : "restore"
                var i = 1
                while first == nil && i <= 40 && s.phase != .ended {
                    let step = Self.fixAt(s, -3_100.0, Self.n + 5_000 * Int64(i), 0.0)
                    s = step.state
                    if !step.events.alarms.isEmpty { first = "fix\(i) \(Self.names(step))" }
                    i += 1
                }
                out += line + " first=\(first ?? "null")\n"
            }
        }
        Report.shared.write("unit/t132p-snapshot.txt", out)
        #expect(decoded["orig"]?.minDChord == true)
        #expect(decoded["missing"]?.minDChord == false)
        #expect(decoded["null"] == nil && decoded["string"] == nil && decoded["number"] == nil && decoded["array"] == nil)
    }

    // MARK: - (4) parity fuzz (Kotlin `fuzzTrip`)

    struct Rng {
        private var x: UInt64
        init(_ seed: Int64) { x = UInt64(bitPattern: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2468ACE }

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

    struct Route {
        let d0: Double
        let off: Double
        let dx: Double
        let dy: Double
        let base: Double
        var segs: [(Double, Double)] = []

        init(_ r: inout Rng) {
            d0 = r.dbl(3_000.0, 80_000.0)
            off = r.chance(0.5) ? r.dbl(0.0, 300.0) : r.dbl(300.0, 5_000.0)
            let dx0 = r.dbl(-1.0, 1.0)
            let dy0 = r.dbl(-1.0, 1.0)
            base = r.dbl(3.0, 35.0)
            var t = 0.0
            while t < 30_000.0 {
                let moveS = r.dbl(120.0, 2_400.0)
                segs.append((t, base * r.dbl(0.6, 1.4)))
                t += moveS
                if r.chance(0.3) {
                    segs.append((t, 0.0))
                    t += r.dbl(20.0, 900.0)
                }
            }
            let norm = (dx0 * dx0 + dy0 * dy0).squareRoot()
            dx = norm < 1e-6 ? 1.0 : dx0 / norm
            dy = norm < 1e-6 ? 0.0 : dy0 / norm
        }

        func along(_ tS: Double) -> Double {
            var s = -d0
            for i in segs.indices {
                let (s0, v) = segs[i]
                if s0 >= tS { break }
                let s1 = i + 1 < segs.count ? Swift.min(segs[i + 1].0, tS) : tS
                s += v * (s1 - s0)
            }
            return s
        }

        func speedAt(_ tS: Double) -> Double { segs.last { $0.0 <= tS }!.1 }
    }

    /// Kotlin `canon`: every Double token replaced by `d` + its bit pattern.
    static func canon(_ json: String) -> String {
        let c = Array(json.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(c.count)
        var i = 0
        var inStr = false
        func isNumChar(_ b: UInt8) -> Bool { (b >= 48 && b <= 57) || b == 46 || b == 101 || b == 69 || b == 43 || b == 45 }
        while i < c.count {
            let ch = c[i]
            if inStr {
                out.append(ch)
                if ch == 34 { inStr = false }
                i += 1
            } else if ch == 34 {
                inStr = true
                out.append(ch)
                i += 1
            } else if ch == 45 || (ch >= 48 && ch <= 57) {
                var j = i + 1
                while j < c.count && isNumChar(c[j]) { j += 1 }
                let tok = Array(c[i..<j])
                if tok.contains(where: { $0 == 46 || $0 == 101 || $0 == 69 }) {
                    let d = Double(String(decoding: tok, as: UTF8.self))!
                    out.append(100)
                    out.append(contentsOf: Array(bits(d).utf8))
                } else {
                    out.append(contentsOf: tok)
                }
                i = j
            } else {
                out.append(ch)
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func fnv(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        let x = String(h, radix: 16)
        return String(repeating: "0", count: 16 - x.count) + x
    }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    static func fuzzTrip(_ seed: Int64, _ out: inout String) throws {
        var r = Rng(seed)
        let mode = AlarmMode.allCases[r.int(3)]
        let thr: Int? = mode == .distance || r.chance(0.3) ? 200 + r.int(9801) : nil
        let thrMin: Int? = mode == .time || (mode != .distance && r.chance(0.3)) ? 5 + r.int(56) : nil
        let preAlert = r.chance(0.7)
        let hint = VehicleKind.allCases[r.int(4)]
        let destLat = r.chance(0.4) ? 0.0 : r.dbl(-60.0, 60.0)
        let destLng = r.dbl(-170.0, 170.0)
        let config = TripConfig(tripId: "px-\(seed)", destLat: destLat, destLng: destLng, mode: mode, distanceThresholdM: thr,
                                timeThresholdMin: thrMin, preAlertEnabled: preAlert, vehicleHint: hint)
        let route = Route(&r)
        let gapA: Double
        switch r.int(3) {
        case 0: gapA = Double.greatestFiniteMagnitude
        case 1: gapA = r.dbl(0.0, 1.3) * route.d0 / route.base
        default: gapA = route.d0 / route.base - r.dbl(60.0, 900.0)
        }
        let gapB = gapA + r.dbl(60.0, 3_000.0)
        var level = 20 + r.int(81)
        let steps = 150 + r.int(350)
        let k = Geo.kMetresPerDegLat
        let cd = Geo.cosDeg(destLat)
        var step = try TripEngine.start(config: config, params: .defaults, nowMs: S)
        var t = S
        var lastFb: Int64? = step.state.fallback.targetAtMs
        out += "trip \(seed) \(mode.jsonName) \(ks(thr))/\(ks(thrMin)) \(preAlert) \(hint.jsonName) dest=\(bits(destLat)),\(bits(destLng)) steps=\(steps)\n"
        func emit(_ i: Int, _ code: String, _ s: Step) {
            let v = s.view
            out += "\(i) \(code) \(t - S) ev=\(names(s)) ph=\(v.phase.jsonName) w=\(ks(v.wakeAtMs.map { $0 - S })) "
                + "p=\(ks(v.predictedAlarmAtMs.map { $0 - S })) f=\(ks(v.fallbackAtMs.map { $0 - S })) "
                + "h=\(fnv(canon(TripEngine.encodeSnapshot(s.state))))\n"
        }
        emit(0, "start", step)
        for i in 1...steps {
            if step.state.phase == .ended { break }
            let s0 = step.state
            let interval = Int64(step.view.samplingPolicy?.intervalS ?? 5) * 1000
            let kk = r.int(100)
            var input: EngineInput?
            var restore: RestoreInfo?
            let code: String
            if kk < 55 {
                t += Swift.max(1, Int64(Double(interval) * r.dbl(0.5, 1.5)))
                let ts = Double(t - S) / 1000.0
                if ts >= gapA && ts < gapB && !r.chance(0.05) {
                    input = .tick(atMs: t)
                    code = "G"
                } else {
                    let sa = route.along(ts)
                    var x = sa * route.dx - route.off * route.dy
                    var y = sa * route.dy + route.off * route.dx
                    if r.chance(0.04) {
                        x += r.dbl(-3_000.0, 3_000.0)
                        y += r.dbl(-3_000.0, 3_000.0)
                    }
                    let acc = r.chance(0.08) ? r.dbl(60.0, 2_000.0) : r.dbl(3.0, 30.0)
                    let age = r.chance(0.05) ? Int64(r.int(200_000)) : Int64(r.int(1_500))
                    let spd: Double? = r.chance(0.3) ? nil : route.speedAt(ts) * r.dbl(0.9, 1.1)
                    input = .locationFix(LocationFix(atMs: t, fixAtMs: t - age, lat: destLat + y / k, lng: destLng + x / (k * cd),
                                                     accuracyM: acc, speedMps: spd))
                    code = "F"
                }
            } else if kk < 70 {
                if let w = step.view.wakeAtMs, w > t { t = w } else { t = t + 1 + Int64(r.int(60_000)) }
                input = .tick(atMs: t)
                code = "T"
            } else if kk < 73 {
                input = .tick(atMs: t - Int64(r.int(20_000)))
                code = "t"
            } else if kk < 77 {
                t += Int64(r.int(5_000))
                level = Swift.max(1, level - r.int(3))
                input = .batterySample(atMs: t, levelPct: level, charging: r.chance(0.15))
                code = "B"
            } else if kk < 83 {
                let at: Int64
                if let lf = lastFb, r.chance(0.8) { at = lf } else { at = t + Int64(r.int(3_600_000)) }
                input = .fallbackScheduled(atMs: t, fallbackAtMs: at, ok: r.chance(0.85))
                code = "S"
            } else if kk < 86 {
                // The OS alarm fires at its own time (due within 60 s, or the app sleeps until then), otherwise a plain Tick.
                if let fb = s0.fallback.targetAtMs, fb <= t + 60_000 || r.chance(0.15) {
                    t = Swift.max(t, fb)
                    input = .fallbackFired(atMs: t, firedAtMs: fb)
                    code = "X"
                } else {
                    t += Int64(r.int(10_000))
                    input = .tick(atMs: t)
                    code = "x"
                }
            } else if kk < 88 {
                input = .alarmSilenced(atMs: t, silencedAtMs: t)
                code = "Q"
            } else if kk < 92 {
                let a: UserActionKind
                switch r.int(6) {
                case 0: a = .dismiss
                case 1: a = .snooze
                case 2: a = .stopTrip
                case 3: a = .batteryMaxSaving
                case 4: a = .batteryAlarmAt5
                default: a = .batteryAlarmEarlier
                }
                input = (a == .dismiss || a == .stopTrip) && !r.chance(0.2) ? .tick(atMs: t) : .userAction(atMs: t, action: a)
                code = "U"
            } else if kk < 95 {
                let cause: AvailabilityCause
                switch r.int(3) {
                case 0: cause = .available
                case 1: cause = .permissionRevoked
                default: cause = .servicesOff
                }
                input = .locationAvailability(atMs: t, cause: cause)
                code = "A"
            } else {
                t += Int64(r.int(600_000))
                switch r.int(5) {
                case 0: restore = RestoreInfo(status: .rang, firedAtMs: t - Int64(r.int(60_000)))
                case 1: restore = RestoreInfo(status: .dismissed, firedAtMs: t - Int64(r.int(60_000)), dismissedAtMs: t)
                case 2: restore = RestoreInfo(status: .pending)
                case 3: restore = RestoreInfo(status: .missing)
                default: restore = RestoreInfo(status: .unknown)
                }
                code = "R"
            }
            if let restore {
                step = TripEngine.restore(try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s0)), nowMs: t, info: restore)
            } else {
                step = TripEngine.reduce(s0, input!)
            }
            emit(i, code, step)
            lastFb = step.state.fallback.targetAtMs ?? lastFb
        }
        out += "end \(step.view.phase.jsonName) \(ks(step.view.outcome?.jsonName)) alarm=\(ks(step.state.alarm.reason?.jsonName))\n"
    }

    @Test("T132P parity fuzz 2000 random trips (chords at destLat != 0, outliers, wake-ups, restores) per-Step transcript (= Kotlin)")
    func parityFuzz() throws {
        var out = ""
        for seed in Int64(9_001)...11_000 { try Self.fuzzTrip(seed, &out) }
        Report.shared.write("unit/t132p-fuzz.txt", out)
        let lines = out.utf8.reduce(0) { $1 == 10 ? $0 + 1 : $0 }
        #expect(lines > 50_000, "fuzz too small: \(lines)")
    }

    @Test("T132P canon/fnv self-check (Kotlin and Swift print Doubles differently; bit patterns do not)")
    func canonSelfCheck() {
        #expect(Self.canon("{\"a\":1.0E7,\"b\":\"x-1.5\",\"c\":12,\"d\":-0.5}") == Self.canon("{\"a\":10000000.0,\"b\":\"x-1.5\",\"c\":12,\"d\":-0.5}"))
        #expect(Self.canon("{\"c\":12}") == "{\"c\":12}")
        #expect(Self.fnv("") == "cbf29ce484222325" && Self.fnv("a") == "af63dc4c8601ec8c")
    }
}
