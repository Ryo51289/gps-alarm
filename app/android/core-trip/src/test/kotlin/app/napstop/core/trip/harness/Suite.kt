package app.napstop.core.trip.harness

import app.napstop.core.trip.Alarm
import java.io.File
import java.util.concurrent.Callable
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Everything a test needs about one main run; records are dropped after analysis to bound memory. */
internal class RunOutcome(
    val key: RunKey,
    val failures: List<String>,
    val transcriptSha: String?,
    val transcriptLines: Int,
    val transcript: String?,
    val firstAlarm: Pair<Int, Alarm>?,
    val killSweep: KillSweepRun?,
    /** Only for j = 0 runs: I8, I9, P06 failures (null = not applicable). */
    val i8: List<String>?,
    val i9: String?,
    val p06: String?,
)

internal class CaseRef(val trace: TraceModel, val entry: CaseEntry) {
    val name: String get() = "${trace.id}/${entry.id}"
}

/** Shared, lazily computed results of all main runs (295 after T10.3) (+ I8/I9/P06), computed in a fixed pool, stored by key. */
internal object Suite {
    val fixturesDir = File(System.getProperty("napstop.fixturesDir") ?: "../../../fixtures/traces")
    val p05Dir = File(System.getProperty("napstop.p05Dir") ?: "../../../fixtures/p05")
    val outDir = File(System.getProperty("napstop.outDir") ?: "build/napstop")
    val updateP05 = System.getProperty("napstop.updateP05") == "true"
    val dumpTranscripts = System.getProperty("napstop.dumpTranscripts") == "true"
    const val SHIFT_P06_MS = 86_400_000L

    val SAMPLE_RUNS = listOf(
        "coach_dn_langco_tunnel/distance_1000_gps_lost/all",
        "coach_dn_langco_tunnel/distance_1000_gps_lost/policy",
        "coach_gb_phuly_overshoot/distance_1000_fallback_silenced/all",
    )

    val traces: List<TraceModel> by lazy { ExpectModel.loadAll(fixturesDir) }

    val cases: List<CaseRef> by lazy { traces.flatMap { t -> t.cases.map { CaseRef(t, it) } } }

