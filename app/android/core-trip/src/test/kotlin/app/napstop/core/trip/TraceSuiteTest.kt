package app.napstop.core.trip

import app.napstop.core.trip.harness.CaseRef
import app.napstop.core.trip.harness.KillSweep
import app.napstop.core.trip.harness.Reports
import app.napstop.core.trip.harness.RunOutcome
import app.napstop.core.trip.harness.Suite
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.DynamicContainer
import org.junit.jupiter.api.DynamicContainer.dynamicContainer
import org.junit.jupiter.api.DynamicNode
import org.junit.jupiter.api.DynamicTest.dynamicTest
import org.junit.jupiter.api.TestFactory

/**
 * TR01–TR35, TR37 + P01–P04, P06, P07 over every fixture case (T12 §8): one test per run (all, policy or
 * policy-j00…j35), plus I8, I9, P06 at j = 0 per mode and killSweep statistics per case.
 */
class TraceSuiteTest {
    /** Reference of the T10.2 model for TR37 (f), (g): late %, late max (s). Non-blocking thresholds +10 pt / +300 s. */
    private val tr37Reference = mapOf(
        "coach_gb_phuly_overshoot/distance_1000_killsweep" to (34.6 to 744L),
        "train_longstop/distance_1000_killsweep" to (13.6 to 340L),
    )

    @TestFactory
    fun traces(): List<DynamicContainer> = Suite.traces.map { trace ->
        dynamicContainer(trace.id, trace.cases.map { entry -> caseNode(CaseRef(trace, entry)) })
    }

    private fun caseNode(ref: CaseRef): DynamicNode {
        val ids = ref.entry.testIds.joinToString(",")
        val name = "$ids ${ref.name}"
        val nodes = ArrayList<DynamicNode>()
        val outs by lazy { Suite.outcomesOf(ref).sortedBy { it.key.run } }
        val model = ref.entry.model
        if (model == null) {
            nodes += dynamicTest("$name config") { fail<Unit>("config error: ${ref.entry.error}") }
            return dynamicContainer(name, nodes)
        }
        val keys = try {
            Suite.keysOf(ref.trace, model)
        } catch (e: Exception) {
            nodes += dynamicTest("$name config") { fail<Unit>("config error: ${e.message}") }
            return dynamicContainer(name, nodes)
        }
        for (k in keys) {
            nodes += dynamicTest("$name ${k.mode}") {
                val o = Suite.outcomes[k.run] ?: fail("run ${k.run} missing")
                assertTrue(o.failures.isEmpty()) { o.failures.joinToString("\n") }
            }
        }
        for (k in keys.filter { it.j == 0 }) {
            nodes += dynamicTest("I8 P04 ${ref.name} ${k.mode}") {
                val o = Suite.outcomes.getValue(k.run)
                assertTrue(o.i8 != null && o.i8.isEmpty()) { o.i8?.joinToString("\n") ?: (o.failures.joinToString("\n")) }
            }
            nodes += dynamicTest("I9 ${ref.name} ${k.mode}") {
                val o = Suite.outcomes.getValue(k.run)
                assertTrue(o.transcriptSha != null && o.i9 == null) { o.i9 ?: o.failures.joinToString("\n") }
            }
            nodes += dynamicTest("P06 ${ref.name} ${k.mode}") {
                val o = Suite.outcomes.getValue(k.run)
                assertTrue(o.transcriptSha != null && o.p06 == null) { o.p06 ?: o.failures.joinToString("\n") }
            }
        }
        if (model.killSweep != null) {
            nodes += dynamicTest("$ids killSweep ${ref.name}") { killSweepReport(ref, outs) }
        }
        if (model.policyPhaseSweep) {
            nodes += dynamicTest("$ids phase table ${ref.name}") { phaseTable(ref, outs) }
        }
        return dynamicContainer(name, nodes)
    }

    private fun killSweepReport(ref: CaseRef, outs: List<RunOutcome>) {
        val all = outs.filter { !it.key.policy }.mapNotNull { it.killSweep }
        val pol = outs.filter { it.key.policy }.mapNotNull { it.killSweep }
        val arrival = ref.trace.arrivalT
        val stats = listOf(KillSweep.Stats("all", all, arrival), KillSweep.Stats("policy", pol, arrival), KillSweep.Stats("all+policy", all + pol, arrival))
        val md = StringBuilder("## ${ref.entry.testIds.joinToString(",")} ${ref.name}\n\n")
        md.append("statsOnly: ${ref.entry.model!!.killSweep!!.statsOnly}; arrival ${arrival}; tA per run: ")
        md.append((all + pol).joinToString(", ") { "${it.key.mode}=${it.tA}" }.take(600)).append("\n\n")
        for (s in stats) md.append(s.text)
        tr37Reference[ref.name]?.let { (refPct, refMax) ->
            val c = stats[2]
            md.append("Reference (T10.2 model, all + 36 phases, every 5 s): ${refPct} % late, max ${refMax} s. ")
            md.append("Measured (all + policy, every 60 s): ${String.format(java.util.Locale.ROOT, "%.1f", c.latePct)} %, max ${c.lateMax} s.\n\n")
            if (c.latePct > refPct + 10.0 || c.lateMax > refMax + 300) {
                md.append("WARN: ${ref.name} late share or late max above reference + 10 pt / + 300 s (non-blocking, T10.2 RK16 c)\n\n")
            }
        }
        Reports.killSweep(ref.name, md.toString(), stats.joinToString(",", "[", "]") { it.json() })
        val fails = (all + pol).flatMap { it.failures }
        assertTrue(fails.isEmpty()) { fails.joinToString("\n") }
    }

    private fun phaseTable(ref: CaseRef, outs: List<RunOutcome>) {
        val md = StringBuilder("### First alarm per run: ${ref.entry.testIds.joinToString(",")} ${ref.name}\n\n| run | tick | reason | ringNow |\n|---|---|---|---|\n")
        for (o in outs) {
            val a = o.firstAlarm
            md.append("| ${o.key.mode} | ${a?.first ?: "-"} | ${a?.second?.reason ?: "-"} | ${a?.second?.ringNow ?: "-"} |\n")
        }
        Reports.section("phase ${ref.name}", md.toString())
    }
}
