package app.napstop.core.trip.runtime.support

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.runtime.ClockAnchor
import app.napstop.core.trip.runtime.ForegroundResult
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.StartOutcome
import app.napstop.core.trip.runtime.StoredTrip
import app.napstop.core.trip.runtime.TripMeta
import kotlin.math.cos

/** Test geometry: a destination and points north of it at a given distance. */
object Geo {
    const val DEST_LAT = 16.0
    const val DEST_LNG = 108.0

    /** Latitude [m] metres north of the destination (meridian, ≈ 111 195 m per degree). */
    fun latNorth(m: Double): Double = DEST_LAT + m / 111_195.0

    fun lngEast(m: Double): Double = DEST_LNG + m / (111_195.0 * cos(Math.toRadians(DEST_LAT)))
}

/** Starts a trip in [w] and lets everything queued run. */
fun World.startTrip(meta: TripMeta = TestData.meta(), lat: Double = Geo.DEST_LAT, lng: Double = Geo.DEST_LNG): StartOutcome {
    tracking.autoResult = ForegroundResult.Started
    return now { runtime.start(meta, lat, lng) }
}

/** A fresh fix (age 0) at [m] metres north of the destination, moving south at [speed] m/s. */
fun World.fixNorth(m: Double, speed: Float? = 15f, acc: Float = 8f) {
    location.emit(RawFix(Geo.latNorth(m), Geo.DEST_LNG, acc, speed, time.elapsedNanos()))
    settle()
}

/**
 * Engine states built with the real engine (fixes every 5 s along the meridian, south-bound at 15 m/s), for restore
 * tests. [startM] metres north of the destination at t0; one fix per 5 s for [fixes] fixes.
 */
object EngineStates {
    fun drive(meta: TripMeta, t0: Long, startM: Double, fixes: Int, speedMps: Double = 15.0, params: EngineParams = EngineParams()): Step {
        val cfg = TripConfig(meta.tripId, Geo.DEST_LAT, Geo.DEST_LNG, meta.mode, meta.distanceThresholdM, meta.timeThresholdMin, meta.preAlertEnabled, meta.vehicleHint)
        var step = TripEngine.start(cfg, params, t0)
        for (i in 0 until fixes) {
            val t = t0 + 5_000L * (i + 1)
            val m = startM - speedMps * 5.0 * (i + 1)
            step = TripEngine.reduce(step.state, LocationFix(t, t, Geo.latNorth(m), Geo.DEST_LNG, 8.0, speedMps))
        }
        return step
    }

    fun stored(meta: TripMeta, step: Step, anchor: ClockAnchor, savedAt: Long = anchor.wallMs) = StoredTrip(StoredTrip.VERSION, meta, anchor, step.state, savedAt)
}
