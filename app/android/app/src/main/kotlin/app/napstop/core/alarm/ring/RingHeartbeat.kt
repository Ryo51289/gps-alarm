package app.napstop.core.alarm.ring

import android.os.Handler
import android.os.SystemClock
import app.napstop.core.alarm.RingBoot
import app.napstop.core.alarm.RingFactsRecord
import app.napstop.core.alarm.RingFactsStore
import app.napstop.core.alarm.RingMode

/**
 * Heartbeat of a ringing session (spec T16 D5): every HEARTBEAT_MS the book gets heartbeatElapsedMs / heartbeatWallMs
 * (no fsync). If the book says the ring is over (another process stopped it, a stop overtook the start, the user
 * dismissed), [onStale] tells the session to stop. A backup record of this trip turns back into SERVICE (this process
 * plays). Ring thread only.
 */
class RingHeartbeat(
    private val handler: Handler,
    private val store: RingFactsStore,
    private val periodMs: Long,
    private val bootCount: () -> Int?,
    private val onStale: (tripId: String, stopSeq: Long?) -> Unit,
    private val onBackupTakenOver: (tripId: String) -> Unit,
) {
    private var tripId: String? = null

    private val beat =
        object : Runnable {
            override fun run() {
                val trip = tripId ?: return
                beatOnce(trip)
                if (tripId == trip) handler.postDelayed(this, periodMs)
            }
        }

    fun start(tripId: String) {
        stop()
        this.tripId = tripId
        handler.postDelayed(beat, periodMs)
    }

    fun stop() {
        tripId = null
        handler.removeCallbacks(beat)
    }

    private fun beatOnce(trip: String) {
        var stale: RingFactsRecord? = null
        var missing = false
        var tookOver = false
        try {
            store.update(trip, sync = false) { raw ->
                // A book of another boot is not this ring's (review T16 #1): it reads as stopped.
                val r = RingBoot.sanitize(raw, bootCount(), RingBoot.nanosBound(SystemClock.elapsedRealtime()))
                when {
                    r == null -> {
                        missing = true
                        null
                    }
                    !r.ringing || r.pendingDismissAtWallMs != null || (r.stopSeq ?: Long.MIN_VALUE) >= r.ringSeq -> {
                        stale = r
                        raw
                    }
                    else -> {
                        tookOver = r.mode == RingMode.BACKUP
                        r.copy(
                            mode = RingMode.SERVICE,
                            heartbeatElapsedMs = SystemClock.elapsedRealtime(),
                            heartbeatWallMs = System.currentTimeMillis(),
                            bootCount = r.bootCount ?: bootCount(),
                        )
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("NapStopRing", "heartbeat failed (${e.javaClass.simpleName})")
            return
        }
        when {
            // clearTrip deleted the book: the trip is over.
            missing -> onStale(trip, null)
            stale != null -> onStale(trip, stale?.stopSeq)
            tookOver -> onBackupTakenOver(trip)
        }
    }
}
