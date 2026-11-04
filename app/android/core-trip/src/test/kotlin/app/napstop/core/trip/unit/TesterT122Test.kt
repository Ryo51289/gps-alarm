package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.BatteryState
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.RestoreInfo
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.Step
import app.napstop.core.trip.StepWork
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.VehicleKind
import app.napstop.core.trip.batteryAt
import app.napstop.core.trip.estimate
import app.napstop.core.trip.fallbackPredictedAt
import app.napstop.core.trip.fallbackTarget
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.StepRecord
import app.napstop.core.trip.support.DEST
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.TestGeo
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import kotlin.math.abs

/**
 * Tester additions for T12.2 (T10.5 + "T10.5 vòng 2"; docs/test-reports/T12.2.md). Question: "is there any situation where the
 * engine does not wake the user on time?"
 *  - (a) restore while GPS is lost, the first fix 0–150 s before the fallback time (round-2 `soon` branch, urgent later shift,
 *    remainder < fallbackMinLeadS): exactly one alarm, no double ring, the fallback moved to fallbackTarget.
 *  - (b) the destination passed inside a tunnel / GPS gap, the first fix <= 90 s before the fallback (RK18 b): alarm time vs
 *    the threshold crossing. T10.5 round 3/3b: flipped to U115 (no TIMEOUT; alarm within a few fixes after the gap).
 *  - (c) GPS lost > 1 h with a changing true speed: GPS_LOST lateness (known spec limitation, T10.6; numbers pinned).
 *  - (d) wake-up storm regression: stopped at tier boundaries 600/900/3600 s with GPS OK, with and without a (sliding) battery
 *    forecast, and moving with a battery forecast sliding just above a boundary.
 *  - (e) fuzz: (e1) a stop near the alarm boundary (new information inside the quiet window), (e2) Doze trips with fixes at
 *    wake-ups, kills/restores, platform cancel lag: no double ring, one alarm, I1–I7, I10–I14 at every Step, urgent shifts set
 *    exactly fallbackTarget.
 * Platform model ([Sim]): an OS fallback alarm per FallbackAlarmChanged(at), set before the old one is cancelled; the old one is
 * cancelled after a lag (0–[Sim.cancelLagMaxMs]); FallbackScheduled(ok) right after; a fired OS alarm is delivered as
 * FallbackFired and cancels the trip's other alarms (obligation 5); a kill keeps the OS alarms; restart = restore (snapshot
 * round trip) with RANG when an OS alarm fired while dead, MISSING clears the OS alarms.
 */
class TesterT122Test {
    private val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop").also { it.mkdirs() }
    private val p = EngineParams()

    private class Rng(seed: Long) {
        private var x = seed * -0x61c8864680b583ebL + 0x7654321L

        fun next(): Long {
            x += -0x61c8864680b583ebL
            var z = x
            z = (z xor (z ushr 30)) * -0x40a7b892e31b1a47L
            z = (z xor (z ushr 27)) * -0x6b2fb644ecceee15L
            return z xor (z ushr 31)
        }

        fun int(n: Int): Int = ((next() ushr 1) % n).toInt()

        fun dbl(): Double = (next() ushr 11).toDouble() / (1L shl 53).toDouble()

        fun dbl(lo: Double, hi: Double): Double = lo + (hi - lo) * dbl()

        fun chance(q: Double): Boolean = dbl() < q
    }

    /** Signed distance to the destination (negative = past it) under a piecewise-constant closing speed; times absolute ms. */
    private class Truth(val d0: Double, val t0: Long) {
        val segs = ArrayList<Pair<Long, Double>>()

        fun dAt(t: Long): Double {
            var d = d0
            for (i in segs.indices) {
                val (s0, v) = segs[i]
                if (s0 >= t) break
                val s1 = if (i + 1 < segs.size) minOf(segs[i + 1].first, t) else t
                d -= v * (s1 - s0) / 1000.0
            }
            return d
        }

        fun speedAt(t: Long): Double = segs.lastOrNull { it.first <= t }?.second ?: 0.0

        /** First ms at which dAt <= x (binary search up to [until]), or null. */
        fun crossAt(x: Double, until: Long): Long? {
            if (dAt(until) > x) return null
            var lo = t0
            var hi = until
            while (hi - lo > 1) {
                val m = (lo + hi) / 2
                if (dAt(m) > x) lo = m else hi = m
            }
            return hi
        }
    }

    private fun fixAt(t: Long, d: Double, acc: Double = 8.0, spd: Double? = null, ageMs: Long = 0, eastM: Double = 0.0): LocationFix {
        val p0 = TestGeo.pointOnMeridian(DEST, d)
        val pt = if (eastM == 0.0) p0 else TestGeo.jitter(p0, eastM, 0.0)
        return LocationFix(t, t - ageMs, pt.lat, pt.lng, acc, spd)
    }

    private class OsAlarm(val at: Long, var cancelAt: Long = Long.MAX_VALUE, var cancelCause: FallbackCause? = null)

