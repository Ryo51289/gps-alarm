package app.napstop.core.trip.harness

/** I8 / P04 (T12 §8.5): restore(decode(encode(s_c)), now = c, PENDING) then continue must equal the original run. */
internal object RestoreEquivalence {
    /** Checkpoints ⌊0.25·D/I⌋·I, ⌊0.5·D/I⌋·I, ⌊0.9·D/I⌋·I, firstAlarmT + I; minus duplicates, dead-engine ticks, ticks > D. */
    fun checkpoints(trace: TraceModel, main: RunResult): List<Int> {
        val d = trace.durationS
        val iS = trace.intervalS
        val raw = arrayListOf((d / 4 / iS) * iS, (d / 2 / iS) * iS, (d * 9 / 10 / iS) * iS)
        // floor(0.25·D/I)·I etc. computed with integers: D/4/I == floor(D/(4I)) for non-negative integers.
        main.firstAlarmT?.let { raw += it + iS }
        val kill = main.killT
        val deadEnd = main.relaunchT ?: Int.MAX_VALUE
        return raw.distinct().filter { c -> c <= d && !(kill != null && c >= kill && c < deadEnd) }
    }

    /** Failures of I8 at each checkpoint, using forks captured by the I9 re-run. */
    fun check(main: RunResult, rerun: RunResult, iS: Int): List<String> {
        val fails = ArrayList<String>()
        for ((c, fork) in rerun.forks) {
            val tag = "${main.key.run} c=$c"
            if (!fork.isAlive()) continue
            val step = fork.restorePendingAt(c)
            if (step.events.isNotEmpty()) fails += "I8: restore Step at c=$c has events ${step.events.map { eventName(it) }} ($tag)"
            try {
                fork.loop(c + iS)
            } catch (e: ConfigError) {
                fails += "I8: resumed run failed: ${e.message} ($tag)"
                continue
            }
            val orig = main.records.filter { it.t > c }.map { Transcript.fullLine(it, main.startMs) }
            val got = fork.records.map { Transcript.fullLine(it, main.startMs) }
            if (orig != got) {
                val i = orig.indices.firstOrNull { it >= got.size || orig[it] != got[it] } ?: got.size
                val o = orig.getOrNull(i)?.take(400)
                val g = got.getOrNull(i)?.take(400)
                fails += "I8: diverges at record $i after c=$c ($tag)\n  original: $o\n  restored: $g"
            }
        }
        return fails
    }
}
