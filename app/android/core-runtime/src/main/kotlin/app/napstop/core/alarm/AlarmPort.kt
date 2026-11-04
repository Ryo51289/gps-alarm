package app.napstop.core.alarm

import app.napstop.core.trip.AlarmReason

// T15 ↔ T16 boundary (spec T15 §3, §4.2). Implemented by T16 AlarmController (:app) over AlarmControllerCore.

enum class RingSource { ENGINE, FALLBACK }

enum class StopCause { SNOOZED, DISMISSED, TRIP_ENDED }

data class RingSettings(
    val soundId: String,
    val volume: Double,
    val rampUp: Boolean,
    /** off | light | medium | strong */
    val vibration: String,
    val flash: Boolean,
    val preferHeadphones: Boolean,
    /** swipe | shake | math */
    val dismissMethod: String,
)

data class RingRequest(
    val tripId: String,
    val source: RingSource,
    /** null when source == FALLBACK fired from the OS (reason not known yet). */
    val reason: AlarmReason?,
    val snoozeAllowed: Boolean,
    val distanceM: Int?,
    val etaS: Int?,
    val batteryPct: Int?,
    /** null if ring_config is unreadable → generic copy. */
    val destinationName: String?,
    /** null → defaults. */
    val settings: RingSettings?,
    val atWallMs: Long,
) {
    override fun toString(): String =
        "RingRequest(tripId=$tripId, source=$source, reason=$reason, snoozeAllowed=$snoozeAllowed, etaS=$etaS, " +
            "batteryPct=$batteryPct, atWallMs=$atWallMs, distance=<redacted>, destination=<redacted>)"
}

data class PreAlertRequest(
    val tripId: String,
    val distanceM: Int,
    val etaS: Int?,
    val destinationName: String?,
    /** T16: mode == DISTANCE → distance copy (T10 §10 preAlertBodyDistance); otherwise minutes. */
    val byDistance: Boolean = false,
) {
    override fun toString(): String =
        "PreAlertRequest(tripId=$tripId, etaS=$etaS, byDistance=$byDistance, distance=<redacted>, destination=<redacted>)"
}

/**
 * Durable, cross-process facts. Times are wall clock ms. Contract (designer "sau test" §1): `ringingNow` is true from the
 * moment ringNow / ringFallback returned normally until the ring stops (a ring asked for ≤ 10 s ago counts as ringing
 * while it starts); otherwise a ring-guard slot could ring a second time.
 */
data class RingFacts(
    /**
     * MUST reflect reality. T16: `ringingNow` = heartbeat of `:ring` fresh (≤ 6 s), or backup notification showing, or a
     * ring requested ≤ 3 s ago in this process.
     */
    val ringingNow: Boolean,
    val ringingSource: RingSource?,
    val ringStartedAtWallMs: Long?,
    /** User dismissed in the native alarm UI, not yet delivered to the engine. */
    val pendingDismissAtWallMs: Long?,
    /** Last auto-stop. */
    val silencedAtWallMs: Long?,
    /**
     * User snoozed in the native alarm UI, not yet handled by the runtime (written before RING_EVENT SNOOZED, cleared
     * by stopRinging(SNOOZED)). A fallback / guard slot set before it must not ring (designer "sau test" G1).
     */
    val pendingSnoozeAtWallMs: Long? = null,
) {
    companion object {
        val NONE = RingFacts(false, null, null, null, null)
    }
}

/**
 * T15 ↔ T16 boundary. Non-blocking, callable from any thread. At most one ring per trip:
 * ringNow/ringFallback while a ring of the same trip is active only updates its content (no second sound).
 */
interface AlarmPort {
    /** Throws if the ring could not be started (then T15 keeps the fallback alarm). */
    fun ringNow(request: RingRequest)

    fun ringFallback(request: RingRequest)

    /** Idempotent. */
    fun stopRinging(tripId: String, cause: StopCause)

    fun preAlert(request: PreAlertRequest)

    fun overshoot(tripId: String, pastM: Int)

    fun ringFacts(tripId: String): RingFacts

    /** After TripEnded: delete the facts of the trip. */
    fun clearTrip(tripId: String)
}