    /** Engine + platform model with checks at every Step (see the class comment). */
    private inner class Sim(start: Step, val tag: String, val rng: Rng, val okP: Double = 1.0, val cancelLagMaxMs: Long = 0L) {
        var step: Step = start
        val records = ArrayList<StepRecord>()
        val viol = ArrayList<String>()
        val os = ArrayList<OsAlarm>()
        var engineRinging = false
        var osRinging = false
        val alarms = ArrayList<Pair<Alarm, String>>()
        val allEvents = ArrayList<app.napstop.core.trip.TripEvent>()
        var osFired = 0
        var raceFired = 0
        val supersedeRaces = ArrayList<String>()
        var urgent = 0
        var soonShifts = 0
        var dead = false
        var steps = 0
        var lastInput = "start"
        var truthSpeed: ((Long) -> Double)? = null
        val believedStopOverLag = ArrayList<String>()
        var trace: StringBuilder? = null

        /** U126: the state after the Step of the first Alarm. */
        var firstAlarmState: app.napstop.core.trip.EngineState? = null

        /** U126 classes: states after every Step; harness death intervals [kill, restart). */
        val states = ArrayList<app.napstop.core.trip.EngineState>()
        val deadIntervals = ArrayList<Pair<Long, Long>>()
        private var killedAt: Long? = null

        init {
            afterStep(null, start, "start")
        }

        val now: Long get() = step.state.nowMs
        val ended: Boolean get() = step.state.phase == TripPhase.ENDED

        fun nextOs(): OsAlarm? = os.filter { it.at < it.cancelAt }.minByOrNull { it.at }

        private fun rel(t: Long) = (t - S) / 1000.0

        fun v(msg: String) {
            if (viol.size < 20) viol += "$tag t=${rel(now)} after $lastInput: $msg"
        }

        fun feed(input: EngineInput, label: String = input.javaClass.simpleName): Step {
            check(!dead)
            val prev = step
            val s = TripEngine.reduce(prev.state, input)
            if (input is LocationFix || input is BatterySample) noteInfo(prev, s)
            return afterStep(prev, s, label, input)
        }

        /** The OS fallback alarm [a] fires; delivered as FallbackFired unless the process is dead. */
        fun fireOs(a: OsAlarm) {
            os.remove(a)
            osFired++
            if (a.cancelAt != Long.MAX_VALUE) raceFired++
            if (engineRinging || osRinging) {
                // An alarm whose cancel was requested by SUPERSEDED / TRIP_ENDED but that fires within the platform cancel lag is a
                // platform race (obligation 4), counted; any other second ring (incl. an ETA move < lag before F) is a violation.
                val c = a.cancelCause
                if (c == FallbackCause.SUPERSEDED || c == FallbackCause.TRIP_ENDED) supersedeRaces += "$tag t=${rel(now)} F=${rel(a.at)} cause=$c"
                else v("double ring: OS fallback at ${rel(a.at)} fires while ${if (engineRinging) "the engine" else "an OS"} alarm rings (race cause $c)")
            }
            osRinging = true
            os.clear() // obligation 5
            if (!dead && alarms.isEmpty()) classifyOsFirst(a.at)
            if (!dead) feed(FallbackFired(maxOf(now, a.at), a.at), "FallbackFired(${rel(a.at)})")
        }

        /** Last Step with new information (fix, battery sample, restore): its now, F/status before, predicted after, moved later. */
        var lastInfo: Triple<Long, Pair<Long?, FallbackStatus>, Pair<Long?, Boolean>>? = null
        val osFirstKinds = sortedMapOf<String, Int>()
        val osFirstEarly = ArrayList<Double>()

        /**
         * The OS fallback is about to be the first alarm while the process lives. T10.5 U111 check: if the last new information
         * was eligible for the urgent later shift (F − t >= minLead, predicted − t > Q, predicted >= F) it must have moved F
         * later. Otherwise classified: "engine believes stopped, <= Q" (RK2/RK19, bounded by predicted + lag + 1 s), or "other".
         */
        private fun classifyOsFirst(f: Long) {
            val li = lastInfo
            val q = p.fallbackQuietBeforeS * 1000L
            if (li != null) {
                val (t, before, after) = li
                val (fB, stB) = before
                val (pA, moved) = after
                if (fB == f && stB != FallbackStatus.FAILED && pA != null && f - t >= p.fallbackMinLeadS * 1000L && pA - t > q && pA >= f && !moved) {
                    v("eligible for the urgent later shift but not rescued (info at ${rel(t)}, F ${rel(f)}, P ${rel(pA)})")
                }
            }
            val pv = step.view.predictedAlarmAtMs
            val believedStop = step.view.gps == GpsStatus.OK && step.state.stopStartMs != null && pv != null && pv - now <= q
            val k = when {
                believedStop -> "believedStop<=Q"
                li != null && li.first > (step.state.fallback.emittedAtMs ?: Long.MIN_VALUE) -> "newInfoAfterPlanning"
                else -> "plannedOnSameInfo"
            }
            osFirstKinds[k] = (osFirstKinds[k] ?: 0) + 1
            if (pv != null) osFirstEarly += (pv - f) / 1000.0
            // T10 "T10.5 vòng 2" (2) bound for U111 is predicted + lag + 1 s; with the near-zone hold band (F2: F up to
            // target + slack) the bound reachable here is predicted + lag + slack + 1 s (counted separately, report note #3).
            if (believedStop && f > pv!! + p.fallbackLagS * 1000L + 1000L) {
                believedStopOverLag += "${rel(f)}: F-P=${(f - pv) / 1000.0} s truthSpeed=${truthSpeed?.invoke(f)}"
            }
            if (believedStop && f > pv + (p.fallbackLagS + p.fallbackNearSlackS) * 1000L + 1000L) {
                v("believed-stop fallback later than predicted + lag + slack + 1 s: F=${rel(f)} P(prev)=${rel(pv)} F-P=${(f - pv) / 1000.0} s " +
                    "emitted=${step.state.fallback.emittedAtMs?.let { rel(it) }} truthSpeed=${truthSpeed?.invoke(f)}")
            }
        }

        private fun noteInfo(prev: Step, s: Step) {
            val f = prev.state.fallback.targetAtMs
            val moved = f != null && s.events.any { it is FallbackAlarmChanged && (it.fallbackAtMs ?: Long.MIN_VALUE) > f }
            lastInfo = Triple(s.state.nowMs, f to prev.state.fallback.status, s.view.predictedAlarmAtMs to moved)
        }

        /** Key of the first alarm as in the firstAlarm table of FuzzStats. */
        fun firstKey(): String {
            val f = alarms.firstOrNull() ?: return "none"
            return "${if (f.second.startsWith("FallbackFired")) "os" else if (f.second.startsWith("RESTORE")) "restore" else "engine"} ${f.first.reason}"
        }

        fun kill(atMs: Long = step.state.nowMs) {
            killedAt = atMs
            dead = true
            engineRinging = false // the engine ring dies with the process (AlarmRingService is T16)
        }

        /** Restart at [at]: RANG if an OS alarm fired while dead, else [info]. */
        fun restart(at: Long, info: FallbackRestoreStatus): Step {
            check(dead)
            val f = nextOs()
            val prev = step
            val (t, ri) = if (f != null && f.at <= at) {
                fireOs(f)
                maxOf(f.at, prev.state.nowMs) to RestoreInfo(FallbackRestoreStatus.RANG, f.at)
            } else {
                if (info == FallbackRestoreStatus.MISSING) os.clear()
                at to RestoreInfo(info)
            }
            dead = false
            killedAt?.let { deadIntervals += it to t }
            killedAt = null
            val snap = TripEngine.decodeSnapshot(TripEngine.encodeSnapshot(prev.state))
            val s = TripEngine.restore(snap, t, ri)
            noteInfo(prev, s)
            return afterStep(prev, s, "RESTORE ${ri.status}", null)
        }

        private fun afterStep(prev: Step?, s: Step, label: String, input: EngineInput? = null): Step {
            step = s
            steps++
            states += s.state
            lastInput = label
            records += StepRecord(((s.state.nowMs - S) / 1000).toInt(), input, "[]", s.events, s.view)
            trace?.append("t=${rel(s.state.nowMs)} $label -> ${s.view.phase} gps=${s.view.gps} d=${s.view.distanceM} P=${s.view.predictedAlarmAtMs?.let { rel(it) }} " +
                "wake=${s.view.wakeAtMs?.let { rel(it) }} fb=${s.view.fallbackAtMs?.let { rel(it) }}/${s.view.fallbackStatus} near=${s.state.fallback.near} " +
                "stop=${s.state.stopStartMs != null} ev=${s.events.map { it.javaClass.simpleName }}")?.append('\n')
            allEvents += s.events
            Checks.finiteStateViolation(s.state)?.let { v(it) }
            // I14 and restore PENDING at now: silent, same state.
            if (s.view.phase != TripPhase.ENDED) {
                val again = TripEngine.reduce(s.state, Tick(s.state.nowMs))
                if (again.events.isNotEmpty() || again.state != s.state || again.view != s.view) v("I14 Tick(now) not silent")
                val rp = TripEngine.restore(s.state, s.state.nowMs, RestoreInfo(FallbackRestoreStatus.PENDING))
                if (rp.events.isNotEmpty() || rp.state != s.state) v("restore PENDING at now not silent")
                val w = s.view.wakeAtMs
                if (w != null) {
                    val rr = TripEngine.reduce(s.state, Tick(w))
                    val ok = rr.events.any { it is Alarm } || rr.state.phase != s.state.phase || (rr.view.wakeAtMs ?: Long.MIN_VALUE) > w
                    if (!ok) v("Tick(wakeAt) neither rings nor re-arms later")
                }
            }
            for (e in s.events) {
                when (e) {
                    is Alarm -> {
                        if (alarms.isEmpty()) firstAlarmState = s.state
                        alarms += e to label
                        if (e.ringNow) {
                            if (osRinging) v("double ring: engine Alarm(${e.reason}, ringNow) while the OS fallback rings")
                            if (engineRinging) v("double ring: engine Alarm(${e.reason}, ringNow) while the engine rings")
                            engineRinging = true
                        }
                    }
                    is FallbackAlarmChanged -> if (e.cause == FallbackCause.ETA && prev != null) {
                        val q = Checks.quietEmission(prev.view, s.view, e, s.state.params)
                        if (q == true) urgent++
                        if (q == false) v("I4 ETA emission inside the quiet window")
                        val pf = prev.state.fallback
                        val cur = pf.targetAtMs
                        val at = e.fallbackAtMs
                        val pr = s.view.predictedAlarmAtMs
                        val far = pr != null && pr - s.state.nowMs > p.fallbackNearS * 1000L
                        val soon = q == null && far && cur != null && at != null && at > cur && pf.status != FallbackStatus.FAILED &&
                            cur - s.state.nowMs <= (p.fallbackQuietBeforeS + p.fallbackMinIntervalS) * 1000L &&
                            s.state.nowMs - (pf.emittedAtMs ?: s.state.nowMs) < p.fallbackMinIntervalS * 1000L
                        if (soon) soonShifts++
                        // Every ETA emission is fallbackTarget of the end-of-Step state (planFallback is the last step): exactly for
                        // the urgent later shift, the round-2 far-zone shift and the far zone; near zone: target .. target + slack.
                        if (pr != null && at != null) {
                            val w = StepWork(s.state)
                            val est = estimate(w)
                            val target = fallbackTarget(w.now, pr, fallbackPredictedAt(w, est, pr), s.state.params)
                            val slackMs = p.fallbackNearSlackS * 1000L
                            val exact = q == true || soon || far || cur == null
                            if (target == null || (exact && at != target) || (!exact && (at < target || at > target + slackMs))) {
                                v("ETA emission at ${rel(at)} vs fallbackTarget ${target?.let { rel(it) }} (urgent=${q == true} soon=$soon far=$far)")
                            }
                        }
                    }
                    is TripEnded -> {
                        engineRinging = false
                        osRinging = false
                    }
                    else -> Unit
                }
            }
            // Platform reaction: set the new OS alarm first, cancel the old one after a lag; then FallbackScheduled.
            for (e in s.events) {
                if (e is FallbackAlarmChanged) {
                    val lag = if (cancelLagMaxMs > 0) rng.int(cancelLagMaxMs.toInt() + 1).toLong() else 0L
                    for (a in os) if (a.cancelAt == Long.MAX_VALUE) {
                        a.cancelAt = s.state.nowMs + lag
                        a.cancelCause = e.cause
                    }
                    os.removeAll { it.cancelAt <= s.state.nowMs }
                    val at = e.fallbackAtMs
                    if (at != null && s.state.phase != TripPhase.ENDED) {
                        val ok = rng.chance(okP)
                        if (ok) os += OsAlarm(at)
                        val prev2 = step
                        val r = TripEngine.reduce(prev2.state, FallbackScheduled(prev2.state.nowMs, at, ok))
                        afterStep(prev2, r, "FallbackScheduled(${rel(at)}, $ok)", null)
                        if (r.events.any { it is Alarm }) v("FallbackScheduled produced an alarm")
                    }
                }
            }
            if (s.events.any { it is TripEnded }) os.clear()
            return s
        }

        /** Harness invariants over the whole trip (I1–I7, I10–I13, C16), one alarm, no double ring. */
        fun finish(): List<String> {
            val n = records.size
            val rr = RunResult(
                RunKey("t122", tag, "sim", false, 0), S, p, records, arrayOfNulls(n), arrayOfNulls(n), null, emptyMap(), null, null,
                null, emptyList(), emptyMap(),
            )
            val out = ArrayList(viol)
            out += Checks.invariants(rr, tag).take(10)
            if (alarms.size > 1) out += "$tag: ${alarms.size} alarms ${alarms.map { it.first.reason }}"
            return out
        }

        /** Delivers the earliest of: OS fallback, wake-up Tick, [nextFix], [other]; returns false when nothing is due before [until]. */
        fun advance(until: Long, nextFix: Long? = null, fix: ((Long) -> LocationFix)? = null): Boolean {
            if (ended) return false
            val f = nextOs()
            val fAt = f?.let { maxOf(it.at, now) }
            val wake = step.view.wakeAtMs
            val cands = listOfNotNull(fAt, wake, nextFix)
            if (cands.isEmpty()) return false
            val t = cands.min()
            if (t >= until) return false
            when {
                fAt != null && t == fAt && (wake == null || fAt < wake) -> fireOs(f!!)
                nextFix != null && t == nextFix -> feed(fix!!(t), "fix")
                else -> feed(Tick(t), "Tick")
            }
            return true
        }
    }

    private fun interval(s: Step): Long = (s.view.samplingPolicy?.intervalS ?: 5) * 1000L

    // ================================================================ (a) restore while GPS lost, first fix 0–150 s before F

    private class ResultA(val line: String, val viol: List<String>)

