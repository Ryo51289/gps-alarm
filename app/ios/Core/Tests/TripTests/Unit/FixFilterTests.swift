import Testing
@testable import Trip

@Suite("FixFilterTests")
struct FixFilterTests {
    @Test("U04 fix age 60 000 ms accepted, 60 001 ms dropped (no GpsRecovered, droppedFixes + 1)")
    func u04() {
        var a = EngineDriver()
        a.fix(100, d: 20_000, fixAge: 60)
        #expect(a.state.last != nil && a.view.droppedFixes == 0)
        var b = EngineDriver()
        b.tick(130)   // NEVER_ACQUIRED emitted at 120
        b.fix(140, d: 20_000, fixAge: 60.001)
        #expect(b.state.last == nil && b.view.droppedFixes == 1)
        #expect(b.events.named("gpsRecovered").isEmpty)
    }

    @Test("U05 accuracy gate: d 1 km acc 150 drop; d 50 km acc 1500 accept; d 50 km acc 2500 drop")
    func u05() {
        var a = EngineDriver(); a.fix(5, d: 1000, acc: 150); #expect(a.view.droppedFixes == 1)
        var b = EngineDriver(); b.fix(5, d: 50_000, acc: 1500); #expect(b.view.droppedFixes == 0 && b.state.last != nil)
        var c = EngineDriver(); c.fix(5, d: 50_000, acc: 2500); #expect(c.view.droppedFixes == 1)
    }

    @Test("U06 three 3.3 km jumps within 10 s are dropped; next good fix accepted; dSmooth does not jump")
    func u06() {
        var d = EngineDriver()
        d.fix(0, d: 20_000, spd: 10)
        d.fix(5, d: 16_700); d.fix(10, d: 16_700); d.fix(15, d: 16_700)
        #expect(d.view.droppedFixes == 3 && d.state.rejects.count == 3)
        d.fix(20, d: 19_800, spd: 10)
        #expect(d.view.droppedFixes == 3 && d.state.rejects.isEmpty)
        #expect(approx(d.state.dSmooth, 19_800, 1e-6))   // no jump towards 16.7 km
    }

    @Test("U07 four consistent fixes 5 km away: +15, +30 dropped; +45 REANCHOR (recent = [it], minD = its d); +60 accepted")
    func u07() {
        var d = EngineDriver()
        d.fix(0, d: 20_000)
        d.fix(15, d: 25_000); d.fix(30, d: 25_000)
        #expect(d.view.droppedFixes == 2)
        d.fix(45, d: 25_000)
        #expect(d.view.droppedFixes == 2)
        #expect(d.state.recent.count == 1 && approx(d.state.minD, 25_000, 1e-6) && d.state.rejects.isEmpty)
        #expect(d.state.last3.count == 1)
        d.fix(60, d: 24_990)
        #expect(d.view.droppedFixes == 2 && d.state.last?.fixAtMs == d.ms(60) && approx(d.state.minD, 24_990, 1e-6))
    }

    @Test("U59 sliding reject window; no REANCHOR if pair (0,1) not plausible; REANCHOR while stopped clears stop, keeps EMA")
    func u59() {
        var d = EngineDriver()
        d.fix(0, d: 20_000)
        // Window [10 (30 km), 25 (40 km), 40 (40 km)]: span 30 s but pair (0,1) not plausible → no REANCHOR.
        d.fix(10, d: 30_000); d.fix(25, d: 40_000); d.fix(40, d: 40_000)
        #expect(d.view.droppedFixes == 3)
        #expect(d.state.rejects.map(\.fixAtMs) == [d.ms(10), d.ms(25), d.ms(40)])
        #expect(d.state.last?.fixAtMs == d.ms(0))
        // 4th consecutive reject slides the window to [25, 40, 55]: both pairs plausible, span 30 s → REANCHOR.
        d.fix(55, d: 40_000)
        #expect(d.view.droppedFixes == 3)
        #expect(d.state.last?.fixAtMs == d.ms(55) && d.state.rejects.isEmpty && d.state.recent.count == 1)
        // Reanchor while stopped: new trip.
        var s = EngineDriver()
        s.drive(from: 0, d0: 30_000, v: 15, count: 40)        // established
        let tStop = 200.0
        s.fix(tStop, d: s.state.dSmooth! - 5, spd: 0)          // STATIONARY → stop
        #expect(s.state.stopStartMs != nil)
        let g = s.state.ground, c = s.state.closing
        s.fix(tStop + 15, d: 10_000, spd: 0); s.fix(tStop + 30, d: 10_000, spd: 0); s.fix(tStop + 45, d: 10_000, spd: 0)
        #expect(s.state.stopStartMs == nil && s.state.stopAnchor == nil)
        #expect(s.state.last3 == [s.state.dSmooth!] && s.state.rejects.isEmpty)
        #expect(s.state.ground == g && s.state.closing == c)
    }
}

@Suite("DistanceSmootherTests")
struct DistanceSmootherTests {
    @Test("U08 dSmooth: d 2000, 900 (jump), 1980 within 12 s → 1980; with two elements {2000, 900} → 2000")
    func u08() {
        var s = EngineDriver().state
        func rec(_ t: Int64, _ d: Double) -> FixRec { FixRec(fixAtMs: t * 1000, lat: 0, lng: 0, accM: 8, d: d, groundSample: nil) }
        FixFilter.updateRecent(&s, rec(0, 2000))
        FixFilter.updateRecent(&s, rec(5, 900))
        #expect(s.dSmooth == 2000)
        FixFilter.updateRecent(&s, rec(10, 1980))
        #expect(s.dSmooth == 1980)
        FixFilter.updateRecent(&s, rec(30, 1500))   // older ones leave the 12 s window
        #expect(s.recent.count == 1 && s.dSmooth == 1500)
    }
}
