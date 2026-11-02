package app.napstop.core.trip.unit

import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** U44 extended (T12 §6): forbidden APIs in src/main/kotlin (determinism D1–D7, no IO / log). */
class SourceScanTest {
    private val mainDir = File(System.getProperty("napstop.mainSrcDir") ?: "src/main/kotlin")

    private val forbidden = listOf(
        Regex("""\b(sin|cos|tan|asin|acos|atan|atan2|exp|expm1|log|log10|log1p|pow|cbrt|hypot)\s*\("""),
        Regex("""\bMath\."""), Regex("""\bStrictMath\."""), Regex("""kotlin\.math\.(min|max)\b"""),
        Regex("""\bminOf\("""), Regex("""\bmaxOf\("""), Regex("""\bcoerce(In|AtLeast|AtMost)\b"""), Regex("""\broundTo(Int|Long)\b"""),
        Regex("""\.round\("""), Regex("""\bfma\b"""), Regex("""java\.util\.Random"""), Regex("""kotlin\.random"""),
        Regex("""System\.currentTimeMillis"""), Regex("""System\.nanoTime"""), Regex("""Instant\.now"""), Regex("""\bClock\b"""),
        Regex("""\bHashMap\b"""), Regex("""\bHashSet\b"""), Regex("""\bhashMapOf\b"""), Regex("""\bhashSetOf\b"""),
        Regex("""\bprintln\b"""), Regex("""\bprint\("""), Regex("""System\.out"""), Regex("""System\.err"""), Regex("""\bLog\."""),
        Regex("""import android"""), Regex("""import java\.io"""), Regex("""import java\.nio"""),
    )
    private val narrowing = Regex("""\.to(Int|Long)\(\)""")
    private val narrowingAllowed = setOf("TMath.kt", "MiniJson.kt", "SnapshotCodec.kt", "EngineParams.kt")

    private fun code(line: String): String = line.substringBefore("//")

    @Test
    fun `U44 engine sources contain no transcendental, library min max, nondeterminism or IO`() {
        val files = mainDir.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.toList()
        assertTrue(files.size >= 21) { "expected the 21 engine files, found ${files.size}" }
        val hits = ArrayList<String>()
        for (f in files) {
            var inBlockComment = false
            f.readLines().forEachIndexed { i, raw ->
                var line = raw
                if (inBlockComment) {
                    if (!line.contains("*/")) return@forEachIndexed
                    line = line.substringAfter("*/")
                    inBlockComment = false
                }
                if (line.trimStart().startsWith("/*") || line.trimStart().startsWith("*")) {
                    if (!line.contains("*/")) inBlockComment = line.trimStart().startsWith("/*")
                    return@forEachIndexed
                }
                val c = code(line)
                for (r in forbidden) if (r.containsMatchIn(c)) hits += "${f.name}:${i + 1}: ${r.pattern}"
                if (f.name !in narrowingAllowed && narrowing.containsMatchIn(c)) hits += "${f.name}:${i + 1}: narrowing conversion"
            }
        }
        assertTrue(hits.isEmpty()) { hits.joinToString("\n") }
    }

    @Test
    fun `U44 the scan itself catches forbidden patterns`() {
        val samples = listOf("val x = Math.max(a, b)", "kotlin.math.min(1.0, 2.0)", "val y = cos(x)", "println(x)", "val m = HashMap<String, Int>()")
        for (s in samples) assertTrue(forbidden.any { it.containsMatchIn(s) }, s)
        for (s in listOf("TMath.max(a, b)", "cosDeg(x)", "val m = LinkedHashMap<String, Int>()", "expectedSpeedMps(h)")) {
            assertTrue(forbidden.none { it.containsMatchIn(s) }, s)
        }
    }
}