    /**
     * DISTANCE 1000, TRAIN, fixes every policy interval at 25 m/s from 120 km for 900 s, then GPS gone (the vehicle moves at
     * [lossSpeed]). Wake-up Ticks until GpsLost; the process is killed at P − 700 s; restart at P − [y] s with [status] (OS alarm
     * of before the kill still pending, unless MISSING); first fix at F − [x] s (F = the fallback in force after the restore);
     * then the vehicle runs at 25 m/s from the fix + 120 s, fixes every interval ([doze]: only at wake-ups, probability 0.5).
     */
    private fun scenarioA(lossSpeed: Double, y: Int, x: Double, status: FallbackRestoreStatus, doze: Boolean, seed: Long): ResultA? {
        val config = cfg(AlarmMode.DISTANCE, thr = 1000, hint = VehicleKind.TRAIN)
        val truth = Truth(120_000.0, S).also { it.segs += S to 25.0 }
        val lossAt = S + 900_000L
        truth.segs += lossAt to lossSpeed
        val rng = Rng(seed)
        val tag = "A loss=$lossSpeed y=$y x=$x $status doze=$doze"
        val sim = Sim(TripEngine.start(config, p, S), tag, rng)
        var lastFix = S
        while (true) {
            val nf = maxOf(lastFix + interval(sim.step), sim.now + 1)
            if (nf >= lossAt) break
            if (!sim.advance(lossAt, nf) { t -> lastFix = t; fixAt(t, truth.dAt(t), spd = 25.0) }) break
        }
        while (sim.allEvents.none { it is GpsLost } && sim.advance(Long.MAX_VALUE)) Unit
        val pDr = sim.step.view.predictedAlarmAtMs ?: return null
        val killAt = pDr - 700_000L
        while (sim.advance(killAt)) Unit
        if (sim.alarms.isNotEmpty()) return null
        sim.kill()
        val tr = pDr - y * 1000L
        val fOld = sim.nextOs()?.at
        sim.restart(tr, status)
        if (sim.alarms.isNotEmpty()) {
            return ResultA("$tag: restore rang ${sim.alarms.first().first.reason} (F old ${fOld?.let { (it - pDr) / 1000.0 }} vs P)", sim.finish())
        }
        val f = sim.step.state.fallback.targetAtMs ?: return null
        val tf = maxOf(sim.now + 1, f - (x * 1000).toLong())
        while (sim.advance(tf)) Unit
        if (sim.alarms.isNotEmpty()) {
            // F = P + 30 s: a fix later than P + 1 s comes after the engine's own c3 alarm (GPS_LOST, ringNow).
            val a = sim.alarms.first().first
            val v = sim.finish().toMutableList()
            if (!a.ringNow || a.reason != AlarmReason.GPS_LOST) v += "$tag: rang before the fix with $a"
            return ResultA("$tag: rang before the fix ${a.reason} ringNow=${a.ringNow}", v)
        }
        truth.segs += (tf + 120_000L) to 25.0
        val fBefore = sim.step.state.fallback.targetAtMs!!
        val emittedBefore = sim.step.state.fallback.emittedAtMs!!
        val fixStep = sim.feed(fixAt(tf, truth.dAt(tf), spd = lossSpeed), "first fix")
        lastFix = tf
        val fac = fixStep.events.filterIsInstance<FallbackAlarmChanged>().singleOrNull()
        val pNew = fixStep.view.predictedAlarmAtMs
        var guard = 0
        while (!sim.ended && ++guard < 200_000) {
            val nf = if (doze) null else maxOf(lastFix + interval(sim.step), sim.now + 1)
            val wake = sim.step.view.wakeAtMs
            val fixFn = { t: Long -> lastFix = t; fixAt(t, truth.dAt(t), spd = truth.speedAt(t)) }
            if (doze && wake != null && rng.chance(0.5) && (sim.nextOs()?.at ?: Long.MAX_VALUE) > wake) {
                sim.feed(fixFn(wake), "fix@wake")
                continue
            }
            if (!sim.advance(Long.MAX_VALUE, nf, fixFn)) break
        }
        val first = sim.alarms.firstOrNull()
        val cross = truth.crossAt(1000.0, S + 48 * 3_600_000L)
        val firstAt = first?.first?.atMs
        val line = "$tag: F-tRestore=${(fBefore - tr) / 1000.0} fix at F-${(fBefore - tf) / 1000.0} s (now-emitted ${(tf - emittedBefore) / 1000.0} s) " +
            "Pnew-t=${pNew?.let { (it - tf) / 1000.0 }} fac=${fac?.let { "${it.cause}@+${it.fallbackAtMs?.let { a -> (a - tf) / 1000.0 }}" }} " +
            "first=${first?.first?.reason}/${first?.first?.ringNow} via ${first?.second} late-vs-cross=${if (firstAt != null && cross != null) (firstAt - cross) / 1000.0 else null} s " +
            "osFired=${sim.osFired} urgent=${sim.urgent} soon=${sim.soonShifts}"
        val viol = sim.finish().toMutableList()
        if (first == null) viol += "$tag: no alarm"
        val lead = fBefore - tf
        // The OS fallback never rings first: the fallback is moved later (at this Step, or at a later Step when the round-2 rule
        // does not apply yet: F − now > 90 s and the last emission < fallbackMinIntervalS ago) and the engine rings first.
        val mustMoveNow = lead >= p.fallbackMinLeadS * 1000L &&
            (lead <= (p.fallbackQuietBeforeS + p.fallbackMinIntervalS) * 1000L || tf - emittedBefore >= p.fallbackMinIntervalS * 1000L)
        if (mustMoveNow && (fac == null || fac.cause != FallbackCause.ETA || (fac.fallbackAtMs ?: 0) < tf + p.fallbackNearS * 1000L)) {
            viol += "$tag: not moved later at the fix Step: $fac"
        }
        if (!mustMoveNow && fac != null) viol += "$tag: moved although not allowed yet: $fac"
        if (first != null && (!first.first.ringNow || first.first.reason == AlarmReason.FALLBACK)) viol += "$tag: first alarm ${first.first} via ${first.second}"
        return ResultA(line, viol)
    }

    @Test
    fun `T122 a restore while GPS lost then the first fix 0 to 150 s before the fallback - one alarm, no double ring, moved later`() {
        val out = StringBuilder()
        val viol = ArrayList<String>()
        var runs = 0
        var moved = 0
        var seed = 1L
        for (status in listOf(FallbackRestoreStatus.PENDING, FallbackRestoreStatus.UNKNOWN, FallbackRestoreStatus.MISSING)) {
            for (lossSpeed in listOf(0.0, 6.0)) for (y in listOf(35, 60, 90, 120)) for (doze in listOf(false, true)) {
                for (x in listOf(150.0, 120.0, 91.0, 90.0, 89.0, 75.0, 63.0, 60.0, 45.0, 33.0, 31.0, 30.0, 29.0, 20.0, 10.0, 9.999, 5.0, 1.0)) {
                    if (x > y + 30) continue
                    val r = scenarioA(lossSpeed, y, x, status, doze, seed++) ?: continue
                    runs++
                    if (r.line.contains("fac=ETA")) moved++
                    out.append(r.line).append('\n')
                    viol += r.viol
                }
            }
        }
        File(outDir, "t122-a-restore.txt").writeText("runs=$runs moved=$moved\nviolations=${viol.take(40)}\n$out")
        assertTrue(runs >= 300) { "runs $runs" }
        assertTrue(viol.isEmpty()) { "violations ${viol.take(10)}" }
    }

    // ================================================================ (b) destination passed inside a tunnel

    private class ResultB(
        val key: String,
        val line: String,
        val viol: List<String>,
        val reason: AlarmReason?,
        val lateS: Double?,
        /** First fix after the gap (null when the engine rang before it) and the first alarm time. */
        val gapFixAtMs: Long?,
        val firstAtMs: Long?,
        /** Fixes every policy interval after the gap ([awake]); fix period right after the first fix after the gap. */
        val awake: Boolean,
        val periodMs: Long?,
    )

