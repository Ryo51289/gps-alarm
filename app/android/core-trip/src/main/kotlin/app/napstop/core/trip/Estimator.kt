package app.napstop.core.trip

// T10 §4.4 "Ước lượng tại now" (computed exactly once per Step, C7) and the `slow` flag.

internal data class Estimate(
    val established: Boolean,
    val v: Double,
    val k: Double,
    val closingV: Double,
    val guardV: Double?,
    val lift: Boolean,
    val vDr: Double,
    val cvDr: Double,
    val elapsedS: Double,
    val dNow: Double,
    val etaS: Double?,
    val errM: Double,
    val etaMinS: Double?,
    val etaMaxS: Double?,
    /** T10.6 (C25): "long loss" mark, seconds after last.fixAtMs; null unless gps == LOST and gpsLostLongS > 0. Not in the view. */
    val lostLongAtS: Double? = null,
)

internal fun expectedSpeedKmh(h: VehicleKind, p: EngineParams): Int = when (h) {
    VehicleKind.TRAIN -> p.expectedSpeedKmhTrain
    VehicleKind.COACH -> p.expectedSpeedKmhCoach
    VehicleKind.BUS -> p.expectedSpeedKmhBus
    VehicleKind.UNKNOWN -> p.expectedSpeedKmhUnknown
}

internal fun expectedSpeedMps(h: VehicleKind, p: EngineParams): Double = expectedSpeedKmh(h, p).toDouble() / 3.6

/** E at `w.now`; null before the first accepted fix. */
internal fun estimate(w: StepWork): Estimate? {
    val last = w.last ?: return null
    val dSmooth = w.dSmooth ?: return null
    val p = w.p
    val established = isEstablished(w.movingTimeS, w.movingSamples, p)
    val ground = w.ground
    val closing = w.closing
    val v = if (established && ground != null) ground else expectedSpeedMps(w.cfg.vehicleHint, p)
    val k = if (!established || closing == null || ground == null) {
        p.routeFactorPrior
    } else if (closing > 0.0) {
        TMath.clamp(ground / closing, p.routeFactorMin, p.routeFactorMax)
    } else {
        p.routeFactorMax
    }
    val closingV = v / k
    // T10.6 (2), C26: before `established` cvGuard is always empty; while LOST the measured ground speed lifts the hint speed.
    val preV = if (p.lostSpeedGuardUpdates > 0 && !established && ground != null) ground / p.routeFactorPrior else null
    var guardV: Double? = null
    if (w.gps == GpsStatus.LOST) {
        if (w.cvGuard.isNotEmpty()) {
            var m = w.cvGuard[0]
            for (i in 1 until w.cvGuard.size) m = TMath.max(m, w.cvGuard[i])
            guardV = m
        } else {
            guardV = preV
        }
    }
    val lift = guardV != null && guardV > closingV
    val vDr = if (lift) guardV!! * k else v
    val cvDr = if (lift) guardV!! else closingV
    val elapsedS = TMath.toS(w.now - last.fixAtMs)
    val inStop = w.stopStartMs != null
    val dNow = if (w.gps == GpsStatus.OK && inStop) dSmooth else TMath.max(0.0, dSmooth - cvDr * elapsedS)
    val pen = p.etaStopPenaltyS.toDouble()
    val etaS = if (vDr >= p.minSpeedForEtaMps) dNow * k / vDr + pen else null
    val errM = if (w.gps == GpsStatus.LOST) last.accM + p.lostErrFrac * cvDr * elapsedS else last.accM
    val frac = p.etaUncertaintyFrac
    val etaMinS = if (etaS == null) null else TMath.max(0.0, (dNow - errM) * k / vDr) * (1.0 - frac) + pen
    val etaMaxS = if (etaS == null) null else ((dNow + errM) * k / vDr) * (1.0 + frac) + pen
    return Estimate(
        established, v, k, closingV, guardV, lift, vDr, cvDr, elapsedS, dNow, etaS, errM, etaMinS, etaMaxS,
        lostLongAtSOf(w, dSmooth, cvDr),
    )
}

/** T10.6 (1)+(4), C25: the "long loss" mark W of §4.5 for the Step's estimate [e] (U119). */
internal fun lostLongAtS(w: StepWork, e: Estimate): Double? = w.dSmooth?.let { lostLongAtSOf(w, it, e.cvDr) }

/**
 * C25: not later than the D4 fallback of a process killed right after the last fix. Dead reckoning restarts from the last fix
 * (dSmooth / cvH, not dNow / cvH) so the mark is fixed between two fixes and never slides with now.
 */
private fun lostLongAtSOf(w: StepWork, dSmooth: Double, cvDr: Double): Double? {
    val p = w.p
    if (p.gpsLostLongS == 0 || w.gps != GpsStatus.LOST) return null
    val cvHintL = p.gpsLostLongHintFactor * expectedSpeedMps(w.cfg.vehicleHint, p) / p.routeFactorPrior
    val cvH = TMath.max(cvDr, cvHintL)
    if (!(cvH > 0.0)) return null
    val thS = dSmooth / cvH + p.etaStopPenaltyS.toDouble() - p.gpsLostAlarmEtaS.toDouble()
    val earlyS = TMath.min(p.fallbackEarlyMaxS.toDouble(), p.fallbackEarlyFrac * TMath.max(0.0, thS - p.fallbackNearS.toDouble()))
    return TMath.max(p.gpsLostLongS.toDouble(), thS - earlyS)
}

/** `slow` (SMART), updated on every Step with an accepted fix (§4.4). */
internal fun updateSlow(w: StepWork, e: Estimate) {
    val p = w.p
    val ground = w.ground
    if (!e.established || ground == null) {
        w.slow = expectedSpeedKmh(w.cfg.vehicleHint, p) < p.smartSlowSpeedKmh
    } else if (!w.slow) {
        if (ground * 3.6 < p.smartSlowSpeedKmh.toDouble()) w.slow = true
    } else {
        if (ground * 3.6 > (p.smartSlowSpeedKmh + p.smartSlowHysteresisKmh).toDouble()) w.slow = false
    }
}
