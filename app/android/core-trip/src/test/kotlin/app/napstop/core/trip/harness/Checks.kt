package app.napstop.core.trip.harness

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.EndReason
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.FixRec
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEvent

/** Event with the tick it was emitted at and the index of its record. */
internal class TimedEvent(val t: Int, val rec: Int, val e: TripEvent)

/** Per-run checks of T12 §8.5 (expect*, forbid*, I1–I7, I10–I12, C16, P02 unless allowFallbackFirst). P07 / finite state come from the runner. */
internal object Checks {
    fun events(r: RunResult): List<TimedEvent> {
        val out = ArrayList<TimedEvent>()
        for ((i, rec) in r.records.withIndex()) for (e in rec.events) out += TimedEvent(rec.t, i, e)
        return out
    }

    fun matches(f: Filter, e: TripEvent): Boolean {
        if (eventName(e) != f.event) return false
        if (f.reason != null && (e !is Alarm || e.reason.name != f.reason)) return false
        if (f.ringNow != null && (e !is Alarm || e.ringNow != f.ringNow)) return false
        if (f.cause != null) {
            val c = when (e) {
                is GpsLost -> e.cause.name
                is FallbackAlarmChanged -> e.cause.name
                else -> return false
            }
            if (c != f.cause) return false
        }
        return true
    }

    /** Tick B of an `At` after the run (runtime anchors resolved from the run). */
    fun resolve(a: At, r: RunResult): Int? = Anchors.resolve(a, r.firstEventT, r.relaunchT, r.osFallbackFiredT, r.killT)

    fun check(trace: TraceModel, case: CaseModel, r: RunResult): List<String> {
        val fails = ArrayList<String>(r.violations)
        val evs = events(r)
        val tag = "${r.key.run} j=${r.key.j}"
        for (x in case.expect) {
            val first = evs.firstOrNull { matches(x.filter, it.e) }
            if (first == null) {
                fails += "expect ${x.filter}: none ($tag)"
            } else if (first.t < x.notBefore || first.t > x.notAfter) {
                fails += "expect ${x.filter}: first at t=${first.t}, window [${x.notBefore}, ${x.notAfter}] ($tag)"
            }
        }
        for (x in case.expectAfter) {
            val b = resolve(x.after, r)
            if (b == null) {
                fails += "expectAfter ${x.filter}: anchor ${x.after} never happened ($tag)"
                continue
            }
            val first = evs.firstOrNull { it.t >= b && matches(x.filter, it.e) }
            if (first == null) {
                fails += "expectAfter ${x.filter}: none after B=$b ($tag)"
            } else if (first.t - b < x.lo || first.t - b > x.hi) {
                fails += "expectAfter ${x.filter}: t=${first.t}, B=$b, within [${x.lo}, ${x.hi}] ($tag)"
            }
        }
        case.expectFallback?.let { x ->
            val last = evs.lastOrNull { it.t <= x.asOfT && it.e is FallbackAlarmChanged }?.e as FallbackAlarmChanged?
            val at = last?.fallbackAtMs
            if (at == null) {
                fails += "expectFallback: no fallbackAtMs as of t=${x.asOfT} ($tag)"
            } else {
                val s = Math.floorDiv(at - r.startMs, 1000L)
                if (s < x.notBefore || s > x.notAfter) fails += "expectFallback: $s not in [${x.notBefore}, ${x.notAfter}] ($tag)"
            }
        }
        val firstEnded = evs.firstOrNull { it.e is TripEnded }?.e as TripEnded?
        case.expectOutcome?.let {
            if (firstEnded == null) fails += "expectOutcome $it: no tripEnded ($tag)"
            else if (firstEnded.outcome.name != it) fails += "expectOutcome $it: got ${firstEnded.outcome} ($tag)"
        }
        case.expectSummaryVehicle?.let {
            if (firstEnded == null) fails += "expectSummary $it: no tripEnded ($tag)"
            else if (firstEnded.summary.vehicleGuess.name != it) fails += "expectSummary $it: got ${firstEnded.summary.vehicleGuess} ($tag)"
        }
        for (name in case.forbid) evs.firstOrNull { eventName(it.e) == name }?.let { fails += "forbid $name: at t=${it.t} ($tag)" }
        for (f in case.forbidMatch) evs.firstOrNull { matches(f, it.e) }?.let { fails += "forbidMatch $f: at t=${it.t} ($tag)" }
        for ((f, a) in case.forbidAfter) {
            val b = resolve(a, r)
            if (b == null) {
                fails += "forbidAfter $f: anchor never happened ($tag)"
                continue
            }
            evs.firstOrNull { it.t > b && matches(f, it.e) }?.let { fails += "forbidAfter $f: at t=${it.t} > B=$b ($tag)" }
        }
        fails += invariants(r, tag)
        if (case.config.kill == null && !case.allowFallbackFirst) {
            val firstAlarm = evs.firstOrNull { it.e is Alarm }?.e as Alarm?
            if (firstAlarm != null && !firstAlarm.ringNow) fails += "P02: first alarm has ringNow=false ($tag)"
        }
        return fails
    }