    /**
     * The vehicle passes the destination inside a tunnel / GPS gap. [fromStart] false: TRACKING DENSE at 30 km, EMA 10 m/s (k 1),
     * last fix at S (state builder, maxTripDurationS = cap). [fromStart] true: a real trip from TripEngine.start at 60 km, fixes
     * every policy interval at 10 m/s until 30 km (so maxTripDurationS comes from the first fix), then the gap. Dead reckoning at
     * 10 m/s gives P = lostAt; near-zone fallback F = P + 30 s. The true speed in the gap is constant, chosen so that the vehicle
     * is [past] m beyond the destination when it leaves the gap at F − [x] s (first fix: unsigned distance, Doppler speed). Then
     * fixes every policy interval ([awake]) or none (Doze, only wake-ups).
     */
    private fun scenarioB(config: TripConfig, past: Double, x: Double, awake: Boolean, fromStart: Boolean, implausibleInGap: Boolean = false): ResultB {
        val key = "${config.mode}${config.distanceThresholdM ?: config.timeThresholdMin ?: ""} fromStart=$fromStart awake=$awake past=${past.toInt()} x=${x.toInt()}"
        val sim: Sim
        val gapStart: Long
        if (fromStart) {
            sim = Sim(TripEngine.start(config, p, S), "B $key", Rng(7))
            var lastFix = S
            gapStart = S + 3_000_000L // 60 km − 10 m/s · 3 000 s = 30 km
            while (true) {
                val nf = maxOf(lastFix + interval(sim.step), sim.now + 1)
                if (nf > gapStart) break
                if (!sim.advance(Long.MAX_VALUE, nf) { t -> lastFix = t; fixAt(t, 60_000.0 - 10.0 * (t - S) / 1000.0, spd = 10.0) }) break
            }
            check(sim.alarms.isEmpty())
        } else {
            val st = trackingState(config, d = 30_000.0, ground = 10.0, closing = 10.0, tier = SamplingTier.DENSE)
            sim = Sim(TripEngine.reduce(st, Tick(S)), "B $key", Rng(7))
            gapStart = S
        }
        val d0 = sim.step.state.dSmooth!!
        val fixAt0 = sim.step.state.last!!.fixAtMs
        while (sim.allEvents.none { it is GpsLost } && sim.alarms.isEmpty() && sim.advance(Long.MAX_VALUE)) Unit
        // U115 variant (T10.5 vòng 3f, RK20 d): one jump fix rejected as IMPLAUSIBLE right after the gap began (500 km away).
        if (implausibleInGap && sim.alarms.isEmpty()) sim.feed(fixAt(sim.now + 1_000L, 500_000.0, spd = 10.0), "implausible in gap")
        val pDr = sim.step.view.predictedAlarmAtMs
        val f = (pDr ?: 0L) + p.fallbackLagS * 1000L
        val tf = f - (x * 1000).toLong()
        while (sim.advance(tf)) Unit
        val v2 = (d0 + past) / ((tf - fixAt0) / 1000.0)
        val truth = Truth(d0, fixAt0).also { it.segs += fixAt0 to v2 }
        var lastFix = tf
        val rangBefore = sim.alarms.isNotEmpty()
        var periodMs: Long? = null
        if (!rangBefore) {
            sim.feed(fixAt(tf, truth.dAt(tf), spd = v2), "first fix")
            periodMs = interval(sim.step)
            var guard = 0
            while (!sim.ended && ++guard < 100_000) {
                val nf = if (awake) maxOf(lastFix + interval(sim.step), sim.now + 1) else null
                if (!sim.advance(Long.MAX_VALUE, nf) { t -> lastFix = t; fixAt(t, truth.dAt(t), spd = v2) }) break
            }
        }
        val first = sim.alarms.firstOrNull()?.first
        val thrD = if (config.mode == AlarmMode.DISTANCE) config.distanceThresholdM!!.toDouble() else 1000.0
        val cross = truth.crossAt(thrD, tf)!!
        val late = first?.let { (it.atMs - cross) / 1000.0 }
        val line = "$key: v=${"%.2f".format(v2)} m/s, F=${(f - S) / 1000.0} fix at ${(tf - S) / 1000.0} cross(${thrD.toInt()} m)=${(cross - S) / 1000.0} " +
            "dest=${(truth.crossAt(0.0, tf)!! - S) / 1000.0}; ${if (rangBefore) "rang before the fix; " else ""}first=${first?.reason}/${first?.ringNow} " +
            "at ${first?.let { (it.atMs - S) / 1000.0 }} late-vs-cross=$late s (no fix after the gap: GPS_LOST at P+1, late ${(pDr!! + 1000 - cross) / 1000.0} s) " +
            "maxTripS=${sim.step.state.maxTripDurationS} urgent=${sim.urgent} soon=${sim.soonShifts} osFired=${sim.osFired}"
        return ResultB(
            key, line, sim.finish() + (if (first == null) listOf("B $key: no alarm") else emptyList()), first?.reason, late,
            if (rangBefore) null else tf, first?.atMs, awake, periodMs,
        )
    }

    /**
     * U115 (T10.5 round 3/3b; flipped from the tester's pinned `T122 b … tunnel`, PINNED_B = 32 TIMEOUT runs): never TIMEOUT; with
     * fixes every policy interval after the gap the first alarm comes no later than the first fix after the gap + [U115_PERIODS]
     * fix periods + 1 s (round 3b: the chord lowers minD, the usual overshoot rule confirms "moving away" on 3 strictly increasing
     * smoothed distances). Doze runs (no fix after the first one): GPS_LOST at c2 as before round 3.
     */
    @Test
    fun `U115 destination passed inside a tunnel, first fix at most 90 s before the fallback - no TIMEOUT, alarm a few fixes after the gap`() {
        val out = StringBuilder()
        val viol = ArrayList<String>()
        val late = ArrayList<String>()
        val afterFix = ArrayList<String>()
        val afterFixS = sortedMapOf<Double, Int>()
        var timeouts = 0
        val configs = listOf(cfg(AlarmMode.DISTANCE, thr = 1000), cfg(AlarmMode.TIME, thrMin = 15), cfg(AlarmMode.SMART))
        for (config in configs) for (fromStart in listOf(false, true)) for (awake in listOf(true, false)) {
            for (past in listOf(300.0, 1_000.0, 2_000.0, 2_900.0, 3_100.0, 3_500.0, 5_000.0, 10_000.0)) {
                for (x in listOf(90.0, 60.0, 31.0, 29.0, 20.0, 10.0)) {
                    if (config.mode != AlarmMode.DISTANCE && (!fromStart || x == 60.0 || x == 20.0)) continue
                    val r = scenarioB(config, past, x, awake, fromStart)
                    out.append(r.line).append('\n')
                    viol += r.viol
                    if (r.reason == AlarmReason.TIMEOUT) timeouts++
                    if ((r.lateS ?: Double.MAX_VALUE) > 900.0) late += "${r.key} ${r.reason} +${r.lateS?.toLong()} s"
                    val gf = r.gapFixAtMs
                    val fa = r.firstAtMs
                    if (gf != null && r.awake) {
                        val after = (fa ?: Long.MAX_VALUE) - gf
                        afterFixS[after / 1000.0] = (afterFixS[after / 1000.0] ?: 0) + 1
                        if (after > U115_PERIODS * r.periodMs!! + 1_000L) afterFix += "${r.key} ${r.reason} at fix + ${after / 1000.0} s"
                    }
                }
            }
        }
        File(outDir, "t122-b-tunnel.txt").writeText(
            "violations=${viol.take(40)}\nTIMEOUT=$timeouts\nawake runs, first alarm − first fix after the gap (s → runs): $afterFixS\n" +
                "over the bound (${afterFix.size}): $afterFix\n" +
                "late > 900 s after the crossing (${late.size}):\n${late.joinToString("\n")}\n\n$out",
        )
        assertTrue(viol.isEmpty()) { "violations ${viol.take(10)}" }
        assertEquals(0, timeouts, "TIMEOUT runs (before T10.5 round 3: 32)")
        assertEquals(emptyList<String>(), afterFix)
        assertEquals(emptyList<String>(), late)
    }

    /**
     * U115 variant (T10.5 vòng 3f, RK20 d, recorded): the same 320 runs, and in every 10th run (10 %) one jump fix rejected as
     * IMPLAUSIBLE arrives right after the gap began; the first fix after the gap is then not a GPS-gap chord fix (T12.1 rule).
     * Prints the TIMEOUT count of the variant runs; the plain runs are U115 above (0 TIMEOUT).
     */
    @Test
    fun `U115 variant one IMPLAUSIBLE fix inside the gap in 10 percent of runs - TIMEOUT count recorded (RK20 d)`() {
        val out = StringBuilder()
        val viol = ArrayList<String>()
        val reasons = sortedMapOf<String, Int>()
        var timeouts = 0
        var runs = 0
        var idx = 0
        val configs = listOf(cfg(AlarmMode.DISTANCE, thr = 1000), cfg(AlarmMode.TIME, thrMin = 15), cfg(AlarmMode.SMART))
        for (config in configs) for (fromStart in listOf(false, true)) for (awake in listOf(true, false)) {
            for (past in listOf(300.0, 1_000.0, 2_000.0, 2_900.0, 3_100.0, 3_500.0, 5_000.0, 10_000.0)) {
                for (x in listOf(90.0, 60.0, 31.0, 29.0, 20.0, 10.0)) {
                    if (config.mode != AlarmMode.DISTANCE && (!fromStart || x == 60.0 || x == 20.0)) continue
                    if (idx++ % 10 != 0) continue
                    val r = scenarioB(config, past, x, awake, fromStart, implausibleInGap = true)
                    runs++
                    out.append(r.line).append('\n')
                    viol += r.viol
                    reasons["${r.reason}"] = (reasons["${r.reason}"] ?: 0) + 1
                    if (r.reason == AlarmReason.TIMEOUT) timeouts++
                }
            }
        }
        File(outDir, "t122-b-tunnel-implausible.txt").writeText(
            "runs=$runs TIMEOUT=$timeouts firstAlarm=$reasons violations=${viol.take(40)}\n\n$out",
        )
        assertTrue(viol.isEmpty()) { "violations ${viol.take(10)}" }
        assertEquals(32, runs)
        assertEquals(U115_VARIANT_TIMEOUT, timeouts, "RK20 d: TIMEOUT runs of the variant")
    }

    /**
     * Minimal repro of the (b) finding (pinned; see docs/test-reports/T12.2.md "Lỗi phát hiện" #1). DISTANCE 1000, GPS LOST since
     * S − 1 761 s with dead reckoning still 11.8 km out at 10 m/s (P = S − 29 s + … ≈ S + 1 s, F = S + 29 s, CONFIRMED, near).
     * The vehicle really passed the destination in the gap: first fix at S, 3 100 m beyond it (unsigned distance), moving away at
     * 18 m/s; then a fix every policy interval. T12.1: the fallback stays (quiet window) and rings at F. T12.2: the urgent later
     * shift moves it to the far zone; PASSED_CLOSEST needs minD < 3 000 m and Overshoot minD < 1 000 m, so nothing rang until
     * TIMEOUT. T10.5 round 3 (flipped, = U114 a): the GPS-gap chord passes the destination, so OVERSHOOT rings at the fix.
     */
    @Test
    fun `T122 b repro passed the destination in a GPS gap, first fix 29 s before F and 3_1 km beyond - OVERSHOOT at the fix`() {
        val n = S
        val config = cfg(AlarmMode.DISTANCE, thr = 1000)
        val dr = 11_800.0 + 10.0 * 1_761.0 // dead-reckoned to 11 800 m (etaS 1 200 at 10 m/s, k 1) at n − 29 000 + … 
        val st = trackingState(
            config, d = dr, ground = 10.0, closing = 10.0, gps = GpsStatus.LOST, now = n - 1_000, lastFixAt = n - 1_761_000,
            tier = SamplingTier.DENSE, maxTripS = 14_400, startedAt = n - 3_000_000,
            fallback = app.napstop.core.trip.FallbackState(n + 29_000, n - 600_000, FallbackStatus.CONFIRMED, n - 599_000, false, true),
        )
        val e = app.napstop.core.trip.support.driverFrom(st)
        val first = e.feed(fixAt(n, -3_100.0, spd = 18.0))
        val fac = first.events.filterIsInstance<FallbackAlarmChanged>().singleOrNull()
        var s = first
        var t = n
        while (s.events.none { it is Alarm } && t < n + 4 * 3_600_000L) {
            t += (s.view.samplingPolicy?.intervalS ?: 5) * 1000L
            s = e.feed(fixAt(t, -3_100.0 - 18.0 * (t - n) / 1000.0, spd = 18.0))
        }
        val a = e.events().filterIsInstance<Alarm>().firstOrNull()
        val got = "gps=${first.view.gps} predicted-now=${first.view.predictedAlarmAtMs?.let { (it - n) / 1000 }} s " +
            "fac=${fac?.cause}@${fac?.fallbackAtMs?.let { (it - n) / 1000 }} s; first alarm ${a?.reason} at ${a?.let { (it.atMs - n) / 1000 }} s after the fix"
        File(outDir, "t122-b-repro.txt").writeText(got + "\n")
        assertEquals(PINNED_B_REPRO, got)
    }

