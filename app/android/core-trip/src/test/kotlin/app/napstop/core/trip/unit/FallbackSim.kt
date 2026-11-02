package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackState
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.planFallback
import app.napstop.core.trip.support.trackingState
import app.napstop.core.trip.support.work

/**
 * FallbackPlanner driven by a synthetic predicted(t) (T12 U73/U74 "hàm predicted(t) tổng hợp"), with the tick model of
 * T10 §4.10 "Kiểm tra F1/F2": at each tick the fallback rings if tick >= fb (checked first), the engine alarms if
 * tick >= predicted. Times in ms.
 */
class FallbackSim(private val p: EngineParams = EngineParams()) {
    data class Emission(val atMs: Long, val targetMs: Long, val lowered: Boolean)

    var fb: FallbackState = FallbackState.CLEARED
    val emissions = ArrayList<Emission>()
    val problems = ArrayList<String>()
    var engineAlarmMs: Long? = null
    var fallbackRangMs: Long? = null
    var lastPredicted: Long = 0

    private val base = trackingState(p = p, phase = TripPhase.TRACKING)

    fun run(startMs: Long, endMs: Long, stepMs: Long = 5000, predicted: (Long) -> Long) {
        var now = startMs
        while (now <= endMs) {
            val target = fb.targetAtMs
            if (target != null && now >= target) {
                fallbackRangMs = now
                return
            }
            val pr = predicted(now)
            lastPredicted = pr
            if (now >= pr) {
                engineAlarmMs = now
                return
            }
            step(now, pr)
            now += stepMs
        }
    }

    fun step(now: Long, pr: Long) {
        val prev = fb
        val w = work(base.copy(nowMs = now))
        w.fallback = prev
        planFallback(w, null, pr)
        fb = w.fallback
        if (fb != prev) {
            val inQuiet = prev.targetAtMs != null && now >= minOf(prev.targetAtMs!!, pr) - p.fallbackQuietBeforeS * 1000L
            if (inQuiet) problems += "emission inside the quiet window at $now"
            emissions += Emission(now, fb.targetAtMs!!, prev.targetAtMs != null && fb.targetAtMs!! < prev.targetAtMs!!)
        }
        val outsideQuiet = now < minOf(fb.targetAtMs!!, pr) - p.fallbackQuietBeforeS * 1000L
        if (pr - now <= p.fallbackNearS * 1000L && outsideQuiet && fb.targetAtMs!! < pr + p.fallbackLagS * 1000L) {
            problems += "near zone: fb ${fb.targetAtMs} < predicted + lag at $now"
        }
    }
}