    val pool: ExecutorService by lazy {
        Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors().coerceIn(1, 8)) { r ->
            Thread(r, "napstop-suite").apply { isDaemon = true }
        }
    }

    fun keysOf(trace: TraceModel, case: CaseModel, phases: Int? = null): List<RunKey> {
        val out = ArrayList<RunKey>()
        for (m in case.samplingModes) {
            if (m == "all") {
                out += RunKey(trace.id, case.id, "all", false, 0)
            } else if (case.policyPhaseSweep) {
                val k = phases ?: phaseCount(trace, case)
                for (j in 0 until k) out += RunKey(trace.id, case.id, "policy-j" + j.toString().padStart(2, '0'), true, j)
            } else {
                out += RunKey(trace.id, case.id, "policy", true, 0)
            }
        }
        return out
    }

    fun phaseCount(trace: TraceModel, case: CaseModel): Int {
        val (_, params) = caseSetup(trace, case, emptyMap())
        if (params.samplingSparseIntervalS % trace.intervalS != 0) throw ConfigError("samplingSparseIntervalS not a multiple of I")
        return params.samplingSparseIntervalS / trace.intervalS
    }

    /** All main runs by run name; a case-level config error produces one failing outcome per case. */
    val outcomes: Map<String, RunOutcome> by lazy { computeAll() }

    fun outcomesOf(ref: CaseRef): List<RunOutcome> = outcomes.values.filter { it.key.traceId == ref.trace.id && it.key.caseId == ref.entry.id }

    private fun computeAll(): Map<String, RunOutcome> {
        if (dumpTranscripts) Transcript.diagEnabled = true
        val futures = ArrayList<Future<RunOutcome>>()
        for (ref in cases) {
            val model = ref.entry.model
            val keys = try {
                if (model == null) throw ConfigError(ref.entry.error ?: "invalid case")
                keysOf(ref.trace, model)
            } catch (e: ConfigError) {
                val k = RunKey(ref.trace.id, ref.entry.id, "config", false, 0)
                futures += pool.submit(Callable { RunOutcome(k, listOf("config error: ${e.message}"), null, 0, null, null, null, null, null, null) })
                continue
            }
            for (k in keys) futures += pool.submit(Callable { runOne(ref.trace, model!!, k) })
        }
        val m = sortedMapOf<String, RunOutcome>()
        for (f in futures) {
            val o = f.get()
            m[o.key.run] = o
        }
        return m
    }

    fun runOne(trace: TraceModel, case: CaseModel, key: RunKey): RunOutcome {
        return try {
            val main = CaseRun.run(trace, case, key)
            val fails = ArrayList(Checks.check(trace, case, main))
            val text = Transcript.build(key.run, main.startMs, main.records)
            if (dumpTranscripts) {
                val dir = File(outDir, "transcripts").apply { mkdirs() }
                val base = key.run.replace("/", "__")
                File(dir, "$base.jsonl").writeText(text, Charsets.UTF_8)
                File(dir, "$base.diag.jsonl").writeText(Transcript.buildDiag(main.records), Charsets.UTF_8)
            }
            var firstAlarm: Pair<Int, Alarm>? = null
            loop@ for (rec in main.records) for (e in rec.events) if (e is Alarm) {
                firstAlarm = rec.t to e
                break@loop
            }
            val ks = case.killSweep?.let { KillSweep.analyse(trace, case, main) }
            ks?.let { fails += it.failures }
            var i8: List<String>? = null
            var i9: String? = null
            var p06: String? = null
            if (key.j == 0) {
                val cps = RestoreEquivalence.checkpoints(trace, main).toSet()
                val rerun = CaseRun.run(trace, case, key, RunOpts(captureAt = cps, probes = false))
                val reText = Transcript.build(key.run, rerun.startMs, rerun.records)
                i9 = if (Transcript.sha256(reText) == Transcript.sha256(text)) null else "I9: re-run transcript differs (${key.run})"
                i8 = RestoreEquivalence.check(main, rerun, trace.intervalS)
                val shifted = CaseRun.run(trace, case, key, RunOpts(timeShiftMs = SHIFT_P06_MS, probes = false))
                val shText = Transcript.build(key.run, shifted.startMs, shifted.records)
                p06 = if (shText == text) null else "P06: +1 day transcript differs (${key.run})"
            }
            val keep = dumpTranscripts || key.run in SAMPLE_RUNS
            RunOutcome(key, fails, Transcript.sha256(text), Transcript.lineCount(text), if (keep) text else null, firstAlarm, ks, i8, i9, p06)
        } catch (e: ConfigError) {
            RunOutcome(key, listOf("config error: ${e.message} (${key.run} j=${key.j})"), null, 0, null, null, null, null, null, null)
        }
    }
}

/** Markdown/JSON reports under build/core-trip/napstop/ (no coordinates). Sections are written in name order. */
internal object Reports {
    private val sections = sortedMapOf<String, String>()
    private val killSections = sortedMapOf<String, String>()
    private val killJson = sortedMapOf<String, String>()

    @Synchronized
    fun section(name: String, md: String) {
        sections[name] = md
        write()
    }

    @Synchronized
    fun killSweep(name: String, md: String, json: String) {
        killSections[name] = md
        killJson[name] = json
        write()
    }

    private fun write() {
        val out = Suite.outDir.apply { mkdirs() }
        val ks = File(out, "killsweep").apply { mkdirs() }
        val ksMd = StringBuilder("# killSweep (T12 §8.6, TR37)\n\n")
        for ((_, v) in killSections) ksMd.append(v).append('\n')
        File(ks, "summary.md").writeText(ksMd.toString(), Charsets.UTF_8)
        File(ks, "killsweep.json").writeText(killJson.entries.joinToString(",\n", "{\n", "\n}\n") { "  \"${it.key}\": ${it.value}" }, Charsets.UTF_8)
        val md = StringBuilder("## core-trip (T12)\n\n")
        for ((_, v) in sections) md.append(v).append('\n')
        md.append(ksMd.toString().replaceFirst("# killSweep", "### killSweep"))
        File(out, "summary.md").writeText(md.toString(), Charsets.UTF_8)
    }
}
