import Testing
@testable import Trip

@Suite("EngineParamsFactoryTests")
struct EngineParamsFactoryTests {
    static func p(_ json: String?) -> ParamsParse { EngineParamsFactory.parseOverrides(json) }
    static let d = EngineParams.defaults

    @Test("U02 bad value / wrong type / unknown key; malformed JSON → all defaults")
    func u02() {
        let r = Self.p(#"{"gpsLostMinS": 5, "fixMaxAgeS": "x", "foo": 1}"#)
        #expect(r.params.gpsLostMinS == 60 && r.params.fixMaxAgeS == 60)
        #expect(r.rejected == ["gpsLostMinS", "fixMaxAgeS"])
        #expect(EngineParamsFactory.fromOverrides("{oops") == Self.d)
        #expect(Self.p("{oops").malformed)
    }

    @Test("U67 (a)–(m) Int/Double kinds, ranges and cross-groups G1–G7")
    func u67() {
        #expect(Self.p(#"{"gpsLostMinS": 60.0}"#).rejected.isEmpty)
        #expect(Self.p(#"{"gpsLostMinS": 60.5}"#).rejected == ["gpsLostMinS"])
        let c = Self.p(#"{"routeFactorMin": 1.4, "routeFactorPrior": 1.3}"#)
        #expect(c.params.routeFactorMin == 1.0 && c.params.routeFactorPrior == 1.2 && c.params.routeFactorMax == 2.0)
        #expect(Set(c.rejected) == ["routeFactorMin", "routeFactorPrior"])
        let dd = Self.p(#"{"denseEnterS": 1800, "mediumEnterS": 1200}"#).params
        #expect(dd.denseEnterS == 900 && dd.mediumEnterS == 3600)
        let e = Self.p(#"{"maxTripMinS": 90000, "maxTripCapS": 86400}"#).params
        #expect(e.maxTripMinS == 14400 && e.maxTripCapS == 172800)
        let f = Self.p(#"{"lowBatteryAlarmPct": 15, "lowBatteryEarlierPct": 15}"#).params
        #expect(f.lowBatteryAlarmPct == 5 && f.lowBatteryEarlierPct == 15)
        let g = Self.p(#"{"fallbackQuietBeforeS": 120, "fallbackNearS": 150}"#).params
        #expect(g.fallbackQuietBeforeS == 30 && g.fallbackNearS == 600)
        for json in [#"{"samplingDenseIntervalS": 15, "samplingMediumIntervalS": 10}"#,
                     #"{"samplingSparseIntervalS": 180, "samplingSparseMinIntervalS": 200}"#] {
            let h = Self.p(json).params
            #expect(h.samplingSparseIntervalS == 180 && h.samplingSparseMinIntervalS == 90 && h.samplingMediumIntervalS == 30
                    && h.samplingMediumMinIntervalS == 15 && h.samplingDenseIntervalS == 5 && h.samplingDenseMinIntervalS == 2)
        }
        let j = Self.p(#"{"fallbackLagS": 10, "samplingDenseIntervalS": 10}"#)
        #expect(j.params.fallbackLagS == 30 && j.params.samplingDenseIntervalS == 10 && j.rejected == ["fallbackLagS"])
        let k = Self.p(#"{"fallbackLagS": 12, "samplingDenseIntervalS": 10}"#)
        #expect(k.rejected.isEmpty && k.params.fallbackLagS == 12)
        #expect(Self.p(#"{"fallbackNearS": 60}"#).params.fallbackNearS == 600)
        #expect(Self.p(#"{"fallbackLagS": 5}"#).params.fallbackLagS == 30)
        for (v, want) in [("0", 0), ("5", 5), ("2.0", 2), ("6", 2), ("-1", 2), ("1.5", 2)] {
            #expect(Self.p("{\"lostSpeedGuardUpdates\": \(v)}").params.lostSpeedGuardUpdates == want)
        }
    }

    @Test("U67 (n)–(q) T25 U05 edge cases, −0.0 normalisation, duplicate keys, malformed inputs")
    func u67Extra() {
        for v in ["300", "300.0", "3e2"] { #expect(Self.p("{\"shortDistanceWarnS\": \(v)}").params.shortDistanceWarnS == 300) }
        for v in ["300.5", "\"300\"", "true", "null", "59", "601", "1e300"] {
            let r = Self.p("{\"shortDistanceWarnS\": \(v), \"foo\": 1}")
            #expect(r.params.shortDistanceWarnS == 240 && r.rejected == ["shortDistanceWarnS"])
        }
        #expect(Self.p(#"{"shortDistanceWarnS": 60}"#).params.shortDistanceWarnS == 60)
        #expect(Self.p(#"{"shortDistanceWarnS": 600}"#).params.shortDistanceWarnS == 600)
        #expect(Self.p(#"{"preAlertMinGapS": -0.0}"#).params.preAlertMinGapS == 0)
        #expect(Self.p(#"{"accRelMax": -0.0}"#).params.accRelMax.bitPattern == (0.0).bitPattern)
        #expect(Self.p(#"{"gpsLostMinS": 90, "gpsLostMinS": 120}"#).params.gpsLostMinS == 120)
        #expect(Self.p(#"{"gpsLostMinS": 90, "gpsLostMinS": "x"}"#).params.gpsLostMinS == 60)
        #expect(Self.p(#"{"gpsLostMinS": 1e400}"#).rejected == ["gpsLostMinS"])
        for bad in ["\u{FEFF}{}", "{\"a\":1,}", "{\"gpsLostMinS\": 012}", "[]", "\"42\""] {
            #expect(Self.p(bad).malformed && Self.p(bad).params == Self.d)
        }
        for none in [nil, "", "   "] as [String?] { #expect(!Self.p(none).malformed && Self.p(none).params == Self.d) }
        #expect(Self.p("null").malformed)
    }

    @Test("U67 (r) PARAM_SPECS: 83 entries, names/kinds/defaults/ranges as T10 §5 (independent hand-written rows)")
    func u67r() {
        let specs = ParamTable.PARAM_SPECS
        #expect(specs.count == 83)
        let hand: [(String, ParamKind, Double, Double, Double)] = [
            ("fixMaxAgeS", .int, 60, 10, 300), ("accRelMax", .double, 0.05, 0, 0.2), ("smoothWindowS", .int, 12, 0, 60),
            ("speedEmaTauS", .int, 300, 30, 1800), ("routeFactorMax", .double, 2.0, 1.2, 4), ("expectedSpeedKmhBus", .int, 20, 5, 150),
            ("smartFloorM", .int, 1000, 500, 3000), ("gpsLostAlarmEtaS", .int, 1200, 300, 3600), ("lostSpeedGuardUpdates", .int, 2, 0, 5),
            ("passedClosestReachFactor", .double, 2.0, 1, 4), ("maxTripCapS", .int, 172800, 3600, 259200),
            ("batteryMinRatePctPerH", .double, 0.5, 0.1, 5), ("tierHysteresisFactor", .double, 1.25, 1, 2),
            ("samplingDenseMinIntervalS", .int, 2, 1, 15), ("fallbackEarlyFrac", .double, 0.25, 0, 0.5),
            ("fallbackEarlyMaxS", .int, 3600, 0, 7200), ("fallbackHintSpeedFactor", .double, 1.0, 0, 2),
            ("fallbackQuietBeforeS", .int, 30, 30, 120), ("vehicleBusMaxAvgKmh", .int, 30, 10, 50),
        ]
        for h in hand {
            guard let i = ParamTable.index(of: h.0) else { Issue.record("missing \(h.0)"); continue }
            let s = specs[i]
            #expect(s.kind == h.1 && s.defaultValue == h.2 && s.min == h.3 && s.max == h.4, "\(h.0)")
        }
        #expect(Set(specs.map(\.name)).count == 83)
        for (i, s) in specs.enumerated() {
            switch Self.d.value(at: i) {
            case let .int(v): #expect(s.kind == .int && Double(v) == s.defaultValue)
            case let .double(v): #expect(s.kind == .double && v == s.defaultValue)
            }
            #expect(s.min <= s.defaultValue && s.defaultValue <= s.max, "\(s.name)")
        }
    }

    @Test("U97 (a) fallbackHintSpeedFactor / fallbackEarlyFrac / fallbackEarlyMaxS ranges")
    func u97a() {
        #expect(Self.p(#"{"fallbackHintSpeedFactor": 0}"#).params.fallbackHintSpeedFactor == 0)
        #expect(Self.p(#"{"fallbackHintSpeedFactor": 2}"#).params.fallbackHintSpeedFactor == 2)
        for v in ["2.5", "-0.1", "\"1\""] { #expect(Self.p("{\"fallbackHintSpeedFactor\": \(v)}").params.fallbackHintSpeedFactor == 1.0) }
        #expect(Self.p(#"{"fallbackEarlyFrac": 0.5}"#).params.fallbackEarlyFrac == 0.5)
        #expect(Self.p(#"{"fallbackEarlyFrac": 0.55}"#).params.fallbackEarlyFrac == 0.25)
        #expect(Self.p(#"{"fallbackEarlyMaxS": 7200}"#).params.fallbackEarlyMaxS == 7200)
        #expect(Self.p(#"{"fallbackEarlyMaxS": 7201}"#).params.fallbackEarlyMaxS == 3600)
    }
}

@Suite("TripConfigValidationTests")
struct TripConfigValidationTests {
    static func start(_ mode: AlarmMode, d: Int? = nil, t: Int? = nil, lat: Double = 0, lng: Double = 0, id: String = "x") -> TripConfigError? {
        let c = TripConfig(tripId: id, destLat: lat, destLng: lng, mode: mode, distanceThresholdM: d, timeThresholdMin: t,
                           preAlertEnabled: true, vehicleHint: .train)
        do { _ = try TripEngine.start(config: c, params: .defaults, nowMs: 0); return nil } catch { return error }
    }

    @Test("U03 thresholds: DISTANCE 150 / 10001, TIME 4 / missing fail; DISTANCE 200 and 10000 valid; T12 C11 order and messages")
    func u03() {
        #expect(Self.start(.distance, d: 150)?.description == "distanceThresholdM: out of range")
        #expect(Self.start(.distance, d: 10001)?.description == "distanceThresholdM: out of range")
        #expect(Self.start(.time, t: 4)?.description == "timeThresholdMin: out of range")
        #expect(Self.start(.time)?.description == "timeThresholdMin: required")
        #expect(Self.start(.distance, d: 200) == nil && Self.start(.distance, d: 10000) == nil)
        #expect(Self.start(.time, t: 60) == nil && Self.start(.time, t: 5) == nil)
        #expect(Self.start(.time, t: 61)?.description == "timeThresholdMin: out of range")
        #expect(Self.start(.smart, d: 150)?.description == "distanceThresholdM: out of range")
        #expect(Self.start(.distance)?.description == "distanceThresholdM: required")
        #expect(Self.start(.distance, d: 150, id: "")?.description == "tripId: empty")
        #expect(Self.start(.distance, d: 150, lat: 95)?.description == "destLat: out of range")
        #expect(Self.start(.distance, d: 1000, lat: .nan)?.description == "destLat: out of range")
        #expect(Self.start(.distance, d: 150, lng: 180)?.description == "destLng: out of range")
        #expect(Self.start(.distance, d: 1000, lng: -180) == nil)
        #expect(Self.start(.smart) == nil)
    }
}

@Suite("TripRulesTests")
struct TripRulesTests {
    @Test("U16 shortDistanceWarning (integer formula) for the 10 T10 pairs")
    func u16() {
        let cases: [(Int, VehicleKind, Bool)] = [(1000, .coach, true), (5000, .coach, false), (4000, .coach, false), (2000, .bus, false),
                                                 (1000, .bus, true), (1333, .bus, true), (1334, .bus, false), (4000, .train, false),
                                                 (3600, .train, true), (3667, .train, false)]
        for (thr, v, want) in cases {
            #expect(TripRules.shortDistanceWarning(thresholdM: thr, vehicle: v, params: .defaults) == want, "\(thr) \(v)")
        }
    }
}
