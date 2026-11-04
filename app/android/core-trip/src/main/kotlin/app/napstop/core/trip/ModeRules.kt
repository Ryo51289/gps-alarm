package app.napstop.core.trip

// T10 §4.5 (three modes, alarm reason priority, predicted alarm time) and §4.13 (max trip duration).

/** `slowDistM = max(smartTargetS · smartSlowSpeedKmh / 3.6, smartFloorM)`; derived, not a parameter. */
internal fun slowDistM(p: EngineParams): Double =
    TMath.max((p.smartTargetS * p.smartSlowSpeedKmh).toDouble() / 3.6, p.smartFloorM.toDouble())

internal fun thrS(cfg: TripConfig): Int = (cfg.timeThresholdMin ?: 0) * 60

internal fun thrM(cfg: TripConfig): Int = cfg.distanceThresholdM ?: 0

/** Mode condition (§4.5 table); null when not reached. */
internal fun modeReason(e: Estimate, cfg: TripConfig, slow: Boolean, p: EngineParams): AlarmReason? {
    val eta = e.etaS
    return when (cfg.mode) {
        AlarmMode.DISTANCE -> if (e.dNow <= thrM(cfg) * p.distanceModeFactor) AlarmReason.DISTANCE else null
        AlarmMode.TIME ->
            if ((eta != null && eta <= thrS(cfg).toDouble()) || e.dNow <= p.arrivedRadiusM.toDouble()) AlarmReason.TIME else null
        AlarmMode.SMART ->
            if (slow) {
                if (e.dNow <= slowDistM(p)) AlarmReason.SMART_SLOW_DISTANCE else null
            } else if (eta != null && eta <= p.smartTargetS.toDouble()) {
                AlarmReason.SMART_TIME
            } else if (e.dNow <= p.smartFloorM.toDouble()) {
                AlarmReason.SMART_DISTANCE
            } else {
                null
            }
    }
}

/** Alarm reason priority (§4.5); only called in ACQUIRING/TRACKING before the first alarm. */
internal fun alarmReason(w: StepWork, e: Estimate?): AlarmReason? {
    val p = w.p
    if (e != null) {
        val m = modeReason(e, w.cfg, w.slow, p)
        if (w.gps == GpsStatus.LOST) {
            val eta = e.etaS
            // T10.6 (1)+(4), C25: "long loss" W, an "or" term.
            val lostLong = e.lostLongAtS
            val longLost = lostLong != null && e.elapsedS >= lostLong
            if (m != null || (eta != null && eta < p.gpsLostAlarmEtaS.toDouble()) || longLost) return AlarmReason.GPS_LOST
        } else if (m != null) {
            return m
        }
    }
    if (lowBatteryCond(w)) return AlarmReason.LOW_BATTERY
    if (w.fixAccepted && e != null && isPassedClosest(w, e)) return AlarmReason.PASSED_CLOSEST
    if (w.now - w.startedAtMs >= w.maxTripDurationS * 1000L) return AlarmReason.TIMEOUT
    return null
}

/** Mode alarm time with the given atDist / atTime functions (shared by §4.5 and the T10.2 fallback variant). */
internal inline fun modeAtWith(
    cfg: TripConfig,
    slow: Boolean,
    p: EngineParams,
    atDist: (Double) -> Long?,
    atTime: (Int) -> Long?,
): Long? = when (cfg.mode) {
    AlarmMode.DISTANCE -> atDist(thrM(cfg) * p.distanceModeFactor)
    AlarmMode.TIME -> TMath.minOrNull(atTime(thrS(cfg)), atDist(p.arrivedRadiusM.toDouble()))
    AlarmMode.SMART ->
        if (slow) atDist(slowDistM(p)) else TMath.minOrNull(atTime(p.smartTargetS), atDist(p.smartFloorM.toDouble()))
}

/**
 * §4.5 predicted alarm time ([noBattery], [withBattery] = predictedAlarmAt) and, T10.5, the wake-up bases of §4.15:
 * [wakeBasis] (`wakeBasisAt`) and [wakeBattery] (`wakeBatteryAt`). The wake-up bases never feed the view or the snapshot.
 */
internal data class Predicted(val noBattery: Long?, val withBattery: Long?, val wakeBasis: Long?, val wakeBattery: Long?) {
    companion object {
        val NONE = Predicted(null, null, null, null)
    }
}

/** §4.5 predicted alarm time; computed once per Step after step 8 (C7). */
internal fun predictedAlarmAt(w: StepWork, e: Estimate?): Predicted {
    if ((w.phase != TripPhase.ACQUIRING && w.phase != TripPhase.TRACKING) || w.alarm.atMs != null) return Predicted.NONE
    val p = w.p
    val now = w.now
    val deadlineAt = w.startedAtMs + w.maxTripDurationS * 1000L
    if (e == null) return Predicted(deadlineAt, deadlineAt, deadlineAt, null)
    val atDist = { x: Double -> if (e.cvDr > 0.0) now + TMath.floorMs(TMath.max(0.0, e.dNow - x) / e.cvDr) else null }
    val atTime = { s: Int -> e.etaS?.let { now + TMath.floorMs(TMath.max(0.0, it - s.toDouble())) } }
    val modeAt = modeAtWith(w.cfg, w.slow, p, atDist, atTime)
    // T10.6: lostLongAt depends only on the last fix, dSmooth, cvDr and params, so it is fixed between two fixes (wake-up basis).
    val lostLongAt = e.lostLongAtS?.let { w.last!!.fixAtMs + TMath.floorMs(it) }
    val lostAt = if (w.gps == GpsStatus.LOST) TMath.minOrNull(atTime(p.gpsLostAlarmEtaS), lostLongAt) else null
    val noBattery = TMath.minOrNull(modeAt, lostAt, deadlineAt)
    val battery = batteryAt(w)
    // T10.5: GPS OK and stopped means dNow = dSmooth (§4.4), so modeAt = now + constant slides with now: not a wake-up basis.
    val wakeBasis = if (slides(w, e)) deadlineAt else noBattery
    return Predicted(noBattery, TMath.minOrNull(noBattery, battery), wakeBasis, battery)
}

/** T10.5 §4.5 `slides`: the estimate is frozen at dSmooth (GPS OK, stop in progress), the same test as [estimate]. */
internal fun slides(w: StepWork, e: Estimate?): Boolean = e != null && w.gps == GpsStatus.OK && w.stopStartMs != null

/** T10.5 §4.5 `wakeBasisAt` alone (U106 g); the engine reads it from [predictedAlarmAt]. */
internal fun wakeBasisAt(w: StepWork, e: Estimate?): Long? = predictedAlarmAt(w, e).wakeBasis

/** §4.13: max trip duration fixed at the Step of the first accepted fix (step 5). */
internal fun maxTripDurationFromFirstFix(etaS: Double?, p: EngineParams): Int =
    if (etaS == null) p.maxTripMinS else TMath.clamp(TMath.roundHalfUp(2.0 * etaS), p.maxTripMinS, p.maxTripCapS)
