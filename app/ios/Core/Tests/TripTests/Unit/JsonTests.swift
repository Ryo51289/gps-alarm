import Testing
@testable import Trip

@Suite("MiniJsonTests")
struct MiniJsonTests {
    @Test("S01 valid JSON: nested objects/arrays, é, escaped slash, surrogate pair, numbers keep their lexeme, asDouble bit-exact")
    func s01() throws {
        let text = #"{"a":{"b":[1,2,{"c":"\u00e9\/x"}]},"e":"😀\ud83d\ude00","n":[-0.0,1e-05,5e-324,1.7976931348623157e308,0,-12]}"#
        let v = try MiniJson.parse(text)
        #expect(v["a"]?["b"]?.arrayValue?.count == 3)
        #expect(v["a"]?["b"]?.arrayValue?[2]["c"]?.stringValue == "é/x")
        #expect(v["e"]?.stringValue == "😀😀")
        let n = v["n"]!.arrayValue!
        #expect(n.map { if case let .number(l) = $0 { return l } else { return "" } } ==
                ["-0.0", "1e-05", "5e-324", "1.7976931348623157e308", "0", "-12"])
        #expect(n[0].asDouble()!.bitPattern == (-0.0).bitPattern)
        #expect(n[1].asDouble()!.bitPattern == (1e-05).bitPattern)
        #expect(n[2].asDouble()!.bitPattern == Double.leastNonzeroMagnitude.bitPattern)
        #expect(n[3].asDouble()! == Double.greatestFiniteMagnitude)
        #expect(n[4].asLongExact() == 0 && n[5].asLongExact() == -12 && n[1].asLongExact() == nil)
        #expect(try MiniJson.parse(" [ ] ") == .array([]))
        // 64 levels are fine.
        _ = try MiniJson.parse(String(repeating: "[", count: 64) + String(repeating: "]", count: 64))
    }

    @Test("S02 invalid JSON is rejected; message has rule + offset, never content")
    func s02() {
        let bad = ["\u{FEFF}{}", "[1,]", "{\"a\":1,}", "/*c*/{}", "NaN", "Infinity", "+1", "01", "1.", ".5", "0x10",
                   #""\ud800""#, #""\udc00x""#, "\"a\u{01}b\"", String(repeating: "[", count: 65) + String(repeating: "]", count: 65),
                   "{} {}", "", "{\"secret\":tru}", "1e", "-"]
        for b in bad {
            do {
                _ = try MiniJson.parse(b)
                Issue.record("accepted: \(b.debugDescription)")
            } catch {
                #expect(error.description.hasPrefix("json: "))
                #expect(!error.description.contains("secret"))
            }
        }
    }

    @Test("S03 duplicate keys: later value wins at the first position (T12 K2)")
    func s03() throws {
        #expect(MiniJson.write(try MiniJson.parse(#"{"a":1,"b":2,"a":3}"#)) == #"{"a":3,"b":2}"#)
        #expect(MiniJson.write(.string("q\"\\\u{01}")) == #""q\"\\\u0001""#)
    }
}

@Suite("SnapshotCodecTests")
struct SnapshotCodecTests {
    /// Deterministic pseudo-random states (U51).
    static func randomState(_ rng: inout SplitMix64, guardCount: Int) -> EngineState {
        var d = EngineDriver(rng.nextInt(2) == 0 ? .distance : .smart, hint: .coach)
        var t = 0.0
        var dist = 20_000 + rng.nextDouble() * 50_000
        for _ in 0..<(5 + rng.nextInt(30)) {
            t += 5
            dist -= 50 + rng.nextDouble() * 40
            d.fix(t, d: dist, acc: 3 + rng.nextDouble() * 20, spd: rng.nextInt(4) == 0 ? nil : 10 + rng.nextDouble() * 10)
        }
        var s = d.state
        s.cvGuard = (0..<guardCount).map { _ in rng.nextDouble() * 30 }
        s.minD = rng.nextInt(3) == 0 ? nil : rng.nextDouble() * 1e5
        s.alarm.snoozeUntilMs = rng.nextInt(2) == 0 ? nil : Int64(rng.nextInt(1_000_000))
        s.battery.levelPct = rng.nextInt(2) == 0 ? nil : rng.nextInt(100)
        s.fallback.near = rng.nextInt(2) == 0
        return s
    }

