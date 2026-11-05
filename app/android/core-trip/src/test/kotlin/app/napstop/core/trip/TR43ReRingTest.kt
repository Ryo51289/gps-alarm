package app.napstop.core.trip

import app.napstop.core.trip.harness.ActionSpec
import app.napstop.core.trip.harness.At
import app.napstop.core.trip.harness.CaseModel
import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.RelaunchSpec
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunOpts
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.Suite
import app.napstop.core.trip.harness.TimedEvent
import app.napstop.core.trip.harness.TraceModel
import app.napstop.core.trip.harness.TraceSample
import app.napstop.core.trip.harness.eventName
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.Locale
import java.util.concurrent.Callable

/**
 * TR43 (T10 mục cuối "T10.7" §9.2, RK24): re-ring OVERSHOOT after an alarm that rang inside the GPS gap of TR40
 * (`coach_gb_caugie_gappass`, gap [2 020, 2 980)), the vehicle passing the destination in the gap. Cases distance_1000, time_15,
 * smart, `all` + `policy`; the case expectations are replaced by the checks below (forbidMatch TIMEOUT kept); every per-run harness
 * check (I1–I7, I10–I12, P07, finite state) must hold. Not in the P05 manifest. Report `t107-tr43.txt` (no coordinates).
 * T10.7 round 2 (C31): the chord after the alarm only proves "came near", so the re-ring waits for 1 km measured from the first
 * fix after the gap: windows [g.end, g.end + 60], (c) snoozed at 2 990, (f-iii) [3 010, 3 070].
 */
class TR43ReRingTest {
    private companion object {
        const val TRACE = "coach_gb_caugie_gappass"
        val CASES = listOf("distance_1000", "time_15", "smart")
        /** T10.7 round 2 (C31): the re-ring needs dSmooth − minD (observed) >= 1 000, window [g.end, g.end + 60] (round 1: 25). */
        const val WINDOW_S = 60

        /** (g2) is the round-3b/3c standing term before any alarm: window unchanged. */
        const val G2_WINDOW_S = 25

        /** By hand for `all` (T10 "T10.7 vòng 2" §4): (a)–(e) 3 030, (f) ≈ 3 060 (measured). */
        const val RERING_T = 3_030
        const val RERING_F_T = 3_060
        const val KILL_T = 2_320
        val LOST_3600 = mapOf("gpsLostAlarmEtaS" to JNumber("3600"))

        /** t107-tr43.txt by "variant case mode" (any test order). */
        val LOG = sortedMapOf<String, String>()
    }

    private val trace: TraceModel by lazy { Suite.traces.first { it.id == TRACE } }
    private val gStart: Int get() = trace.gpsGaps.first().first
    private val gEnd: Int get() = trace.gpsGaps.first().second

    private fun model(
        caseId: String,
        ringMaxS: Int? = null,
        kill: Int? = null,
        relaunch: Int? = null,
        actions: List<ActionSpec> = emptyList(),
    ): CaseModel {
        val base = trace.cases.first { it.id == caseId }.model!!
        return base.copy(
            config = base.config.copy(
                osRingMaxS = ringMaxS,
                kill = kill?.let { At(it, null, 0) },
                relaunch = relaunch?.let { RelaunchSpec(At(it, null, 0), "auto") },
                actions = base.config.actions + actions,
            ),
            expect = emptyList(),
            expectAfter = emptyList(),
        )
    }

    /**
     * TR43 (g)/(g2): the vehicle stops at the first fix after the gap — every sample with t ≥ [tS] gets the position of the
     * sample at [tS], speed 0, accuracy kept. In memory only.
     */
    private fun parkedAfter(tr: TraceModel, tS: Int): TraceModel {
        val samples = tr.gpx.samples
        val at = samples.first { it.t == tS }
        return tr.withSamples(samples.map { s -> if (s.t < tS) s else TraceSample(s.index, s.t, at.lat, at.lng, s.accuracyM, 0.0) })
    }

    private fun desc(e: TimedEvent): String = when (val x = e.e) {
        is Alarm -> "${e.t} alarm ${x.reason} ringNow=${x.ringNow}"
        is FallbackAlarmChanged -> "${e.t} fallbackAlarmChanged ${if (x.fallbackAtMs == null) "null" else "set"} ${x.cause}"
        else -> "${e.t} ${eventName(x)}"
    }

