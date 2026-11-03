package app.napstop.core.trip

import app.napstop.core.trip.harness.Suite
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** Meta test (T12 §8.1): every ID of T10 has a test. */
class IdCoverageTest {
    private val testSrc = File(System.getProperty("napstop.testSrcDir") ?: "src/test/kotlin")

    @Test
    fun `U01 to U118 each have a test named with the ID prefix`() {
        val unitDir = File(testSrc, "app/napstop/core/trip/unit")
        val names = HashSet<String>()
        val re = Regex("fun `(U\\d{2,3})\\b")
        unitDir.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.forEach { f ->
            re.findAll(f.readText()).forEach { names += it.groupValues[1] }
        }
        val missing = (1..118).map { "U" + it.toString().padStart(2, '0') }.filter { it !in names }
        assertTrue(missing.isEmpty()) { "missing unit IDs: $missing" }
    }

    @Test
    fun `TR01 to TR35, TR37 and TR38 appear in fixture testIds, TR36 in NegativeSweepTest and TR39 in DozeModelTest`() {
        val ids = Suite.cases.flatMap { it.entry.testIds }.toSet()
        val want = (1..38).filter { it != 36 }.map { "TR" + it.toString().padStart(2, '0') }
        val missing = want.filter { it !in ids }
        assertTrue(missing.isEmpty()) { "missing trace IDs in fixtures: $missing" }
        val neg = File(testSrc, "app/napstop/core/trip/NegativeSweepTest.kt").readText()
        assertTrue(neg.contains("fun `TR36")) { "TR36 test missing" }
        val doze = File(testSrc, "app/napstop/core/trip/DozeModelTest.kt").readText()
        assertTrue(doze.contains("fun `TR39")) { "TR39 test missing" }
    }
}
