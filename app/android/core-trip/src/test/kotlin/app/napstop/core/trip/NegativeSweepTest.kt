package app.napstop.core.trip

import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Checks
import app.napstop.core.trip.harness.KillSweep
import app.napstop.core.trip.harness.Reports
import app.napstop.core.trip.harness.RunOpts
import app.napstop.core.trip.harness.Suite
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.util.concurrent.Callable

/** Negative harness runs (T12 §8.7): they prove the sweeps catch the risks. Not in the P05 manifest. */
class NegativeSweepTest {
    private fun case(traceId: String, caseId: String) =
        Suite.cases.first { it.trace.id == traceId && it.entry.id == caseId }.let { it.trace to it.entry.model!! }

    @Test
    fun `TR36 TR30 phase sweep without the lost-GPS speed guard fails at least one phase`() {
        val (trace, case) = case("train_hn_dh_stopgap", "distance_1000")
        val keys = Suite.keysOf(trace, case).filter { it.policy }
        val opts = RunOpts(paramOverrides = mapOf("lostSpeedGuardUpdates" to JNumber("0")), probes = false)
        val results = keys.map { k ->
            Suite.pool.submit(
                Callable {
                    val r = CaseRun.run(trace, case, k, opts)
                    val evs = Checks.events(r)
                    val x = case.expect.single()
                    val first = evs.firstOrNull { Checks.matches(x.filter, it.e) }
                    val ok = first != null && first.t >= x.notBefore && first.t <= x.notAfter
                    val firstAlarm = evs.firstOrNull { it.e is Alarm }
                    Triple(k.j, ok, firstAlarm?.let { "${it.t} ${(it.e as Alarm).reason}" } ?: "none")
                },
            )
        }.map { it.get() }
        val failed = results.filter { !it.second }
        val md = StringBuilder("### TR36 (lostSpeedGuardUpdates = 0, 36 phases)\n\nFailing phases: ${failed.size}/${results.size}\n\n")
        md.append("| j | TR30 expectation | first alarm |\n|---|---|---|\n")
        for ((j, ok, a) in results) md.append("| $j | ${if (ok) "pass" else "FAIL"} | $a |\n")
        Reports.section("negative TR36", md.toString())
        assertTrue(failed.isNotEmpty()) { "TR36: no phase fails without the speed guard; report to the designer" }
    }

    @Test
    fun `TR37 negative old T10 fallback params give a fallback after arrival`() {
        val (trace, case) = case("train_hn_dh", "distance_1000_killsweep")
        val keys = Suite.keysOf(trace, case)
        val opts = RunOpts(
            paramOverrides = mapOf(
                "fallbackEarlyFrac" to JNumber("0.1"),
                "fallbackEarlyMaxS" to JNumber("1800"),
                "fallbackHintSpeedFactor" to JNumber("0"),
            ),
            probes = false,
        )
        val runs = keys.map { k -> Suite.pool.submit(Callable { KillSweep.analyse(trace, case, CaseRun.run(trace, case, k, opts)) }) }.map { it.get() }
        val n = runs.sumOf { it.points.size }
        val late = runs.sumOf { r -> r.points.count { it.late > 0 } }
        Reports.section(
            "negative TR37",
            "### TR37 negative (train_hn_dh/distance_1000_killsweep, T10 params 0.1 / 1800 / 0)\n\nk after arrival: $late / $n " +
                "(k every 60 s, all + policy; reviewer model: 443 / 1 122)\n",
        )
        assertTrue(late >= 1) { "TR37 negative: no late k with the old T10 parameters; report to the designer" }
    }
}