    /** Events and the KILL / RESTORE / AlarmSilenced / UserAction markers in [g.start − 60, g.end + 120]. */
    private fun timeline(r: RunResult): String {
        val out = ArrayList<String>()
        for ((i, rec) in r.records.withIndex()) {
            if (rec.t < gStart - 60 || rec.t > gEnd + 120) continue
            when {
                rec.inJson == "[\"KILL\"]" -> out += "${rec.t} KILL"
                rec.restoreInfo != null -> out += "${rec.t} RESTORE ${rec.restoreInfo.status}"
                rec.input is AlarmSilenced -> out += "${rec.t} in:alarmSilenced"
                rec.input is UserAction -> out += "${rec.t} in:${rec.input.action}"
            }
            for (e in rec.events) out += desc(TimedEvent(rec.t, i, e))
        }
        return out.joinToString("; ")
    }

    private class Run(val caseId: String, val key: RunKey, val r: RunResult) {
        val evs: List<TimedEvent> = Checks.events(r)
        val alarms: List<TimedEvent> get() = evs.filter { it.e is Alarm }
        val overshoot: TimedEvent? get() = evs.firstOrNull { it.e is Overshoot }
    }

    private fun runs(variant: String, m: (String) -> CaseModel, tr: TraceModel = trace, opts: RunOpts = RunOpts(probes = false)): List<Run> {
        val jobs = CASES.flatMap { c -> val cm = m(c); Suite.keysOf(tr, cm).map { k -> Triple(c, cm, k) } }
        return jobs.map { (c, cm, k) -> Suite.pool.submit(Callable { Run(c, k, CaseRun.run(tr, cm, k, opts)) }) }.map { it.get() }
            .also { rs -> for (x in rs) note(variant, x) }
    }

    private fun note(variant: String, x: Run, extra: String = "") {
        synchronized(LOG) {
            LOG["$variant ${x.caseId} ${x.key.mode}"] = "($variant) ${x.caseId} ${x.key.mode}: ${timeline(x.r)}$extra"
            File(Suite.outDir.apply { mkdirs() }, "t107-tr43.txt").writeText(LOG.values.joinToString("\n", postfix = "\n"))
        }
    }

    private fun inWindow(t: Int?, from: Int = gEnd): Boolean = t != null && t >= from && t <= from + WINDOW_S

    private fun tag(x: Run) = "${x.caseId}/${x.key.mode}"

    /** Harness checks of the case (forbidMatch TIMEOUT, I1–I7, I10–I12, P07, finite state) under [m]. */
    private fun harness(x: Run, m: CaseModel, tr: TraceModel = trace): List<String> = Checks.check(tr, m, x.r).map { "${tag(x)}: $it" }

    /** The re-ring: exactly one Alarm from g.end, OVERSHOOT ringNow=true in the window, with the Overshoot in the same Step. */
    private fun reRing(x: Run, from: Int = gEnd): List<String> {
        val f = ArrayList<String>()
        val after = x.alarms.filter { it.t >= from }
        val ov = x.overshoot
        if (after.size != 1) f += "${tag(x)}: ${after.size} alarms from $from: ${after.map { desc(it) }}"
        val a = after.firstOrNull()
        if (a == null || (a.e as Alarm).reason != AlarmReason.OVERSHOOT || !a.e.ringNow || !inWindow(a.t, from)) {
            f += "${tag(x)}: re-ring ${a?.let { desc(it) }}, want alarm OVERSHOOT ringNow=true in [$from, ${from + WINDOW_S}]"
        }
        if (ov == null || a == null || ov.rec != a.rec) f += "${tag(x)}: overshoot ${ov?.t} not in the Step of the re-ring ${a?.t}"
        return f
    }

    private fun phaseAt(x: Run, e: TimedEvent?): TripPhase? = e?.let { x.r.records[it.rec].view?.phase }

