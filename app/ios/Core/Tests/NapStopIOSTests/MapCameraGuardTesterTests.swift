import Foundation
import Testing
@testable import NapStopIOS

/// T23.3 tester (outside the spec table): properties of the D11 camera guard over a deterministic grid of views
/// (portrait phone, landscape phone, screen 4 card, iPad), paddings and boxes. Pure arithmetic, runs on WSL.
@Suite("MapCameraGuardTester")
struct MapCameraGuardTesterTests {
    static let cap = 109.4
    static let limit = 110.9
    static let west = 102.0

    /// (width, height) in points.
    static let views: [(Double, Double)] = [
        (390, 531), (320, 400), (844, 300), (358, 213), (343, 200), (1024, 700), (700, 1024), (800, 300),
    ]
    static let pads: [(Double, Double, Double, Double)] = [
        (0, 0, 0, 0), (48, 48, 48, 48), (191, 48, 48, 48), (48, 0, 120, 0),
    ]
    static let boxes: [(Double, Double)] = [
        (0, 0), (0.018, 0.018), (0.2, 0.2), (1, 2), (2, 1), (2, 4), (0.1, 1), (7.7, 16), (12, 3),
    ]

    @Test("targetLngSpan: the box fits on both axes at the returned scale")
    func targetSpanFits() {
        for (w, h) in Self.views {
            for (t, l, b, r) in Self.pads {
                for (rw, rh) in Self.boxes {
                    let got = MapCameraGuard.targetLngSpan(
                        rectLngSpan: rw, rectHeightLng: rh, viewWidth: w, viewHeight: h, padTop: t, padLeft: l,
                        padBottom: b, padRight: r)
                    let innerW = w - l - r
                    let innerH = h - t - b
                    guard innerW > 0, innerH > 0 else {
                        #expect(got == nil, "\(w)x\(h) pad \(t),\(l),\(b),\(r)")
                        continue
                    }
                    guard let span = got else {
                        Issue.record("nil for \(w)x\(h) box \(rw)x\(rh)")
                        continue
                    }
                    // degrees per point = span / w; the inner area must hold the box on BOTH axes (R3-1).
                    let perPoint = span / w
                    #expect(perPoint * innerW >= rw - 1e-9, "width \(w)x\(h) box \(rw)x\(rh)")
                    #expect(perPoint * innerH >= rh - 1e-9, "height \(w)x\(h) box \(rw)x\(rh)")
                    // ...and is tight on at least one axis (not an over-estimate).
                    let tight = abs(perPoint * innerW - rw) < 1e-9 || abs(perPoint * innerH - rh) < 1e-9
                    #expect(tight, "tight \(w)x\(h) box \(rw)x\(rh)")
                    #expect(span >= rw - 1e-12)
                }
            }
        }
    }

    @Test("boundary from the target span keeps the framed east edge at or below 110.9")
    func boundaryFromTargetKeepsInvariant() {
        // What frame() does: east = max(west, centerEastLimit(target)); then the camera centred at that east edge
        // shows target/2 more. The invariant holds for every span a valid center can serve (≤ 2 × (110.9 − 102)).
        for (w, h) in Self.views {
            for (t, l, b, r) in Self.pads {
                for (rw, rh) in Self.boxes {
                    guard
                        let span = MapCameraGuard.targetLngSpan(
                            rectLngSpan: rw, rectHeightLng: rh, viewWidth: w, viewHeight: h, padTop: t, padLeft: l,
                            padBottom: b, padRight: r), span <= 2 * (Self.limit - Self.west)
                    else { continue }
                    let east = max(
                        Self.west, MapCameraGuard.centerEastLimit(visibleLngSpan: span, capEast: Self.cap, eastLimit: Self.limit))
                    #expect(east + span / 2 <= Self.limit + 1e-9, "\(w)x\(h) box \(rw)x\(rh)")
                    #expect(east <= Self.cap)
                }
            }
        }
    }

    @Test("centerEastLimit: fine sweep, knee at 3.0°, monotone (same as the Dart tester test)")
    func centerEastLimitSweep() {
        var previous = Double.infinity
        for i in 0...8800 {
            let span = Double(i) / 1000
            let v = MapCameraGuard.centerEastLimit(visibleLngSpan: span, capEast: Self.cap, eastLimit: Self.limit)
            #expect(v <= previous)
            if span > 0 { #expect(v + span / 2 <= Self.limit + 1e-9, "\(span)") }
            previous = v
        }
        #expect(MapCameraGuard.centerEastLimit(visibleLngSpan: 3, capEast: Self.cap, eastLimit: Self.limit) == Self.cap)
        #expect(
            MapCameraGuard.centerEastLimit(visibleLngSpan: 3 + 1e-6, capEast: Self.cap, eastLimit: Self.limit) < Self.cap)
        #expect(
            MapCameraGuard.centerEastLimit(visibleLngSpan: -.infinity, capEast: Self.cap, eastLimit: Self.limit)
                == Self.cap)
    }

    @Test("maxDistance: the measured distance scales back to the measured span")
    func maxDistanceScales() {
        for d in [1_000.0, 450_000, 800_000, 3_000_000] {
            for s in [0.01, 1, 4, 8.8, 20] {
                let got = MapCameraGuard.maxDistance(currentDistance: d, currentLngSpan: s, maxLngSpan: 8.8)
                #expect(got != nil)
                if let got { #expect(abs(got * s / 8.8 - d) < 1e-6 * d) }
            }
        }
        #expect(MapCameraGuard.maxDistance(currentDistance: .infinity, currentLngSpan: 1, maxLngSpan: 8.8) == nil)
        #expect(MapCameraGuard.maxDistance(currentDistance: 1, currentLngSpan: 1, maxLngSpan: .nan) == nil)
    }
}
