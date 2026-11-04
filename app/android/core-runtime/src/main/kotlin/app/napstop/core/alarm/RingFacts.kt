package app.napstop.core.alarm

import app.napstop.core.trip.AlarmReason
import java.util.Properties

/** SERVICE = AlarmRingService in `:ring` plays; BACKUP = the backup notification of D4 (the system plays its sound). */
enum class RingMode { SERVICE, BACKUP }

enum class RingEnd { DISMISSED, SNOOZED, SILENCED, STOPPED, LOST }

/**
 * The ring book of one trip (spec T16 §4.6, D5): `noBackupFilesDir/napstop_ring/<tripId>.properties`, written by `:ring`
 * (and by the main process for the backup ring / stops), the one source of truth for "ringing". No coordinates, no
 * destination name, no distance.
 *
 * [snoozedAtWallMs] is also the `pendingSnoozeAtWallMs` of [RingFacts] (T15 "sau test" G1): written by `:ring` before
 * RING_EVENT SNOOZED, cleared by `stopRinging(SNOOZED)` once the runtime handled the snooze.
 */
data class RingFactsRecord(
    val version: Int = RingFactsCodec.VERSION,
    val tripId: String,
    /** elapsedRealtimeNanos when the ring was asked for (monotonic within one boot). */
    val ringSeq: Long,
    val ringing: Boolean,
    val mode: RingMode,
    val source: RingSource,
    val reason: AlarmReason?,
    val startedAtWallMs: Long,
    val heartbeatElapsedMs: Long?,
    val heartbeatWallMs: Long?,
    val bootCount: Int?,
    val pendingDismissAtWallMs: Long?,
    val snoozedAtWallMs: Long?,
    val silencedAtWallMs: Long?,
    val endedBy: RingEnd?,
    /** A ring with ringSeq ≤ stopSeq must not sound (a stop that reached `:ring` before its RING_START). */
    val stopSeq: Long?,
    val restarts: Int,
) {
    override fun toString(): String =
        "RingFactsRecord(tripId=$tripId, seq=$ringSeq, ringing=$ringing, mode=$mode, source=$source, reason=$reason, " +
            "endedBy=$endedBy, stopSeq=$stopSeq, restarts=$restarts)"

    companion object {
        /** Record for a trip that has no ring yet (a stop before the ring: only [stopSeq] matters, within [bootCount]). */
        fun stub(tripId: String, seq: Long, nowWallMs: Long, bootCount: Int? = null): RingFactsRecord =
            RingFactsRecord(
                tripId = tripId, ringSeq = seq, ringing = false, mode = RingMode.SERVICE, source = RingSource.ENGINE, reason = null,
                startedAtWallMs = nowWallMs, heartbeatElapsedMs = null, heartbeatWallMs = null, bootCount = bootCount,
                pendingDismissAtWallMs = null, snoozedAtWallMs = null, silencedAtWallMs = null, endedBy = null, stopSeq = seq,
                restarts = 0,
            )
    }
}

/** Properties codec of [RingFactsRecord]. Unreadable, other version or the T15 interim file (no `version`) → null. */
object RingFactsCodec {
    const val VERSION = 1
    private val TRIP_ID = Regex("^[A-Za-z0-9_-]{1,64}$")

    fun encode(r: RingFactsRecord): Properties {
        val p = Properties()
        p["version"] = r.version.toString()
        p["tripId"] = r.tripId
        p["ringSeq"] = r.ringSeq.toString()
        p["ringing"] = r.ringing.toString()
        p["mode"] = r.mode.name
        p["source"] = r.source.name
        r.reason?.let { p["reason"] = it.name }
        p["startedAtWallMs"] = r.startedAtWallMs.toString()
        r.heartbeatElapsedMs?.let { p["heartbeatElapsedMs"] = it.toString() }
        r.heartbeatWallMs?.let { p["heartbeatWallMs"] = it.toString() }
        r.bootCount?.let { p["bootCount"] = it.toString() }
        r.pendingDismissAtWallMs?.let { p["pendingDismissAtWallMs"] = it.toString() }
        r.snoozedAtWallMs?.let { p["snoozedAtWallMs"] = it.toString() }
        r.silencedAtWallMs?.let { p["silencedAtWallMs"] = it.toString() }
        r.endedBy?.let { p["endedBy"] = it.name }
        r.stopSeq?.let { p["stopSeq"] = it.toString() }
        p["restarts"] = r.restarts.toString()
        return p
    }

    fun decode(p: Properties): RingFactsRecord? =
        try {
            if (p.getProperty("version")?.toIntOrNull() != VERSION) {
                null
            } else {
                RingFactsRecord(
                    version = VERSION,
                    tripId = p.req("tripId").also { if (!TRIP_ID.matches(it)) throw Invalid() },
                    ringSeq = p.req("ringSeq").toLongOrNull() ?: throw Invalid(),
                    ringing = bool(p.req("ringing")),
                    mode = enumOf<RingMode>(p.req("mode")),
                    source = enumOf<RingSource>(p.req("source")),
                    reason = p.getProperty("reason")?.let { enumOf<AlarmReason>(it) },
                    startedAtWallMs = p.req("startedAtWallMs").toLongOrNull() ?: throw Invalid(),
                    heartbeatElapsedMs = p.optLong("heartbeatElapsedMs"),
                    heartbeatWallMs = p.optLong("heartbeatWallMs"),
                    bootCount = p.getProperty("bootCount")?.let { it.toIntOrNull() ?: throw Invalid() },
                    pendingDismissAtWallMs = p.optLong("pendingDismissAtWallMs"),
                    snoozedAtWallMs = p.optLong("snoozedAtWallMs"),
                    silencedAtWallMs = p.optLong("silencedAtWallMs"),
                    endedBy = p.getProperty("endedBy")?.let { enumOf<RingEnd>(it) },
                    stopSeq = p.optLong("stopSeq"),
                    restarts = p.req("restarts").toIntOrNull()?.takeIf { it >= 0 } ?: throw Invalid(),
                )
            }
        } catch (e: Invalid) {
            null
        }