    @Test
    fun `TR43 a b c alarm rang in the gap - chime stopped re-rings OVERSHOOT, still ringing gives Overshoot only, snoozed supersedes`() {
        val fails = ArrayList<String>()
        // (a) GPS_LOST forced inside the gap, the chime stops after 60 s.
        val a = runs("a", { c -> model(c, ringMaxS = 60) }, opts = RunOpts(probes = false, paramOverrides = LOST_3600))
        for (x in a) {
            fails += harness(x, model(x.caseId, ringMaxS = 60))
            val first = x.alarms.firstOrNull()
            if (first == null || (first.e as Alarm).reason != AlarmReason.GPS_LOST || first.t <= gStart || first.t >= gEnd) {
                fails += "${tag(x)} (a): first alarm ${first?.let { desc(it) }}, want GPS_LOST inside the gap"
            }
            if (x.r.records.none { it.input is AlarmSilenced && it.t < gEnd }) fails += "${tag(x)} (a): no AlarmSilenced before g.end"
            fails += reRing(x).map { "(a) $it" }
            if (phaseAt(x, x.overshoot) != TripPhase.OVERSHOT) fails += "${tag(x)} (a): phase ${phaseAt(x, x.overshoot)} at the overshoot"
            if (!x.key.policy && (first?.t != 2_105 || x.overshoot?.t != RERING_T)) {
                fails += "${tag(x)} (a): by hand GPS_LOST 2105, OVERSHOOT $RERING_T; got ${first?.t}, ${x.overshoot?.t}"
            }
        }
        // (b) the chime still rings: Overshoot only (screen 8), no Alarm after GPS_LOST.
        val b = runs("b", { c -> model(c) }, opts = RunOpts(probes = false, paramOverrides = LOST_3600))
        for (x in b) {
            fails += harness(x, model(x.caseId))
            val ov = x.overshoot
            if (!inWindow(ov?.t)) fails += "${tag(x)} (b): overshoot at ${ov?.t}"
            if (x.alarms.size != 1 || (x.alarms.first().e as Alarm).reason != AlarmReason.GPS_LOST) {
                fails += "${tag(x)} (b): alarms ${x.alarms.map { desc(it) }}, want GPS_LOST only"
            }
            if (ov != null && x.r.records[ov.rec].view?.alarmRinging != true) fails += "${tag(x)} (b): alarmRinging false at the overshoot"
            if (!x.key.policy && ov?.t != RERING_T) fails += "${tag(x)} (b): by hand $RERING_T, got ${ov?.t}"
        }
        // (c) as (a), snoozed at 2 960 (until 3 020): the re-ring supersedes the snooze before it ends.
        val snooze = listOf(ActionSpec(At(2_990, null, 0), "snooze"))
        val c = runs("c", { cid -> model(cid, ringMaxS = 60, actions = snooze) }, opts = RunOpts(probes = false, paramOverrides = LOST_3600))
        for (x in c) {
            fails += harness(x, model(x.caseId, ringMaxS = 60, actions = snooze))
            if (x.evs.none { it.e is Snoozed && it.t == 2_990 }) fails += "${tag(x)} (c): no snoozed at 2990"
            fails += reRing(x).map { "(c) $it" }
            val a = x.alarms.lastOrNull()
            val sup = x.evs.firstOrNull {
                it.rec == a?.rec && it.e is FallbackAlarmChanged && it.e.cause == FallbackCause.SUPERSEDED
            }
            if (a == null || sup == null || (sup.e as FallbackAlarmChanged).fallbackAtMs != null) {
                fails += "${tag(x)} (c): fallbackAlarmChanged(null, SUPERSEDED) ${sup?.let { desc(it) }} not in the Step of the re-ring ${a?.t}"
            }
            if (a == null || a.t >= 3_050) fails += "${tag(x)} (c): re-ring at ${a?.t}, want before snoozeUntil 3050"
            if (x.alarms.any { (it.e as Alarm).reason == AlarmReason.SNOOZE_END }) fails += "${tag(x)} (c): SNOOZE_END"
            if (!x.key.policy && x.overshoot?.t != RERING_T) fails += "${tag(x)} (c): by hand $RERING_T, got ${x.overshoot?.t}"
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    @Test
    fun `TR43 d e f process killed in the gap, relaunch before or after the GPS returns`() {
        val fails = ArrayList<String>()
        // (d) relaunch at 2 920 (GPS back at 2 980), the OS chime stops after 60 s: re-ring (= TesterT113Test e).
        val d = runs("d", { c -> model(c, ringMaxS = 60, kill = KILL_T, relaunch = 2_920) })
        for (x in d) {
            fails += harness(x, model(x.caseId, ringMaxS = 60, kill = KILL_T, relaunch = 2_920))
            val fb = x.r.osFallbackFiredT
            if (fb == null || fb > gEnd) fails += "${tag(x)} (d): OS fallback at $fb, want <= g.end"
            val restoreAlarm = x.alarms.firstOrNull { it.t == 2_920 }
            if (restoreAlarm == null || (restoreAlarm.e as Alarm).reason != AlarmReason.FALLBACK || restoreAlarm.e.ringNow) {
                fails += "${tag(x)} (d): at relaunch ${restoreAlarm?.let { desc(it) }}, want alarm FALLBACK ringNow=false"
            }
            if (x.r.records.none { it.input is AlarmSilenced && it.t >= 2_920 }) fails += "${tag(x)} (d): no AlarmSilenced after relaunch"
            fails += reRing(x).map { "(d) $it" }
            if (!x.key.policy && x.overshoot?.t != RERING_T) fails += "${tag(x)} (d): by hand $RERING_T, got ${x.overshoot?.t}"
        }
        // (e) as (d), the OS chime still rings (= TesterT113Test a): Overshoot only.
        val e = runs("e", { c -> model(c, kill = KILL_T, relaunch = 2_920) })
        for (x in e) {
            fails += harness(x, model(x.caseId, kill = KILL_T, relaunch = 2_920))
            if (!inWindow(x.overshoot?.t)) fails += "${tag(x)} (e): overshoot at ${x.overshoot?.t}"
            val rang = x.alarms.filter { it.t >= 2_920 && (it.e as Alarm).ringNow }
            if (rang.isNotEmpty()) fails += "${tag(x)} (e): ${rang.map { desc(it) }} after relaunch"
            if (!x.key.policy && x.overshoot?.t != RERING_T) fails += "${tag(x)} (e): by hand $RERING_T, got ${x.overshoot?.t}"
        }
        // (f) relaunch at 3 010 (after the GPS came back), the OS chime stopped while the engine was dead (= TesterT113Test d).
        val relF = 3_010
        val f = runs("f", { c -> model(c, ringMaxS = 60, kill = KILL_T, relaunch = relF) }, opts = RunOpts(probes = true))
        for (x in f) {
            fails += harness(x, model(x.caseId, ringMaxS = 60, kill = KILL_T, relaunch = relF))
            val g = x.r.gapProbes.filter { it.atMs - x.r.startMs >= relF * 1000L }.minByOrNull { it.atMs }
            val chord = g?.dChord
            val silencedAtRelaunch = x.r.records.any { it.input is AlarmSilenced && it.t == relF }
            val probe = String.format(
                Locale.ROOT, " | first fix after relaunch: t=%d gapFix=%s phase=%s u=%s dChord=%s; AlarmSilenced at relaunch=%s",
                g?.let { (it.atMs - x.r.startMs) / 1000 }, g?.gapFix, g?.phase, g?.u?.let { "%.4f".format(Locale.ROOT, it) },
                chord?.let { "%.1f".format(Locale.ROOT, it) }, silencedAtRelaunch,
            )
            note("f", x, probe)
            // T10 "T10.7" §9.2 (f), deterministic gate: the OS chime (2 885 / 2 880 + 60 s) stopped before the relaunch, so the
            // harness relaunch sends AlarmSilenced (T12 §8.4, T16 §8) and the overshoot must re-ring.
            // (f-i) restore RANG → Alarm(FALLBACK, ringNow=false) at 3 010, and AlarmSilenced at 3 010 (harness precondition).
            val restoreAlarm = x.alarms.firstOrNull { it.t == relF }
            if (restoreAlarm == null || (restoreAlarm.e as Alarm).reason != AlarmReason.FALLBACK || restoreAlarm.e.ringNow) {
                fails += "${tag(x)} (f): at relaunch ${restoreAlarm?.let { desc(it) }}, want alarm FALLBACK ringNow=false"
            }
            if (!silencedAtRelaunch) fails += "${tag(x)} (f): harness precondition: no AlarmSilenced at relaunch"
            // (f-ii) the first fix after the relaunch is a chord fix in ALARMING with dChord < 1 000 (nearRadius of the cases).
            if (g == null || !g.gapFix || g.phase != TripPhase.ALARMING || chord == null || chord >= 1_000.0) {
                fails += "${tag(x)} (f): first fix after relaunch not an ALARMING chord fix < 1000 m:$probe"
            }
            // (f-iii) exactly one Alarm(ringNow=true) from 3 010: OVERSHOOT, in the Step of the single overshoot, in the window.
            val ov = x.overshoot
            if (!inWindow(ov?.t, relF)) fails += "${tag(x)} (f): overshoot at ${ov?.t}, window [$relF, ${relF + WINDOW_S}]"
            val rang = x.alarms.filter { it.t >= relF && (it.e as Alarm).ringNow }
            val a = rang.singleOrNull()
            if (a == null || (a.e as Alarm).reason != AlarmReason.OVERSHOOT || a.rec != ov?.rec) {
                fails += "${tag(x)} (f): after relaunch ${rang.map { desc(it) }}, want one alarm OVERSHOOT ringNow=true with the overshoot ${ov?.t}"
            }
            if (!x.key.policy && ov?.t != RERING_F_T) fails += "${tag(x)} (f): measured $RERING_F_T, got ${ov?.t}"
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    @Test
    fun `TR43 g g2 parked beyond the destination after the gap - no re-ring once the chime stopped, OVERSHOOT before any alarm`() {
        val fails = ArrayList<String>()
        val parked = parkedAfter(trace, gEnd)
        assertEquals(trace.gpx.samples.map { it.t }, parked.gpx.samples.map { it.t })
        // (g) as (a) on the parked trace: nothing after g.end until the end of the trace (alarmMaxActiveS not reached).
        val g = runs("g", { c -> model(c, ringMaxS = 60) }, tr = parked, opts = RunOpts(probes = true, paramOverrides = LOST_3600))
        for (x in g) {
            fails += harness(x, model(x.caseId, ringMaxS = 60), parked)
            // Not vacuous (review T12.4 nit #2): the first fix after the gap is a chord fix in ALARMING with dChord < nearRadius.
            val chordAtEnd = x.r.gapProbes.firstOrNull { it.atMs - x.r.startMs == gEnd * 1000L }
            if (chordAtEnd == null || chordAtEnd.phase != TripPhase.ALARMING || (chordAtEnd.dChord ?: Double.MAX_VALUE) >= 1_000.0) {
                fails += "${tag(x)} (g): no ALARMING chord fix < 1000 m at g.end (phase=${chordAtEnd?.phase} dChord=${chordAtEnd?.dChord})"
            }
            val first = x.alarms.firstOrNull()
            if (first == null || (first.e as Alarm).reason != AlarmReason.GPS_LOST || first.t >= gEnd) {
                fails += "${tag(x)} (g): first alarm ${first?.let { desc(it) }}, want GPS_LOST in the gap"
            }
            val after = x.evs.filter { it.t >= gEnd && (it.e is Alarm || it.e is Overshoot) }
            if (after.isNotEmpty()) fails += "${tag(x)} (g): ${after.map { desc(it) }} after g.end"
            if (x.evs.any { it.e is TripEnded }) fails += "${tag(x)} (g): trip ended before the end of the trace"
        }
        // (g2) control, default params (no alarm before the gap): the round-3b/3c standing term rings OVERSHOOT; TIME rings TIME.
        val g2 = runs("g2", { c -> model(c) }, tr = parked)
        for (x in g2) {
            fails += harness(x, model(x.caseId), parked)
            if (x.caseId == "time_15") continue // printed only (T10.7 §9.2)
            val first = x.alarms.firstOrNull()
            if (first == null || (first.e as Alarm).reason != AlarmReason.OVERSHOOT || !first.e.ringNow || first.t < gEnd || first.t > gEnd + G2_WINDOW_S) {
                fails += "${tag(x)} (g2): first alarm ${first?.let { desc(it) }}, want OVERSHOOT ringNow=true in the window"
            }
            if (first == null || x.overshoot?.rec != first.rec) fails += "${tag(x)} (g2): overshoot ${x.overshoot?.t} not with the alarm ${first?.t}"
            if (!x.key.policy && first?.t != 2_985) fails += "${tag(x)} (g2): by hand 2985, got ${first?.t}"
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }
}
