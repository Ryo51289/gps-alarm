package app.napstop.core.trip

import kotlin.math.sqrt

// T10 §4.1 = T02 §5.2 (same constants and operation order as tools/tracegen/lib/src/geo.dart).

/** Mean Earth radius (IUGG), metres. */
internal const val K_EARTH_RADIUS_M = 6371008.8

/** Degrees to radians with a literal pi. */
internal const val K_DEG_TO_RAD = 3.141592653589793 / 180

/** Metres per degree of latitude. */
internal const val K_METRES_PER_DEG_LAT = K_EARTH_RADIUS_M * K_DEG_TO_RAD

private val COS_DENOMINATORS = doubleArrayOf(462.0, 380.0, 306.0, 240.0, 182.0, 132.0, 90.0, 56.0, 30.0, 12.0, 2.0)

/** Cosine of an angle in degrees, |degrees| <= 90, Taylor series in Horner form (no libm). */
internal fun cosDeg(degrees: Double): Double {
    require(degrees >= -90.0 && degrees <= 90.0) { "cosDeg: out of range" }
    val x = degrees * K_DEG_TO_RAD
    val y = x * x
    var r = 1.0
    for (den in COS_DENOMINATORS) {
        r = 1.0 - y / den * r
    }
    return r
}

/** Equirectangular distance in metres, cosine at the mid-latitude. */
internal fun distanceM(aLat: Double, aLng: Double, bLat: Double, bLng: Double): Double {
    val kx = K_METRES_PER_DEG_LAT * cosDeg((aLat + bLat) / 2)
    val dx = (bLng - aLng) * kx
    val dy = (bLat - aLat) * K_METRES_PER_DEG_LAT
    return sqrt(dx * dx + dy * dy)
}

internal fun distanceM(a: FixRec, b: FixRec): Double = distanceM(a.lat, a.lng, b.lat, b.lng)