    // ================================================================ (c) GPS lost > 1 h, changing speed (T10.6: U121)

    private class CRes(val line: String, val lateS: Long, val lostLongAtS: Double?)

    /**
     * TRACKING DENSE, EMA ground 15 / closing 12.5 (k 1.2, cvDr 12.5), fix at S, GPS lost from then on; d chosen so that dead
     * reckoning gives lostAt = S + [lossS]. Truth closing speed alternates m·12.5·(1 ± 0.3) every 600 s (sign from a fixed seed).
     * Only wake-up Ticks (Doze). Measures the GPS_LOST alarm vs (i) the instant the true remaining time is 1 200 s, (ii) the
     * DISTANCE 1000 threshold crossing, and the instant a hypothetical `etaMinS < 1200` rule would ring (T10.6 input).
     * T10.6 (U121): with W on ([params] gpsLostLongS > 0) the line gets a `lostLongAtS` column.
     */
    private fun scenarioC(lossS: Int, m: Double, mode: AlarmMode, params: EngineParams = p): CRes {
        val config = if (mode == AlarmMode.DISTANCE) cfg(AlarmMode.DISTANCE, thr = 1000) else cfg(mode)
        val d = 12.5 * (1180.0 + lossS)
        val st = trackingState(config, p = params, d = d, tier = SamplingTier.DENSE)
        val truth = Truth(d, S)
        val r = Rng(433)
        var t = S
        while (t < S + 48 * 3_600_000L) {
            truth.segs += t to 12.5 * m * (if (r.chance(0.5)) 1.3 else 0.7)
            t += 600_000L
        }
        val sim = Sim(TripEngine.reduce(st, Tick(S)), "C", Rng(1))
        while (sim.alarms.isEmpty() && sim.advance(Long.MAX_VALUE)) Unit
        val a = sim.alarms.first().first
        val dest = truth.crossAt(0.0, S + 48 * 3_600_000L)!!
        // Instant the true remaining time to the destination is 1 200 s.
        var lo = S
        var hi = dest
        while (hi - lo > 1) {
            val mid = (lo + hi) / 2
            if (dest - mid > 1_200_000L) lo = mid else hi = mid
        }
        val ideal = hi
        val cross = truth.crossAt(1000.0, dest)!!
        // Hypothetical etaMinS rule (10 s grid from GpsLost).
        var etaMinAt: Long? = null
        var probe = S + 60_000L
        while (probe < a.atMs + 3_600_000L) {
            val w = StepWork(TripEngine.reduce(st, Tick(probe)).state)
            val e = estimate(w)
            if (e?.etaMinS != null && e.etaMinS!! < p.gpsLostAlarmEtaS) {
                etaMinAt = probe
                break
            }
            probe += 10_000L
        }
        val lostLong = estimate(StepWork(TripEngine.reduce(st, Tick(S + 60_000L)).state))!!.lostLongAtS
        val v = sim.finish()
        assertTrue(v.isEmpty()) { "$v" }
        val late = (a.atMs - ideal) / 1000
        val line = "loss=${lossS}s m=$m $mode: alarm ${a.reason} at ${(a.atMs - S) / 1000} s; late vs trueRemaining1200 $late s; " +
            "true remaining at alarm ${(dest - a.atMs) / 1000} s; late vs cross1000 ${(a.atMs - cross) / 1000} s; " +
            "etaMinS<1200 rule would ring at ${etaMinAt?.let { (it - S) / 1000 }} s (late vs trueRemaining1200 ${etaMinAt?.let { (it - ideal) / 1000 }} s)" +
            (if (params.gpsLostLongS > 0) "; lostLongAtS ${lostLong?.let { String.format(java.util.Locale.ROOT, "%.1f", it) }}" else "")
        return CRes(line, late, lostLong)
    }

    private fun tableC(params: EngineParams): List<CRes> {
        val rows = ArrayList<CRes>()
        for (lossS in listOf(3_600, 7_200, 10_800)) for (m in listOf(0.7, 1.0, 1.15, 1.3, 1.5)) {
            rows += scenarioC(lossS, m, AlarmMode.DISTANCE, params)
        }
        rows += scenarioC(7_200, 1.3, AlarmMode.TIME, params)
        rows += scenarioC(7_200, 1.3, AlarmMode.SMART, params)
        return rows
    }

    /**
     * U121 (T10.6 (1), flipped from the tester's `T122 c`): same 17 runs with the "long loss" rule W on (defaults, Q12 = A). DISTANCE
     * lateness vs "true remaining 1 200 s" = T10 "T10.6" §1.4 column "W, Q12 A" (± 5 s), every row <= +460 s, TIME/SMART at
     * (2 h, 1.3) = DISTANCE. With gpsLostLongS = 0 the old pinned table PINNED_C (T12.2) comes back unchanged.
     */
    @Test
    fun `U121 GPS lost for more than 1 h with a changing true speed - the long-loss rule W bounds the GPS_LOST lateness`() {
        val rows = tableC(p)
        val txt = rows.joinToString("\n") { it.line }
        File(outDir, "t122-c-longloss.txt").writeText(txt + "\n")
        val handW = listOf(-3711L, -1352L, -872L, -504L, -127L, -6171L, -2763L, -1461L, -515L, 401L, -8988L, -3526L, -2048L, -1123L, 450L)
        for ((i, want) in handW.withIndex()) assertTrue(abs(rows[i].lateS - want) <= 5) { "row $i: ${rows[i].lateS} vs hand ${want}" }
        assertTrue(rows.all { it.lateS <= 460 }) { rows.joinToString("\n") { it.line } }
        assertEquals(rows[8].lateS, rows[15].lateS)
        assertEquals(rows[8].lateS, rows[16].lateS)
        val hand = listOf(2784.8, 5435.7, 8086.6)
        for ((i, l) in hand.withIndex()) assertEquals(l, rows[i * 5].lostLongAtS!!, 0.1)
        assertEquals(PINNED_U121, txt)
        // W off: the T12.2 table, line for line.
        val off = tableC(EngineParams(gpsLostLongS = 0)).joinToString("\n") { it.line }
        assertEquals(PINNED_C, off)
    }

    // ================================================================ (d) wake-up storm regression, with a battery forecast

    /** Battery state whose batteryAt − now at [now] is [leadS] (+ < 1 ms), level [level], not charging, armed. */
    private fun batteryWithLead(now: Long, level: Int, leadS: Double): BatteryState {
        val rate = (level - p.lowBatteryAlarmPct) * 3600.0 / leadS // %/h
        val drop = maxOf(1, Math.ceil(rate * p.batteryMinRateWindowS / 3600.0).toInt() + 1)
        val windowMs = Math.round(drop * 3_600_000.0 / rate)
        return BatteryState(level, false, now - windowMs, level + drop, true, true, null, null)
    }

    private class StormResult(val wakes: Int, val minGapMs: Long, val line: String)

    /**
     * TRACKING, GPS OK, DISTANCE 1000 at cvDr 12.5: T = B + 0.5 s. [stopped]: the last fix is STATIONARY and stationary fixes
     * come every [fixEveryS] s (0 = none: Doze, GPS lost at c2, then dead reckoning); otherwise moving fixes along the truth.
     * [battery]: a battery forecast with batteryAt − now = [leadS]. Counts wake-up Ticks (Ticks before the next fix) over
     * [horizonS] and the minimum gap between two of them.
     */
    private fun storm(tier: SamplingTier, b: Int, stopped: Boolean, battery: Boolean, leadS: Double, fixEveryS: Int, horizonS: Int): StormResult {
        val d = 1000.0 + 12.5 * (b + 0.5)
        val bat = if (battery) batteryWithLead(S, 40, leadS) else BatteryState.EMPTY
        val st = trackingState(cfg(), d = d, inStop = stopped, tier = tier, battery = bat)
        val w0 = StepWork(st)
        val lead0 = batteryAt(w0)?.let { (it - S) / 1000.0 }
        val sim = Sim(TripEngine.reduce(st, Tick(S + 1)), "D", Rng(3))
        var wakes = 0
        var lastWake: Long? = null
        var minGap = Long.MAX_VALUE
        var nextFix = if (fixEveryS > 0) S + fixEveryS * 1000L else null
        val end = S + horizonS * 1000L
        while (!sim.ended && sim.now < end) {
            val wake = sim.step.view.wakeAtMs ?: break
            if (sim.alarms.isNotEmpty()) break
            if (nextFix != null && nextFix <= wake) {
                val t = nextFix
                val dd = if (stopped) d else d - 12.5 * (t - S) / 1000.0
                sim.feed(fixAt(t, dd, spd = if (stopped) 0.0 else 15.0), "fix")
                nextFix = t + if (stopped) fixEveryS * 1000L else interval(sim.step) // moving: fixes follow the policy
            } else {
                if (wake >= end) break
                sim.feed(Tick(wake), "wake")
                wakes++
                lastWake?.let { minGap = minOf(minGap, wake - it) }
                lastWake = wake
            }
        }
        val v = sim.finish()
        assertTrue(v.isEmpty()) { "$v" }
        val line = "tier=$tier B=$b stopped=$stopped battery=$battery lead0=$lead0 s fixEvery=$fixEveryS s horizon=$horizonS s: " +
            "wake Ticks=$wakes minGap=${if (minGap == Long.MAX_VALUE) "-" else "${minGap / 1000.0} s"} alarms=${sim.alarms.map { it.first.reason }} gps=${sim.step.view.gps}"
        return StormResult(wakes, minGap, line)
    }

