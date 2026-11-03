package app.napstop.core.bridge

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.SystemClock
import android.util.Log
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * `PermissionHostApi.distancesFromLastKnownM()` on Android (spec T23 §6, D9): "cách X km"
 * on screen 2 from the position the system already has. Never asks for a permission,
 * never turns on a provider, never requests a fix; only `LocationManager` (no Play
 * services). The user's position stays here: only distances go back to Dart.
 *
 * PRIVACY: never log a position, a distance or the station coordinates. Distances leave
 * this class rounded to what screen 2 displays ([LastKnownMath.roundForDisplay]), so a set
 * of them to public stations cannot pin the user down to a few metres (review T23 #3).
 */
class LastKnownDistance(
    context: Context,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    private val appContext = context.applicationContext

    suspend fun distances(pairs: List<Double>, maxAgeMs: Long): List<Double>? =
        withContext(io) {
            try {
                compute(pairs, maxAgeMs)
            } catch (e: Exception) {
                Log.w(TAG, "last known distance: ${e.javaClass.simpleName}")
                null
            }
        }

    private fun compute(pairs: List<Double>, maxAgeMs: Long): List<Double>? {
        if (!LastKnownMath.validPairs(pairs) || maxAgeMs <= 0) return null
        if (!granted(Manifest.permission.ACCESS_FINE_LOCATION) &&
            !granted(Manifest.permission.ACCESS_COARSE_LOCATION)
        ) {
            return null
        }
        val lm = appContext.getSystemService(LocationManager::class.java) ?: return null
        if (!locationEnabled(lm)) return null
        val candidates =
            lm.getProviders(true).mapNotNull { provider ->
                val fix =
                    try {
                        lm.getLastKnownLocation(provider)
                    } catch (_: SecurityException) {
                        null
                    } catch (_: IllegalArgumentException) {
                        null
                    }
                fix?.let { LastKnownMath.Candidate(it.elapsedRealtimeNanos, it) }
            }
        val best =
            LastKnownMath.freshest(candidates, SystemClock.elapsedRealtimeNanos(), maxAgeMs) ?: return null
        val from = best.payload as Location
        val out = FloatArray(1)
        return List(pairs.size / 2) { i ->
            Location.distanceBetween(from.latitude, from.longitude, pairs[2 * i], pairs[2 * i + 1], out)
            LastKnownMath.roundForDisplay(out[0].toDouble())
        }
    }

    /** `isLocationEnabled` is API 28+; on 26-27 any enabled provider counts. */
    private fun locationEnabled(lm: LocationManager): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            lm.isLocationEnabled
        } else {
            lm.getProviders(true).any { it != LocationManager.PASSIVE_PROVIDER }
        }

    private fun granted(permission: String): Boolean =
        appContext.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private companion object {
        const val TAG = "NapStopBridge"
    }
}

/** Pure parts of [LastKnownDistance], JVM-testable (T23 TK02). */
object LastKnownMath {
    /** Most numbers accepted (50 stations). */
    const val MAX_NUMBERS = 100

    /** A cached fix: when it was taken (elapsed realtime) and the platform object. */
    data class Candidate(val elapsedRealtimeNanos: Long, val payload: Any? = null)

    /**
     * Even, non-empty, at most [MAX_NUMBERS], finite, lat in [-90, 90], lng in [-180, 180].
     * An empty list is invalid (spec TK02 lists `[]` as true; nothing to measure, so the call
     * answers null — see T23 Implementation notes, round 2).
     */
    fun validPairs(p: List<Double>): Boolean {
        if (p.isEmpty() || p.size % 2 != 0 || p.size > MAX_NUMBERS) return false
        for (i in p.indices step 2) {
            val lat = p[i]
            val lng = p[i + 1]
            if (!lat.isFinite() || !lng.isFinite()) return false
            if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) return false
        }
        return true
    }

    /**
     * [meters] at the resolution `formatDistanceShort` shows: nearest 10 m below 1 km, nearest
     * 100 m from 1 km on. Negative or non-finite input gives 0.
     */
    fun roundForDisplay(meters: Double): Double {
        if (!meters.isFinite() || meters <= 0.0) return 0.0
        val step = if (meters < 1000.0) 10.0 else 100.0
        return Math.round(meters / step) * step
    }

    /** The newest candidate not older than [maxAgeMs] at [nowElapsedNanos], or null. */
    fun freshest(c: List<Candidate>, nowElapsedNanos: Long, maxAgeMs: Long): Candidate? {
        val newest = c.maxByOrNull { it.elapsedRealtimeNanos } ?: return null
        val ageMs = (nowElapsedNanos - newest.elapsedRealtimeNanos) / 1_000_000L
        return if (ageMs <= maxAgeMs) newest else null
    }
}
