package app.napstop.core.trip.support

import app.napstop.core.trip.K_METRES_PER_DEG_LAT
import app.napstop.core.trip.cosDeg
import app.napstop.core.trip.distanceM

data class LatLng(val lat: Double, val lng: Double)

/** Test destination: on the equator so points on the same meridian have distance = |Δlat| · K exactly. */
val DEST = LatLng(0.0, 106.0)

object TestGeo {
    /** Point due south of [dest] (lat = 0) with distanceM(point, dest) == d exactly (nextUp/nextDown search). */
    fun pointAtExactDistance(dest: LatLng, d: Double): LatLng {
        require(dest.lat == 0.0)
        var lat = -(d / K_METRES_PER_DEG_LAT)
        repeat(1000) {
            val got = distanceM(lat, dest.lng, dest.lat, dest.lng)
            if (got == d) return LatLng(lat, dest.lng)
            lat = if (got < d) Math.nextDown(lat) else Math.nextUp(lat)
        }
        error("no exact point for $d")
    }

    /** Point due south of [dest] at about d metres (error < 1e-6 m). */
    fun pointOnMeridian(dest: LatLng, d: Double): LatLng = LatLng(dest.lat - d / K_METRES_PER_DEG_LAT, dest.lng)

    fun jitter(p: LatLng, eastM: Double, northM: Double): LatLng =
        LatLng(p.lat + northM / K_METRES_PER_DEG_LAT, p.lng + eastM / (K_METRES_PER_DEG_LAT * cosDeg(p.lat)))
}