    static func bitsEqual(_ a: EngineState, _ b: EngineState) -> Bool {
        func fx(_ x: FixRec?, _ y: FixRec?) -> Bool {
            switch (x, y) {
            case (nil, nil): return true
            case let (p?, q?): return p.fixAtMs == q.fixAtMs && Bits.same(p.lat, q.lat) && Bits.same(p.lng, q.lng)
                && Bits.same(p.accM, q.accM) && Bits.same(p.d, q.d) && Bits.same(p.groundSample, q.groundSample)
            default: return false
            }
        }
        return a == b && Bits.same(a.dSmooth, b.dSmooth) && Bits.same(a.dStartM, b.dStartM) && Bits.same(a.minD, b.minD)
            && Bits.same(a.last3, b.last3) && Bits.same(a.ground, b.ground) && Bits.same(a.closing, b.closing)
            && Bits.same(a.movingTimeS, b.movingTimeS) && Bits.same(a.movingDistM, b.movingDistM) && Bits.same(a.cvGuard, b.cvGuard)
            && fx(a.last, b.last) && fx(a.stopAnchor, b.stopAnchor) && a.recent.count == b.recent.count
            && zip(a.recent, b.recent).allSatisfy { fx($0, $1) } && zip(a.rejects, b.rejects).allSatisfy { fx($0, $1) }
            && Bits.same(a.config.destLat, b.config.destLat)
    }

    @Test("U51 encode → decode is bit-identical for 20 deterministic states (cvGuard 0, 1, 2, 5 elements); version 2 fails; unknown keys ignored")
    func u51() throws {
        var rng = SplitMix64(51)
        for i in 0..<20 {
            var s = Self.randomState(&rng, guardCount: [0, 1, 2, 5][i % 4])
            s.minDChord = i % 2 == 0   // T10.5 round 3e: both values
            let json = TripEngine.encodeSnapshot(s)
            let back = try TripEngine.decodeSnapshot(json)
            #expect(Self.bitsEqual(s, back), "state \(i)")
            #expect(TripEngine.encodeSnapshot(back) == json)
        }
        let s = EngineDriver().state
        let json = TripEngine.encodeSnapshot(s)
        #expect(throws: SnapshotError(rule: "unsupported version")) {
            try TripEngine.decodeSnapshot(json.replacingOccurrences(of: "\"snapshotVersion\":1", with: "\"snapshotVersion\":2"))
        }
        let extra = "{\"zzz\":[1,2],\"nested\":{\"x\":null}," + json.dropFirst()
        #expect(try TripEngine.decodeSnapshot(String(extra)) == s)
    }

    @Test("U69 Doubles 0.1, 1/3, 2/3·1e-300, 123456.789, 5e-324, 1.7976931348623157e308 round-trip bit-exact")
    func u69() throws {
        let values = [0.1, 1.0 / 3.0, 2.0 / 3.0 * 1e-300, 123456.789, Double.leastNonzeroMagnitude, 1.7976931348623157e308, -0.0]
        var s = EngineDriver().state
        s.last3 = values
        s.cvGuard = values
        s.movingDistM = values[3]
        for chord in [false, true] {   // T10.5 round 3e: minDChord both values
            s.minDChord = chord
            let back = try TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(s))
            #expect(Bits.same(back.last3, values))
            #expect(Bits.same(back.cvGuard, values))
            #expect(Self.bitsEqual(s, back))
        }
    }

    @Test("U118 minDChord is written right after minD, round-trips, a missing key reads false and a wrong type (string, null) fails")
    func u118() throws {
        for chord in [true, false] {
            var st = TesterT13Tests.t12TrackingState(d: 50_000.0)
            st.minD = 1234.5
            st.minDChord = chord
            let json = TripEngine.encodeSnapshot(st)
            #expect(json.contains("\"minD\":1234.5,\"minDChord\":\(chord),"), "\(json)")
            #expect(try TripEngine.decodeSnapshot(json).minDChord == chord)
            // Named exception to C20: a snapshot without the key (older writer, hand-made fixture) reads false.
            let without = json.replacingOccurrences(of: ",\"minDChord\":\(chord)", with: "")
            #expect(!without.contains("minDChord"))
            var expected = st
            expected.minDChord = false
            #expect(try TripEngine.decodeSnapshot(without) == expected)
            // A present key must be a bool.
            for bad in ["\"\(chord)\"", "null"] {
                let wrong = json.replacingOccurrences(of: "\"minDChord\":\(chord)", with: "\"minDChord\":\(bad)")
                #expect(throws: SnapshotError(rule: "minDChord invalid")) { try TripEngine.decodeSnapshot(wrong) }
            }
        }
    }

    @Test("U51 (T12) missing key / snapshotVersion 0 / \"x\" / malformed → SnapshotError without content")
    func errors() {
        let json = TripEngine.encodeSnapshot(EngineDriver().state)
        let cases = [json.replacingOccurrences(of: "\"nowMs\":", with: "\"nowMsX\":"),
                     json.replacingOccurrences(of: "\"snapshotVersion\":1", with: "\"snapshotVersion\":0"),
                     json.replacingOccurrences(of: "\"snapshotVersion\":1", with: "\"snapshotVersion\":\"x\""),
                     json.replacingOccurrences(of: "\"slow\":false", with: "\"slow\":1"),
                     "{", "[]"]
        for c in cases {
            do {
                _ = try TripEngine.decodeSnapshot(c)
                Issue.record("accepted")
            } catch {
                #expect(error.description.hasPrefix("snapshot: "))
                #expect(!error.description.contains("trip-1"))
            }
        }
    }
}
