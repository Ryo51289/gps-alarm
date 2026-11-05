package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.JNumber
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.TMath
import app.napstop.core.trip.distanceM
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.harness.ActionSpec
import app.napstop.core.trip.harness.At
import app.napstop.core.trip.harness.CaseModel
import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.GpxTrace
import app.napstop.core.trip.harness.RelaunchSpec
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunOpts
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.Suite
import app.napstop.core.trip.harness.TimedEvent
import app.napstop.core.trip.harness.TraceModel
import app.napstop.core.trip.harness.TraceSample
import app.napstop.core.trip.harness.eventName
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.Locale
import java.util.Random
import java.util.concurrent.Callable
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * T12.4 (tester): T10.7 / RK24 beyond U127 and TR43 (review T12.4 "Ghi chú cho tester"); expectations per T10 "T10.7 vòng 2" (C31,
 * Q14 = A: after the alarm the chord only proves "came near" (alarmedChordD), the 1 km rise is measured from real fixes).
 *
 * 1. TR40 (`coach_gb_caugie_gappass`, gap [2 020, 2 980)): (f2) relaunch at 3 010 while the OS chime still rings; SNOOZED with the
 *    chord fix after snoozeUntil (s1, s2: chime still ringing at the overshoot; s1b, s3: chime stopped before it); (k) process killed
 *    right after the chord fix (alarmedChordD through the snapshot). Each overshoot is also checked against an independent replay of
 *    C31 (first fix with a measured rise >= 1 km; pastM = dSmooth − alarmedChordD).
 * 2. RK20 (e) on synthetic loop routes built in memory (never written to a file): the alarm rang before / in a GPS gap that hides a
 *    loop; the chord passes within 1 km of the destination while the real road stays >= 3 km away. Gates as U128 (Gaussian noise
 *    here, uniform there): L2–L5 no early Overshoot; L1 (RK20 e, accepted) only after a real rise >= 1 km.
 * Report: build/core-trip/napstop/t124-tester.txt (times, distances, u, phases; no coordinates).
 */
class TesterT124Test {
    private companion object {
        const val TRACE = "coach_gb_caugie_gappass"
        val CASES = listOf("distance_1000", "time_15", "smart")
        const val WINDOW_S = 25
        const val KILL_T = 2_320
        val LOST_3600 = mapOf("gpsLostAlarmEtaS" to JNumber("3600"))
        val LOG = sortedMapOf<String, String>()

        /** Metres per degree of latitude used to place the synthetic routes (only the layout; distances come from the engine). */
        const val M_PER_DEG = 111_320.0
    }

    private val tr40: TraceModel by lazy { Suite.traces.first { it.id == TRACE } }

    private fun note(key: String, line: String) {
        synchronized(LOG) {
            LOG[key] = line
            File(Suite.outDir.apply { mkdirs() }, "t124-tester.txt").writeText(LOG.values.joinToString("\n", postfix = "\n"))
        }
    }

    private fun desc(e: TimedEvent): String = when (val x = e.e) {
        is Alarm -> "${e.t} alarm ${x.reason} ringNow=${x.ringNow}"
        is Overshoot -> "${e.t} overshoot pastM=${x.pastM}"
        is FallbackAlarmChanged -> "${e.t} fallbackAlarmChanged ${if (x.fallbackAtMs == null) "null" else "set"} ${x.cause}"
        is TripEnded -> "${e.t} tripEnded ${x.outcome} ${x.endReason}"
        else -> "${e.t} ${eventName(x)}"
    }

    private fun timeline(r: RunResult, from: Int, to: Int): String {
        val out = ArrayList<String>()
        for ((i, rec) in r.records.withIndex()) {
            if (rec.t < from || rec.t > to) continue
            when {
                rec.inJson == "[\"KILL\"]" -> out += "${rec.t} KILL"
                rec.restoreInfo != null -> out += "${rec.t} RESTORE ${rec.restoreInfo.status}"
                rec.input is AlarmSilenced -> out += "${rec.t} in:alarmSilenced"
                rec.input is app.napstop.core.trip.UserAction -> out += "${rec.t} in:${rec.input.action}"
            }
            for (e in rec.events) if (eventName(e) != "fallbackAlarmChanged" || (e as FallbackAlarmChanged).fallbackAtMs == null) {
                out += desc(TimedEvent(rec.t, i, e))
            }
        }
        return out.joinToString("; ")
    }

