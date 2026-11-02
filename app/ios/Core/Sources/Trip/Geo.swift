// Geometry identical to tools/tracegen/lib/src/geo.dart (T02 §5.2, T10 §4.1): basic IEEE-754 operations only.

enum Geo {
    static let kEarthRadiusM = 6371008.8
    static let kDegToRad = 3.141592653589793 / 180.0
    static let kMetresPerDegLat = kEarthRadiusM * kDegToRad

    private static let cosDenominators: [Double] = [462, 380, 306, 240, 182, 132, 90, 56, 30, 12, 2]

    /// Cosine of an angle in degrees, |degrees| ≤ 90, Taylor series in Horner form.
    static func cosDeg(_ degrees: Double) -> Double {
        guard degrees >= -90.0 && degrees <= 90.0 else {
            preconditionFailure("cosDeg: degrees out of range")
        }
        let x = degrees * kDegToRad
        let y = x * x
        var r = 1.0
        for den in cosDenominators {
            r = 1.0 - y / den * r
        }
        return r
    }

    /// Equirectangular distance in metres (cosine at the mid-latitude).
    static func distanceM(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
        let kx = kMetresPerDegLat * cosDeg((aLat + bLat) / 2.0)
        let dx = (bLng - aLng) * kx
        let dy = (bLat - aLat) * kMetresPerDegLat
        return (dx * dx + dy * dy).squareRoot()
    }
}
