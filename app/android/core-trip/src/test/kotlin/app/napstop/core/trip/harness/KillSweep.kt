package app.napstop.core.trip.harness

import app.napstop.core.trip.FallbackAlarmChanged

/** One kill time k of a killSweep run (T12 §8.6). Times are seconds relative to start. */
internal class KPoint(val j: Int, val k: Int, val fbRel: Long, val remaining: Int, val tAtDeath: Long, val far: Boolean, val late: Long, val early: Long)

/** killSweep data of one run; the run itself has no coordinates. */
internal class KillSweepRun(
    val key: RunKey,
    val tA: Int,
    val points: List<KPoint>,
    val facTimes: List<Int>,
    val facFarCount: Int,
    val failures: List<String>,
)

private fun fmt(f: String, x: Double): String = String.format(java.util.Locale.ROOT, f, x)

internal object KillSweep {
    /** Checks and data of one live run (no engine re-run per k: fbOs(k − I) of the live run is the value). */
    fun analyse(trace: TraceModel, case: CaseModel, r: RunResult): KillSweepRun {
        val ks = case.killSweep!!
        val tag = "${r.key.run} j=${r.key.j}"
        val fails = ArrayList<String>()
        val tA = r.firstAlarmT ?: return KillSweepRun(r.key, -1, emptyList(), emptyList(), 0, listOf("killSweep: no alarm ($tag)"))
        val iS = trace.intervalS
        val notAfter = ks.notAfter.t ?: throw ConfigError("killSweep.notAfter without t")
        val earlyFrom = ks.earlyFrom.t ?: throw ConfigError("killSweep.earlyFrom without t")
        val from = ks.from.t ?: throw ConfigError("killSweep.from without t")
        if (from < iS || ks.everyS <= 0 || ks.everyS % iS != 0) throw ConfigError("killSweep from/everyS invalid")
        val nearMs = r.params.fallbackNearS * 1000L
        val pts = ArrayList<KPoint>()
        var k = from
        while (k <= tA) {
            val idx = (k - iS) / iS
            val fb = r.fbOsAfterTick[idx]
            if (fb == null) {
                fails += "killSweep: no fallback held after tick ${k - iS} (k=$k, $tag)"
            } else {
                val fbRel = Math.floorDiv(fb - r.startMs, 1000L)
                val late = fbRel - notAfter
                if (!ks.statsOnly && late > 0) fails += "killSweep: k=$k fallback at $fbRel > notAfter $notAfter ($tag)"
                val pred = r.predAfterTick[idx]
                val nowMs = r.startMs + 1000L * (k - iS)
                val tDeath = if (pred == null) Long.MIN_VALUE else Math.floorDiv(pred - nowMs, 1000L)
                pts += KPoint(r.key.j, k, fbRel, trace.arrivalT - k, tDeath, pred != null && pred - nowMs > nearMs, late, earlyFrom - fbRel)
            }
            k += ks.everyS
        }
        val facTimes = ArrayList<Int>()
        var far = 0
        for (rec in r.records) {
            if (rec.t > tA) break
            val v = rec.view ?: continue
            for (e in rec.events) {
                if (e !is FallbackAlarmChanged) continue
                facTimes += rec.t
                val p = v.predictedAlarmAtMs
                if (p != null && p - v.atMs > nearMs) far++
            }
        }
        return KillSweepRun(r.key, tA, pts, facTimes, far, fails)
    }

    private fun pct(sorted: List<Long>, p: Double): Long {
        val idx = Math.ceil(p * sorted.size).toInt() - 1
        return sorted[idx.coerceIn(0, sorted.size - 1)]
    }

    /** Markdown statistics of a group of runs (label = all / policy / all+policy). */
    class Stats(val label: String, runs: List<KillSweepRun>, arrivalT: Int) {
        val n: Int
        val lateCount: Int
        val latePct: Double
        val lateMax: Long
        val lateMean: Double
        val text: String

        init {
            val pts = runs.flatMap { it.points }
            n = pts.size
            val late = pts.filter { it.late > 0 }
            lateCount = late.size
            latePct = if (n == 0) 0.0 else 100.0 * lateCount / n
            lateMax = late.maxOfOrNull { it.late } ?: 0
            lateMean = if (late.isEmpty()) 0.0 else late.sumOf { it.late }.toDouble() / late.size
            val sb = StringBuilder()
            sb.append("| $label | runs ${runs.size} | k ${n} | late $lateCount (${fmt("%.1f", latePct)} %) | late max ${lateMax} s | late mean ${fmt("%.0f", lateMean)} s | min margin (notAfter - fb) ${pts.minOfOrNull { -it.late } ?: 0} s |\n\n")
            sb.append("Earliness `earlyFrom − fb` (s) by `arrival − k`, nearest-rank:\n\n| group | n | p10 | p50 | p90 | max |\n|---|---|---|---|---|---|\n")
            val groups = listOf("< 3600" to { r: Int -> r < 3600 }, "[3600, 7200)" to { r: Int -> r in 3600 until 7200 },
                "[7200, 14400)" to { r: Int -> r in 7200 until 14400 }, ">= 14400" to { r: Int -> r >= 14400 })
            for ((g, sel) in groups) {
                val xs = pts.filter { sel(it.remaining) }.map { it.early }.sorted()
                if (xs.isEmpty()) sb.append("| $g | 0 | | | | |\n")
                else sb.append("| $g | ${xs.size} | ${pct(xs, 0.1)} | ${pct(xs, 0.5)} | ${pct(xs, 0.9)} | ${xs.last()} |\n")
            }
            val hours = runs.sumOf { it.tA.coerceAtLeast(1) } / 3600.0
            val facs = runs.sumOf { it.facTimes.size }
            val farFacs = runs.sumOf { it.facFarCount }
            var maxWin = 0
            for (r in runs) {
                var lo = 0
                for (hi in r.facTimes.indices) {
                    while (r.facTimes[hi] - r.facTimes[lo] >= 3600) lo++
                    maxWin = maxOf(maxWin, hi - lo + 1)
                }
            }
            sb.append("\nFallbackAlarmChanged on [0, tA]: ${fmt("%.1f", facs / hours)} /h (far zone ${fmt("%.1f", farFacs / hours)} /h); ")
            sb.append("max in a 3600 s window: $maxWin\n\n")
            val worst = late.sortedWith(compareByDescending<KPoint> { it.late }.thenBy { it.j }.thenBy { it.k }).take(10)
            if (worst.isNotEmpty()) {
                sb.append("10 latest k:\n\n| j | k | arrival − k | fb (s) | late (s) | T at death (s) | zone |\n|---|---|---|---|---|---|---|\n")
                for (p in worst) sb.append("| ${p.j} | ${p.k} | ${p.remaining} | ${p.fbRel} | ${p.late} | ${p.tAtDeath} | ${if (p.far) "far" else "near"} |\n")
                sb.append('\n')
            }
            text = sb.toString()
        }

        fun json(): String = "{\"label\":\"$label\",\"k\":$n,\"late\":$lateCount,\"latePct\":${fmt("%.3f", latePct)},\"lateMaxS\":$lateMax," +
            "\"lateMeanS\":${fmt("%.1f", lateMean)}}"
    }
}
