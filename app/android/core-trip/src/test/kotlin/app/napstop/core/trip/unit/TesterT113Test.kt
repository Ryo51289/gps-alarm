package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.harness.At
import app.napstop.core.trip.harness.CaseModel
import app.napstop.core.trip.harness.CaseRef
import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.RelaunchSpec
import app.napstop.core.trip.harness.RunOpts
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.Suite
import app.napstop.core.trip.harness.TimedEvent
import app.napstop.core.trip.harness.eventName
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File
import java.util.concurrent.Callable

/**
 * T11.3 (tester): TR40 fixture `coach_gb_caugie_gappass` on the Kotlin engine, beyond the per-case checks of TraceSuiteTest:
 * the event timeline around the GPS gap, every policy phase, the Doze model, a process kill inside the gap, and that the P05
 * manifest changes only by the new runs. Report: build/core-trip/napstop/t113-tr40.txt (no coordinates).
 */
class TesterT113Test {
    private companion object {
        const val TRACE = "coach_gb_caugie_gappass"

        /** T10.5 round 3b (orchestrator 03/11): OVERSHOOT within [g.end, g.end + 25]. */
        const val WINDOW_S = 25

        val CASES = listOf("distance_1000", "time_15", "smart", "summary_unknown")
        val LOG = StringBuffer()
    }

    private val outDir = Suite.outDir.apply { mkdirs() }

    private fun ref(caseId: String): CaseRef = Suite.cases.first { it.trace.id == TRACE && it.entry.id == caseId }

    /** (fromT, toT) of the single GPS gap, from the GPX itself (first sample after the gap is at toT). */
    private val gap: Pair<Int, Int> by lazy {
        val trace = Suite.traces.first { it.id == TRACE }
        val s = trace.gpx.samples
        val i = s.indices.first { it > 0 && s[it].t - s[it - 1].t > trace.intervalS }
        (s[i - 1].t + trace.intervalS) to s[i].t
    }

    private fun alarms(r: RunResult) = Checks.events(r).filter { it.e is Alarm }

    private fun desc(e: TimedEvent): String = when (val x = e.e) {
        is Alarm -> "${e.t} alarm ${x.reason} ringNow=${x.ringNow}"
        else -> "${e.t} ${eventName(x)}"
    }

    private fun note(title: String, lines: List<String>) {
        LOG.append("## ").append(title).append('\n')
        for (l in lines) LOG.append(l).append('\n')
        LOG.append('\n')
        File(outDir, "t113-tr40.txt").writeText(LOG.toString())
    }

    /** Assertions shared by every TR40 run: nothing rings before g.end, the first alarm rings at once and in the window. */
    private fun checkRun(tag: String, r: RunResult, gEnd: Int, from: Int = gEnd, overshootReason: Boolean): List<String> {
        val fails = ArrayList<String>()
        val al = alarms(r)
        val first = al.firstOrNull()
        val firstOv = al.firstOrNull { (it.e as Alarm).reason == AlarmReason.OVERSHOOT }
        val ov = Checks.events(r).firstOrNull { it.e is Overshoot }
        if (first == null) {
            fails += "$tag: no alarm"
            return fails
        }
        if (first.t < from) fails += "$tag: first alarm before the GPS returned: ${desc(first)}"
        if (first.t > from + WINDOW_S) fails += "$tag: first alarm late: ${desc(first)} (window [$from, ${from + WINDOW_S}])"
        if (!(first.e as Alarm).ringNow) fails += "$tag: first alarm ringNow=false"
        if (overshootReason && (first.e as Alarm).reason != AlarmReason.OVERSHOOT) fails += "$tag: first alarm ${desc(first)}, want OVERSHOOT"
        if (overshootReason && (firstOv == null || firstOv.t > from + WINDOW_S)) fails += "$tag: alarm OVERSHOOT ${firstOv?.t}"
        // T10.5 round 3b U114 (d): TIME 15 rings for its own reason at the first fix after the gap (ETA from a short fix).
        if (!overshootReason && (first.e as Alarm).reason != AlarmReason.TIME) fails += "$tag: first alarm ${desc(first)}, want TIME (U114 d)"
        if (ov == null || ov.t < from || ov.t > from + WINDOW_S) fails += "$tag: overshoot event at ${ov?.t}"
        if (al.any { (it.e as Alarm).reason == AlarmReason.TIMEOUT }) fails += "$tag: TIMEOUT"
        return fails
    }

    private fun timeline(r: RunResult, gStart: Int, gEnd: Int): String =
        Checks.events(r).filter { it.t in (gStart - 60)..(gEnd + 120) }.joinToString("; ") { desc(it) }

