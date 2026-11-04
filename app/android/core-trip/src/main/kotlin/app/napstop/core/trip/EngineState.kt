package app.napstop.core.trip

// Engine state of T10 §7.1 (field name = snapshot JSON key). Immutable; reduce() never mutates its input.

data class FixRec(
    val fixAtMs: Long,
    val lat: Double,
    val lng: Double,
    val accM: Double,
    val d: Double,
    val groundSample: Double?,
) {
    override fun toString(): String = "FixRec(fixAtMs=$fixAtMs, accM=$accM, d=$d, groundSample=$groundSample, position=<redacted>)"
}

enum class AlarmSource { ENGINE, FALLBACK }

data class AlarmState(
    val atMs: Long?,
    val reason: AlarmReason?,
    val source: AlarmSource?,
    val lastRingAtMs: Long?,
    val lastReason: AlarmReason?,
    val ringing: Boolean,
    val snoozeCount: Int,
    val snoozeUntilMs: Long?,
    val dismissedAtMs: Long?,
) {
    companion object {
        val EMPTY = AlarmState(null, null, null, null, null, false, 0, null, null)
    }
}

data class FallbackState(
    val targetAtMs: Long?,
    val emittedAtMs: Long?,
    val status: FallbackStatus,
    val confirmedAtMs: Long?,
    val resync: Boolean,
    val near: Boolean,
) {
    companion object {
        val CLEARED = FallbackState(null, null, FallbackStatus.NONE, null, false, false)
    }
}

data class BatteryState(
    val levelPct: Int?,
    val charging: Boolean,
    val segT0: Long?,
    val segL0: Int?,
    val armed: Boolean,
    val riskEmitted: Boolean,
    val choice: UserActionKind?,
    val choicePct: Int?,
) {
    companion object {
        val EMPTY = BatteryState(null, false, null, null, false, false, null, null)
    }
}

data class EndedState(val outcome: TripOutcome, val endReason: EndReason, val atMs: Long)

data class EngineState(
    val snapshotVersion: Int,
    val params: EngineParams,
    val config: TripConfig,
    val nowMs: Long,
    val startedAtMs: Long,
    val phase: TripPhase,
    val gps: GpsStatus,
    val locationCause: AvailabilityCause,
    val last: FixRec?,
    val stopAnchor: FixRec?,
    val recent: List<FixRec>,
    val rejects: List<FixRec>,
    val dSmooth: Double?,
    val dStartM: Double?,
    val minD: Double?,
    /** T10.5 round 3e: minD comes from a GPS-gap chord (not from an observed fix); gates the `notCloser` overshoot term. */
    val minDChord: Boolean = false,
    /** T10.6 (C27, C28): distance mark of the slow-vehicle passed-closest net, set only once already past the closest point. */
    val passAnchorD: Double? = null,
    val last3: List<Double>,
    val ground: Double?,
    val closing: Double?,
    val movingTimeS: Double,
    val movingSamples: Int,
    val movingDistM: Double,
    val stopStartMs: Long?,
    val slow: Boolean,
    val cvGuard: List<Double>,
    val policy: SamplingPolicy?,
    val policyIntervalAtLastFixS: Int,
    val gpsLostAtMs: Long?,
    val lostEmittedBeforeFirstFix: Boolean,
    val preAlertArmed: Boolean,
    val preAlertFired: Boolean,
    val arrivedFired: Boolean,
    val alarm: AlarmState,
    val overshootAtMs: Long?,
    val overshootPastM: Int?,
    val fallback: FallbackState,
    val battery: BatteryState,
    val maxTripDurationS: Int,
    val droppedFixes: Int,
    val ended: EndedState?,
) {
    override fun toString(): String = "EngineState(<redacted>)"
}
