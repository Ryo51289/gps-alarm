package app.napstop.core.trip

import app.napstop.core.trip.harness.CaseRef
import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.Reports
import app.napstop.core.trip.harness.RunKey
import app.napstop.core.trip.harness.RunOpts
import app.napstop.core.trip.harness.RunResult
import app.napstop.core.trip.harness.Suite
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.Locale
import java.util.concurrent.Callable

/**
 * TR39 (T10 mục T10.4 §7.3): Doze model on the fixture. Every case on a trace with `gpsGaps` and without kill / relaunch /
 * osDismiss / allowFallbackFirst, mode `all`: inside the GPS gaps the platform delivers no grid Tick, only Tick(wakeAtMs) and the
 * OS fallback (whichever is earlier). Compared with the normal `all` run of the same case. Check only, not in the P05 manifest.
 */
class DozeModelTest {
    private class Row(val name: String, val fails: List<String>, val md: String)

    private fun firstLost(r: RunResult): GpsLost? = r.records.asSequence().flatMap { it.events }.filterIsInstance<GpsLost>().firstOrNull()

    private fun firstAlarm(r: RunResult): Pair<Int, Alarm>? {
        for (rec in r.records) for (e in rec.events) if (e is Alarm) return rec.t to e
        return null
    }

    private fun s3(ms: Long?, startMs: Long): String =
        ms?.let { String.format(Locale.ROOT, "%.3f", (it - startMs) / 1000.0) } ?: "-"

    private fun check(ref: CaseRef): Row {
        val model = ref.entry.model!!
        val key = RunKey(ref.trace.id, ref.entry.id, "all", false, 0)
        val tag = "${key.run} (TR39 doze)"
        val normal = CaseRun.run(ref.trace, model, key, RunOpts(probes = false))
        val doze = CaseRun.run(ref.trace, model, key, RunOpts(dozeModel = true))
        val fails = ArrayList<String>()
        // (a) I1–I7, I10–I13 at every Step; I14, P08, P07 and finite state come from the runner.
        fails += doze.violations.map { "$it (TR39 doze)" }
        fails += Checks.invariants(doze, tag)
        // (b) first gpsLost at the same atMs.
        val nl = firstLost(normal)
        val dl = firstLost(doze)
        if (nl?.atMs != dl?.atMs) fails += "(b) first gpsLost ${s3(dl?.atMs, doze.startMs)} s, normal run ${s3(nl?.atMs, normal.startMs)} s ($tag)"
        // (c), (d) first alarm: same reason, ringNow, within [tW − I, tW + wakeGuard + 1 ms]; never a fallback first.
        val na = firstAlarm(normal)
        val da = firstAlarm(doze)
        val iS = ref.trace.intervalS
        if (na == null) {
            fails += "(c) normal run has no alarm ($tag)"
        } else if (da == null) {
            fails += "(c) no alarm in the Doze model ($tag)"
        } else {
            val (tW, a0) = na
            val a = da.second
            val rel = a.atMs - doze.startMs
            if (a.reason == AlarmReason.FALLBACK || a.reason == AlarmReason.FALLBACK_MISSED) {
                fails += "(d) first alarm is ${a.reason} at ${s3(a.atMs, doze.startMs)} s ($tag)"
            }
            if (a.reason != a0.reason) fails += "(c) first alarm ${a.reason}, normal run ${a0.reason} ($tag)"
            if (!a.ringNow) fails += "(c) first alarm ringNow=false ($tag)"
            if (rel < 1000L * (tW - iS) || rel > 1000L * tW + WAKE_GUARD_MS + 1) {
                fails += "(c) first alarm at $rel ms, window [${1000L * (tW - iS)}, ${1000L * tW + WAKE_GUARD_MS + 1}] ($tag)"
            }
        }
        val wakeTicks = doze.records.count { it.input is Tick && (it.input.atMs - doze.startMs) % (1000L * iS) != 0L }
        val md = "| ${ref.name} | ${nl?.let { s3(it.atMs, normal.startMs) } ?: "-"} | ${dl?.let { s3(it.atMs, doze.startMs) } ?: "-"} | " +
            "${na?.let { "${it.first} ${it.second.reason}" } ?: "-"} | ${da?.let { "${s3(it.second.atMs, doze.startMs)} ${it.second.reason} " +
                "ringNow=${it.second.ringNow}" } ?: "-"} | $wakeTicks | ${if (fails.isEmpty()) "pass" else "FAIL"} |\n"
        return Row(ref.name, fails, md)
    }

    @Test
    fun `TR39 Doze model on the gpsGaps cases alarms from the engine like the normal run`() {
        val refs = Suite.cases.filter { ref ->
            val m = ref.entry.model
            ref.trace.gpsGapCount > 0 && m != null && m.config.kill == null && m.config.relaunch == null &&
                m.config.osDismissOffsetS == null && !m.allowFallbackFirst && "all" in m.samplingModes
        }
        assertEquals(11, refs.size) { "TR39 case set changed: ${refs.map { it.name }}" }
        val rows = refs.map { ref -> Suite.pool.submit(Callable { check(ref) }) }.map { it.get() }.sortedBy { it.name }
        val md = StringBuilder("### TR39 Doze model (T10.4 §7.3, mode all, no 9-minute Doze limit)\n\n")
        md.append("| case | gpsLost normal (s) | gpsLost Doze (s) | first alarm normal (t) | first alarm Doze (s) | wake Ticks off grid | result |\n")
        md.append("|---|---|---|---|---|---|---|\n")
        for (r in rows) md.append(r.md)
        Reports.section("TR39 doze", md.toString())
        val fails = rows.flatMap { it.fails }
        assertTrue(fails.isEmpty()) { fails.take(40).joinToString("\n") }
    }
}
