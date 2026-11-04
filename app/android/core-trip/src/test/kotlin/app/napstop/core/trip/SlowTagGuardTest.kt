package app.napstop.core.trip

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/**
 * T01.1 §4: `-Pnapstop.quick=true` skips the methods tagged `slow`. This guard (runs in both modes) keeps the tags exactly the
 * reviewed list, at method level right above `@Test`/`@TestFactory`, and never on a class that must run in quick mode (§3.1).
 * Adding a slow test means adding it to [EXPECTED], so the change shows up in review.
 */
class SlowTagGuardTest {
    private val testSrc = File(System.getProperty("napstop.testSrcDir") ?: "src/test/kotlin")

    private companion object {
        /** T01.1 §3.2 (measured 04/11, each >= 2 s in the full run; T123 g reruns U126 a/b). File name # method name. */
        val EXPECTED: Set<String> = setOf(
            "TesterT12Test.kt#U105 a fuzz 1000 seeded trips keep the safety invariants, I13 and I14 at every Step",
            "TesterT121Test.kt#U126 a Doze fuzz lateness T12_2 vs T10_6, long-loss alarms and the review seeds",
            "TesterT122Test.kt#T122 e fuzz urgent later shift path - no double ring, one alarm, I1-I7 I10-I14 at every Step, " +
                "emissions equal fallbackTarget",
            "TesterT122Test.kt#U126 b e1 e2 fuzz lateness T12_2 vs T10_6 and long-loss alarms",
            "TesterT123Test.kt#T123 g U126 numeric thresholds of T10_6 section 9 hold",
            "TesterT132ParityTest.kt#T132P parity fuzz 2000 random trips (chords at destLat != 0, outliers, wake-ups, restores) " +
                "per-Step transcript",
        )

        /** T01.1 §3.1: whole classes that always run in quick mode. */
        val MUST_RUN: Set<String> = setOf(
            "P05ManifestTest.kt", "IdCoverageTest.kt", "TraceSuiteTest.kt", "NegativeSweepTest.kt", "DozeModelTest.kt",
            "HarnessSelfTest.kt", "TesterT113Test.kt", "SourceScanTest.kt", "PrivacyTest.kt",
        )

        val ANY_TAG = Regex("""@Tag\("([^"]*)"\)""")
        val PLACED = Regex("""@Tag\("slow"\)\s*\R\s*@(Test|TestFactory)\s*\R\s*fun\s+(`[^`]+`|\w+)""")
    }

    @Test
    fun `T01_1 slow tags are exactly the reviewed list, method level, never on must-run classes`() {
        val files = testSrc.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") && it.name != "SlowTagGuardTest.kt" }.toList()
        assertTrue(files.isNotEmpty()) { "no test source under $testSrc" }
        val found = sortedSetOf<String>()
        for (f in files) {
            val text = f.readText()
            val anyTag = ANY_TAG.findAll(text).toList()
            for (t in anyTag) assertEquals("slow", t.groupValues[1]) { "unknown tag ${t.groupValues[1]} in ${f.name}" }
            val placed = PLACED.findAll(text).toList()
            assertEquals(anyTag.size, placed.size) { "@Tag must sit right above @Test/@TestFactory (${f.name})" }
            if (f.name in MUST_RUN) assertEquals(0, anyTag.size) { "${f.name} must run in quick mode" }
            placed.forEach { found += f.name + "#" + it.groupValues[2].trim('`') }
        }
        assertEquals(EXPECTED.toSortedSet(), found) { "missing ${EXPECTED - found}, extra ${found - EXPECTED}" }
    }
}
