package app.napstop.core.trip

// T10 §4.15 wake-up time (c1–c8; C13: c7 applies in every phase except ENDED).

/** [s] is the state at the end of the Step (now = s.nowMs); [predicted] is the Step's predictedAlarmAt. */
internal fun wakeAt(s: EngineState, predicted: Long?): Long? {
    if (s.phase == TripPhase.ENDED) return null
    val p = s.params
    val now = s.nowMs
    val c = ArrayList<Long>(10)
    val active = s.phase == TripPhase.ACQUIRING || s.phase == TripPhase.TRACKING
    if (s.phase == TripPhase.ACQUIRING && !s.lostEmittedBeforeFirstFix) c += s.startedAtMs + p.acquireTimeoutS * 1000L
    val last = s.last
    if (s.gps == GpsStatus.OK && last != null) {
        c += last.fixAtMs + lostAfterS(p, s.policyIntervalAtLastFixS, s.policy) * 1000L
    }
    if (active && predicted != null) {
        c += predicted
        c += predicted - p.fallbackNearS * 1000L
    }
    if (s.phase == TripPhase.TRACKING && predicted != null) {
        c += predicted - p.denseEnterS * 1000L
        c += predicted - p.mediumEnterS * 1000L
    }
    if (s.phase == TripPhase.SNOOZED) s.alarm.snoozeUntilMs?.let { c += it }
    if (s.phase == TripPhase.ALARMING || s.phase == TripPhase.OVERSHOT) {
        s.alarm.lastRingAtMs?.let { c += it + p.alarmMaxActiveS * 1000L }
    }
    val fb = s.fallback
    if (fb.status == FallbackStatus.FAILED) fb.emittedAtMs?.let { c += it + p.fallbackRetryS * 1000L }
    if (active && fb.targetAtMs != null) {
        c += fb.targetAtMs - (p.fallbackQuietBeforeS + p.fallbackMinIntervalS) * 1000L
    }
    var best: Long? = null
    for (x in c) if (x > now && (best == null || x < best)) best = x
    return best
}