    @Test
    fun `T122 d no wake-up storm at tier boundaries with GPS OK, with and without a sliding battery forecast`() {
        val out = StringBuilder()
        val bad = ArrayList<String>()
        fun expect(ok: Boolean, line: String) {
            out.append(if (ok) "" else "FAIL ").append(line).append('\n')
            if (!ok) bad += line
        }
        for ((tier, b) in listOf(SamplingTier.DENSE to 600, SamplingTier.MEDIUM to 900, SamplingTier.SPARSE to 3600)) {
            for (battery in listOf(false, true)) {
                // Battery forecast just above the same boundary (it slides with now between two samples), and one far away.
                for (leadS in if (battery) listOf(b + 0.5, b + 5.0, 20_000.0) else listOf(0.0)) {
                    // Stopped with stationary fixes every policy interval for 20 minutes: no wake-up Tick at all.
                    val every = when (tier) { SamplingTier.DENSE -> 5; SamplingTier.MEDIUM -> 30; SamplingTier.SPARSE -> 180 }
                    val a = storm(tier, b, stopped = true, battery = battery, leadS = leadS, fixEveryS = every, horizonS = 1_200)
                    expect(a.wakes == 0, a.line)
                    // Stopped, Doze (no fix at all): c2, then dead reckoning. Bounded: a few fixed candidates, no sub-10-s gaps.
                    val z = storm(tier, b, stopped = true, battery = battery, leadS = leadS, fixEveryS = 0, horizonS = 3_600)
                    expect(z.wakes <= 8 && (z.wakes < 2 || z.minGapMs >= 10_000L), z.line)
                    // Moving with fixes every policy interval: the forecast does not slide; wakes only at fixed candidates.
                    val mv = storm(tier, b, stopped = false, battery = battery, leadS = leadS, fixEveryS = every, horizonS = 1_200)
                    expect(mv.wakes <= 6 && (mv.wakes < 2 || mv.minGapMs >= 1_000L), mv.line)
                }
            }
        }
        // Moving, GPS OK then lost (Doze, no fix), the battery forecast is the smallest component and slides (no BatterySample):
        // T10.5 §1.2 keeps c3 = batteryAt + 1 s (slides >= 12 s at the max measured rate); the near-zone fallback follows the
        // sliding forecast, so c8 = F − 90 s also slides. Accepted: no storm below 10 s.
        for (leadS in listOf(600.5, 900.5, 3600.5, 120.0, 30.0)) {
            val r = storm(SamplingTier.SPARSE, 20_000, stopped = false, battery = true, leadS = leadS, fixEveryS = 0, horizonS = 3_600)
            expect(r.wakes < 2 || r.minGapMs >= 10_000L, "far mode forecast: " + r.line)
        }
        File(outDir, "t122-d-storm.txt").writeText(out.toString())
        assertTrue(bad.isEmpty()) { bad.joinToString("\n") }
    }

    // ================================================================ (e) fuzz

    /** Key of the first alarm as in the firstAlarm table of FuzzStats. */
    private fun firstKey(sim: Sim): String = sim.firstKey()

    /** U126 (after T12.3, D5): a DISTANCE first alarm more than 1 800 s after the threshold crossing, one classified line. */
    private fun noteLate(sim: Sim, truth: Truth, config: TripConfig, a: Alarm, cross: Long, st: FuzzStats) {
        val lateS = (a.atMs - cross) / 1000.0
        if (lateS <= 1_800.0) return
        st.lateLines += lateS to app.napstop.core.trip.support.lateCaseLine(
            sim.tag, config.vehicleHint, lateS, firstKey(sim), sim.deadIntervals.any { cross >= it.first && cross < it.second }, cross,
            config.distanceThresholdM!!.toDouble(), sim.states.lastOrNull { it.nowMs <= cross },
        ) { ms -> truth.dAt(ms) }
    }

    /** U126: a first GPS_LOST alarm due to W alone, and the true time left to the destination at it. */
    private fun noteLongLost(sim: Sim, truth: Truth, st: FuzzStats) {
        val a = sim.alarms.firstOrNull()?.first ?: return
        val state = sim.firstAlarmState ?: return
        if (a.reason != AlarmReason.GPS_LOST || !app.napstop.core.trip.support.lostAlarmInfo(state).longLostOnly) return
        st.longLost++
        truth.crossAt(0.0, S + 60 * 3_600_000L)?.let { st.longLostRemaining += (it - a.atMs) / 1000.0 }
    }

    private class FuzzStats {
        var trips = 0
        var steps = 0
        var urgent = 0
        var soon = 0
        var osFired = 0
        var raceFired = 0
        var kills = 0
        val first = sortedMapOf<String, Int>()
        val viol = ArrayList<String>()
        var violTrips = 0
        val lateCross = ArrayList<Double>()
        val supersedeRaces = ArrayList<String>()
        val wrongWording = ArrayList<String>()
        val osFirstKinds = sortedMapOf<String, Int>()
        val osFirstEarly = ArrayList<Double>()
        val believedStopOverLag = ArrayList<String>()

        /** U126 (after T12.3, D5): DISTANCE cases late > 1 800 s, (late, line). */
        val lateLines = ArrayList<Pair<Double, String>>()

        /** U126 (T10.6): first alarms due to the "long loss" term W alone; true seconds to the destination at them (< 0: after). */
        var longLost = 0
        val longLostRemaining = ArrayList<Double>()

        fun add(sim: Sim) {
            trips++
            steps += sim.steps
            urgent += sim.urgent
            soon += sim.soonShifts
            osFired += sim.osFired
            raceFired += sim.raceFired
            supersedeRaces += sim.supersedeRaces
            for ((k, n) in sim.osFirstKinds) osFirstKinds[k] = (osFirstKinds[k] ?: 0) + n
            osFirstEarly += sim.osFirstEarly
            believedStopOverLag += sim.believedStopOverLag.map { "${sim.tag} $it" }
            val f = sim.alarms.firstOrNull()
            val k = sim.firstKey()
            first[k] = (first[k] ?: 0) + 1
            val v = sim.finish() + (if (f == null) listOf("${sim.tag}: trip without alarm") else emptyList())
            if (v.isNotEmpty()) violTrips++
            if (viol.size < 30) viol += v.take(3)
        }

        fun text(name: String): String {
            val l = lateCross.sorted()
            val lt = if (l.isEmpty()) "-" else "n ${l.size}, p50 ${l[l.size / 2]}, p90 ${l[minOf(l.size - 1, (l.size * 0.9).toInt())]}, max ${l.last()}"
            return "$name: trips=$trips steps=$steps urgentLaterShifts=$urgent farZoneSoonShifts=$soon osFallbackFired=$osFired " +
                "(after a cancel request: $raceFired) kills=$kills violatingTrips=$violTrips\nfirstAlarm=$first\n" +
                "OVERSHOOT/PASSED_CLOSEST first while the truth has not passed the destination: ${wrongWording.size} $wrongWording" + NL +
                "believed-stop OS fallback later than P(prev Step) + lag + 1 s (U111 bound; within the hold band): ${believedStopOverLag.size} $believedStopOverLag" + NL +
                "OS fallback first while alive, by kind: $osFirstKinds; predicted(prev Step) − F, s: ${osFirstEarly.sorted().let { e -> if (e.isEmpty()) "-" else "min ${e.first()} p50 ${e[e.size / 2]} max ${e.last()}" }}\n" +
                "DISTANCE late vs truth crossing (rang after the threshold, s): $lt\nviolations=$viol\n"
        }
    }

