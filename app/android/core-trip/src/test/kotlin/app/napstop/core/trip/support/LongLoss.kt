package app.napstop.core.trip.support

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.StepWork
import app.napstop.core.trip.estimate
import app.napstop.core.trip.modeReason
import java.util.Locale

/** T10.6 off (C29): the T12.2 behaviour (`preV` has no switch of its own besides lostSpeedGuardUpdates). */
internal val T106_OFF_PARAMS: EngineParams = EngineParams(gpsLostLongS = 0, passedClosestSlowRiseM = 0)

/**
 * U126: what the estimate says at the Step of a GPS_LOST alarm ([s] = the state after it). [longLostOnly]: the "long loss" term W
 * holds and neither the mode condition nor `etaS < gpsLostAlarmEtaS` does (the alarm is due to W alone). [preV]: dead reckoning
 * lifted by the speed measured before `established` (C26).
 */
internal class LostAlarmInfo(val longLostOnly: Boolean, val cvDr: Double?, val preV: Boolean, val elapsedS: Double?, val lostLongAtS: Double?)

internal fun lostAlarmInfo(s: EngineState): LostAlarmInfo {
    val e = estimate(StepWork(s)) ?: return LostAlarmInfo(false, null, false, null, null)
    val lla = e.lostLongAtS
    val longLost = s.gps == GpsStatus.LOST && lla != null && e.elapsedS >= lla
    val m = modeReason(e, s.config, s.slow, s.params)
    val eta = e.etaS
    val etaRule = eta != null && eta < s.params.gpsLostAlarmEtaS.toDouble()
    val preV = e.lift && !e.established && s.cvGuard.isEmpty()
    return LostAlarmInfo(longLost && m == null && !etaRule, e.cvDr, preV, e.elapsedS, lla)
}

/** C25 parts (thS, earlyS, cvH) of the state's W mark, recomputed test-side (C29 report, U126 classes); null when W does not apply. */
internal fun lostLongParts(s: EngineState): Triple<Double, Double, Double>? {
    val e = estimate(StepWork(s)) ?: return null
    if (e.lostLongAtS == null) return null
    val p = s.params
    val cvHintL = p.gpsLostLongHintFactor * app.napstop.core.trip.expectedSpeedMps(s.config.vehicleHint, p) / p.routeFactorPrior
    val cvH = if (e.cvDr >= cvHintL) e.cvDr else cvHintL
    val thS = s.dSmooth!! / cvH + p.etaStopPenaltyS.toDouble() - p.gpsLostAlarmEtaS.toDouble()
    val early = p.fallbackEarlyFrac * (if (thS - p.fallbackNearS >= 0.0) thS - p.fallbackNearS else 0.0)
    return Triple(thS, if (p.fallbackEarlyMaxS.toDouble() <= early) p.fallbackEarlyMaxS.toDouble() else early, cvH)
}

/**
 * U126 (T10 "T10.6 — sau số đo T12.3"): one DISTANCE case rung more than 1 800 s after the truth crossed the threshold, classified
 * dead → short → fast → ?. [st] = the state of the last Step before [crossMs]; [dTruthAtMs] = true distance at a time (ms).
 */
internal fun lateCaseLine(
    tag: String,
    hint: app.napstop.core.trip.VehicleKind,
    lateS: Double,
    first: String,
    dead: Boolean,
    crossMs: Long,
    thrM: Double,
    st: EngineState?,
    dTruthAtMs: (Long) -> Double,
): String {
    val lastFix = st?.last?.fixAtMs
    val noFix = lastFix?.let { (crossMs - it) / 1000.0 }
    val vTruth = if (lastFix == null) null else (dTruthAtMs(lastFix) - thrM) / ((crossMs - lastFix) / 1000.0)
    val cvH = st?.let { lostLongParts(it)?.third }
    val lost = st?.gps == GpsStatus.LOST
    val gpsLostLongS = (st?.params ?: EngineParams()).gpsLostLongS.toDouble()
    val cls = when {
        dead -> "dead"
        !lost || noFix == null || noFix < gpsLostLongS -> "short"
        cvH != null && vTruth != null && vTruth > cvH -> "fast"
        else -> "?"
    }
    fun f1(x: Double?) = x?.let { String.format(Locale.ROOT, "%.1f", it) } ?: "null"
    fun f2(x: Double?) = x?.let { String.format(Locale.ROOT, "%.2f", it) } ?: "null"
    return "late>1800 $tag hint=$hint late=${f1(lateS)} first=$first dead=$dead noFix=${f1(noFix)} vTruth=${f2(vTruth)} cvH=${f2(cvH)} class=$cls"
}

/** "n, p50, p90, max" of [xs] (or "-"). */
internal fun quantiles(xs: List<Double>): String {
    if (xs.isEmpty()) return "n 0"
    val l = xs.sorted()
    fun q(f: Double) = l[minOf(l.size - 1, (f * l.size).toInt())]
    fun f(x: Double) = String.format(Locale.ROOT, "%.1f", x)
    return "n ${l.size}, p50 ${f(q(0.5))}, p90 ${f(q(0.9))}, max ${f(l.last())}"
}
