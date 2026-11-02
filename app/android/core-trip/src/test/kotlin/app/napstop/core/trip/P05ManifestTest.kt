package app.napstop.core.trip

import app.napstop.core.trip.harness.CaseRun
import app.napstop.core.trip.harness.Suite
import app.napstop.core.trip.harness.Transcript
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.io.File

/** P05 regression key (T12 §9.4): lines + SHA-256 of all main runs (295 after T10.3/T11.2), and 3 byte-exact samples. */
class P05ManifestTest {
    private companion object {
        /** T10.3 / T11.2: 55 cases × 2 modes + 5 phase-swept cases × 37 runs. */
        const val EXPECTED_RUNS = 295
    }

    private val manifestFile = File(Suite.p05Dir, "manifest.json")
    private val samplesDir = File(Suite.p05Dir, "samples")

    private fun sampleFile(run: String) = File(samplesDir, run.replace("/", "__") + ".jsonl")

    private fun manifestText(entries: List<Triple<String, Int, String>>): String {
        val sb = StringBuilder("{\n  \"p05\": 1,\n  \"runs\": [\n")
        entries.forEachIndexed { i, (run, lines, sha) ->
            sb.append("    {\"run\": \"").append(run).append("\", \"lines\": ").append(lines).append(", \"sha256\": \"").append(sha).append("\"}")
            sb.append(if (i < entries.size - 1) ",\n" else "\n")
        }
        sb.append("  ]\n}\n")
        return sb.toString()
    }

    @Test
    fun `P05 manifest of all main runs and samples match`() {
        val outs = Suite.outcomes.values.filter { it.transcriptSha != null }
        val entries = outs.map { Triple(it.key.run, it.transcriptLines, it.transcriptSha!!) }.sortedBy { it.first }
        val text = manifestText(entries)
        if (Suite.updateP05) {
            samplesDir.mkdirs()
            manifestFile.writeText(text, Charsets.UTF_8)
            for (run in Suite.SAMPLE_RUNS) sampleFile(run).writeText(Suite.outcomes.getValue(run).transcript!!, Charsets.UTF_8)
            return
        }
        assertEquals(EXPECTED_RUNS, entries.size) { "expected $EXPECTED_RUNS main runs" }
        assertTrue(manifestFile.isFile) { "fixtures/p05/manifest.json missing; generate with -Pnapstop.updateP05=true (designer-approved only)" }
        val committed = manifestFile.readText(Charsets.UTF_8)
        val mismatched = ArrayList<String>()
        if (committed != text) {
            val want = Regex("\"run\": \"([^\"]+)\", \"lines\": (\\d+), \"sha256\": \"([0-9a-f]{64})\"").findAll(committed)
                .associate { it.groupValues[1] to (it.groupValues[2].toInt() to it.groupValues[3]) }
            for ((run, lines, sha) in entries) if (want[run] != (lines to sha)) mismatched += run
            for (run in want.keys) if (entries.none { it.first == run }) mismatched += run
            dumpMismatches(mismatched)
        }
        val sampleFails = Suite.SAMPLE_RUNS.filter { run ->
            !sampleFile(run).isFile || sampleFile(run).readText(Charsets.UTF_8) != Suite.outcomes.getValue(run).transcript
        }
        assertTrue(committed == text && sampleFails.isEmpty()) {
            "P05 mismatch: runs ${mismatched.take(20)} (${mismatched.size}); samples $sampleFails. Transcripts in build/core-trip/napstop/p05-mismatch/"
        }
    }

    private fun dumpMismatches(runs: List<String>) {
        val dir = File(Suite.outDir, "p05-mismatch").apply { mkdirs() }
        for (run in runs.take(50)) {
            val ref = Suite.cases.firstOrNull { run.startsWith(it.name + "/") } ?: continue
            val model = ref.entry.model ?: continue
            val key = Suite.keysOf(ref.trace, model).firstOrNull { it.run == run } ?: continue
            val r = CaseRun.run(ref.trace, model, key)
            File(dir, run.replace("/", "__") + ".jsonl").writeText(Transcript.build(run, r.startMs, r.records), Charsets.UTF_8)
        }
    }
}