    /** I1–I7, I10–I12 (T10 §3). I4 against the previous Step's view and the current Step's predictedAlarmAtMs. */
    fun invariants(r: RunResult, tag: String): List<String> {
        val f = ArrayList<String>()
        val quietMs = r.params.fallbackQuietBeforeS * 1000L
        var alarmSeen = false
        var releasedSinceAlarm = false
        var ended = false
        var preAlerts = 0
        var overshoots = 0
        var expectLost = true
        var prevView: app.napstop.core.trip.TripView? = null
        for (rec in r.records) {
            val view = rec.view ?: continue
            if (rec.input is AlarmSilenced) releasedSinceAlarm = true
            var alarms = 0
            var facs = 0
            for (e in rec.events) {
                when (e) {
                    is Alarm -> {
                        alarms++
                        if (ended) f += "I2: alarm after tripEnded at t=${rec.t} ($tag)"
                        if (e.ringNow && alarmSeen && !releasedSinceAlarm) f += "I1: Alarm(ringNow) while the previous still rings at t=${rec.t} ($tag)"
                        alarmSeen = true
                        releasedSinceAlarm = false
                    }
                    is Snoozed -> releasedSinceAlarm = true
                    is FallbackAlarmChanged -> {
                        facs++
                        if (alarmSeen && e.fallbackAtMs != null && e.cause != FallbackCause.SNOOZE && e.cause != FallbackCause.RESYNC) {
                            f += "I3: FallbackAlarmChanged(${e.cause}) with a time after the first alarm at t=${rec.t} ($tag)"
                        }
                        if (e.cause == FallbackCause.ETA) {
                            val pv = prevView
                            val prevTarget = pv?.fallbackAtMs
                            val pred = view.predictedAlarmAtMs
                            if (pv != null && prevTarget != null && pv.fallbackStatus != FallbackStatus.FAILED && pred != null) {
                                val lim = minOf(prevTarget, pred) - quietMs
                                if (view.atMs >= lim) f += "I4: ETA emission inside the quiet window at t=${rec.t} ($tag)"
                            }
                        }
                    }
                    is PreAlert -> {
                        preAlerts++
                        if (alarmSeen) f += "I5: preAlert after an alarm at t=${rec.t} ($tag)"
                    }
                    is Overshoot -> overshoots++
                    is GpsLost -> {
                        if (!expectLost) f += "I7: gpsLost twice at t=${rec.t} ($tag)"
                        expectLost = false
                    }
                    is GpsRecovered -> {
                        if (expectLost) f += "I7: gpsRecovered without gpsLost at t=${rec.t} ($tag)"
                        expectLost = true
                    }
                    is TripEnded -> {
                        if (e.endReason != EndReason.USER_STOP && !alarmSeen) f += "I10: silent end ${e.endReason} at t=${rec.t} ($tag)"
                        ended = true
                    }
                    else -> Unit
                }
            }
            if (alarms > 1) f += "I11: $alarms alarms in one Step at t=${rec.t} ($tag)"
            if (facs > 1) f += "I12: $facs FallbackAlarmChanged in one Step at t=${rec.t} ($tag)"
            if ((view.snoozeUntilMs != null) != (view.phase == app.napstop.core.trip.TripPhase.SNOOZED)) {
                f += "C16: snoozeUntilMs ${if (view.snoozeUntilMs == null) "null" else "set"} in phase ${view.phase} at t=${rec.t} ($tag)"
            }
            prevView = view
        }
        if (preAlerts > 1) f += "I5: $preAlerts preAlerts ($tag)"
        if (overshoots > 1) f += "I6: $overshoots overshoots ($tag)"
        return f
    }

    /** Every Double in the state must be finite (T12 §6). */
    fun finiteStateViolation(s: EngineState): String? {
        fun bad(x: Double?) = x != null && !x.isFinite()
        fun badFix(x: FixRec?) = x != null && (bad(x.lat) || bad(x.lng) || bad(x.accM) || bad(x.d) || bad(x.groundSample))
        val any = bad(s.dSmooth) || bad(s.dStartM) || bad(s.minD) || bad(s.ground) || bad(s.closing) ||
            bad(s.movingTimeS) || bad(s.movingDistM) || s.last3.any { bad(it) } || s.cvGuard.any { bad(it) } ||
            badFix(s.last) || badFix(s.stopAnchor) || s.recent.any { badFix(it) } || s.rejects.any { badFix(it) }
        return if (any) "non-finite double in state" else null
    }
}
