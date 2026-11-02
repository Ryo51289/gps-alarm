import Foundation
import Testing
@testable import Trip

@Suite("PrivacyTest")
struct PrivacyTests {
    @Test("U56 no event payload and no TripView field is named lat/lng/latitude/longitude (Mirror)")
    func u56() {
        let sum = TripSummary(startedAtMs: 0, alarmAtMs: nil, alarmReason: nil, dismissedAtMs: nil, snoozeCount: 0, travelledM: 0, vehicleGuess: .bus)
        let pol = SamplingPolicy(tier: .dense, intervalS: 5, minIntervalS: 2, accuracy: .high)
        let payloads: [Any] = [
            TripEvent.PreAlert(atMs: 0, distanceM: 0, etaS: nil),
            TripEvent.Alarm(atMs: 0, reason: .distance, ringNow: true, snoozeAllowed: true, distanceM: nil, etaS: nil, batteryPct: nil),
            TripEvent.Snoozed(atMs: 0, untilMs: 0), TripEvent.GpsLost(atMs: 0, cause: .noFixTimeout, lastFixAgeS: nil),
            TripEvent.GpsRecovered(atMs: 0, lostForS: 0), TripEvent.LowBatteryRisk(atMs: 0, levelPct: 0, availableMin: 0, neededMin: 0),
            TripEvent.Overshoot(atMs: 0, pastM: 0), TripEvent.Arrived(atMs: 0, distanceM: 0),
            TripEvent.FallbackAlarmChanged(atMs: 0, fallbackAtMs: nil, cause: .eta), TripEvent.SamplingPolicyChanged(atMs: 0, policy: pol),
            TripEvent.TripEnded(atMs: 0, outcome: .onTime, endReason: .dismissed, summary: sum), sum, pol, EngineDriver().view,
        ]
        let banned: Set<String> = ["lat", "lng", "latitude", "longitude"]
        for p in payloads {
            for c in Mirror(reflecting: p).children { #expect(!banned.contains(c.label ?? ""), "\(type(of: p)).\(c.label ?? "")") }
        }
    }

    @Test("U80 description / debugDescription / String(reflecting:) / dump never print coordinates; error messages have no values")
    func u80() {
        let cfg = TripConfig(tripId: "t", destLat: 21.0285123, destLng: 105.8542, mode: .distance, distanceThresholdM: 1000,
                             timeThresholdMin: nil, preAlertEnabled: true, vehicleHint: .train)
        let fix = LocationFix(atMs: 1, fixAtMs: 1, lat: 16.4637211, lng: 107.5, accuracyM: 8, speedMps: 3)
        var state = try! TripEngine.start(config: cfg, params: .defaults, nowMs: 0).state
        let step = TripEngine.reduce(state, .locationFix(fix))
        state = step.state
        let things: [Any] = [cfg, fix, EngineInput.locationFix(fix), state, step, state.last!]
        for x in things {
            var dumped = ""
            dump(x, to: &dumped)
            for text in [String(describing: x), String(reflecting: x), dumped] {
                #expect(!text.contains("21.0285") && !text.contains("16.4637") && !text.contains("105.85") && !text.contains("107.5"),
                        "\(type(of: x))")
            }
        }
        var bad = cfg
        bad.destLat = 95
        do { _ = try TripEngine.start(config: bad, params: .defaults, nowMs: 0); Issue.record("accepted") } catch {
            #expect(!error.description.contains("95") && error.description == "destLat: out of range")
        }
        let json = TripEngine.encodeSnapshot(state).replacingOccurrences(of: "\"slow\":false", with: "\"slow\":\"21.0285\"")
        do { _ = try TripEngine.decodeSnapshot(json); Issue.record("accepted") } catch {
            #expect(!error.description.contains("21.0285"))
        }
    }
}

@Suite("ViewTest")
struct ViewTests {
    @Test("U85 progress 0.6, alarmMarkerProgress 0.9 (DISTANCE 1000) / 0.12 (TIME 15, closingV 10); distanceErrorM 8 for acc 7.6")
    func u85() {
        var s = EngineDriver().state
        s.dStartM = 10_000
        let e = makeE(dNow: 4000, v: 10, k: 1)
        var v = ViewBuilder.buildView(s, e, predicted: nil, risk: false, wakeAtMs: nil)
        #expect(approx(v.progress, 0.6, 1e-12) && approx(v.alarmMarkerProgress, 0.9, 1e-12))
        var t = EngineDriver(.time, thr: nil, thrMin: 15).state
        t.dStartM = 10_000
        v = ViewBuilder.buildView(t, e, predicted: nil, risk: false, wakeAtMs: nil)
        #expect(approx(v.alarmMarkerProgress, 1 - 8800.0 / 10_000, 1e-12))
        var d = EngineDriver()
        d.fix(0, d: 20_000, acc: 7.6)
        #expect(d.view.distanceErrorM == 8)
    }
}

