@testable import Trip

/// Synthetic geometry (as T12 `TestGeo`): destination at (0, 0); points on the same meridian, south of it.
enum TestGeo {
    static let destLat = 0.0
    static let destLng = 0.0

    /// Latitude south of the destination at ≈ d metres (error < 1e-6 m).
    static func latOnMeridian(_ d: Double) -> Double { -(d / Geo.kMetresPerDegLat) }

    /// Latitude whose distanceM to (0, 0) is exactly `d` (nextUp/nextDown search, ≤ 1 000 steps).
    static func latAtExactDistance(_ d: Double) -> Double {
        var lat = latOnMeridian(d)
        for _ in 0..<1000 {
            let x = Geo.distanceM(lat, 0.0, destLat, destLng)
            if x == d { return lat }
            // more negative latitude = farther away
            lat = x < d ? lat.nextDown : lat.nextUp
        }
        return lat
    }

    static func dist(_ lat: Double, _ lng: Double) -> Double { Geo.distanceM(lat, lng, destLat, destLng) }

    /// Point `east` metres east of the meridian point at north–south distance `d` (off-route destination).
    static func point(d: Double, east: Double) -> (Double, Double) {
        let lat = latOnMeridian(d)
        return (lat, east / (Geo.kMetresPerDegLat * Geo.cosDeg(lat)))
    }
}
