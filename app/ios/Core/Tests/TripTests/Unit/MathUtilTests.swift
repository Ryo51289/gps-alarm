import Testing
@testable import Trip

@Suite("MathUtilTests")
struct MathUtilTests {
    @Test("U09 blend: null EMA takes the sample; then 10 + 10·5/305")
    func u09() {
        let a = TMath.blend(nil, 10, 5, tauS: 300)
        #expect(a == 10)
        #expect(TMath.blend(a, 20, 5, tauS: 300) == 10 + 10.0 * 5 / 305)
    }

    @Test("U62 minOrNull(null, 5, 3) = 3; minOrNull(null, null) = null")
    func u62MinOrNull() {
        #expect(TMath.minOrNull(nil, 5, 3) == 3)
        #expect(TMath.minOrNull(nil, nil) == nil)
    }

    @Test("U66 medianHi: [null, 3, 5] → 5; [4, null] → 4; [null, null] → null (recentSpeed falls back to ground 2)")
    func u66() {
        #expect(TMath.medianHi([nil, 3, 5]) == 5)
        #expect(TMath.medianHi([4, nil]) == 4)
        #expect(TMath.medianHi([nil, nil]) == nil)
        #expect(TMath.medianHi([3]) == 3)
        #expect(TMath.medianHi([1, 9, 5]) == 5)
        var s = EngineDriver().state
        s.recent = [FixRec(fixAtMs: 0, lat: 0, lng: 0, accM: 8, d: 1, groundSample: nil),
                    FixRec(fixAtMs: 1, lat: 0, lng: 0, accM: 8, d: 1, groundSample: nil)]
        s.ground = 2
        #expect(OvershootDetector.recentSpeed(s) == 2)
    }

    @Test("MathUtil (T12) max(0.0, −0.0) = 0.0 and min(−0.0, 0.0) = −0.0 by bits; roundHalfUp(2.5) = 3; floorMs(0.0009999) = 0")
    func extras() {
        #expect(TMath.max(0.0, -0.0).bitPattern == (0.0).bitPattern)
        #expect(TMath.min(-0.0, 0.0).bitPattern == (-0.0).bitPattern)
        #expect(TMath.roundHalfUp(2.5) == 3)
        #expect(TMath.floorMs(0.0009999) == 0)
        #expect(TMath.toS(1500) == 1.5)
        #expect(TMath.clamp(5.0, 1.0, 2.0) == 2.0)
    }

    @Test("S04 kotlinToLong / kotlinToInt saturate like Kotlin and never trap")
    func s04() {
        #expect(TMath.kotlinToLong(.nan) == 0)
        #expect(TMath.kotlinToLong(0.0) == 0 && TMath.kotlinToLong(-0.0) == 0)
        #expect(TMath.kotlinToLong(9223372036854775808.0) == Int64.max)
        #expect(TMath.kotlinToLong(-9223372036854775808.0) == Int64.min)
        #expect(TMath.kotlinToLong(9.3e18) == Int64.max)
        #expect(TMath.kotlinToLong(1e300) == Int64.max)
        #expect(TMath.kotlinToLong(-1e300) == Int64.min)
        #expect(TMath.kotlinToLong(-2.9) == -2)
        #expect(TMath.kotlinToInt(.nan) == 0)
        #expect(TMath.kotlinToInt(2147483647.9) == 2147483647)
        #expect(TMath.kotlinToInt(2147483648) == 2147483647)
        #expect(TMath.kotlinToInt(-2147483649) == -2147483648)
        #expect(TMath.kotlinToInt(1e300) == 2147483647)
        #expect(TMath.kotlinToInt(-0.0) == 0)
    }

    @Test("S05 a * b + c is not contracted into an FMA: contractionProbe(0.1, 10, −1) == 0.0 (args read at runtime)")
    func s05() {
        let args = [0.1, 10.0, -1.0].shuffled().sorted()   // runtime array: no constant folding
        let r = TMath.contractionProbe(args[1], args[2], args[0])
        #expect(r.bitPattern == 0)
        #expect((-1.0).addingProduct(0.1, 10) != 0.0)
    }
}