@Suite("SourceScanTest")
struct SourceScanTests {
    static func sources() throws -> [(String, String)] {
        let dir = FixturePaths.sourcesDir
        return try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".swift") }.sorted()
            .map { ($0, try FixturePaths.read(dir + "/" + $0)) }
    }

    /// Source with comments and string literals blanked (scan code only).
    static func codeOnly(_ s: String) -> String {
        var out = ""
        for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var l = String(line)
            if let r = l.range(of: "//") { l = String(l[..<r.lowerBound]) }
            l = l.replacingOccurrences(of: #""[^"]*""#, with: "\"\"", options: .regularExpression)
            out += l + "\n"
        }
        return out
    }

    @Test("U44 Sources/Trip: no transcendental functions, FMA, imports, bare min/max, Dictionary/Set/random/clock, logging; Int( only in conversion files")
    func u44() throws {
        let files = try Self.sources()
        #expect(files.count >= 20)
        let rules: [(String, String)] = [
            (#"(?<![\w.])(sin|cos|tan|asin|acos|atan|atan2|exp|expm1|log|log2|log10|log1p|pow|cbrt|hypot)\s*\("#, "transcendental"),
            (#"\bfma\b|addingProduct|formRemainder|truncatingRemainder"#, "FMA/remainder"),
            (#"^\s*import\s"#, "import"),
            (#"(?<![\w.])(min|max)\s*\("#, "bare min/max"),
            (#"Swift\.(min|max)"#, "Swift.min/max"),
            (#"\bDictionary\b|\bSet<|\.random|hashValue|\bDate\b|ContinuousClock|SuspendingClock"#, "nondeterminism"),
            (#"(?<![\w.])(print|debugPrint|dump|NSLog|os_log)\s*\("#, "logging"),
            (#"\.squareRoot\(\)|\.rounded\(\.down\)"#, "allowed"),
        ]
        let conversionFiles: Set<String> = ["TMath.swift", "MiniJson.swift", "SnapshotCodec.swift", "EngineParams.swift"]
        for (name, text) in files {
            let code = Self.codeOnly(text)
            for (i, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let l = String(line)
                for (pattern, label) in rules where label != "allowed" {
                    if label == "bare min/max" && l.range(of: #"func (min|max)\("#, options: .regularExpression) != nil { continue }
                    if l.range(of: pattern, options: .regularExpression) != nil { Issue.record("\(name):\(i + 1) \(label): \(l)") }
                }
                if !conversionFiles.contains(name), l.range(of: #"(?<![\w.])(Int|Int64)\("#, options: .regularExpression) != nil {
                    Issue.record("\(name):\(i + 1) Int(/Int64( outside conversion files: \(l)")
                }
            }
        }
        // Package.swift: no unsafeFlags / fast-math.
        let pkg = try FixturePaths.read(FixturePaths.packageDir + "/Package.swift")
        #expect(!pkg.contains("unsafeFlags") && !pkg.contains("Ounchecked") && !pkg.contains("fast-math"))
    }
}

@Suite("StartStepTest")
struct StartStepTests {
    @Test("StartStep C3: SamplingPolicyChanged(DENSE) then FallbackAlarmChanged(start + 10 980 000, ETA); C4 event fields from the view; C5")
    func startStep() {
        let d = EngineDriver(startMs: 0)
        #expect(d.events == [.samplingPolicyChanged(.init(atMs: 0, policy: SamplingPolicy(tier: .dense, intervalS: 5, minIntervalS: 2, accuracy: .high))),
                             .fallbackAlarmChanged(.init(atMs: 0, fallbackAtMs: 10_980_000, cause: .eta))])
        #expect(d.view.phase == .acquiring && d.view.gps == .noFixYet && d.view.fallbackStatus == .requested)
        var a = EngineDriver()
        a.battery(0, 50)
        a.fix(1, d: 800)
        let al = a.events.alarms[0]
        #expect(al.distanceM == a.view.distanceM && al.etaS == a.view.etaS && al.batteryPct == a.view.batteryPct && al.batteryPct == 50)
        var g = EngineDriver()
        g.drive(from: 0, d0: 20_000, v: 15, count: 4)
        g.tick(15 + 90.4)
        let lost = g.events.compactMap(\.asGpsLost).first
        #expect(lost?.lastFixAgeS == TMath.roundHalfUp(90.4))
        #expect(g.state.gpsLostAtMs == g.ms(105.4))
        g.fix(130, d: 20_000 - 15 * 130, spd: 15)
        let rec = g.events.compactMap { if case let .gpsRecovered(r) = $0 { return r.lostForS } else { return nil } }
        #expect(rec == [TMath.roundHalfUp(24.6)])
        var n = EngineDriver()
        n.tick(120)
        #expect(n.state.gpsLostAtMs == n.ms(120))
    }
}
