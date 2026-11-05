package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.harness.At
import app.napstop.core.trip.harness.CaseModel
import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.LoopRoutes
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunOpts
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.Suite
import app.napstop.core.trip.harness.TimedEvent
import app.napstop.core.trip.harness.TraceModel
import app.napstop.core.trip.harness.eventName
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.Locale
import java.util.concurrent.Callable

/**
 * U128 (T10 "T10.7 vòng 2" §7, C31, RK20 e): loop routes ([LoopRoutes], the tester's T12.4 geometry) with an alarm before / in
 * the GPS gap that hides the loop; the chord passes through the destination while the road stays ≥ 3 km away. TR40 case models
 * `distance_1000` (GPS_LOST in the gap) and `time_15` (TIME before the gap) × `all`/`policy` × chime {osRingMaxS 60, unlimited}.
 * Gates: L2, L3, L4 (every seed, a = 5 and 14), L4n, L5: no Overshoot before the vehicle really passed the destination; L3, L4,
 * L4n, L5: an Overshoot in [arrival, arrival + 120 s], with Alarm(OVERSHOOT, ringNow=true) in its Step when the chime stopped;
 * L1 (accepted RK20 e): exactly one wrong-wording Overshoot, at the first Step whose dSmooth (= d(t − 5)) is 1 km beyond minD
 * (3 000 m); every run 0 harness violations. Report `u128-loop.txt` (t, distances, u, phase; no coordinates).
 */
class T107LoopTest {
    private companion object {
        const val TRACE = "coach_gb_caugie_gappass"
        val CASES = listOf("distance_1000", "time_15")
        const val AFTER_ARRIVAL_S = 120
        const val NOISE_SEED = 124L
        val LOG = sortedMapOf<String, String>()
    }

    private val tr40: TraceModel by lazy { Suite.traces.first { it.id == TRACE } }

    private fun note(key: String, line: String) {
        synchronized(LOG) {
            LOG[key] = line
            File(Suite.outDir.apply { mkdirs() }, "u128-loop.txt").writeText(LOG.values.joinToString("\n", postfix = "\n"))
        }
    }

    private fun model(caseId: String, ringMaxS: Int?): CaseModel {
        val base = tr40.cases.first { it.id == caseId }.model!!
        return base.copy(config = base.config.copy(osRingMaxS = ringMaxS), expect = emptyList(), expectAfter = emptyList())
    }

    private fun desc(e: TimedEvent): String = when (val x = e.e) {
        is Alarm -> "${e.t} alarm ${x.reason} ringNow=${x.ringNow}"
        is Overshoot -> "${e.t} overshoot pastM=${x.pastM}"
        else -> "${e.t} ${eventName(x)}"
    }

    private class Run(val tag: String, val m: CaseModel, val ring: Int?, val r: RunResult) {
        val evs: List<TimedEvent> = Checks.events(r)
    }

