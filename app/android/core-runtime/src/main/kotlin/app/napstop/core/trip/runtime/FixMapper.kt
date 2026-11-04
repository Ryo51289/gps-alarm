package app.napstop.core.trip.runtime

import app.napstop.core.trip.LocationFix

/** Raw platform fix → engine input (spec T15 §5.4, as S1 and T10 §2.2). Pure. */
object FixMapper {
    /**
     * [nowTripMs] = trip clock at delivery, [nowElapsedNanos] = elapsed realtime at delivery. Returns null when the
     * platform gave no usable accuracy (absent, ≤ 0 or not finite); the caller counts it as `droppedPlatform`.
     * Negative or non-finite speeds are passed through: the engine treats them as null.
     */
    fun map(raw: RawFix, nowTripMs: Long, nowElapsedNanos: Long): LocationFix? {
        val acc = raw.accuracyM ?: return null
        if (!acc.isFinite() || acc <= 0f) return null
        return LocationFix(
            atMs = nowTripMs,
            fixAtMs = nowTripMs - ageMs(raw, nowElapsedNanos),
            lat = raw.lat,
            lng = raw.lng,
            accuracyM = acc.toDouble(),
            speedMps = raw.speedMps?.toDouble(),
        )
    }

    fun ageMs(raw: RawFix, nowElapsedNanos: Long): Long = maxOf(0L, (nowElapsedNanos - raw.elapsedRealtimeNanos) / 1_000_000L)
}
