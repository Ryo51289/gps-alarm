package app.napstop.core.trip

// T10 §4.11: overshoot, passed-closest net, arrived. Only evaluated on a Step with an accepted fix.

/** ACCEPT: minD and the last 3 dSmooth values. */
internal fun updateMinDLast3(w: StepWork) {
    val ds = w.dSmooth ?: return
    val m = w.minD
    w.minD = if (m == null) ds else TMath.min(m, ds)
    w.last3 = (w.last3 + ds).takeLast(3)
}

internal fun recentSpeed(w: StepWork): Double = TMath.medianHi(w.recent.map { it.groundSample }) ?: w.ground ?: 0.0

internal fun increasing(last3: List<Double>): Boolean = last3.size == 3 && last3[0] < last3[1] && last3[1] < last3[2]

internal fun isFast(w: StepWork): Boolean = recentSpeed(w) * 3.6 > w.p.overshootMinSpeedKmh.toDouble()

internal fun isOvershoot(w: StepWork): Boolean {
    val p = w.p
    val minD = w.minD ?: return false
    val ds = w.dSmooth ?: return false
    val phaseOk = w.phase == TripPhase.TRACKING || w.phase == TripPhase.ALARMING || w.phase == TripPhase.SNOOZED
    val nearRadius = TMath.max(p.overshootNearMinM, if (w.cfg.mode == AlarmMode.DISTANCE) thrM(w.cfg) else 0)
    return w.overshootAtMs == null && phaseOk && minD < nearRadius.toDouble() &&
        ds - minD >= p.overshootOpenM.toDouble() && increasing(w.last3) && isFast(w)
}

internal fun isPassedClosest(w: StepWork, e: Estimate): Boolean {
    val p = w.p
    val minD = w.minD ?: return false
    val ds = w.dSmooth ?: return false
    val dStart = w.dStartM ?: return false
    val cfg = w.cfg
    val reachM = when (cfg.mode) {
        AlarmMode.DISTANCE -> thrM(cfg).toDouble()
        AlarmMode.TIME -> e.closingV * thrS(cfg)
        AlarmMode.SMART -> TMath.max(slowDistM(p), e.closingV * p.smartTargetS)
    }
    val passedRadius = TMath.max(p.passedClosestMinRadiusM.toDouble(), p.passedClosestReachFactor * reachM)
    val openNeedM = TMath.max(p.passedClosestOpenMinM.toDouble(), p.passedClosestOpenFrac * minD)
    return (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null &&
        w.gps == GpsStatus.OK && minD < passedRadius &&
        dStart - minD >= p.passedClosestOpenMinM.toDouble() &&
        ds - minD >= openNeedM && increasing(w.last3) && isFast(w)
}

internal fun isArrived(w: StepWork): Boolean {
    val ds = w.dSmooth ?: return false
    return !w.arrivedFired && ds <= w.p.arrivedRadiusM.toDouble()
}
