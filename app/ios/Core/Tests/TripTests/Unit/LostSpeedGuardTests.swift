import Testing
@testable import Trip

@Suite("LostSpeedGuardTests")
struct LostSpeedGuardTests {
    static let u90Fixes: [(Double, Double, Double)] = [(0, 100_000, 12), (180, 97_840, 12), (360, 95_680, 12), (540, 93_520, 12),
                                                       (720, 91_360, 12), (900, 89_400, 1.0)]

    static func driver(_ guardN: Int?) -> EngineDriver {
        EngineDriver(.distance, thr: 1000, hint: .train, params: guardN.map { "{\"lostSpeedGuardUpdates\": \($0)}" })
    }

    /// Runs ticks every 60 s from `from` until the first alarm (or `until`); returns the tick of the first alarm.
    static func tickUntilAlarm(_ d: inout EngineDriver, from: Double, until: Double = 20_000) -> Double? {
        var t = from
        while t <= until {
            d.tick(t)
            if !d.events.alarms.isEmpty { return t }
            t += 60
        }
        return nil
    }

    @Test("U90 brake sample before GPS loss: cvGuard [12, 12], GpsLost at 1440, predicted constant, Alarm(GPS_LOST) 7200 (N = 0: 11 100)")
    func u90() {
        // Default N = 2.
        var d = Self.driver(nil)
        for f in Self.u90Fixes { d.fix(f.0, d: f.1, spd: f.2) }
        #expect(approx(d.state.ground, 7.875) && approx(d.state.closing, 11.583333333333334, 1e-6))
        #expect(d.estimate!.k == 1.0 && approx(d.estimate!.closingV, 7.875))
        #expect(d.state.cvGuard.count == 2 && approx(d.state.cvGuard[0], 12, 1e-6) && approx(d.state.cvGuard[1], 12, 1e-6))
        var t = 960.0
        while t <= 1380 { d.tick(t); #expect(d.events.named("gpsLost").isEmpty); t += 60 }
        d.tick(1440)
        #expect(d.events.compactMap(\.asGpsLost).first == TripEvent.GpsLost(atMs: d.ms(1440), cause: .noFixTimeout, lastFixAgeS: 540))
        #expect(d.view.distanceM == 82_920)
        let p = d.view.predictedAlarmAtMs!
        #expect((p - d.ms(7170)).magnitude <= 1)
        #expect(d.events.fallbacks == [TripEvent.FallbackAlarmChanged(atMs: d.ms(1440), fallbackAtMs: d.ms(5_619.742), cause: .eta)])
        var at = 1500.0, alarmT: Double? = nil
        while at <= 20_000 {
            d.tick(at)
            if d.events.alarms.isEmpty { #expect((d.view.predictedAlarmAtMs! - p).magnitude <= 1) } else { alarmT = at; break }
            at += 60
        }
        #expect(alarmT == 7200)
        #expect(d.events.alarms.first?.reason == .gpsLost)
        // N = 0 (T10 before T10.1).
        var z = Self.driver(0)
        for f in Self.u90Fixes { z.fix(f.0, d: f.1, spd: f.2) }
        #expect(z.state.cvGuard.isEmpty)
        var zt = 960.0
        while zt < 1440 { z.tick(zt); zt += 60 }
        z.tick(1440)
        #expect(z.view.distanceM == 85_148)
        #expect((z.view.predictedAlarmAtMs! - z.ms(11_072.380)).magnitude <= 1)
        #expect(Self.tickUntilAlarm(&z, from: 1500) == 11_100)
        #expect(z.state.cvGuard.isEmpty)
    }

    @Test("U90 (T10 override 0.1/1800/0) fallback at tick 1440 is S + 6 687 000 as in T10.1")
    func u90Override() {
        var d = EngineDriver(.distance, thr: 1000, hint: .train,
                             params: #"{"fallbackEarlyFrac": 0.1, "fallbackEarlyMaxS": 1800, "fallbackHintSpeedFactor": 0}"#)
        for f in Self.u90Fixes { d.fix(f.0, d: f.1, spd: f.2) }
        var t = 960.0
        while t <= 1440 { d.tick(t); t += 60 }
        let fb = d.steps.last { !$0.events.fallbacks.isEmpty }!.events.fallbacks.last!
        #expect(fb.fallbackAtMs == d.ms(6_687))
    }

    @Test("U91 brake → stop → restart sample: cvGuard [12, 7.875], GpsLost 1980, Alarm(GPS_LOST) 7680 / 11 580 / 14 160 for N = 2 / 1 / 0")
    func u91() {
        for (n, want) in [(2, 7680.0), (1, 11_580.0), (0, 14_160.0)] {
            var d = Self.driver(n == 2 ? nil : n)
            for f in Self.u90Fixes { d.fix(f.0, d: f.1, spd: f.2) }
            d.fix(1080, d: 89_398, spd: 0); d.fix(1260, d: 89_398, spd: 0); d.fix(1440, d: 89_000, spd: 4.0)
            #expect(approx(d.state.ground, 6.421875) && approx(d.state.closing, 8.06875, 1e-6))
            if n == 2 { #expect(d.state.cvGuard.count == 2 && approx(d.state.cvGuard[0], 12, 1e-6) && approx(d.state.cvGuard[1], 7.875, 1e-6)) }
            var t = 1500.0, lostAt: Double? = nil, alarmAt: Double? = nil
            while t <= 20_000 {
                d.tick(t)
                if lostAt == nil, !d.events.named("gpsLost").isEmpty { lostAt = t }
                if !d.events.alarms.isEmpty { alarmAt = t; break }
                t += 60
            }
            #expect(lostAt == 1980, "N = \(n)")
            #expect(alarmAt == want, "N = \(n)")
            #expect(d.events.alarms.first?.reason == .gpsLost)
        }
    }

    static func transcript(_ d: EngineDriver) -> [String] {
        d.steps.map { s in s.events.map { Transcript.event($0, d.startMs) }.joined() + Transcript.view(s.view, d.startMs) }
    }

    @Test("U92 no change to old behaviour: (a) GPS OK uses EMA 7.875; (b) not established; (c) accelerating; (d) N = 3; (e) no guard update; (f) closingVOf")
    func u92() {
        // (a)
        var a = Self.driver(nil)
        for f in Self.u90Fixes { a.fix(f.0, d: f.1, spd: f.2) }
        a.tick(1000)
        #expect(a.view.distanceM == 88_613)
        // (b)
        for n in [nil, 0] as [Int?] { _ = n }
        var b2 = Self.driver(nil), b0 = Self.driver(0)
        for f in Self.u90Fixes.prefix(3) { b2.fix(f.0, d: f.1, spd: f.2); b0.fix(f.0, d: f.1, spd: f.2) }
        var t = 420.0
        while t <= 6000 { b2.tick(t); b0.tick(t); t += 60 }
        #expect(b2.state.cvGuard.isEmpty)
        #expect(Self.transcript(b2) == Self.transcript(b0))
        // (c) accelerating: Doppler 8…14 every 180 s, Δd = mean of neighbouring Dopplers × 180
        var c2 = Self.driver(nil), c0 = Self.driver(0)
        var dist = 100_000.0
        for i in 0..<7 {
            let v = Double(8 + i)
            if i > 0 { dist -= (Double(7 + i) + v) / 2 * 180 }
            c2.fix(Double(i) * 180, d: dist, spd: v); c0.fix(Double(i) * 180, d: dist, spd: v)
        }
        #expect(c2.state.cvGuard.allSatisfy { $0 < c2.estimate!.closingV })
        t = 1140
        while t <= 9000 { c2.tick(t); c0.tick(t); t += 60 }
        #expect(Self.transcript(c2) == Self.transcript(c0))
        // (d) N = 3: closingV before each of the last 3 EMA updates.
        var dd = Self.driver(3)
        var expected: [Double] = []
        dist = 100_000
        for i in 0..<10 {
            let v = 10.0 + Double(i)
            if i > 0 { dist -= v * 180 }
            let before = dd.state
            dd.fix(Double(i) * 180, d: dist, spd: v)
            if Estimator.isEstablished(before), let g = before.ground { expected.append(SpeedEstimator.closingVOf(g, before.closing, before.params)) }
        }
        #expect(dd.state.cvGuard == Array(expected.suffix(3)))
        // (e) STATIONARY, MOVING inside the anchor, Δt 901 s (UNKNOWN), DROP and REANCHOR leave cvGuard unchanged.
        var e = Self.driver(nil)
        for f in Self.u90Fixes.prefix(5) { e.fix(f.0, d: f.1, spd: f.2) }
        let g0 = e.state.cvGuard
        e.fix(900, d: 91_360, spd: 0)          // STATIONARY
        e.fix(905, d: 91_340, spd: 5)          // MOVING but 20 m from the anchor
        e.fix(1806, d: 80_000, spd: 12)        // Δt 901 → UNKNOWN
        e.fix(1811, d: 60_000, spd: 12)        // DROP (implausible)
        #expect(e.state.cvGuard == g0)
        e.fix(1826, d: 60_000); e.fix(1841, d: 60_000)   // REANCHOR (span 30 s)
        #expect(e.state.cvGuard == g0 && e.state.last?.fixAtMs == e.ms(1841))
        // (f)
        let p = EngineParams.defaults
        #expect(SpeedEstimator.closingVOf(12, 12, p) == 12)
        #expect(SpeedEstimator.closingVOf(7.875, 11.583333, p) == 7.875)
        #expect(SpeedEstimator.closingVOf(15, 12.5, p) == 12.5)
        #expect(SpeedEstimator.closingVOf(10, nil, p) == 10 / 1.2)
        #expect(SpeedEstimator.closingVOf(10, -1, p) == 5)
    }
}
