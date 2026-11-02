import Foundation
import Testing
@testable import Trip

@Suite("GeoTests")
struct GeoTests {
    /// Reference values from tools/tracegen/lib/src/geo.dart (run once with Dart 3.13.7, raw bits).
    static let pairs: [(Double, Double, Double, Double, String)] = [
        (21.0242144, 105.8410943, 17.4689199, 106.5997285, "41189d265c8e642b"),
        (16.0549823, 108.1733614, 16.256, 108.07, "40d8586af7628810"),
        (20.9805, 105.7922, 20.5411, 106.3356, "40f23c7d1fa41cf0"),
        (21.0285123, 105.8542, 21.0285123, 105.8642, "409037969ad4dab7"),
        (10.7769, 106.7009, 10.7769, 106.7009, "0000000000000000"),
        (-33.8688, 151.2093, -33.9, 151.25, "40b3f9d2728c510b"),
    ]

    @Test("U01 distanceM equals tracegen (6 pairs, bit-exact, so within ± 1e-6 m) and is symmetric by bits")
    func u01() {
        for p in Self.pairs {
            let d = Geo.distanceM(p.0, p.1, p.2, p.3)
            #expect(Bits.hex(d) == p.4)
            #expect(Geo.distanceM(p.2, p.3, p.0, p.1).bitPattern == d.bitPattern)
        }
        #expect(Bits.hex(Geo.kMetresPerDegLat) == "40fb25b148a2f4fe")
        #expect(Bits.hex(Geo.kDegToRad) == "3f91df46a2529d39")
    }

    @Test("U01 (T12) cosDeg(90.0001) stops the process (Kotlin throws IllegalArgumentException)")
    func u01OutOfRange() async {
        await #expect(processExitsWith: .failure) {
            _ = Geo.cosDeg(90.0001)
        }
    }

    @Test("S06 cosDeg bit-exact with tracegen at 7 points; |cosDeg − Foundation.cos| ≤ 1e-15 on [−90, 90] step 0.01")
    func s06() {
        let ref: [(Double, String)] = [(0, "3ff0000000000000"), (16.4637211, "3feeb01f76470f1b"), (-16.4637211, "3feeb01f76470f1b"),
                                       (21.0242144, "3feddea64316ae2d"), (-21.0242144, "3feddea64316ae2d"),
                                       (90, "0000000000000000"), (-90, "0000000000000000")]
        for (x, h) in ref { #expect(Bits.hex(Geo.cosDeg(x)) == h, "x = \(x)") }
        var worst = 0.0
        for i in -9000...9000 {
            let x = Double(i) / 100.0
            worst = Swift.max(worst, abs(Geo.cosDeg(x) - Foundation.cos(x * Double.pi / 180)))
        }
        #expect(worst <= 1e-15)
    }
}
