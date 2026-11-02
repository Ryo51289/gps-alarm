import Testing
@testable import Trip

@Suite("SpeedEstimatorTests")
struct SpeedEstimatorTests {
    /// Running at 15 m/s (Doppler, 5 s), straight at the destination; returns driver and last t / d.
    static func running(count: Int = 40) -> (EngineDriver, Double, Double) {
        var d = EngineDriver()
        d.drive(from: 0, d0: 40_000, v: 15, count: count)
        let t = Double(count - 1) * 5
        return (d, t, 40_000 - 15 * t)
    }

    @Test("U10 short stop (25 s) is blended into the EMA: blend(blend(·, 0, 25), sample, 5)")
    func u10() {
        var (d, t, dist) = Self.running()
        let g0 = d.state.ground!
        let t1 = t + 5, dStop = dist - 75
        for i in 0..<6 { d.fix(t1 + Double(i) * 5, d: dStop, spd: 0) }
        #expect(d.state.stopStartMs == d.ms(t1))
        d.fix(t1 + 30, d: dStop - 75, spd: 15)
        let expected = TMath.blend(TMath.blend(g0, 0, 25, tauS: 300), 15, 5, tauS: 300)
        #expect(d.state.ground == expected)
        #expect(d.state.stopStartMs == nil)
    }

    @Test("U11 long stop (300 s) is skipped: EMA unchanged, ETA after restart = ETA before (same d)")
    func u11() {
        var (d, t, dist) = Self.running()
        let g0 = d.state.ground!, c0 = d.state.closing!
        let t1 = t + 5, dStop = dist - 75
        var tt = t1
        while tt <= t1 + 300 { d.fix(tt, d: dStop, spd: 0); tt += 5 }
        #expect(d.state.ground == g0 && d.state.closing == c0)
        let etaStopped = d.estimate!.etaS!
        d.fix(tt, d: dStop - 75, spd: 15)
        #expect(approx(d.state.ground, 15, 1e-9) && d.state.stopStartMs == nil)
        let e = d.estimate!
        #expect(approx(e.etaS, d.state.dSmooth! * e.k / e.v + 20, 1e-9))
        #expect(approx(etaStopped, dStop * e.k / e.v + 20, 1e-3))
    }

    @Test("U12 route factor k: ground 20 with closing 16 / 25 / −1 → 1.25 / 1.0 / 2.0; not established → 1.2")
    func u12() {
        var (d, _, _) = Self.running()
        for (c, want) in [(16.0, 1.25), (25.0, 1.0), (-1.0, 2.0)] {
            d.state.ground = 20; d.state.closing = c
            #expect(d.estimate!.k == want)
        }
        d.state.movingSamples = 1
        #expect(d.estimate!.k == 1.2)
    }

    @Test("U13 etaS: d 9000, v 15, k 1.2, penalty 20 → 740; v 0.4 → null")
    func u13() {
        var (d, _, _) = Self.running()
        d.state.dSmooth = 9000; d.state.ground = 15; d.state.closing = 12.5; d.state.last!.fixAtMs = d.state.nowMs
        #expect(approx(d.estimate!.etaS, 740, 1e-9))
        d.state.ground = 0.4; d.state.closing = 0.4 / 1.2
        #expect(d.estimate!.etaS == nil)
    }

    @Test("U60 sample gap: 900 s updates the EMA with dt 900, 901 s does not (Doppler and displacement branches)")
    func u60() {
        for withSpeed in [true, false] {
            for (gap, updates) in [(900.0, true), (901.0, false)] {
                var (d, t, dist) = Self.running()
                let g0 = d.state.ground!
                let sample = 20.0
                d.fix(t + gap, d: dist - sample * gap / 2, spd: withSpeed ? sample : nil)
                if updates {
                    let gs = withSpeed ? sample : (sample * gap / 2) / gap
                    #expect(approx(d.state.ground, TMath.blend(g0, gs, gap, tauS: 300), 1e-6))
                } else {
                    #expect(d.state.ground == g0)
                }
            }
        }
    }

    @Test("U61 established by Doppler but every pair has last.acc > 50 and a small displacement → closing null → k = prior")
    func u61() {
        var d = EngineDriver()
        var dist = 40_000.0
        for i in 0..<12 {
            let acc = i % 2 == 0 ? 60.0 : 40.0
            d.fix(Double(i) * 30, d: dist, acc: acc, spd: 15)
            dist -= 450
        }
        #expect(d.state.closing == nil)
        #expect(Estimator.isEstablished(d.state))
        #expect(d.estimate!.k == 1.2)
    }

    @Test("U72 600 s stop with jittering speed-less fixes: one stop, EMA unchanged, stop ends at the first fix > 50 m from the anchor")
    func u72() {
        var (d, t, dist) = Self.running()
        let g0 = d.state.ground!, c0 = d.state.closing!
        let dStop = dist - 10
        d.fix(t + 5, d: dStop, spd: nil)              // ≤ 16 m from previous → STATIONARY → stop starts
        let stopStart = d.state.stopStartMs
        #expect(stopStart == d.ms(t + 5))
        let jitter: [Double] = [0, 18, -2, 19, 1, -17, 3, 20, 0, -18]
        var tt = t + 10, starts = 1
        var i = 0
        while tt <= t + 605 {
            d.fix(tt, d: dStop + jitter[i % jitter.count], spd: nil)
            if d.state.stopStartMs != stopStart { starts += 1 }
            tt += 5; i += 1
        }
        #expect(starts == 1 && d.state.ground == g0 && d.state.closing == c0)
        d.fix(tt, d: dStop - 45, spd: nil)             // 45 m from anchor: still stopped
        #expect(d.state.stopStartMs == stopStart)
        d.fix(tt + 5, d: dStop - 120, spd: nil)        // 120 m: leaves the stop; long stop skipped
        #expect(d.state.stopStartMs == nil)
        #expect(approx(d.state.ground, TMath.blend(g0, 75.0 / 5, 5, tauS: 300), 1e-6))
    }
}
