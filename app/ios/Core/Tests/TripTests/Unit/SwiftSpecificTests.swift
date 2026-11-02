import Foundation
import Testing
@testable import Trip

@Suite("SwiftSpecificTests")
struct SwiftSpecificTests {
    @Test("S07 every enum: jsonName ↔ init?(jsonName:) round-trips; FallbackStatus.notSet is \"NONE\"; unknown names → nil")
    func s07() {
        func check<T: CaseIterable & Equatable>(_ t: T.Type, _ name: (T) -> String, _ make: (String) -> T?) {
            for c in T.allCases {
                #expect(make(name(c)) == c)
                #expect(name(c) == name(c).uppercased())
            }
            #expect(make("nope") == nil)
            #expect(Set(T.allCases.map(name)).count == T.allCases.count)
        }
        check(AlarmMode.self, \.jsonName, AlarmMode.init(jsonName:))
        check(VehicleKind.self, \.jsonName, VehicleKind.init(jsonName:))
        check(AvailabilityCause.self, \.jsonName, AvailabilityCause.init(jsonName:))
        check(UserActionKind.self, \.jsonName, UserActionKind.init(jsonName:))
        check(AlarmReason.self, \.jsonName, AlarmReason.init(jsonName:))
        check(GpsLostCause.self, \.jsonName, GpsLostCause.init(jsonName:))
        check(FallbackCause.self, \.jsonName, FallbackCause.init(jsonName:))
        check(TripOutcome.self, \.jsonName, TripOutcome.init(jsonName:))
        check(EndReason.self, \.jsonName, EndReason.init(jsonName:))
        check(SamplingTier.self, \.jsonName, SamplingTier.init(jsonName:))
        check(AccuracyLevel.self, \.jsonName, AccuracyLevel.init(jsonName:))
        check(TripPhase.self, \.jsonName, TripPhase.init(jsonName:))
        check(GpsStatus.self, \.jsonName, GpsStatus.init(jsonName:))
        check(FallbackStatus.self, \.jsonName, FallbackStatus.init(jsonName:))
        check(FallbackRestoreStatus.self, \.jsonName, FallbackRestoreStatus.init(jsonName:))
        #expect(FallbackStatus.notSet.jsonName == "NONE")
        #expect(SamplingTier.sparse < .medium && SamplingTier.medium < .dense)
        #expect(AlarmReason.smartSlowDistance.jsonName == "SMART_SLOW_DISTANCE" && UserActionKind.batteryAlarmAt5.jsonName == "BATTERY_ALARM_AT_5")
    }

