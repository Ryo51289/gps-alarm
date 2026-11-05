package app.napstop.core.alarm

import android.os.SystemClock

/**
 * One in-memory slot for the action MainActivity was opened with (spec T16 §4.5, T27 §9): `overshootRoute` from "Xem
 * đường quay lại", with the trip id and how far past the destination the alarm was dismissed. Flutter takes it once
 * through `AlarmHostApi.consumeLaunchAction` (T27 D4); it expires after [TTL_MS] (D5). No coordinates (T14 D5).
 */
object LaunchActions {
    const val EXTRA_LAUNCH = "napstop.launch"
    const val EXTRA_TRIP_ID = "napstop.tripId"
    const val EXTRA_PAST_M = "napstop.pastM"

    /** Wall clock (ms) of the "Xem đường quay lại" tap; required (review T27 #1). */
    const val EXTRA_AT_WALL_MS = "napstop.atWallMs"
    const val OVERSHOOT_ROUTE = "overshootRoute"

    /** = `Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY` (a constant, so the pure gate needs no Android class). */
    const val FLAG_LAUNCHED_FROM_HISTORY = 0x00100000

    /** D5: a launch action older than this is dropped (10 min, `elapsedRealtime`). */
    const val TTL_MS = 600_000L

    /** Largest `pastM` kept (1 000 km); anything else becomes "unknown". */
    const val PAST_M_MAX = 1_000_000

    /** PRIVACY: [toString] prints neither the trip id nor the distance. */
    data class Action(val action: String, val tripId: String, val pastM: Int?, val atElapsedMs: Long = 0L) {
        override fun toString(): String = "Action($action, pastM=${if (pastM == null) "unset" else "set"})"
    }

    /** Clock of the slot; JVM tests replace it. */
    @Volatile
    var elapsed: () -> Long = SystemClock::elapsedRealtime

    private var slot: Action? = null

    /**
     * Pure: the action of MainActivity's extras, or null when [action] is unknown or [tripId] invalid (MainActivity is
     * exported). A [pastM] outside 0..[PAST_M_MAX] becomes null.
     */
    fun parse(action: String?, tripId: String?, pastM: Int?): Action? {
        if (action != OVERSHOOT_ROUTE) return null
        val trip = RingIntents.validTripId(tripId) ?: return null
        return Action(action, trip, pastM?.takeIf { it in 0..PAST_M_MAX })
    }

    /**
     * Review T27 #1: the system keeps the task's original intent and gives it back, extras included, when the activity
     * is recreated after the process died (or relaunched from Recents). Such an intent is not a new "Xem đường quay lại".
     * True when [restored] (`savedInstanceState != null`) or the intent carries `FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`.
     */
    fun isReplay(restored: Boolean, intentFlags: Int): Boolean =
        restored || (intentFlags and FLAG_LAUNCHED_FROM_HISTORY) != 0

    /**
     * Pure gate of MainActivity (two layers, review T27 #1): a replayed intent ([isReplay]) is ignored; otherwise the
     * action must carry [atWallMs] (wall clock of the tap in AlarmActivity) at most [TTL_MS] before [nowWallMs].
     */
    fun fromIntent(
        action: String?,
        tripId: String?,
        pastM: Int?,
        atWallMs: Long?,
        nowWallMs: Long,
        restored: Boolean,
        intentFlags: Int,
    ): Action? {
        if (isReplay(restored, intentFlags)) return null
        if (atWallMs == null || nowWallMs - atWallMs !in 0..TTL_MS) return null
        return parse(action, tripId, pastM)
    }

    /** Replaces the slot; the action's age counts from now. */
    @Synchronized
    fun set(a: Action) {
        slot = a.copy(atElapsedMs = elapsed())
    }

    /** Returns and clears the slot; null when empty or older than [TTL_MS]. */
    @Synchronized
    fun consume(): Action? {
        val a = slot ?: return null
        slot = null
        return a.takeIf { elapsed() - a.atElapsedMs in 0..TTL_MS }
    }
}
