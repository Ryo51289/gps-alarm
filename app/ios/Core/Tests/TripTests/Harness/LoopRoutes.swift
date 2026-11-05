import Foundation
@testable import Trip

/// T10.7 round 2 §7 (U128; Kotlin `harness/LoopRoutes.kt`): the loop-route geometry of the tester's `TesterT124Test` RK20e (T12.4
/// test report #1) as a shared trace builder, built in memory around the TR40 destination (never written to a file, not in P05).
/// Local plane x east / y north in metres, converted with s = kEarthRadiusM · kDegToRad and cosDeg(destLat) as `chordClosest`.
/// Vehicle `v` m/s, a sample every 5 s, accuracy 8 m, Doppler `v`; approach from (−3 000, −15 000) north; the gap hides the loop
/// north of the destination: (−3 000, 0) → (−3 000, 3 000) → (3 000, 3 000) → (3 000, 0), so the chord passes through it
/// (dChord ≈ 0) while the road stays ≥ 3 km away. Noise: uniform in ±a m per axis from splitmix64 (`Mix`; x then y, delivered
/// samples only). Same arithmetic order as Kotlin.
enum LoopRoutes {
    static let v = 15.0

    /// Last fix (−3 000, 0) at 1 000, first fix (3 000, 0) at 1 800 (12 km at 15 m/s).
    static let gap = (fromT: 1_005, toT: 1_800)

    /// Polyline in the local plane (x east, y north, metres).
    struct Route: Sendable {
        let pts: [[Double]]
        let cum: [Double]

        init(_ pts: [[Double]]) {
            self.pts = pts
            var c = [Double](repeating: 0.0, count: pts.count)
            for i in 1..<pts.count { c[i] = c[i - 1] + Route.len(pts[i - 1], pts[i]) }
            cum = c
        }

        var length: Double { cum[cum.count - 1] }

        func at(_ s: Double) -> [Double] {
            if s <= 0.0 { return pts[0] }
            for i in 1..<pts.count where s <= cum[i] {
                let k = (s - cum[i - 1]) / (cum[i] - cum[i - 1])
                return [pts[i - 1][0] + k * (pts[i][0] - pts[i - 1][0]), pts[i - 1][1] + k * (pts[i][1] - pts[i - 1][1])]
            }
            return pts[pts.count - 1]
        }

        /// Arc length of the first route point closest to the destination (1 m steps).
        func closestS() -> Double {
            var best = Double.greatestFiniteMagnitude
            var bs = 0.0
            var s = 0.0
            while s <= length {
                let p = at(s)
                let d = (p[0] * p[0] + p[1] * p[1]).squareRoot()
                if d < best - 1e-9 {
                    best = d
                    bs = s
                }
                s += 1.0
            }
            return bs
        }

        static func len(_ a: [Double], _ b: [Double]) -> Double {
            let dx = b[0] - a[0]
            let dy = b[1] - a[1]
            return (dx * dx + dy * dy).squareRoot()
        }
    }

    /// A built trace with its truth: the vehicle is at arc length v·t; `sD` = arc length of the closest point to the destination.
    struct Synth: Sendable {
        let id: String
        let trace: LoadedTrace
        let route: Route
        let sD: Double
        let gap: (fromT: Int, toT: Int)

        var arrivalS: Double { sD / LoopRoutes.v }

        /// Truth: the vehicle reached the destination (its closest route point) at tick `t`.
        func passed(_ t: Int) -> Bool { LoopRoutes.v * Double(t) >= sD }

        func trueD(_ t: Int) -> Double {
            let p = route.at(LoopRoutes.v * Double(t))
            return (p[0] * p[0] + p[1] * p[1]).squareRoot()
        }
    }

    static func pt(_ x: Double, _ y: Double) -> [Double] { [x, y] }