    @Test("S08 SHA-256 FIPS 180-4 vectors: \"\", \"abc\", 448-bit message, 1 000 000 × a")
    func s08() {
        #expect(Sha256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(Sha256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(Sha256.hex(bytes: [UInt8](repeating: 0x61, count: 1_000_000))
            == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        var s = Sha256()
        for chunk in stride(from: 0, to: 1_000_000, by: 333) { s.update([UInt8](repeating: 0x61, count: min(333, 1_000_000 - chunk))) }
        #expect(s.finalize().map { String(format: "%02x", $0) }.joined() == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test("S09 GPX coach_dn_langco_tunnel: 337 points, sample 0, gap [1175, 1535); train_longstop_nospd has points without spd")
    func s09() throws {
        let t = try LoadedTrace.load("coach_dn_langco_tunnel.expect.json")
        #expect(t.samples.count == 337 && t.file.sampleCount == 337 && t.file.startTime == "2026-03-14T02:00:00Z")
        let s0 = t.samples[0]
        #expect(s0.lat == 16.0549823 && s0.accuracyM == 8.1 && s0.speedMps == 0.17 && s0.index == 0 && s0.t == 0)
        #expect(!t.samples.contains { $0.t >= 1175 && $0.t < 1535 })
        let n = try LoadedTrace.load("train_longstop_nospd.expect.json")
        #expect(n.samples.contains { $0.speedMps == nil })
    }

    @Test("S10 IsoTime: three valid instants; offsets / missing Z rejected")
    func s10() throws {
        #expect(try IsoTime.parseMs("2026-03-14T02:00:00Z") == 1_773_453_600_000)
        #expect(try IsoTime.parseMs("2000-02-29T23:59:59Z") == 951_868_799_000)
        #expect(try IsoTime.parseMs("1970-01-01T00:00:00Z") == 0)
        for bad in ["2026-03-14T02:00:00+07:00", "2026-03-14T02:00:00", "2026-13-14T02:00:00Z", "x"] {
            #expect(throws: (any Error).self) { try IsoTime.parseMs(bad) }
        }
    }

    /// Inserts `"zzUnknown": 1` into the object at `path` (keys / array indices).
    static func inject(_ v: JsonValue, _ path: [String]) -> JsonValue {
        guard let head = path.first else {
            guard case var .object(p) = v else { return v }
            p.append(("zzUnknown", .number("1")))
            return .object(p)
        }
        switch v {
        case var .object(p):
            for i in p.indices where p[i].0 == head { p[i].1 = inject(p[i].1, Array(path.dropFirst())) }
            return .object(p)
        case var .array(a):
            let i = Int(head)!
            a[i] = inject(a[i], Array(path.dropFirst()))
            return .array(a)
        default:
            return v
        }
    }

    @Test("S11 must-understand: unknown key in cases[i], config, config.params, expect[0].window.notBefore, killSweep.earlyFrom, forbidAfter[0].after fails with the key path; unknown key in truth ignored")
    func s11() throws {
        func raw(_ trace: String, _ caseId: String) throws -> (JsonValue, Int) {
            let t = try ExpectModel.parseTrace(try FixturePaths.read(FixturePaths.tracesDir + "/\(trace).expect.json"))
            let i = t.rawCases.firstIndex { $0["id"]?.stringValue == caseId }!
            return (t.rawCases[i], i)
        }
        let (smart, si) = try raw("bus_hn_slow", "smart_floor")
        let (ks, ki) = try raw("train_hn_dh", "distance_1000_killsweep")
        let (fa, fi) = try raw("train_hn_dh", "distance_1000_kill_rang")
        let cases: [(JsonValue, Int, [String], String)] = [
            (smart, si, [], "cases[\(si)].zzUnknown"), (smart, si, ["config"], "cases[\(si)].config.zzUnknown"),
            (smart, si, ["expect", "0", "window", "notBefore"], "cases[\(si)].expect[0].window.notBefore.zzUnknown"),
            (ks, ki, ["killSweep", "earlyFrom"], "cases[\(ki)].killSweep.earlyFrom.zzUnknown"),
            (fa, fi, ["forbidAfter", "0", "after"], "cases[\(fi)].forbidAfter[0].after.zzUnknown"),
        ]
        for (v, i, path, want) in cases {
            do { _ = try ExpectModel.parseCase(Self.inject(v, path), index: i); Issue.record("accepted \(want)") } catch {
                #expect(String(describing: error) == "unknown key \(want)")
            }
        }
        // config.params: unknown parameter name.
        guard case var .object(p) = smart, let ci = p.firstIndex(where: { $0.0 == "config" }), case var .object(cfg) = p[ci].1,
              let pi = cfg.firstIndex(where: { $0.0 == "params" }), case var .object(params) = cfg[pi].1 else { Issue.record("shape"); return }
        params.append(("fooParam", .number("1")))
        cfg[pi].1 = .object(params); p[ci].1 = .object(cfg)
        do { _ = try ExpectModel.parseCase(.object(p), index: si); Issue.record("accepted params") } catch {
            #expect(String(describing: error) == "unknown key cases[\(si)].config.params.fooParam")
        }
        // truth: ignored.
        let text = try FixturePaths.read(FixturePaths.tracesDir + "/bus_hn_slow.expect.json")
        let tree = Self.inject(try MiniJson.parse(text), ["truth"])
        #expect((try? ExpectModel.parseTrace(MiniJson.write(tree))) != nil)
    }

    static func caseJson(_ body: String) throws -> CaseSpec {
        try ExpectModel.parseCase(try MiniJson.parse(body), index: 0)
    }

    @Test("S12 harness configuration errors fail (not skip): rejected params, action while dead, sweep with sparse 182, run anchor never occurs, killSweep without alarm")
    func s12() throws {
        guard let trace = LoadedTrace.named("bus_hn_brt01") else { Issue.record("trace"); return }
        let base = #""id":"x","status":"final","testIds":["TR04"],"expect":[],"forbid":[]"#
        let specs = [
            try Self.caseJson("{\(base),\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"params\":{\"gpsLostMinS\":5}}}"),
            try Self.caseJson("{\(base),\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"kill\":{\"t\":100},\"actions\":[{\"at\":{\"t\":200},\"action\":\"stop\"}]}}"),
            try Self.caseJson("{\(base),\"policyPhaseSweep\":true,\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"params\":{\"samplingSparseIntervalS\":182}}}"),
            try Self.caseJson("{\(base),\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"actions\":[{\"at\":{\"anchor\":\"event:overshoot\",\"offsetS\":5},\"action\":\"dismiss\"}]}}"),
        ]
        for (i, spec) in specs.enumerated() {
            var r = Runner(trace: trace, spec: spec, mode: i == 2 ? "policy-j01" : "all")
            r.runAll()
            let f = Checks.run(r)
            #expect(f.contains { $0.contains("config error") }, "case \(i): \(f.prefix(3))")
        }
        let ks = try Self.caseJson("{\(base),\"config\":{\"mode\":\"distance\",\"thresholdM\":1000,\"preAlert\":true,\"actions\":[{\"at\":{\"t\":100},\"action\":\"stop\"}]},\"killSweep\":{\"from\":{\"t\":60},\"everyS\":60,\"notAfter\":{\"t\":2000},\"earlyFrom\":{\"t\":1900}}}")
        var r = Runner(trace: trace, spec: ks, mode: "all")
        r.runAll()
        let (f, stats) = KillSweep.evaluate(r, ks.killSweep!)
        #expect(stats == nil && f.contains { $0.contains("không có alarm") })
    }

    @Test("S14 policy-j07 delays the first SPARSE-gated delivery by exactly 35 s versus j00; later ones follow intervalS")
    func s14() throws {
        let (trace, spec) = try NegativeSweepTests.loadCase("train_hn_dh_stopgap", "distance_1000")
        func deliveries(_ mode: String) -> [Int] {
            var r = Runner(trace: trace, spec: spec, mode: mode)
            r.runAll()
            return r.records.compactMap { rec in
                if case let .input(x, _) = rec.input, case .locationFix = x { return rec.t } else { return nil }
            }
        }
        let a = deliveries("policy-j00"), b = deliveries("policy-j07")
        guard let k = Array(zip(a, b)).firstIndex(where: { $0.0 != $0.1 }) else { Issue.record("no difference"); return }
        #expect(b[k] - a[k] == 35)
        #expect(a[k] - a[k - 1] == 180)
        #expect(b[k + 1] - b[k] == 180)
    }
}
