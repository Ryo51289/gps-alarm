package app.napstop.core.trip.harness

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.Step
import app.napstop.core.trip.TripEnded

internal enum class Ringing { NONE, ENGINE, FALLBACK }

/**
 * OS model of T10 §8.1-4 / T12 §8.4 (platform obligations 1, 3–6). Copyable for I8 resumes.
 * `enabled == false` (config.osSim false) makes every operation a no-op.
 */
internal class OsSim(val enabled: Boolean, val osRingMaxS: Int?, val osDismissOffsetS: Int?) {
    var fbOs: Long? = null
    var ringing = Ringing.NONE
    var ringStartMs: Long? = null
    var osFallbackFiredT: Int? = null
    var osFallbackFiredAtMs: Long? = null
    var osDismissedAtMs: Long? = null

    fun copy(): OsSim {
        val o = OsSim(enabled, osRingMaxS, osDismissOffsetS)
        o.fbOs = fbOs
        o.ringing = ringing
        o.ringStartMs = ringStartMs
        o.osFallbackFiredT = osFallbackFiredT
        o.osFallbackFiredAtMs = osFallbackFiredAtMs
        o.osDismissedAtMs = osDismissedAtMs
        return o
    }

    /** OS inputs of tick [t], in order a (osDismiss), b (osRingMaxS), c (fallback fires). */
    fun tick(t: Int, nowMs: Long, alive: Boolean): List<EngineInput> {
        if (!enabled) return emptyList()
        val out = ArrayList<EngineInput>(2)
        val firedT = osFallbackFiredT
        if (!alive && firedT != null && osDismissOffsetS != null && t == firedT + osDismissOffsetS) {
            ringing = Ringing.NONE
            osDismissedAtMs = nowMs
        }
        val start = ringStartMs
        if (osRingMaxS != null && ringing != Ringing.NONE && start != null && nowMs >= start + osRingMaxS * 1000L) {
            val s = start + osRingMaxS * 1000L
            ringing = Ringing.NONE
            if (alive) out += AlarmSilenced(nowMs, s)
        }
        val fb = fbOs
        if (fb != null && nowMs >= fb) {
            ringing = Ringing.FALLBACK
            ringStartMs = fb
            fbOs = null
            if (alive) {
                out += FallbackFired(nowMs, fb)
            } else if (osFallbackFiredT == null) {
                osFallbackFiredT = t
                osFallbackFiredAtMs = fb
            }
        }
        return out
    }

    /** Reaction to one Step's events, in order. Immediate inputs go to [queue]; P07(i) violations to [violations]. */
    fun react(step: Step, queue: ArrayDeque<EngineInput>, violations: MutableList<String>, where: String) {
        if (!enabled) return
        val now = step.view.atMs
        for (e in step.events) {
            when (e) {
                is Alarm -> if (e.ringNow) {
                    if (ringing == Ringing.ENGINE) violations += "P07(i) Alarm(ringNow=true) while the engine alarm rings at $where"
                    if (ringing == Ringing.FALLBACK) {
                        queue.addLast(FallbackFired(now, ringStartMs!!))
                    } else {
                        ringing = Ringing.ENGINE
                        ringStartMs = now
                        fbOs = null
                    }
                }
                is Snoozed, is TripEnded -> ringing = Ringing.NONE
                is FallbackAlarmChanged -> {
                    fbOs = e.fallbackAtMs
                    if (e.fallbackAtMs != null) queue.addLast(FallbackScheduled(now, e.fallbackAtMs!!, true))
                }
                else -> Unit
            }
        }
    }

    fun onUserDismissOrStop() {
        if (enabled) ringing = Ringing.NONE
    }

    fun onKill() {
        if (enabled && ringing == Ringing.ENGINE) ringing = Ringing.NONE
    }

    /** MISSING (README §6 point 4): the OS lost the fallback alarm. */
    fun dropForMissing() {
        if (!enabled) return
        fbOs = null
        if (ringing == Ringing.FALLBACK) ringing = Ringing.NONE
    }
}
