package app.napstop.core.trip

import kotlin.math.abs

// T10 §4.10 (+ T10.2) fallback alarm planner; fb state changes follow T12 C1.

/** T10.2: predicted alarm time "if the vehicle is faster than estimated"; far zone only. Always <= predicted. */
internal fun fallbackPredictedAt(w: StepWork, e: Estimate?, predicted: Long?): Long? {
    if (predicted == null) return null
    if (e == null) return predicted
    val p = w.p
    val now = w.now
    val cvHint = p.fallbackHintSpeedFactor * expectedSpeedMps(w.cfg.vehicleHint, p) / p.routeFactorPrior
    val cvFb = TMath.max(e.cvDr, cvHint)
    if (!(cvFb > e.cvDr)) return predicted
    val etaFb = e.dNow / cvFb + p.etaStopPenaltyS.toDouble()
    val atDistFb = { x: Double -> now + TMath.floorMs(TMath.max(0.0, e.dNow - x) / cvFb) }
    val atTimeFb = { s: Int -> now + TMath.floorMs(TMath.max(0.0, etaFb - s.toDouble())) }
    val modeAtFb = modeAtWith(w.cfg, w.slow, p, atDistFb, atTimeFb)
    val lostAtFb = if (w.gps == GpsStatus.LOST) atTimeFb(p.gpsLostAlarmEtaS) else null
    return TMath.minOrNull(predicted, modeAtFb, lostAtFb)
}

/** Ideal fallback time (lower edge of the hold band in the near zone). */
internal fun fallbackTarget(now: Long, predicted: Long?, predictedFb: Long?, p: EngineParams): Long? {
    if (predicted == null) return null
    val t = TMath.max(0.0, TMath.toS(predicted - now))
    if (t <= p.fallbackNearS.toDouble()) {
        return TMath.max(now + p.fallbackMinLeadS * 1000L, TMath.max(predicted, now) + p.fallbackLagS * 1000L)
    }
    val pFb = predictedFb ?: predicted
    val tf = TMath.max(0.0, TMath.toS(pFb - now))
    val earlyMs = TMath.floorMs(
        TMath.min(p.fallbackEarlyMaxS.toDouble(), p.fallbackEarlyFrac * TMath.max(0.0, tf - p.fallbackNearS.toDouble())),
    )
    return TMath.max(now + p.fallbackNearS * 1000L, pFb + p.fallbackLagS * 1000L - earlyMs)
}

/** Time to emit, or null for "no emission". Only called while active (ACQUIRING/TRACKING, no alarm yet). */
internal fun nextFallbackAt(fb: FallbackState, target: Long?, predicted: Long, now: Long, p: EngineParams): Long? {
    if (target == null) return null
    if (fb.status == FallbackStatus.FAILED) {
        val emitted = fb.emittedAtMs ?: return target
        return if (now - emitted >= p.fallbackRetryS * 1000L) target else null
    }
    val cur = fb.targetAtMs ?: return target
    if (now >= TMath.min(cur, predicted) - p.fallbackQuietBeforeS * 1000L) return null
    val emitted = fb.emittedAtMs ?: now
    if (TMath.toS(predicted - now) <= p.fallbackNearS.toDouble()) {
        val slackMs = p.fallbackNearSlackS * 1000L
        if (cur < target) return if (fb.near) target + p.fallbackNearSlackS * 500L else target
        if (cur - (target + slackMs) >= p.fallbackMinShiftS * 1000L && now - emitted >= p.fallbackMinIntervalS * 1000L) {
            return target + slackMs
        }
        return null
    }
    if (abs(target - cur) < p.fallbackMinShiftS * 1000L) return null
    if (target < cur) return target
    return if (now - emitted >= p.fallbackMinIntervalS * 1000L) target else null
}

/** Step 9 FallbackPlanner. */
internal fun planFallback(w: StepWork, e: Estimate?, predicted: Long?) {
    val active = (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null
    if (!active || predicted == null) return
    val p = w.p
    val target = fallbackTarget(w.now, predicted, fallbackPredictedAt(w, e, predicted), p)
    val at = nextFallbackAt(w.fallback, target, predicted, w.now, p) ?: return
    val cause = if (w.fallback.targetAtMs == null && w.fallback.resync) FallbackCause.RESYNC else FallbackCause.ETA
    w.fallback = FallbackState(at, w.now, FallbackStatus.REQUESTED, null, false, TMath.toS(predicted - w.now) <= p.fallbackNearS.toDouble())
    w.events += FallbackAlarmChanged(w.now, at, cause)
}
