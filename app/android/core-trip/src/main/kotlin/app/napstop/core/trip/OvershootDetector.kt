package app.napstop.core.trip

import kotlin.math.abs
import kotlin.math.sqrt

// T10 §4.11: overshoot, passed-closest net, arrived. Only evaluated on a Step with an accepted fix.
// T10.5 round 3/3b: destination passed inside a GPS gap (chord between the fix before the gap and the first fix after it lowers
// minD; no immediate chord alarm, round 3b). T10.7: also after an alarm (ALARMING/SNOOZED), so a chime that stopped by itself
// re-rings OVERSHOOT by the usual rule (increasing && fast) when the vehicle passed the destination inside the gap (RK24).
// T10.7 round 2 (C31): after the alarm the chord only proves "came near" (alarmedChordD → nearD), never "moved away 1 km".

/** ACCEPT: minD and the last 3 dSmooth values. */
internal fun updateMinDLast3(w: StepWork) {
    val ds = w.dSmooth ?: return
    val m = w.minD
    if (m == null || ds < m) {
        w.minD = ds
        w.minDChord = false // T10.5 round 3e: an observed fix closer than the chord (equal keeps the flag)
    }
    w.last3 = (w.last3 + ds).takeLast(3)
}

internal fun recentSpeed(w: StepWork): Double = TMath.medianHi(w.recent.map { it.groundSample }) ?: w.ground ?: 0.0

internal fun increasing(last3: List<Double>): Boolean = last3.size == 3 && last3[0] < last3[1] && last3[1] < last3[2]

internal fun isFast(w: StepWork): Boolean = recentSpeed(w) * 3.6 > w.p.overshootMinSpeedKmh.toDouble()

private fun nearRadiusM(w: StepWork): Double =
    TMath.max(w.p.overshootNearMinM, if (w.cfg.mode == AlarmMode.DISTANCE) thrM(w.cfg) else 0).toDouble()

/**
 * T10.7 round 2 (C31): "came near" distance — minD, or min(minD, alarmedChordD) when a chord was taken after the first alarm
 * (exactly minD, no call to min, when alarmedChordD is null).
 */
internal fun nearD(w: StepWork): Double? {
    val m = w.minD ?: return null
    val a = w.alarmedChordD ?: return m
    return TMath.min(m, a)
}

