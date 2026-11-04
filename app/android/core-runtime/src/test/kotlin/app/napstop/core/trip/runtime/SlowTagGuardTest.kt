package app.napstop.core.trip.runtime

import java.io.File
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * T01.1 §4: `-Pnapstop.quick=true` skips the methods tagged `slow`. This guard (runs in both modes) keeps the tags exactly the
 * reviewed list, at method level right above `@Test`/`@TestFactory`, and never on a class that must run in quick mode (§3.1).
 * Adding a slow test means adding it to [EXPECTED], so the change shows up in review.
 */
class SlowTagGuardTest {
    private val testSrc = File(System.getProperty("napstop.testSrcDir") ?: "src/test/kotlin")

    private companion object {
        /**
         * T01.1 §3.2 (measured 04/11, each >= 2 s in the full run; T16TraceTest at1 measured 0.8 s, so it is not tagged).
         * File name # method name.
         */
        val EXPECTED: Set<String> = setOf(
            "KillSweepRuntimeTest.kt#l31_killSweepEvery300s",
            "T15TesterRound2Test.kt#startTripWithSlowRead2500AnswersWithin15s",
            "T18TesterSimTest.kt#ts02_bundledTracesAtTheUiSpeed10xAndOddSpeeds",
            "SimTraceRuntimeTest.kt#sm19_bundledTracesAtThreeSpeedsGiveTheSameEvents",
            "T15TesterRuntimeTest.kt#wholeDiskHungStillRingsWithinTheReceiverBudget",
        )

        /** T01.1 §3.1: whole classes that always run in quick mode. */
        val MUST_RUN: Set<String> = setOf(
            "TraceRuntimeTest.kt", "T18TesterRealTripParityTest.kt", "DozeRuntimeTest.kt", "T15TesterRestoreMatrixTest.kt",
            "RuntimeUnitTest.kt", "PureUnitsTest.kt",
        )

        /** T01.1 §3.1: every test of `core/alarm` always runs in quick mode. */
        const val MUST_RUN_DIR = "app/napstop/core/alarm/"

        val ANY_TAG = Regex("""@Tag\("([^"]*)"\)""")
        val PLACED = Regex("""@Tag\("slow"\)\s*\R\s*@(Test|TestFactory)\s*\R\s*fun\s+(`[^`]+`|\w+)""")
    }

    @Test
    fun t011_slowTagsAreTheReviewedList() {
        val files = testSrc.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") && it.name != "SlowTagGuardTest.kt" }.toList()
        assertTrue(files.isNotEmpty()) { "no test source under $testSrc" }
        val found = sortedSetOf<String>()
        for (f in files) {
            val text = f.readText()
            val anyTag = ANY_TAG.findAll(text).toList()
            for (t in anyTag) assertEquals("slow", t.groupValues[1]) { "unknown tag ${t.groupValues[1]} in ${f.name}" }
            val placed = PLACED.findAll(text).toList()
            assertEquals(anyTag.size, placed.size) { "@Tag must sit right above @Test/@TestFactory (${f.name})" }
            val mustRun = f.name in MUST_RUN || f.relativeTo(testSrc).invariantSeparatorsPath.startsWith(MUST_RUN_DIR)
            if (mustRun) assertEquals(0, anyTag.size) { "${f.name} must run in quick mode" }
            placed.forEach { found += f.name + "#" + it.groupValues[2].trim('`') }
        }
        assertEquals(EXPECTED.toSortedSet(), found) { "missing ${EXPECTED - found}, extra ${found - EXPECTED}" }
    }
}