    /**
     * (e1) Approach with a real stop placed around the predicted alarm boundary (P0 ± 90 s), stop 20–1 500 s, then a new speed
     * 0.5–1.5×; fixes every policy interval with drop-outs (probability [fixP]), GPS jumps, poor accuracy, no Doppler; cancel lag
     * up to 5 s; FallbackScheduled fails 10 %. New information keeps arriving inside the quiet window of the fallback.
     */
    private fun stopNearAlarm(seed: Long, st: FuzzStats, params: EngineParams = p) {
        val r = Rng(seed)
        val mode = AlarmMode.entries[r.int(3)]
        val config = TripConfig(
            "e1-$seed", DEST.lat, DEST.lng, mode, if (mode == AlarmMode.DISTANCE) 200 + r.int(9801) else null,
            if (mode == AlarmMode.TIME) 5 + r.int(56) else null, r.chance(0.7), VehicleKind.entries[r.int(4)],
        )
        val c = r.dbl(4.0, 30.0)
        val g = c * r.dbl(1.0, 1.4)
        val d0 = r.dbl(8_000.0, 60_000.0)
        val s0 = trackingState(config, p = params, d = d0, ground = g, closing = c, slow = mode == AlarmMode.SMART && g * 3.6 < p.smartSlowSpeedKmh, tier = SamplingTier.DENSE)
        val sim = Sim(TripEngine.reduce(s0, Tick(S)), "e1 seed=$seed $mode thr=${config.distanceThresholdM}/${config.timeThresholdMin}", r, okP = 0.9, cancelLagMaxMs = 5_000)
        if (seed == TRACE_SEED) sim.trace = StringBuilder()
        val p0 = sim.step.view.predictedAlarmAtMs ?: return
        val truth = Truth(d0, S)
        truth.segs += S to c
        val stopAt = p0 + r.int(180_000) - 90_000L
        truth.segs += stopAt to 0.0
        val resume = stopAt + (r.dbl(20.0, 1_500.0) * 1000).toLong()
        truth.segs += resume to c * r.dbl(0.5, 1.5)
        sim.truthSpeed = truth::speedAt
        val fixP = r.dbl(0.3, 1.0)
        // Doze (60 %): from some time before the stop, a fix only at a wake-up Tick (probability fixInDozeP), as U111 withfix.
        val dozeAt = if (r.chance(0.6)) stopAt - r.int(1_800_000) else Long.MAX_VALUE
        val fixInDozeP = r.dbl(0.2, 0.9)
        var lastFix = S
        var guard = 0
        val killAt = if (r.chance(0.2)) stopAt + r.int(120_000) - 60_000L else null
        var killed = false
        var nf: Long? = null
        while (!sim.ended && ++guard < 50_000) {
            if (killAt != null && !killed && sim.alarms.isEmpty()) {
                val nextAny = listOfNotNull(sim.step.view.wakeAtMs, sim.nextOs()?.at, nf).minOrNull() ?: Long.MAX_VALUE
                if (nextAny >= killAt) {
                    killed = true
                    sim.kill(killAt)
                    st.kills++
                    val statuses = FallbackRestoreStatus.entries.filter { it != FallbackRestoreStatus.DISMISSED && it != FallbackRestoreStatus.RANG }
                    sim.restart(maxOf(killAt, sim.now) + r.int(300_000) + 1_000L, statuses[r.int(statuses.size)])
                    nf = null
                    continue
                }
            }
            if (sim.now >= dozeAt) {
                val w = sim.step.view.wakeAtMs
                nf = if (w != null && r.chance(fixInDozeP)) w else null
            } else if (nf == null || nf <= sim.now) {
                var x = maxOf(lastFix + interval(sim.step), sim.now + 1)
                while (!r.chance(fixP)) x += interval(sim.step)
                nf = x
            }
            val ok = sim.advance(Long.MAX_VALUE, nf) { t ->
                lastFix = t
                val dd = truth.dAt(t)
                var dist = abs(dd)
                if (r.chance(0.03)) dist += r.dbl(-1_000.0, 3_000.0)
                val acc = if (r.chance(0.1)) r.dbl(60.0, 300.0) else r.dbl(4.0, 25.0)
                fixAt(t, if (dd < 0) -dist else dist, acc = acc, spd = if (r.chance(0.3)) null else truth.speedAt(t) * r.dbl(0.9, 1.1), ageMs = r.int(1_500).toLong(), eastM = r.dbl(-15.0, 15.0))
            }
            if (!ok) break
        }
        sim.trace?.let { File(outDir, "t122-e1-trace-$seed.txt").writeText(it.toString()) }
        sim.alarms.firstOrNull()?.first?.let { a ->
            if ((a.reason == AlarmReason.OVERSHOOT || a.reason == AlarmReason.PASSED_CLOSEST) && truth.dAt(a.atMs) > 0.0) {
                st.wrongWording += "${sim.tag} ${a.reason} at truth d=${truth.dAt(a.atMs).toInt()} m"
            }
        }
        if (config.mode == AlarmMode.DISTANCE) {
            val f = sim.alarms.firstOrNull()?.first
            val cross = truth.crossAt(config.distanceThresholdM!!.toDouble(), S + 48 * 3_600_000L)
            if (f != null && cross != null && f.atMs > cross) {
                st.lateCross += (f.atMs - cross) / 1000.0
                noteLate(sim, truth, config, f, cross, st)
            }
        }
        noteLongLost(sim, truth, st)
        st.add(sim)
    }

    /**
     * (e2) Doze trips (model of U111 `withfix`, own generator): awake phase with fixes every policy interval, then Doze with a fix
     * only at wake-ups (probability 0.2–0.9); GPS gap; battery samples every 10 min (charging 10 %); kills (40 %) with restart after
     * 1 s–2 h (RANG when an OS alarm fired meanwhile, else PENDING 80 % / MISSING 10 % / UNKNOWN 10 %; a third of kills land inside
     * a GPS gap); FallbackScheduled fails 15 %; cancel lag up to 5 s.
     */
    private fun dozeTrip(seed: Long, st: FuzzStats, params: EngineParams = p) {
        val r = Rng(seed)
        val mode = AlarmMode.entries[r.int(3)]
        val config = TripConfig(
            "e2-$seed", DEST.lat, DEST.lng, mode,
            if (mode == AlarmMode.DISTANCE || r.chance(0.3)) 200 + r.int(9801) else null,
            if (mode == AlarmMode.TIME || (mode != AlarmMode.DISTANCE && r.chance(0.3))) 5 + r.int(56) else null,
            r.chance(0.7), VehicleKind.entries[r.int(4)],
        )
        val d0 = r.dbl(3_000.0, 300_000.0)
        val base = r.dbl(3.0, 35.0)
        val truth = Truth(d0, S)
        var t = S
        while (t < S + 60 * 3_600_000L) {
            truth.segs += t to base * r.dbl(0.7, 1.3)
            t += (r.dbl(300.0, 3_600.0) * 1000).toLong()
            if (r.chance(0.3)) {
                truth.segs += t to 0.0
                t += (r.dbl(30.0, 1_500.0) * 1000).toLong()
            }
        }
        val tripS = d0 / base
        val dozeAt = S + (r.dbl(0.0, 1.0) * tripS * 1000).toLong()
        val gapA = if (r.chance(0.5)) S + (r.dbl(0.0, 1.2) * tripS * 1000).toLong() else Long.MAX_VALUE
        val gapB = if (gapA == Long.MAX_VALUE) gapA else gapA + (r.dbl(60.0, 7_200.0) * 1000).toLong()
        val fixInDozeP = r.dbl(0.2, 0.9)
        var killAt: Long? = if (r.chance(0.4)) {
            if (gapA != Long.MAX_VALUE && r.chance(0.33)) gapA + (r.dbl(0.0, 1.0) * (gapB - gapA)).toLong()
            else S + (r.dbl(0.0, 1.5) * tripS * 1000).toLong()
        } else null
        val sim = Sim(TripEngine.start(config, params, S), "e2 seed=$seed $mode thr=${config.distanceThresholdM}/${config.timeThresholdMin} d0=${d0.toInt()}", r, okP = 0.85, cancelLagMaxMs = 5_000)
        var lastFix = S - 1_000_000L
        var batteryAtT = S
        var level = 20 + r.int(81)
        val drainPerH = r.dbl(1.0, 12.0)
        var guard = 0
        fun inGap(x: Long) = x >= gapA && x < gapB
        fun mkFix(x: Long): LocationFix {
            lastFix = x
            val dd = truth.dAt(x)
            var dist = abs(dd)
            if (r.chance(0.03)) dist += r.dbl(-2_000.0, 4_000.0)
            val acc = if (r.chance(0.1)) r.dbl(60.0, 400.0) else r.dbl(4.0, 30.0)
            return fixAt(x, if (dd < 0) -dist else dist, acc = acc, spd = if (r.chance(0.3)) null else truth.speedAt(x) * r.dbl(0.9, 1.1), ageMs = r.int(1_500).toLong(), eastM = r.dbl(-15.0, 15.0))
        }
        while (!sim.ended && ++guard < 60_000) {
            val now = sim.now
            val awake = now < dozeAt
            val wake = sim.step.view.wakeAtMs
            var nf: Long? = if (awake) maxOf(lastFix + interval(sim.step), now + 1) else if (wake != null && r.chance(fixInDozeP)) wake else null
            if (nf != null && inGap(nf)) nf = null
            val nb = batteryAtT + 600_000L
            val os = sim.nextOs()?.let { maxOf(it.at, now) }
            val cands = listOfNotNull(wake, os, nf, nb, killAt?.coerceAtLeast(now))
            val x = cands.min()
            if (killAt != null && x == killAt.coerceAtLeast(now)) {
                sim.kill(x)
                st.kills++
                val restartAt = x + (r.dbl(1.0, 7_200.0) * 1000).toLong()
                val status = when (r.int(10)) {
                    0 -> FallbackRestoreStatus.MISSING
                    1 -> FallbackRestoreStatus.UNKNOWN
                    else -> FallbackRestoreStatus.PENDING
                }
                killAt = if (r.chance(0.3)) restartAt + (r.dbl(60.0, 7_200.0) * 1000).toLong() else null
                sim.restart(restartAt, status)
                continue
            }
            if (os != null && x == os && (wake == null || os < wake)) {
                sim.fireOs(sim.nextOs()!!)
            } else if (nf != null && x == nf) {
                sim.feed(mkFix(x), "fix")
            } else if (wake != null && x == wake) {
                sim.feed(Tick(x), "Tick")
            } else {
                batteryAtT = x
                level = maxOf(1, level - maxOf(0, (drainPerH / 6.0 + r.dbl(-0.5, 0.5)).toInt()))
                sim.feed(BatterySample(x, level, r.chance(0.1)), "battery")
            }
        }
        sim.alarms.firstOrNull()?.first?.let { a ->
            if ((a.reason == AlarmReason.OVERSHOOT || a.reason == AlarmReason.PASSED_CLOSEST) && truth.dAt(a.atMs) > 0.0) {
                st.wrongWording += "${sim.tag} ${a.reason} at truth d=${truth.dAt(a.atMs).toInt()} m"
            }
        }
        if (config.mode == AlarmMode.DISTANCE) {
            val f = sim.alarms.firstOrNull()?.first
            val cross = truth.crossAt(config.distanceThresholdM!!.toDouble(), S + 60 * 3_600_000L)
            if (f != null && cross != null && f.atMs > cross) {
                st.lateCross += (f.atMs - cross) / 1000.0
                noteLate(sim, truth, config, f, cross, st)
            }
        }
        noteLongLost(sim, truth, st)
        st.add(sim)
    }

    @Test
    fun `T122 e fuzz urgent later shift path - no double ring, one alarm, I1-I7 I10-I14 at every Step, emissions equal fallbackTarget`() {
        val e1 = FuzzStats()
        for (seed in 1L..6_000L) stopNearAlarm(seed, e1)
        val e2 = FuzzStats()
        for (seed in 10_001L..12_000L) dozeTrip(seed, e2)
        File(outDir, "t122-e-fuzz.txt").writeText(e1.text("e1 stop near the alarm boundary") + "\n" + e2.text("e2 Doze with fixes at wake-ups, kills"))
        assertTrue(e1.urgent + e2.urgent >= 150) { "the fuzz exercises the urgent later shift: ${e1.urgent} + ${e2.urgent}" }
        assertTrue(e1.viol.isEmpty() && e2.viol.isEmpty()) { "e1 ${e1.viol.take(5)}\ne2 ${e2.viol.take(5)}" }
        // U125 (T10.6): no OVERSHOOT / PASSED_CLOSEST before the truth passed the destination.
        assertTrue(e1.wrongWording.isEmpty() && e2.wrongWording.isEmpty()) { "e1 ${e1.wrongWording.take(5)}\ne2 ${e2.wrongWording.take(5)}" }
    }