    private class Invalid : RuntimeException()

    private fun Properties.req(key: String): String = getProperty(key) ?: throw Invalid()

    /** Absent → null; present but not a number → the record is invalid. */
    private fun Properties.optLong(key: String): Long? = getProperty(key)?.let { it.toLongOrNull() ?: throw Invalid() }

    private fun bool(s: String): Boolean =
        when (s) {
            "true" -> true
            "false" -> false
            else -> throw Invalid()
        }

    private inline fun <reified E : Enum<E>> enumOf(s: String): E = enumValues<E>().firstOrNull { it.name == s } ?: throw Invalid()
}

/**
 * `ringSeq` / `stopSeq` are elapsedRealtimeNanos: they only compare within one boot, while the book survives a reboot
 * (review T16 #1). A record of another boot — other BOOT_COUNT, or a seq later than "now", which no seq of this boot can be —
 * keeps its user facts (pendingDismiss, snoozedAt, silencedAt, startedAt) but loses its seqs and is not ringing.
 */
object RingBoot {
    fun fromOtherBoot(r: RingFactsRecord, bootCount: Int?, nowNanos: Long): Boolean =
        (r.bootCount != null && bootCount != null && r.bootCount != bootCount) || maxOf(r.ringSeq, r.stopSeq ?: Long.MIN_VALUE) > nowNanos

    fun sanitize(r: RingFactsRecord?, bootCount: Int?, nowNanos: Long): RingFactsRecord? =
        if (r == null || !fromOtherBoot(r, bootCount, nowNanos)) {
            r
        } else {
            r.copy(ringSeq = Long.MIN_VALUE, stopSeq = null, ringing = false, heartbeatElapsedMs = null, bootCount = bootCount, restarts = 0)
        }

    /** Upper bound of the elapsedRealtimeNanos of anything that happened by [elapsedMs] (ms resolution). */
    fun nanosBound(elapsedMs: Long): Long = (elapsedMs + 1) * 1_000_000L - 1
}

/** A ring asked for in this process and not yet confirmed by `:ring` (in memory only, D5). */
data class StartingMarker(val tripId: String, val ringSeq: Long, val source: RingSource, val atElapsedMs: Long, val atWallMs: Long)

data class LivenessEnv(val nowWallMs: Long, val nowElapsedMs: Long, val bootCount: Int?, val backupShowing: Boolean)

/** Liveness of a ring (spec T16 §5.2). Pure. */
object RingLiveness {
    fun alive(r: RingFactsRecord, env: LivenessEnv, c: AlarmConstants): Boolean {
        if (!r.ringing) return false
        if (r.bootCount != null && env.bootCount != null && r.bootCount != env.bootCount) return false
        if (env.nowWallMs > r.startedAtWallMs + c.ringMaxMs + c.livenessGraceMs) return false
        return when (r.mode) {
            RingMode.SERVICE -> {
                val hb = r.heartbeatElapsedMs ?: return false
                val age = env.nowElapsedMs - hb
                age in 0..c.heartbeatStaleMs
            }
            RingMode.BACKUP -> env.backupShowing
        }
    }

    /** Whether [starting] is a ring `:ring` has not confirmed yet and that still counts as ringing. */
    fun pendingStart(r: RingFactsRecord?, starting: StartingMarker?, env: LivenessEnv, c: AlarmConstants): Boolean {
        if (starting == null || (r != null && r.tripId != starting.tripId)) return false
        if (r != null && r.ringSeq >= starting.ringSeq) return false
        if (r?.stopSeq != null && r.stopSeq >= starting.ringSeq) return false
        return env.nowElapsedMs - starting.atElapsedMs in 0..c.ringConfirmMs
    }

    /**
     * [RingFacts] of T15 from the book, the STARTING marker and the environment. `ringStartedAtWallMs` is also given
     * after the ring stopped (T15 "sau test" G3 tells "rang and stopped" from "never rang" with it).
     */
    fun facts(r: RingFactsRecord?, starting: StartingMarker?, env: LivenessEnv, c: AlarmConstants): RingFacts {
        val pending = pendingStart(r, starting, env, c)
        val alive = r != null && alive(r, env, c)
        val live = pending || alive
        return RingFacts(
            ringingNow = live,
            ringingSource = if (pending) starting!!.source else if (alive) r!!.source else null,
            ringStartedAtWallMs = if (pending) starting!!.atWallMs else r?.startedAtWallMs,
            pendingDismissAtWallMs = r?.pendingDismissAtWallMs,
            silencedAtWallMs = r?.silencedAtWallMs ?: if (r != null && r.ringing && !live) r.heartbeatWallMs ?: r.startedAtWallMs else null,
            pendingSnoozeAtWallMs = r?.snoozedAtWallMs,
        )
    }
}