internal fun isOvershoot(w: StepWork): Boolean {
    val p = w.p
    val minD = w.minD ?: return false
    val ds = w.dSmooth ?: return false
    val nd = nearD(w)!!
    val phaseOk = w.phase == TripPhase.TRACKING || w.phase == TripPhase.ALARMING || w.phase == TripPhase.SNOOZED
    // T10.5 round 3b/3c: or, before any alarm, the vehicle is not getting closer: a stop in progress, or dSmooth not below its
    // value 2 fixes earlier (lag-2, also true for repeated or alternating coordinates of a parked vehicle with poor fixes).
    // T10.5 round 3e: only while minD comes from the GPS-gap chord (minDChord); normal tracking is the T12.1 rule.
    val l3 = w.last3
    // T10.5 round 3d: the 3 smoothed distances are all >= minD + overshootOpenM, so one accepted outlier fix cannot fake minD.
    val notCloser = w.stopStartMs != null ||
        (l3.size == 3 && l3[2] >= l3[0] && TMath.min(l3[0], TMath.min(l3[1], l3[2])) - minD >= p.overshootOpenM.toDouble())
    val notYet = (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null
    // T10.7 round 2 (C31): (1) came near uses nearD (may come from a chord after the alarm); (2) moved away > 1 km uses minD
    // (observed fixes, or a chord before any alarm), never alarmedChordD.
    return w.overshootAtMs == null && phaseOk && nd < nearRadiusM(w) &&
        ds - minD >= p.overshootOpenM.toDouble() && ((increasing(l3) && isFast(w)) || (notYet && w.minDChord && notCloser))
}

/** Projection of the destination on the chord [l] → [f] in a local plane around it: parameter u and distance (m). */
internal class Chord(val u: Double, val distM: Double)

/**
 * T10.5 round 3 `chordClosest` without the `0 < u < 1` test (diagnostics, U116). Local plane around the destination with
 * cosDeg(destLat) (D1: only + − × ÷ sqrt); null when a longitude is more than 180° away or the chord has zero length.
 */
internal fun chordProjection(lLat: Double, lLng: Double, fLat: Double, fLng: Double, cfg: TripConfig): Chord? {
    if (abs(lLng - cfg.destLng) > 180.0 || abs(fLng - cfg.destLng) > 180.0) return null
    val s = K_EARTH_RADIUS_M * K_DEG_TO_RAD
    val c = cosDeg(cfg.destLat)
    val ax = (lLng - cfg.destLng) * c * s
    val ay = (lLat - cfg.destLat) * s
    val ex = (fLng - cfg.destLng) * c * s - ax
    val ey = (fLat - cfg.destLat) * s - ay
    val len2 = ex * ex + ey * ey
    if (len2 == 0.0) return null
    val u = -(ax * ex + ay * ey) / len2
    val px = ax + u * ex
    val py = ay + u * ey
    return Chord(u, sqrt(px * px + py * py))
}

/** T10 §4.11 (T10.5 round 3) `chordClosest`: distance from the destination to the chord L → f, only when 0 < u < 1. */
internal fun chordClosest(l: FixRec, f: FixRec, cfg: TripConfig): Double? {
    val ch = chordProjection(l.lat, l.lng, f.lat, f.lng, cfg) ?: return null
    return if (ch.u > 0.0 && ch.u < 1.0) ch.distM else null
}

/**
 * T10.5 round 3 `gapFix`: first accepted fix after a GPS gap. [phase], [overshootAtMs], [gpsBefore],
 * [policyIntervalAtLastFixS] and [policy] are the values before step 2 changed them; [l] is `last` before this fix.
 * T10.7 (C30, RK24): also after an alarm (ALARMING/SNOOZED). T10.7 round 2 (C31): there the chord no longer lowers minD;
 * it only records alarmedChordD (the "came close" half via nearD), the re-ring still needs increasing && fast against minD.
 */
internal fun isGapFix(
    phase: TripPhase,
    overshootAtMs: Long?,
    gpsBefore: GpsStatus,
    l: FixRec?,
    f: FixRec,
    p: EngineParams,
    policyIntervalAtLastFixS: Int,
    policy: SamplingPolicy?,
): Boolean = l != null &&
    (phase == TripPhase.ACQUIRING || phase == TripPhase.TRACKING || phase == TripPhase.ALARMING || phase == TripPhase.SNOOZED) &&
    overshootAtMs == null &&
    (gpsBefore == GpsStatus.LOST || f.fixAtMs - l.fixAtMs >= lostAfterS(p, policyIntervalAtLastFixS, policy) * 1000L)

private fun passedRadiusM(w: StepWork, e: Estimate): Double {
    val p = w.p
    val cfg = w.cfg
    val reachM = when (cfg.mode) {
        AlarmMode.DISTANCE -> thrM(cfg).toDouble()
        AlarmMode.TIME -> e.closingV * thrS(cfg)
        AlarmMode.SMART -> TMath.max(slowDistM(p), e.closingV * p.smartTargetS)
    }
    return TMath.max(p.passedClosestMinRadiusM.toDouble(), p.passedClosestReachFactor * reachM)
}

private fun openNeedM(p: EngineParams, minD: Double): Double = TMath.max(p.passedClosestOpenMinM.toDouble(), p.passedClosestOpenFrac * minD)

internal fun isPassedClosest(w: StepWork, e: Estimate): Boolean {
    val p = w.p
    val minD = w.minD ?: return false
    val ds = w.dSmooth ?: return false
    val dStart = w.dStartM ?: return false
    val passedRadius = passedRadiusM(w, e)
    val openNeedM = openNeedM(p, minD)
    return (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null &&
        w.gps == GpsStatus.OK && minD < passedRadius &&
        dStart - minD >= p.passedClosestOpenMinM.toDouble() &&
        ds - minD >= openNeedM && increasing(w.last3) && (isFast(w) || slowAway(w))
}

/**
 * T10.6 (3), C27: on every Step with an accepted fix (ACCEPT/REANCHOR), after step 7 and before alarmReason, in every phase.
 * The mark is the smoothed distance measured once the gap to minD is already open, from good (GNSS) fixes only, going down only;
 * it is cleared whenever the geometric terms of passedClosest stop holding.
 */
internal fun updatePassAnchor(w: StepWork, e: Estimate?) {
    val p = w.p
    val minD = w.minD
    val ds = w.dSmooth
    val dStart = w.dStartM
    val f = w.last
    val passOpen = p.passedClosestSlowRiseM > 0 && e != null && minD != null && ds != null && dStart != null && f != null &&
        (w.phase == TripPhase.ACQUIRING || w.phase == TripPhase.TRACKING) && w.alarm.atMs == null &&
        w.gps == GpsStatus.OK && minD < passedRadiusM(w, e) &&
        dStart - minD >= p.passedClosestOpenMinM.toDouble() && ds - minD >= openNeedM(p, minD)
    if (!passOpen) {
        w.passAnchorD = null
        return
    }
    if (!isGoodFix(w)) return
    val a = w.passAnchorD
    w.passAnchorD = if (a == null) ds else TMath.min(a, ds!!)
}

private fun isGoodFix(w: StepWork): Boolean {
    val f = w.last ?: return false
    return f.accM <= w.p.speedSampleMaxAccM
}

/** T10.6 (3), C27: two smoothed distances in a row at least passedClosestSlowRiseM above the mark (read after the update). */
internal fun slowAway(w: StepWork): Boolean {
    val a = w.passAnchorD ?: return false
    val l3 = w.last3
    return isGoodFix(w) && l3.size == 3 && l3[1] - a >= w.p.passedClosestSlowRiseM.toDouble()
}

internal fun isArrived(w: StepWork): Boolean {
    val ds = w.dSmooth ?: return false
    return !w.arrivedFired && ds <= w.p.arrivedRadiusM.toDouble()
}
