package app.napstop.core.location

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.PowerManager
import android.util.Log
import app.napstop.core.trip.runtime.FixSink
import app.napstop.core.trip.runtime.FlpPriority
import app.napstop.core.trip.runtime.FlpRequestSpec
import app.napstop.core.trip.runtime.LocationSource
import app.napstop.core.trip.runtime.RawFix
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Fused Location Provider (spec T15 §5.4): `LocationRequest.Builder(priority, interval)` + min interval, no batching
 * (maxUpdateDelay 0), max update age [G-LRB]; callback on its own executor thread `napstop-loc` [G-FLPC]. Each fix
 * holds a PARTIAL_WAKE_LOCK until the runtime finished its Step ([StepWakeLock], capped at [stepWakeLockMs]). The
 * runtime checks the permissions before requesting and turns a SecurityException into PERMISSION_REVOKED.
 */
class FusedLocationSource(context: Context, private val stepWakeLockMs: Long) : LocationSource {
    private val ctx = context.applicationContext
    private val client by lazy { LocationServices.getFusedLocationProviderClient(ctx) }
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "napstop-loc").apply { isDaemon = true } }
    private val wakeLock: PowerManager.WakeLock? by lazy {
        ctx.getSystemService(PowerManager::class.java)?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "napstop:step")?.apply {
            setReferenceCounted(false)
        }
    }
    private val stepLock =
        StepWakeLock(
            acquire = { ms -> wakeLock?.acquire(ms) },
            release = { wakeLock?.let { if (it.isHeld) it.release() } },
            capMs = stepWakeLockMs,
        )
    private val lock = Any()
    private var callback: LocationCallback? = null

    @SuppressLint("MissingPermission") // checked by the runtime; SecurityException is caught there
    override fun request(spec: FlpRequestSpec, sink: FixSink) {
        val priority = if (spec.priority == FlpPriority.HIGH_ACCURACY) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
        val request =
            LocationRequest.Builder(priority, spec.intervalMs)
                .setMinUpdateIntervalMillis(spec.minUpdateIntervalMs)
                .setMaxUpdateDelayMillis(spec.maxUpdateDelayMs)
                .setMaxUpdateAgeMillis(spec.maxUpdateAgeMs)
                .build()
        val cb =
            object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    for (loc in result.locations) {
                        val done = stepLock.begin()
                        try {
                            sink.onFix(loc.toRaw(), done)
                        } catch (e: Exception) {
                            done()
                            Log.w(TAG, "fix delivery failed (${e.javaClass.simpleName})")
                        }
                    }
                }
            }
        synchronized(lock) {
            callback?.let { client.removeLocationUpdates(it) }
            callback = null
            client.requestLocationUpdates(request, executor, cb)
            callback = cb
        }
    }

    override fun stop() {
        synchronized(lock) {
            callback?.let { client.removeLocationUpdates(it) }
            callback = null
        }
    }

    @SuppressLint("MissingPermission")
    override suspend fun lastKnown(): RawFix? =
        try {
            suspendCancellableCoroutine { cont ->
                client.lastLocation
                    .addOnSuccessListener { loc -> if (cont.isActive) cont.resume(loc?.toRaw()) }
                    .addOnFailureListener { if (cont.isActive) cont.resume(null) }
            }
        } catch (e: SecurityException) {
            null
        }

    private fun Location.toRaw(): RawFix =
        RawFix(
            lat = latitude,
            lng = longitude,
            accuracyM = if (hasAccuracy()) accuracy else null,
            speedMps = if (hasSpeed()) speed else null,
            elapsedRealtimeNanos = elapsedRealtimeNanos,
        )

    private companion object {
        const val TAG = "NapStopRuntime"
    }
}

/**
 * One wake lock shared by the fixes in flight (review T15 #4): each fix acquires it with a timeout of [capMs] and gets
 * a `done` callback; the lock is released when every pending fix is done, at the latest by the timeout. Pure, so it is
 * JVM-tested with fake acquire/release.
 */
class StepWakeLock(private val acquire: (Long) -> Unit, private val release: () -> Unit, private val capMs: Long) {
    private val lock = Any()
    private var pending = 0

    /**
     * Acquires (re-arming the cap) and returns the idempotent `done` of this fix. Counter and lock change under one
     * monitor, so a `done` can never release the lock that a concurrent `begin` just took (review T15 R2-5).
     */
    fun begin(): () -> Unit {
        synchronized(lock) {
            pending++
            try {
                acquire(capMs)
            } catch (e: Exception) {
                Log.w("NapStopRuntime", "wake lock failed (${e.javaClass.simpleName})")
            }
        }
        val finished = AtomicBoolean(false)
        return {
            if (finished.compareAndSet(false, true)) {
                synchronized(lock) {
                    pending = maxOf(0, pending - 1)
                    if (pending == 0) {
                        try {
                            release()
                        } catch (e: Exception) {
                            Log.w("NapStopRuntime", "wake lock release failed (${e.javaClass.simpleName})")
                        }
                    }
                }
            }
        }
    }

    val inFlight: Int get() = synchronized(lock) { pending }
}