    /** Checks of one run; [kind]: "none" (no early Overshoot, an Overshoot after arrival), "noEarly" (L2), "l1". */
    private fun check(s: LoopRoutes.Synth, x: Run, kind: String): List<String> {
        val f = ArrayList<String>()
        f += Checks.check(s.trace, x.m, x.r).map { "${x.tag}: $it" }
        val gEnd = s.gap.second
        val first = x.evs.firstOrNull { it.e is Alarm }
        if (first == null || first.t >= gEnd) f += "${x.tag}: precondition: no alarm before g.end (${first?.let { desc(it) }})"
        val g = x.r.gapProbes.firstOrNull { it.atMs - x.r.startMs == gEnd * 1000L }
        if (g == null || !g.gapFix || g.phase != TripPhase.ALARMING || (g.dChord ?: Double.MAX_VALUE) >= 1_000.0) {
            f += "${x.tag}: precondition: fix at g.end gapFix=${g?.gapFix} phase=${g?.phase} dChord=${g?.dChord}"
        }
        val ovs = x.evs.filter { it.e is Overshoot }
        val ov = ovs.firstOrNull()
        val early = ov != null && !s.passed(ov.t)
        val arrival = s.arrivalS
        when (kind) {
            "l1" -> {
                // RK20 (e) accepted: exactly one wrong-wording Overshoot, when the vehicle really went 1 km farther than minD.
                if (ov == null || !early || ovs.size != 1) f += "${x.tag}: L1 want one wrong-wording Overshoot (RK20 e accepted), got ${ovs.map { desc(it) }}"
                if (ov != null && !(s.trueD(ov.t - 5) >= 4_000.0 && s.trueD(ov.t - 10) < 4_000.0)) {
                    f += "${x.tag}: L1 Overshoot at ${ov.t} not the first Step with d(t − 5) >= 4 000 (d ${s.trueD(ov.t - 5).toInt()})"
                }
            }
            else -> {
                if (early) f += "${x.tag}: Overshoot at ${ov.t} before the vehicle passed the destination (arrival ${"%.0f".format(Locale.ROOT, arrival)})"
                if (kind == "none") {
                    if (ov == null || ov.t < arrival || ov.t > arrival + AFTER_ARRIVAL_S) {
                        f += "${x.tag}: Overshoot ${ov?.t} not in [arrival, arrival + $AFTER_ARRIVAL_S] (arrival ${"%.0f".format(Locale.ROOT, arrival)})"
                    }
                    val reRing = ov != null && x.evs.any { it.rec == ov.rec && it.e is Alarm && it.e.reason == AlarmReason.OVERSHOOT && it.e.ringNow }
                    if (x.ring != null && ov != null && !reRing) {
                        f += "${x.tag}: chime stopped but no Alarm(OVERSHOOT, ringNow=true) with the Overshoot at ${ov.t}"
                    }
                }
            }
        }
        note(
            x.tag,
            String.format(
                Locale.ROOT,
                "%s: first %s; g.end %d chord u=%s dChord=%s phase=%s d_f=%.0f; arrival %.0f; overshoot %s (%s, trueD %s)%s",
                x.tag, first?.let { desc(it) }, gEnd, g?.u?.let { "%.4f".format(Locale.ROOT, it) }, g?.dChord?.let { "%.1f".format(Locale.ROOT, it) },
                g?.phase, g?.dFixM ?: Double.NaN, arrival, ov?.let { desc(it) } ?: "none",
                if (ov == null) "-" else if (early) "NOT PASSED" else "passed", ov?.let { "%.0f".format(Locale.ROOT, s.trueD(it.t)) } ?: "-",
                ov?.let { o -> x.evs.firstOrNull { it.rec == o.rec && it.e is Alarm }?.let { " + ${desc(it)}" } } ?: "",
            ),
        )
        return f
    }

    private fun runAll(s: LoopRoutes.Synth): List<Run> {
        val jobs = ArrayList<Triple<String, Pair<CaseModel, Int?>, RunKey>>()
        for (ring in listOf<Int?>(60, null)) for (c in CASES) {
            val m = model(c, ring)
            for (k in Suite.keysOf(s.trace, m)) jobs += Triple("${s.id} $c/${k.mode} ring=${ring ?: "inf"}", m to ring, k)
        }
        return jobs.map { (tag, mr, k) -> Suite.pool.submit(Callable { Run(tag, mr.first, mr.second, CaseRun.run(s.trace, mr.first, k, RunOpts(probes = true))) }) }
            .map { it.get() }
    }

    @Test
    fun `U128 loop routes after an alarm - no wrong-wording Overshoot except L1, the real overshoot after the arrival`() {
        val fails = ArrayList<String>()
        val routes = listOf(
            Triple(LoopRoutes.synth(tr40, "L1", LoopRoutes.l1()), "l1", 0),
            Triple(LoopRoutes.synth(tr40, "L2", LoopRoutes.l2()), "noEarly", 0),
            Triple(LoopRoutes.synth(tr40, "L3", LoopRoutes.l3()), "none", 0),
            Triple(LoopRoutes.synth(tr40, "L4", LoopRoutes.l4(), noiseA = 5.0, seed = NOISE_SEED), "none", 0),
            Triple(LoopRoutes.synth(tr40, "L4n", LoopRoutes.l4()), "none", 0),
            Triple(LoopRoutes.synth(tr40, "L5", LoopRoutes.l5(), noiseA = 5.0, seed = NOISE_SEED), "none", 0),
        )
        for ((s, kind, _) in routes) {
            val runs = runAll(s)
            assertTrue(runs.size == 8) { "${s.id}: ${runs.size} runs" }
            for (x in runs) fails += check(s, x, kind)
        }
        // L4 sweep: seeds 1..20 × a ∈ {5, 14} m, distance_1000 `all`, chime stopped.
        val m = model("distance_1000", 60)
        val sweep = (1L..20L).flatMap { seed -> listOf(5.0, 14.0).map { a -> seed to a } }.map { (seed, a) ->
            Suite.pool.submit(
                Callable {
                    val s = LoopRoutes.synth(tr40, "L4s${seed}a${a.toInt()}", LoopRoutes.l4(), noiseA = a, seed = seed)
                    s to Run("${s.id} distance_1000/all ring=60", m, 60, CaseRun.run(s.trace, m, RunKey(s.trace.id, m.id, "all", false, 0), RunOpts(probes = true)))
                },
            )
        }.map { it.get() }
        for ((s, x) in sweep) fails += check(s, x, "none")
        assertTrue(fails.isEmpty()) { fails.take(30).joinToString("\n") }
    }
}