    @Test
    fun `TR40 timeline per case and sampling mode - no alarm inside the gap, first alarm in g_end + 25, OVERSHOOT for DISTANCE and SMART`() {
        val (gStart, gEnd) = gap
        val trace = Suite.traces.first { it.id == TRACE }
        val lines = ArrayList<String>()
        lines += "gap [$gStart, $gEnd), arrival ${trace.arrivalT}, passed the destination ${gEnd - trace.arrivalT} s before GPS returned"
        val fails = ArrayList<String>()
        for (caseId in CASES) {
            val ref = ref(caseId)
            val model = ref.entry.model!!
            for (k in Suite.keysOf(ref.trace, model)) {
                val r = CaseRun.run(ref.trace, model, k)
                val probes = r.gapProbes.filter { it.dChord != null }.joinToString { "u=%.3f dChord=%.1f".format(java.util.Locale.ROOT, it.u, it.dChord) }
                lines += "${k.run}: ${timeline(r, gStart, gEnd)} | chord: $probes"
                fails += checkRun(k.run, r, gEnd, overshootReason = caseId != "time_15")
            }
        }
        note("TR40 timeline (all, policy)", lines)
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /** Out of spec: the case runs with one policy phase; here every phase of the SPARSE delivery grid (36) as TR30 does. */
    @Test
    fun `TR40 every policy phase (36) keeps the first alarm in g_end + 25`() {
        val (_, gEnd) = gap
        val lines = ArrayList<String>()
        val fails = ArrayList<String>()
        for (caseId in CASES) {
            val ref = ref(caseId)
            val swept = ref.entry.model!!.copy(policyPhaseSweep = true)
            val keys = Suite.keysOf(ref.trace, swept).filter { it.policy }
            assertEquals(36, keys.size)
            val res = keys.map { k -> Suite.pool.submit(Callable { k to CaseRun.run(ref.trace, swept, k, RunOpts(probes = false)) }) }.map { it.get() }
            val firsts = res.map { (k, r) -> k.j to alarms(r).firstOrNull() }
            lines += "$caseId: " + firsts.joinToString(", ") { (j, a) -> "j$j=${a?.let { "${it.t}/${(it.e as Alarm).reason}" } ?: "-"}" }
            for ((k, r) in res) fails += checkRun("${ref.name}/${k.mode}", r, gEnd, overshootReason = caseId != "time_15")
        }
        note("TR40 policy phase sweep", lines)
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /** Out of spec: TR39 Doze model (no Tick inside the gap, only wakeAtMs) must not change the first alarm. */
    @Test
    fun `TR40 Doze model gives the same first alarm as the normal run`() {
        val (_, gEnd) = gap
        val lines = ArrayList<String>()
        val fails = ArrayList<String>()
        for (caseId in CASES) {
            val ref = ref(caseId)
            val model = ref.entry.model!!
            val k = Suite.keysOf(ref.trace, model).first { !it.policy }
            val normal = alarms(CaseRun.run(ref.trace, model, k, RunOpts(probes = false))).first()
            val dozeRun = CaseRun.run(ref.trace, model, k, RunOpts(probes = false, dozeModel = true))
            val doze = alarms(dozeRun).firstOrNull()
            lines += "$caseId: normal ${desc(normal)}, doze ${doze?.let { desc(it) }}, doze timeline ${timeline(dozeRun, gap.first, gEnd)}"
            if (doze == null || doze.t != normal.t || (doze.e as Alarm).reason != (normal.e as Alarm).reason) {
                fails += "$caseId: doze first alarm ${doze?.let { desc(it) }} != normal ${desc(normal)}"
            }
            fails += checkRun("${ref.name}/doze", dozeRun, gEnd, overshootReason = caseId != "time_15")
        }
        note("TR40 Doze model", lines)
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /**
     * Out of spec (restart mid-trip): the process dies 300 s into the gap. (a) relaunch 60 s before the GPS returns, (b) relaunch 30 s
     * after it returned (the first fix is lost), (c) no relaunch, (d)/(e) as (b)/(a) with an OS ring limit of 60 s. With the coach hint
     * floor the OS fallback rings while the process is dead, before the GPS returns. Asserted: it rings no later than g.end + 25, the
     * harness invariants hold, no TIMEOUT. Measured (report): what the engine does after the relaunch (overshoot / re-ring).
     */
    @Test
    fun `TR40 process killed inside the gap - relaunch before or after GPS returns, or never`() {
        val (gStart, gEnd) = gap
        val trace = Suite.traces.first { it.id == TRACE }
        val ref = ref("distance_1000")
        val base = ref.entry.model!!
        val killT = gStart + 300
        fun variant(relaunchT: Int?, ringMaxS: Int? = null): CaseModel = base.copy(
            config = base.config.copy(
                kill = At(killT, null, 0),
                relaunch = relaunchT?.let { RelaunchSpec(At(it, null, 0), "auto") },
                osRingMaxS = ringMaxS,
            ),
            expect = emptyList(),
            expectAfter = emptyList(),
        )
        val lines = ArrayList<String>()
        val fails = ArrayList<String>()
        val variants = listOf(
            Triple("a relaunch g.end-60", gEnd - 60, null),
            Triple("b relaunch g.end+30", gEnd + 30, null),
            Triple("c no relaunch", null, null),
            Triple("d relaunch g.end+30, osRingMaxS 60", gEnd + 30, 60),
            Triple("e relaunch g.end-60, osRingMaxS 60", gEnd - 60, 60),
        )
        for ((name, relaunchT, ringMaxS) in variants) {
            val m = variant(relaunchT, ringMaxS)
            for (k in Suite.keysOf(trace, m)) {
                val r = CaseRun.run(trace, m, k, RunOpts(probes = false))
                fails += Checks.check(trace, m, r).map { "$name ${k.mode}: $it" }
                val fb = r.osFallbackFiredT
                val after = Checks.events(r).filter { it.t >= gEnd && (it.e is Alarm || it.e is Overshoot) }.joinToString("; ") { desc(it) }
                lines += "$name ${k.mode}: OS fallback fired at $fb (+${fb?.minus(trace.arrivalT)} s after passing the destination, " +
                    "${fb?.let { gEnd - it }} s before GPS returned); engine alarms/overshoot from g.end: [$after]; " +
                    "timeline ${timeline(r, gStart, gEnd + 60)}"
                // The user is woken no later than the live engine's TR40 window (here: by the OS fallback while the process is dead).
                if (fb == null || fb > gEnd + WINDOW_S) fails += "$name ${k.mode}: OS fallback at $fb, after g.end + $WINDOW_S"
                if (Checks.events(r).any { it.e is Alarm && (it.e as Alarm).reason == AlarmReason.TIMEOUT }) fails += "$name ${k.mode}: TIMEOUT"
            }
        }
        note("TR40 kill inside the gap (kill at $killT)", lines)
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /**
     * Out of spec, measured only (design question for the designer, see test report T11.3): the engine stays alive but an alarm already
     * rang inside the gap (GPS_LOST forced early with gpsLostAlarmEtaS 3600) and stopped by itself (osRingMaxS 60) before the vehicle
     * passed the destination. The chord rule only runs before any alarm (§4.11 "chưa báo"), so once the GPS returns 4.6 km past the
     * destination nothing re-rings (PO #18 re-ring needs minD < nearRadius). Logged, asserted only: the GPS_LOST alarm rang in the gap.
     */
    @Test
    fun `TR40 measured - alarm silenced inside the gap, then the vehicle passes the destination before GPS returns`() {
        val (gStart, gEnd) = gap
        val trace = Suite.traces.first { it.id == TRACE }
        val lines = ArrayList<String>()
        val fails = ArrayList<String>()
        for (caseId in listOf("distance_1000", "time_15", "smart")) {
            val ref = ref(caseId)
            val base = ref.entry.model!!
            val m = base.copy(config = base.config.copy(osRingMaxS = 60), expect = emptyList(), forbidMatch = emptyList())
            val opts = RunOpts(probes = false, paramOverrides = mapOf("gpsLostAlarmEtaS" to app.napstop.core.trip.JNumber("3600")))
            for (k in Suite.keysOf(trace, m)) {
                val r = CaseRun.run(trace, m, k, opts)
                val ev = Checks.events(r)
                val first = ev.firstOrNull { it.e is Alarm }
                val afterGap = ev.filter { it.t >= gEnd && (it.e is Alarm || it.e is Overshoot) }
                lines += "$caseId ${k.mode}: first ${first?.let { desc(it) }}; AlarmSilenced input at ${r.records.firstOrNull { it.input is app.napstop.core.trip.AlarmSilenced }?.t}" +
                    "; from g.end: [${afterGap.joinToString("; ") { desc(it) }}]"
                if (first == null || first.t >= gEnd || first.t < gStart) fails += "$caseId ${k.mode}: first alarm not in the gap: ${first?.let { desc(it) }}"
            }
        }
        note("TR40 measured: alarm silenced in the gap (gpsLostAlarmEtaS 3600, osRingMaxS 60), arrival ${trace.arrivalT}, g.end $gEnd", lines)
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    /**
     * P05 within the TR40 scope only (review T11.3 #1): the manifest on disk lists exactly the 8 TR40 runs written below for this trace,
     * and their lines / sha256 match this run. No git, no total count (T11.4 adds runs of other traces; P05ManifestTest covers all).
     */
    @Test
    fun `P05 manifest on disk has exactly the 8 TR40 runs and they match`() {
        val text = File(Suite.p05Dir, "manifest.json").readText(Charsets.UTF_8)
        val onDisk = Regex("\"run\": \"([^\"]+)\", \"lines\": (\\d+), \"sha256\": \"([0-9a-f]{64})\"").findAll(text)
            .associate { it.groupValues[1] to (it.groupValues[2].toInt() to it.groupValues[3]) }
            .filterKeys { it.startsWith("$TRACE/") }
        val expected = listOf("distance_1000", "smart", "summary_unknown", "time_15")
            .flatMap { c -> listOf("$TRACE/$c/all", "$TRACE/$c/policy") }.toSet()
        note("P05 (TR40 scope)", onDisk.entries.sortedBy { it.key }.map { "${it.key} lines ${it.value.first} sha ${it.value.second}" })
        assertEquals(expected, onDisk.keys) { "TR40 runs in fixtures/p05/manifest.json" }
        val mismatched = expected.filter { run ->
            val o = Suite.outcomes[run]
            o?.transcriptSha == null || onDisk[run] != (o.transcriptLines to o.transcriptSha)
        }
        assertTrue(mismatched.isEmpty()) { "TR40 P05 entries differ from this run: $mismatched" }
    }
}