    /**
     * U126 b (T10.6, statistics): e1 / e2 with T10.6 off (T12.2) and on. Gate (T10.6 on): no violation, an alarm on every trip, no
     * wrong-wording OVERSHOOT / PASSED_CLOSEST. Written to u126-longloss-t122.txt (DISTANCE lateness vs the threshold crossing,
     * first alarms due to W alone and the true time left at them).
     */
    @Test
    fun `U126 b e1 e2 fuzz lateness T12_2 vs T10_6 and long-loss alarms`() {
        val off = app.napstop.core.trip.support.T106_OFF_PARAMS
        val e1Off = FuzzStats().also { st -> for (seed in 1L..6_000L) stopNearAlarm(seed, st, off) }
        val e2Off = FuzzStats().also { st -> for (seed in 10_001L..12_000L) dozeTrip(seed, st, off) }
        val e1 = FuzzStats().also { st -> for (seed in 1L..6_000L) stopNearAlarm(seed, st) }
        val e2 = FuzzStats().also { st -> for (seed in 10_001L..12_000L) dozeTrip(seed, st) }
        val q = { xs: List<Double> -> app.napstop.core.trip.support.quantiles(xs) }
        val out = StringBuilder("# U126 b (T10.6) e1 / e2 of TesterT122Test: off (gpsLostLongS 0, passedClosestSlowRiseM 0; preV on) -> T10.6\n")
        for ((name, a, b) in listOf(Triple("e1", e1Off, e1), Triple("e2", e2Off, e2))) {
            out.append("\n## $name\nDISTANCE late vs truth crossing (s): off ${q(a.lateCross)} -> T10.6 ${q(b.lateCross)}\n")
                .append("late > 1800 s: off ${a.lateCross.count { it > 1_800.0 }} -> T10.6 ${b.lateCross.count { it > 1_800.0 }}\n")
            for ((_, l) in b.lateLines.sortedByDescending { it.first }) out.append(l).append('\n')
            out
                .append("first alarms due to W alone: ${b.longLost}; true time left at them (s): ${q(b.longLostRemaining)}; after arrival: ")
                .append("${b.longLostRemaining.count { it < 0.0 }}\nfirstAlarm off ${a.first}\nfirstAlarm T10.6 ${b.first}\n")
                .append("violatingTrips off ${a.violTrips} -> T10.6 ${b.violTrips}; wrong wording ${a.wrongWording.size} -> ${b.wrongWording.size}\n")
        }
        File(outDir, "u126-longloss-t122.txt").writeText(out.toString())
        assertTrue(e1.viol.isEmpty() && e2.viol.isEmpty()) { "e1 ${e1.viol.take(5)}\ne2 ${e2.viol.take(5)}" }
        assertTrue(e1.wrongWording.isEmpty() && e2.wrongWording.isEmpty())
    }

    private companion object {
        val PINNED_C = """
loss=3600s m=0.7 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 -2896 s; true remaining at alarm 4096 s; late vs cross1000 -3933 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -3717 s)
loss=3600s m=1.0 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 -537 s; true remaining at alarm 1737 s; late vs cross1000 -1675 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -1358 s)
loss=3600s m=1.15 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 -57 s; true remaining at alarm 1257 s; late vs cross1000 -1204 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -878 s)
loss=3600s m=1.3 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 311 s; true remaining at alarm 888 s; late vs cross1000 -841 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -509 s)
loss=3600s m=1.5 DISTANCE: alarm GPS_LOST at 3601 s; late vs trueRemaining1200 688 s; true remaining at alarm 511 s; late vs cross1000 -470 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -132 s)
loss=7200s m=0.7 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 -4407 s; true remaining at alarm 5607 s; late vs cross1000 -5519 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -5948 s)
loss=7200s m=1.0 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 -999 s; true remaining at alarm 2199 s; late vs cross1000 -2084 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -2540 s)
loss=7200s m=1.15 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 303 s; true remaining at alarm 896 s; late vs cross1000 -843 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -1237 s)
loss=7200s m=1.3 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 1249 s; true remaining at alarm -49 s; late vs cross1000 137 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s)
loss=7200s m=1.5 DISTANCE: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 2165 s; true remaining at alarm -965 s; late vs cross1000 1006 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 624 s)
loss=10800s m=0.7 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 -6276 s; true remaining at alarm 7476 s; late vs cross1000 -7313 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -8537 s)
loss=10800s m=1.0 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 -814 s; true remaining at alarm 2014 s; late vs cross1000 -1952 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -3075 s)
loss=10800s m=1.15 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 664 s; true remaining at alarm 535 s; late vs cross1000 -481 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -1596 s)
loss=10800s m=1.3 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 1589 s; true remaining at alarm -389 s; late vs cross1000 436 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -671 s)
loss=10800s m=1.5 DISTANCE: alarm GPS_LOST at 10801 s; late vs trueRemaining1200 3162 s; true remaining at alarm -1962 s; late vs cross1000 2039 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 901 s)
loss=7200s m=1.3 TIME: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 1249 s; true remaining at alarm -49 s; late vs cross1000 137 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s)
loss=7200s m=1.3 SMART: alarm GPS_LOST at 7201 s; late vs trueRemaining1200 1249 s; true remaining at alarm -49 s; late vs cross1000 137 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s)
""".trim()
        /** U121: measured with W on (T12.3); DISTANCE rows within ± 5 s of T10 "T10.6" §1.4 column "W, Q12 A". */
        val PINNED_U121 = """
loss=3600s m=0.7 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -3712 s; true remaining at alarm 4912 s; late vs cross1000 -4748 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -3717 s); lostLongAtS 2784.8
loss=3600s m=1.0 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -1352 s; true remaining at alarm 2552 s; late vs cross1000 -2491 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -1358 s); lostLongAtS 2784.8
loss=3600s m=1.15 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -873 s; true remaining at alarm 2073 s; late vs cross1000 -2019 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -878 s); lostLongAtS 2784.8
loss=3600s m=1.3 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -504 s; true remaining at alarm 1704 s; late vs cross1000 -1656 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -509 s); lostLongAtS 2784.8
loss=3600s m=1.5 DISTANCE: alarm GPS_LOST at 2785 s; late vs trueRemaining1200 -127 s; true remaining at alarm 1327 s; late vs cross1000 -1285 s; etaMinS<1200 rule would ring at 2780 s (late vs trueRemaining1200 -132 s); lostLongAtS 2784.8
loss=7200s m=0.7 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -6172 s; true remaining at alarm 7372 s; late vs cross1000 -7284 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -5948 s); lostLongAtS 5435.7
loss=7200s m=1.0 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -2763 s; true remaining at alarm 3963 s; late vs cross1000 -3848 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -2540 s); lostLongAtS 5435.7
loss=7200s m=1.15 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -1460 s; true remaining at alarm 2660 s; late vs cross1000 -2607 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -1237 s); lostLongAtS 5435.7
loss=7200s m=1.3 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -514 s; true remaining at alarm 1714 s; late vs cross1000 -1627 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s); lostLongAtS 5435.7
loss=7200s m=1.5 DISTANCE: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 400 s; true remaining at alarm 799 s; late vs cross1000 -758 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 624 s); lostLongAtS 5435.7
loss=10800s m=0.7 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -8989 s; true remaining at alarm 10189 s; late vs cross1000 -10026 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -8537 s); lostLongAtS 8086.6
loss=10800s m=1.0 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -3527 s; true remaining at alarm 4727 s; late vs cross1000 -4666 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -3075 s); lostLongAtS 8086.6
loss=10800s m=1.15 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -2048 s; true remaining at alarm 3248 s; late vs cross1000 -3195 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -1596 s); lostLongAtS 8086.6
loss=10800s m=1.3 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 -1124 s; true remaining at alarm 2324 s; late vs cross1000 -2276 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 -671 s); lostLongAtS 8086.6
loss=10800s m=1.5 DISTANCE: alarm GPS_LOST at 8087 s; late vs trueRemaining1200 449 s; true remaining at alarm 750 s; late vs cross1000 -674 s; etaMinS<1200 rule would ring at 8540 s (late vs trueRemaining1200 901 s); lostLongAtS 8086.6
loss=7200s m=1.3 TIME: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -514 s; true remaining at alarm 1714 s; late vs cross1000 -1627 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s); lostLongAtS 5435.7
loss=7200s m=1.3 SMART: alarm GPS_LOST at 5436 s; late vs trueRemaining1200 -514 s; true remaining at alarm 1714 s; late vs cross1000 -1627 s; etaMinS<1200 rule would ring at 5660 s (late vs trueRemaining1200 -291 s); lostLongAtS 5435.7
""".trim()
        const val TRACE_SEED = -1L // set to an e1 seed to write t122-e1-trace-<seed>.txt
        const val NL = "\n"

        /** U115 bound in fix periods (T10.5 vòng 3c: 2; round 3b needed 4, the smoothed distance of fixes 2 and 3 is equal). */
        const val U115_PERIODS = 2L

        /** U115 variant (RK20 d): TIMEOUT runs out of 32, measured in T12.2 round 8. */
        const val U115_VARIANT_TIMEOUT = 3
        // T10.5 round 3 (before: "gps=OK predicted-now=210 s fac=ETA@240 s; first alarm TIMEOUT at 11400 s after the fix").
        // Round 3 ("… SUPERSEDED@null s; first alarm OVERSHOOT at 0 s after the fix"); round 3b: no immediate chord alarm, the urgent
        // later shift moves the fallback, OVERSHOOT on the 5th fix (+20 s); round 3c (lag-2 `notCloser`): the 3rd fix (+10 s).
        const val PINNED_B_REPRO = "gps=OK predicted-now=210 s fac=ETA@240 s; first alarm OVERSHOOT at 10 s after the fix"
    }
}