    /// 90 points from angle `a0` to `a1` (degrees, math convention), radius `r` → `r1`.
    static func arc(_ r: Double, _ a0: Double, _ a1: Double, _ r1: Double? = nil) -> [[Double]] {
        let rEnd = r1 ?? r
        return (1...90).map { i in
            let a = (a0 + (a1 - a0) * Double(i) / 90.0) * Double.pi / 180.0
            let ri = r + (rEnd - r) * Double(i) / 90.0
            return pt(ri * cos(a), ri * sin(a))
        }
    }

    static func approach() -> [[Double]] {
        [pt(-3_000.0, -15_000.0), pt(-3_000.0, 0.0), pt(-3_000.0, 3_000.0), pt(3_000.0, 3_000.0), pt(3_000.0, 0.0)]
    }

    /// L1: 3 km south (away, d 3 000 → 4 243 m), west, then north to the destination and 3 km on.
    static func l1() -> Route { Route(approach() + [pt(3_000.0, -3_000.0), pt(0.0, -3_000.0), pt(0.0, 0.0), pt(0.0, 3_000.0)]) }

    /// L2: 300 m south (d +15 m), west 3 km, north 300 m to the destination and 3 km on.
    static func l2() -> Route { Route(approach() + [pt(3_000.0, -300.0), pt(0.0, -300.0), pt(0.0, 0.0), pt(0.0, 3_000.0)]) }

    /// L3 (control): straight to the destination and 3 km past it.
    static func l3() -> Route { Route(approach() + [pt(0.0, 0.0), pt(-3_000.0, 0.0)]) }

    /// L4: a quarter circle of radius 3 000 m around the destination, then north to it and 3 km on.
    static func l4() -> Route { Route(approach() + arc(3_000.0, 0.0, -90.0) + [pt(0.0, 0.0), pt(0.0, 3_000.0)]) }

    /// L5: a spiral (radius 3 000 → 2 000 m over a quarter turn), then north to the destination and 3 km on.
    static func l5() -> Route { Route(approach() + arc(3_000.0, 0.0, -90.0, 2_000.0) + [pt(0.0, 0.0), pt(0.0, 3_000.0)]) }

    /// Samples every 5 s along `route` around `base`'s destination (same start time), none in `gap`; noise ±`noiseA` m.
    static func synth(_ base: LoadedTrace, _ id: String, _ route: Route, noiseA: Double = 0.0, seed: Int64 = 124,
                      gap: (fromT: Int, toT: Int) = LoopRoutes.gap) -> Synth {
        let s = Geo.kEarthRadiusM * Geo.kDegToRad
        let c = Geo.cosDeg(base.file.destLat)
        let dur = (KW.ki(route.length / v) / 5) * 5
        var rnd = Mix(seed)
        var samples: [TraceSample] = []
        var t = 0
        while t <= dur {
            if t < gap.fromT || t >= gap.toT {
                let p = route.at(v * Double(t))
                let nx = noiseA > 0.0 ? rnd.dbl(-noiseA, noiseA) : 0.0
                let ny = noiseA > 0.0 ? rnd.dbl(-noiseA, noiseA) : 0.0
                samples.append(TraceSample(index: samples.count, t: t, lat: base.file.destLat + (p[1] + ny) / s,
                                           lng: base.file.destLng + (p[0] + nx) / (c * s), accuracyM: 8.0, speedMps: v))
            }
            t += 5
        }
        let sD = route.closestS()
        let b = base.file
        let file = TraceFile(traceId: "u128_\(id)", vehicle: "coach", gpx: "u128_\(id).gpx", startTime: b.startTime, startMs: b.startMs,
                             intervalS: 5, durationS: dur, sampleCount: samples.count, destLat: b.destLat, destLng: b.destLng,
                             arrivalT: KW.ki(sD / v), gpsGaps: [gap], overshootT: nil, closestT: nil, closestDepartT: nil,
                             routeT: [:], straightT: [:], rawCases: [])
        var byTick = [Int?](repeating: nil, count: dur / 5 + 1)
        for x in samples { byTick[x.t / 5] = x.index }
        return Synth(id: id, trace: LoadedTrace(file: file, samples: samples, byTick: byTick), route: route, sD: sD, gap: gap)
    }
}