    private class Run(val caseId: String, val key: RunKey, val m: CaseModel, val r: RunResult) {
        val evs: List<TimedEvent> = Checks.events(r)
        val alarms: List<TimedEvent> get() = evs.filter { it.e is Alarm }
        val overshoots: List<TimedEvent> get() = evs.filter { it.e is Overshoot }
        val tag: String get() = "$caseId/${key.mode}"
    }

    private fun model(
        caseId: String,
        ringMaxS: Int? = null,
        kill: Int? = null,
        relaunch: Int? = null,
        actions: List<ActionSpec> = emptyList(),
    ): CaseModel {
        val base = tr40.cases.first { it.id == caseId }.model!!
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

    private fun runs(tr: TraceModel, cases: List<String>, m: (String) -> CaseModel, opts: RunOpts): List<Run> {
        val jobs = cases.flatMap { c -> val cm = m(c); Suite.keysOf(tr, cm).map { k -> Triple(c, cm, k) } }
        return jobs.map { (c, cm, k) -> Suite.pool.submit(Callable { Run(c, k, cm, CaseRun.run(tr, cm, k, opts)) }) }.map { it.get() }
    }

    private fun harness(tr: TraceModel, x: Run): List<String> = Checks.check(tr, x.m, x.r).map { "${x.tag}: $it" }

    private fun inWindow(t: Int?, from: Int, w: Int = WINDOW_S): Boolean = t != null && t >= from && t <= from + w

    /**
     * Independent replay of T10 §4.3 / §4.11 on the fixes the engine actually received (all accepted on TR40): dSmooth = medianHi of the
     * raw distances of the newest 3 fixes within smoothWindowS, minD = min dSmooth since the start (C31: never lowered by a chord after
     * the alarm). [firstRiseT]: first fix tick >= fromT with dSmooth − minD >= overshootOpenM (C31 term (2), "the measured distance
     * rose 1 km"); [dSmoothAt]: dSmooth at every fix tick.
     */
    private class Replay(val firstRiseT: Int?, val dSmoothAt: Map<Int, Double>)

    private fun replay(x: Run, fromT: Int): Replay {
        val p = x.r.params
        val recent = ArrayList<Pair<Long, Double>>()
        var minD: Double? = null
        var rise: Int? = null
        val ds = LinkedHashMap<Int, Double>()
        for (rec in x.r.records) {
            val f = rec.input as? LocationFix ?: continue
            val d = distanceM(f.lat, f.lng, tr40.destLat, tr40.destLng)
            recent.removeAll { it.first < f.fixAtMs - p.smoothWindowS * 1000L }
            recent += f.fixAtMs to d
            while (recent.size > 3) recent.removeAt(0)
            val sm = TMath.medianHi(recent.map { it.second })!!
            ds[rec.t] = sm
            val m = if (minD == null || sm < minD) sm else minD
            minD = m
            if (rise == null && rec.t >= fromT && sm - m >= p.overshootOpenM) rise = rec.t
        }
        return Replay(rise, ds)
    }

    /**
     * C31 at the overshoot Step [ov]: it is the first fix where the measured rise reached overshootOpenM (term (2) from real fixes only),
     * and pastM = roundHalfUp(dSmooth − nearD), nearD = the chord distance after the alarm ([chordD], below minD here).
     */
    private fun c31(x: Run, ov: TimedEvent?, fromT: Int, chordD: Double?, label: String): List<String> {
        if (ov == null || chordD == null) return listOf("${x.tag} ($label): C31 check without overshoot/chord")
        val f = ArrayList<String>()
        val rp = replay(x, fromT)
        if (rp.firstRiseT != ov.t) f += "${x.tag} ($label): overshoot ${ov.t}, first measured rise >= 1 km at ${rp.firstRiseT} (C31 term 2)"
        val want = rp.dSmoothAt[ov.t]?.let { TMath.roundHalfUp(it - chordD) }
        val pastM = (ov.e as Overshoot).pastM
        if (want == null || abs(pastM - want) > 1) f += "${x.tag} ($label): pastM $pastM, want dSmooth − alarmedChordD = $want (C31)"
        return f
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // 1. TR40 variants (T10 "T10.7" + "T10.7 vòng 2" §4: the re-ring needs the measured distance to rise 1 km, Q14 = A)
    // ---------------------------------------------------------------------------------------------------------------------------

    /**
     * Review T12.4 "Ghi chú cho tester" (f): as TR43 (f) (kill 2 320, relaunch 3 010 after the GPS came back) but no osRingMaxS — the
     * OS fallback chime (2 885 / 2 880) still rings at the relaunch. Expected: restore RANG → Alarm(FALLBACK, ringNow=false), no
     * AlarmSilenced, the first fix after the relaunch is an ALARMING chord fix (stored as alarmedChordD, C31), then the overshoot only
     * (screen 8), no second ring. T10.7 vòng 2 §4 row "T124 f2": ≈ 3 060 (minD = d(3 010) ≈ 5 310 measured, needs d(t − 5) ≥ 6 310);
     * window as TR43 (f-iii) [3 010, 3 070].
     */
    @Test
    fun `T124 f2 relaunch after the GPS returned while the OS chime still rings - Overshoot only, no second ring`() {
        val fails = ArrayList<String>()
        val rel = 3_010
        val rs = runs(tr40, CASES, { c -> model(c, kill = KILL_T, relaunch = rel) }, RunOpts(probes = true))
        for (x in rs) {
            fails += harness(tr40, x)
            val fb = x.r.osFallbackFiredT
            if (fb == null || fb >= rel) fails += "${x.tag} (f2): OS fallback fired at $fb, want before the relaunch $rel"
            val restore = x.alarms.firstOrNull { it.t == rel }
            if (restore == null || (restore.e as Alarm).reason != AlarmReason.FALLBACK || restore.e.ringNow) {
                fails += "${x.tag} (f2): at relaunch ${restore?.let { desc(it) }}, want alarm FALLBACK ringNow=false"
            }
            val ov = x.overshoots.singleOrNull()
            if (x.r.records.any { it.input is AlarmSilenced && it.t >= rel && (ov == null || it.t <= ov.t) }) {
                fails += "${x.tag} (f2): precondition: AlarmSilenced while the OS chime should still ring"
            }
            val g = x.r.gapProbes.filter { it.atMs - x.r.startMs >= rel * 1000L }.minByOrNull { it.atMs }
            if (g == null || !g.gapFix || g.phase != TripPhase.ALARMING || (g.dChord ?: Double.MAX_VALUE) >= 1_000.0) {
                fails += "${x.tag} (f2): first fix after relaunch gapFix=${g?.gapFix} phase=${g?.phase} dChord=${g?.dChord}"
            }
            if (!inWindow(ov?.t, rel, 60)) fails += "${x.tag} (f2): overshoot ${x.overshoots.map { desc(it) }}, window [$rel, ${rel + 60}]"
            val rang = x.alarms.filter { it.t >= rel && (it.e as Alarm).ringNow }
            if (rang.isNotEmpty()) fails += "${x.tag} (f2): second ring ${rang.map { desc(it) }}"
            if (ov != null) {
                val v = x.r.records[ov.rec].view
                if (v?.alarmRinging != true) fails += "${x.tag} (f2): alarmRinging ${v?.alarmRinging} at the overshoot"
                if (v?.phase != TripPhase.OVERSHOT) fails += "${x.tag} (f2): phase ${v?.phase} at the overshoot"
            }
            fails += c31(x, ov, rel, g?.dChord, "f2")
            if (!x.key.policy && ov?.t != 3_060) fails += "${x.tag} (f2): by hand 3060 (T10.7 vòng 2 §4), got ${ov?.t}"
            note(
                "1 f2 ${x.tag}",
                String.format(
                    Locale.ROOT, "(f2) %s: OS fallback %s; chord t=%s u=%s dChord=%s; first measured rise >= 1 km at %s; %s", x.tag, fb,
                    g?.let { (it.atMs - x.r.startMs) / 1000 }, g?.u?.let { "%.4f".format(Locale.ROOT, it) },
                    g?.dChord?.let { "%.1f".format(Locale.ROOT, it) }, replay(x, rel).firstRiseT, timeline(x.r, 2_880, 3_100),
                ),
            )
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /**
     * Review T12.4 "Ghi chú cho tester" (SNOOZED + chord): the chord fix (2 980) comes after snoozeUntilMs, SNOOZE_END already rang.
     * After T10.7 vòng 2 the overshoot comes at 3 030 (`all`; measured rise 1 km), so each variant's chime timing is set against 3 030:
     * (s1)  osRingMaxS 60, snooze 2 915 (until 2 975): SNOOZE_END 2 975 still rings at 3 030 (stops 3 035) → Overshoot only.
     * (s1b) osRingMaxS 60, snooze 2 900 (until 2 960): SNOOZE_END 2 960 stops at 3 020, after the chord fix and before the overshoot →
     *       AlarmSilenced 3 020, then one re-ring OVERSHOOT (PO #18). This was s1 in Lần 1, when the overshoot came at 3 000.
     * (s2)  snooze 2 900, no osRingMaxS (the chime never stops) → Overshoot only.
     * (s3)  osRingMaxS 60, snooze 2 840 (until 2 900): SNOOZE_END 2 900 stopped at 2 960, before the GPS returns → one re-ring OVERSHOOT.
     */
    @Test
    fun `T124 s1 s1b s2 s3 snoozed, chord fix after snoozeUntil - still ringing gives Overshoot only, stopped chime re-rings OVERSHOOT`() {
        val fails = ArrayList<String>()
        val gEnd = tr40.gpsGaps.first().second
        data class V(val id: String, val ringMax: Int?, val snoozeAt: Int, val ringingAtOvershoot: Boolean, val silencedAt: Int?)
        val variants = listOf(
            V("s1", 60, 2_915, true, null), V("s1b", 60, 2_900, false, 3_020), V("s2", null, 2_900, true, null),
            V("s3", 60, 2_840, false, 2_960),
        )
        for (v in variants) {
            val acts = listOf(ActionSpec(At(v.snoozeAt, null, 0), "snooze"))
            val until = v.snoozeAt + 60
            val rs = runs(tr40, CASES, { c -> model(c, ringMaxS = v.ringMax, actions = acts) }, RunOpts(probes = true, paramOverrides = LOST_3600))
            for (x in rs) {
                fails += harness(tr40, x)
                val first = x.alarms.firstOrNull()
                if (first == null || (first.e as Alarm).reason != AlarmReason.GPS_LOST || first.t >= v.snoozeAt) {
                    fails += "${x.tag} (${v.id}): first alarm ${first?.let { desc(it) }}, want GPS_LOST before the snooze"
                }
                if (x.evs.none { it.e is Snoozed && it.t == v.snoozeAt }) fails += "${x.tag} (${v.id}): no snoozed at ${v.snoozeAt}"
                val se = x.alarms.firstOrNull { (it.e as Alarm).reason == AlarmReason.SNOOZE_END }
                if (se == null || se.t != until || !(se.e as Alarm).ringNow) {
                    fails += "${x.tag} (${v.id}): SNOOZE_END ${se?.let { desc(it) }}, want ringNow=true at $until"
                }
                val ov = x.overshoots.singleOrNull()
                // Precondition on the OS chime: AlarmSilenced between SNOOZE_END and the overshoot exactly where planned.
                val silenced = x.r.records.filter { it.input is AlarmSilenced && it.t >= until && (ov == null || it.t <= ov.t) }.map { it.t }
                if (silenced != listOfNotNull(v.silencedAt)) {
                    fails += "${x.tag} (${v.id}): precondition: AlarmSilenced at $silenced, want ${listOfNotNull(v.silencedAt)}"
                }
                val g = x.r.gapProbes.firstOrNull { it.atMs - x.r.startMs == gEnd * 1000L }
                if (g == null || !g.gapFix || g.phase != TripPhase.ALARMING || (g.dChord ?: Double.MAX_VALUE) >= 1_000.0) {
                    fails += "${x.tag} (${v.id}): fix at g.end gapFix=${g?.gapFix} phase=${g?.phase} dChord=${g?.dChord}"
                }
                if (!inWindow(ov?.t, gEnd, 60)) fails += "${x.tag} (${v.id}): overshoot ${x.overshoots.map { desc(it) }}, window [$gEnd, ${gEnd + 60}]"
                val after = x.alarms.filter { it.t > until }
                if (v.ringingAtOvershoot) {
                    if (after.isNotEmpty()) fails += "${x.tag} (${v.id}): ${after.map { desc(it) }} after SNOOZE_END (chime still rings)"
                    if (ov != null && x.r.records[ov.rec].view?.alarmRinging != true) fails += "${x.tag} (${v.id}): alarmRinging false"
                } else {
                    val a = after.singleOrNull()
                    if (a == null || (a.e as Alarm).reason != AlarmReason.OVERSHOOT || !a.e.ringNow || a.rec != ov?.rec) {
                        fails += "${x.tag} (${v.id}): after SNOOZE_END ${after.map { desc(it) }}, want one OVERSHOOT ringNow=true with the overshoot"
                    }
                }
                if (ov != null && x.r.records[ov.rec].view?.phase != TripPhase.OVERSHOT) fails += "${x.tag} (${v.id}): phase at the overshoot"
                fails += c31(x, ov, gEnd, g?.dChord, v.id)
                if (!x.key.policy && ov?.t != 3_030) fails += "${x.tag} (${v.id}): by hand 3030 (T10.7 vòng 2 §4, as TR43 a), got ${ov?.t}"
                note("2 ${v.id} ${x.tag}", "(${v.id}) ${x.tag}: ${timeline(x.r, 2_830, 3_060)}")
            }
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /**
     * Out of the spec lists (restart in mid-trip, T10.7 §5 I8; T10.7 vòng 2 §4 row "T124 k": alarmedChordD through the snapshot): the
     * chime stopped (TR43 a), the process is killed at 2 990 right after the chord fix (2 980) stored alarmedChordD in ALARMING, and is
     * relaunched at 2 995. Without alarmedChordD in the snapshot nearD would be minD (≈ 4 600 m ≥ nearRadius) and nothing would ring.
     * Gate: one re-ring OVERSHOOT with the overshoot in [g.end, g.end + 60] (`all` 3 030), C31 (rise and pastM), and the same t and pastM
     * as the run without the kill.
     */
    @Test
    fun `T124 k process killed right after the chord fix in ALARMING - the re-ring survives the restart`() {
        val fails = ArrayList<String>()
        val kill = 2_990
        val rel = 2_995
        val gEnd = tr40.gpsGaps.first().second
        val opts = RunOpts(probes = true, paramOverrides = LOST_3600)
        val ref = runs(tr40, CASES, { c -> model(c, ringMaxS = 60) }, opts).associateBy { it.tag }
        val rs = runs(tr40, CASES, { c -> model(c, ringMaxS = 60, kill = kill, relaunch = rel) }, opts)
        for (x in rs) {
            fails += harness(tr40, x)
            val g = x.r.gapProbes.firstOrNull { it.atMs - x.r.startMs == 2_980_000L }
            if (g == null || !g.gapFix || g.phase != TripPhase.ALARMING || (g.dChord ?: Double.MAX_VALUE) >= 1_000.0) {
                fails += "${x.tag} (k): no ALARMING chord fix at 2980 (${g?.phase} ${g?.dChord})"
            }
            if (x.evs.any { (it.e is Overshoot || it.e is Alarm) && it.t in 2_980 until kill }) fails += "${x.tag} (k): precondition: event before the kill"
            val after = x.alarms.filter { it.t >= kill && (it.e as Alarm).ringNow }
            val ov = x.overshoots.singleOrNull()
            val a = after.singleOrNull()
            if (a == null || (a.e as Alarm).reason != AlarmReason.OVERSHOOT || ov == null || a.rec != ov.rec || !inWindow(ov.t, gEnd, 60)) {
                fails += "${x.tag} (k): after relaunch ${after.map { desc(it) }} overshoot ${x.overshoots.map { desc(it) }}, want one OVERSHOOT re-ring in [$gEnd, ${gEnd + 60}]"
            }
            fails += c31(x, ov, gEnd, g?.dChord, "k")
            val r0 = ref[x.tag]?.overshoots?.singleOrNull()
            if (r0 == null || ov == null || r0.t != ov.t || (r0.e as Overshoot).pastM != (ov.e as Overshoot).pastM) {
                fails += "${x.tag} (k): overshoot ${ov?.let { desc(it) }}, run without the kill ${r0?.let { desc(it) }}"
            }
            if (!x.key.policy && ov?.t != 3_030) fails += "${x.tag} (k): by hand 3030 (T10.7 vòng 2 §4), got ${ov?.t}"
            note("3 k ${x.tag}", "(k) ${x.tag}: ${timeline(x.r, 2_970, 3_060)}; without the kill: ${r0?.let { desc(it) }}")
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    // ---------------------------------------------------------------------------------------------------------------------------
    // 2. RK20 (e): synthetic loop routes (in memory)
    // ---------------------------------------------------------------------------------------------------------------------------

    /** Polyline in a local plane around the destination (x east, y north, metres). */
    private class Route(val pts: List<DoubleArray>) {
        val cum: DoubleArray = DoubleArray(pts.size).also { c ->
            for (i in 1 until pts.size) c[i] = c[i - 1] + len(pts[i - 1], pts[i])
        }
        val length: Double get() = cum.last()

        fun at(s: Double): DoubleArray {
            if (s <= 0.0) return pts.first()
            for (i in 1 until pts.size) {
                if (s <= cum[i]) {
                    val k = (s - cum[i - 1]) / (cum[i] - cum[i - 1])
                    return doubleArrayOf(pts[i - 1][0] + k * (pts[i][0] - pts[i - 1][0]), pts[i - 1][1] + k * (pts[i][1] - pts[i - 1][1]))
                }
            }
            return pts.last()
        }

        /** Arc length of the first route point closest to the destination (1 m steps). */
        fun closestS(): Double {
            var best = Double.MAX_VALUE
            var bs = 0.0
            var s = 0.0
            while (s <= length) {
                val p = at(s)
                val d = sqrt(p[0] * p[0] + p[1] * p[1])
                if (d < best - 1e-9) { best = d; bs = s }
                s += 1.0
            }
            return bs
        }

        companion object {
            fun len(a: DoubleArray, b: DoubleArray): Double { val dx = b[0] - a[0]; val dy = b[1] - a[1]; return sqrt(dx * dx + dy * dy) }
        }
    }

    private class Synth(val trace: TraceModel, val route: Route, val v: Double, val sD: Double, val gap: Pair<Int, Int>) {
        /** Truth: the vehicle reached the destination's closest route point at tick [t]. */
        fun passed(t: Int): Boolean = v * t >= sD

        fun trueD(t: Int): Double { val p = route.at(v * t); return sqrt(p[0] * p[0] + p[1] * p[1]) }

        /** Smallest true distance so far (the real road). */
        fun trueMinD(t: Int): Double { var m = Double.MAX_VALUE; var u = 0; while (u <= t) { m = minOf(m, trueD(u)); u += 5 }; return m }
    }

    private fun pt(x: Double, y: Double) = doubleArrayOf(x, y)

    /** Quarter-ish arc points around the destination, radius [r], from angle [a0] to [a1] (degrees, math convention). */
    private fun arc(r: Double, a0: Double, a1: Double, r1: Double = r): List<DoubleArray> {
        val n = 90
        return (1..n).map { i ->
            val a = (a0 + (a1 - a0) * i / n) * PI / 180.0
            val ri = r + (r1 - r) * i / n
            pt(ri * cos(a), ri * sin(a))
        }
    }

    /**
     * Samples every 5 s at constant speed [v] along [route], none in [gap] (fromT inclusive, toT exclusive), accuracy 8 m, Doppler [v],
     * optional seeded Gaussian position noise. Placed around the TR40 destination, same start time. Duration = last full 5 s tick.
     */
    private fun synth(id: String, route: Route, v: Double, gap: Pair<Int, Int>, noiseM: Double = 0.0, seed: Long = 124L): Synth {
        val dLat = tr40.destLat
        val dLng = tr40.destLng
        val cosLat = cos(dLat * PI / 180.0)
        val dur = ((route.length / v).toInt() / 5) * 5
        val rnd = Random(seed)
        val samples = ArrayList<TraceSample>()
        var t = 0
        while (t <= dur) {
            if (t < gap.first || t >= gap.second) {
                val p = route.at(v * t)
                val nx = if (noiseM > 0) rnd.nextGaussian() * noiseM else 0.0
                val ny = if (noiseM > 0) rnd.nextGaussian() * noiseM else 0.0
                samples += TraceSample(samples.size, t, dLat + (p[1] + ny) / M_PER_DEG, dLng + (p[0] + nx) / (M_PER_DEG * cosLat), 8.0, v)
            }
            t += 5
        }
        require(samples.last().t == dur)
        val sD = route.closestS()
        val tr = TraceModel(
            "t124_$id", "coach", File("t124_$id.gpx"), tr40.startMs, 5, dur, samples.size, dLat, dLng, (sD / v).toInt(),
            emptyList(), listOf(gap), gpxOverride = GpxTrace(tr40.startMs, samples),
        )
        return Synth(tr, route, v, sD, gap)
    }

    private val v = 15.0

    /** Approach 15 km north along x = −3 000 to (−3 000, 0) at t = 1 000; the gap hides the loop north of the destination. */
    private fun approach() = listOf(pt(-3_000.0, -15_000.0), pt(-3_000.0, 0.0), pt(-3_000.0, 3_000.0), pt(3_000.0, 3_000.0), pt(3_000.0, 0.0))

    /** Gap [1 005, 1 800): last fix (−3 000, 0) at 1 000, first fix (3 000, 0) at 1 800 (12 km at 15 m/s); chord through D (dChord ≈ 0). */
    private val loopGap = 1_005 to 1_800

    private class LoopResult(val id: String, val wrong: Int, val lines: List<String>, val fails: List<String>)

    /** What U128 / T10.7 vòng 2 §6–§7 demand of a loop route. */
    private enum class LoopGate {
        /** L1 (RK20 e, accepted): a wrong-wording Overshoot only after the real distance rose >= overshootOpenM above the real minimum. */
        RK20E,

        /** L2: no Overshoot before the vehicle reached the destination. */
        NO_EARLY,

        /** L3, L4, L4n, L5: no early Overshoot, and the Overshoot in [arrival, arrival + 120]. */
        AFTER_ARRIVAL,
    }

    /** Runs distance_1000 and time_15 (TR40 case models), chime stopped (osRingMaxS 60) and still ringing, `all` + `policy`. */
    private fun loopRuns(id: String, s: Synth, gate: LoopGate): LoopResult {
        val fails = ArrayList<String>()
        val lines = ArrayList<String>()
        var wrong = 0
        val gEnd = s.gap.second
        for (ring in listOf<Int?>(60, null)) {
            val rs = runs(s.trace, listOf("distance_1000", "time_15"), { c -> model(c, ringMaxS = ring) }, RunOpts(probes = true))
            for (x in rs) {
                val tag = "$id ${x.tag} ring=${ring ?: "inf"}"
                fails += harness(s.trace, x).map { "$id ring=${ring ?: "inf"} $it" }
                val first = x.alarms.firstOrNull()
                if (first == null || first.t >= gEnd) fails += "$tag: precondition: no alarm before g.end (${first?.let { desc(it) }})"
                val g = x.r.gapProbes.firstOrNull { it.atMs - x.r.startMs == gEnd * 1000L }
                if (g == null || !g.gapFix || g.phase != TripPhase.ALARMING) {
                    fails += "$tag: precondition: fix at g.end gapFix=${g?.gapFix} phase=${g?.phase}"
                }
                val ov = x.overshoots.firstOrNull()
                val ovAlarm = ov?.let { o -> x.alarms.firstOrNull { it.rec == o.rec } }
                val early = ov != null && !s.passed(ov.t)
                if (early) wrong++
                val arr = s.trace.arrivalT
                when (gate) {
                    LoopGate.RK20E -> if (ov != null && early && s.trueD(ov.t) - s.trueMinD(ov.t) < 1_000.0 - 10.0) {
                        fails += "$tag: wrong-wording Overshoot at ${ov.t} with a real rise of only ${s.trueD(ov.t) - s.trueMinD(ov.t)} m (C31)"
                    }
                    LoopGate.NO_EARLY -> if (ov != null && early) fails += "$tag: Overshoot at ${ov.t} before the arrival $arr"
                    LoopGate.AFTER_ARRIVAL -> if (ov == null || early || ov.t > arr + 120) {
                        fails += "$tag: Overshoot ${ov?.t}, want in [$arr, ${arr + 120}]"
                    }
                }
                // PO #18: with the chime stopped the Overshoot re-rings in its Step; while it still rings, no second ring.
                val ovA = ovAlarm?.e as? Alarm
                if (ov != null && ring != null && (ovA == null || ovA.reason != AlarmReason.OVERSHOOT || !ovA.ringNow)) {
                    fails += "$tag: overshoot ${ov.t} without the re-ring (${ovAlarm?.let { desc(it) }})"
                }
                if (ring == null && x.alarms.drop(1).any { (it.e as Alarm).ringNow }) fails += "$tag: second ring while the chime rings"
                val ended = x.evs.firstOrNull { it.e is TripEnded }
                val afterArrival = x.alarms.filter { it.t >= arr - 60 }
                lines += String.format(
                    Locale.ROOT,
                    "%s: first %s; chord fix t=%d u=%s dChord=%s d_f=%.0f trueMinD=%.0f; overshoot %s%s (truth %s, trueD=%s); arrival %d, alarms from arrival−60: %s; %s",
                    tag, first?.let { desc(it) }, gEnd, g?.u?.let { "%.4f".format(Locale.ROOT, it) },
                    g?.dChord?.let { "%.1f".format(Locale.ROOT, it) }, g?.dFixM ?: Double.NaN, s.trueMinD(gEnd),
                    ov?.let { desc(it) } ?: "none", ovAlarm?.let { " + ${desc(it)}" } ?: "",
                    if (ov == null) "-" else if (early) "NOT PASSED (wrong wording)" else "passed",
                    ov?.let { "%.0f".format(Locale.ROOT, s.trueD(it.t)) } ?: "-", arr,
                    afterArrival.map { desc(it) }, ended?.let { desc(it) } ?: "no tripEnded",
                )
            }
        }
        lines.forEach { note("4 $it", "(RK20e) $it") }
        return LoopResult(id, wrong, lines, fails)
    }

    /**
     * RK20 (e) on loop routes (T10 "T10.7" §4/§11, rewritten in "T10.7 vòng 2" §6; U128 is the coder's gate on the same geometry with
     * uniform splitmix64 noise, this test keeps an independent Gaussian-noise variant). Alarm before / in the gap, the gap hides the
     * loop north of the destination, chord through the destination (dChord ≈ 0 m) although the real road stays >= 3 000 m away.
     * - L1: after the gap the road goes 3 km south (away, d 3 000 → 4 243 m) then back west and north to the destination. RK20 (e) as
     *   accepted: a wrong-wording Overshoot may happen, but only once the real distance rose >= 1 km (gate).
     * - L2: only 300 m south (d 3 000 → 3 015 m), then west and north to the destination: no early Overshoot (gate).
     * - L3: straight to the destination and on past it. L4: a quarter circle of radius 3 000 m around the destination, Gaussian noise
     *   σ 3 m (seed 124), then north to it. L4n: L4 without noise. L5: spiral 3 000 → 2 000 m, σ 3 m. Gate: no early Overshoot, the
     *   Overshoot within 120 s after the arrival, re-ring when the chime stopped.
     * - L4 sweep: seeds 1–20 × σ {3, 8} m, distance_1000 `all`, chime stopped: 0 early, Overshoot within 120 s after the arrival.
     */
    @Test
    fun `T124 RK20e loop route - alarm before the gap, chord cuts within 1 km, vehicle still approaching`() {
        val fails = ArrayList<String>()
        val l1 = synth("L1", Route(approach() + listOf(pt(3_000.0, -3_000.0), pt(0.0, -3_000.0), pt(0.0, 0.0), pt(0.0, 3_000.0))), v, loopGap)
        val l2 = synth("L2", Route(approach() + listOf(pt(3_000.0, -300.0), pt(0.0, -300.0), pt(0.0, 0.0), pt(0.0, 3_000.0))), v, loopGap)
        val l3 = synth("L3", Route(approach() + listOf(pt(0.0, 0.0), pt(-3_000.0, 0.0))), v, loopGap)
        val l4 = synth(
            "L4", Route(approach() + arc(3_000.0, 0.0, -90.0) + listOf(pt(0.0, 0.0), pt(0.0, 3_000.0))), v, loopGap, noiseM = 3.0,
        )
        val l4n = synth("L4n", Route(approach() + arc(3_000.0, 0.0, -90.0) + listOf(pt(0.0, 0.0), pt(0.0, 3_000.0))), v, loopGap)
        val l5 = synth(
            "L5", Route(approach() + arc(3_000.0, 0.0, -90.0, 2_000.0) + listOf(pt(0.0, 0.0), pt(0.0, 3_000.0))), v, loopGap, noiseM = 3.0,
        )
        val res = listOf(
            loopRuns("L1", l1, LoopGate.RK20E), loopRuns("L2", l2, LoopGate.NO_EARLY), loopRuns("L3", l3, LoopGate.AFTER_ARRIVAL),
            loopRuns("L4", l4, LoopGate.AFTER_ARRIVAL), loopRuns("L4n", l4n, LoopGate.AFTER_ARRIVAL),
            loopRuns("L5", l5, LoopGate.AFTER_ARRIVAL),
        )
        for (r in res) {
            fails += r.fails
            note("5 ${r.id}", "(RK20e) ${r.id}: wrong-wording overshoots ${r.wrong}/${r.lines.size} runs")
        }
        for (sigma in listOf(3.0, 8.0)) {
            val hits = ArrayList<String>()
            val ts = sortedMapOf<Int, Int>()
            for (seed in 1L..20L) {
                val route = Route(approach() + arc(3_000.0, 0.0, -90.0) + listOf(pt(0.0, 0.0), pt(0.0, 3_000.0)))
                val s = synth("L4s$seed", route, v, loopGap, sigma, seed)
                val cm = model("distance_1000", ringMaxS = 60)
                val r = CaseRun.run(s.trace, cm, RunKey(s.trace.id, cm.id, "all", false, 0), RunOpts(probes = false))
                fails += Checks.check(s.trace, cm, r).map { "L4 seed $seed sigma $sigma: $it" }
                val ov = Checks.events(r).firstOrNull { it.e is Overshoot }
                if (ov != null) ts[ov.t] = (ts[ov.t] ?: 0) + 1
                if (ov != null && !s.passed(ov.t)) hits += "seed $seed t=${ov.t}"
                if (ov == null || !s.passed(ov.t) || ov.t > s.trace.arrivalT + 120) {
                    fails += "L4 seed $seed sigma $sigma: Overshoot ${ov?.t}, want in [${s.trace.arrivalT}, ${s.trace.arrivalT + 120}]"
                }
            }
            note(
                "6 L4 sweep $sigma",
                "(RK20e) L4 sweep sigma=${sigma.toInt()} m: wrong-wording overshoots ${hits.size}/20 [${hits.joinToString(", ")}]; overshoot t $ts",
            )
        }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }
}
