package app.napstop.core.trip.runtime

import java.io.File
import org.json.JSONObject

/**
 * Reads a T15 debug journal (`journal.ndjson`, spec §5.14) and prints, for the device protocol LM1–LM4:
 * every wake-up (requested time, delivery delay, candidate label c8 / c3 / c3-near / c4 / other), the gaps between
 * fixes per sampling tier, fix ages, the fallback alarms and the first alarm. No coordinates exist in the journal.
 *
 *   ./gradlew :core-runtime:analyzeJournal -Pjournal=/path/to/journal.ndjson
 */
object JournalAnalyzer {
    @JvmStatic
    fun main(args: Array<String>) {
        val path = args.firstOrNull()?.takeIf { it.isNotBlank() } ?: error("usage: analyzeJournal -Pjournal=<journal.ndjson>")
        println(analyze(File(path).readLines()))
    }

    private fun JSONObject.longOrNull(k: String): Long? = if (has(k) && !isNull(k)) getLong(k) else null

    /** Candidate of T10 §4.15 a wake time matches, from the last Step before it was set. */
    fun label(at: Long, predicted: Long?, fb: Long?): String =
        when {
            fb != null && at == fb - 90_000L -> "c8"
            predicted != null && at == predicted + 1_000L -> "c3"
            predicted != null && at == predicted - 599_000L -> "c3-near"
            predicted != null && (at == predicted - 899_000L || at == predicted - 3_599_000L) -> "c4"
            else -> "other"
        }

    fun analyze(lines: List<String>): String {
        val out = StringBuilder()
        var predicted: Long? = null
        var fb: Long? = null
        var tier: String? = null
        var setAt: Long? = null
        var setLabel = "other"
        var lastFixT: Long? = null
        val gapsByTier = LinkedHashMap<String, MutableList<Long>>()
        val ages = ArrayList<Long>()
        val wakes = ArrayList<String>()
        var firstAlarm: String? = null
        var fbSets = 0
        var fbFires = 0
        var idle: String? = null
        for (raw in lines) {
            if (raw.isBlank()) continue
            val j = JSONObject(raw)
            val t = j.longOrNull("t")
            when (j.getString("ev")) {
                "step" -> {
                    predicted = j.longOrNull("predicted")
                    fb = j.longOrNull("fb")
                    tier = j.optString("tier").ifEmpty { null }
                    if (firstAlarm == null) {
                        val evs = j.optJSONArray("events")
                        if (evs != null && (0 until evs.length()).any { evs.getString(it) == "Alarm" }) {
                            firstAlarm = "t=$t phase=${j.optString("phase")} input=${j.optString("input")}"
                        }
                    }
                }
                "wake_set" -> {
                    setAt = j.longOrNull("at")
                    setLabel = setAt?.let { label(it, predicted, fb) } ?: "other"
                }
                "wake_fire" -> {
                    val at = j.longOrNull("at")
                    // No `at` (alarm set by an older build, or a restore retry): not a wake-up of the delay table (F5).
                    if (at == null) continue
                    val late = j.longOrNull("lateMs")
                    val lbl = if (at != null && at == setAt) setLabel else "other"
                    val quiet = if (lbl == "c8" && fb != null && at != null && late != null && at + late > fb!! - 30_000L) " AFTER fb-30s" else ""
                    wakes += "  at=$at late=${late?.let { it / 1000.0 }}s label=$lbl idle=$idle$quiet"
                }
                "fix" -> {
                    if (t != null && !j.optBoolean("dropped")) {
                        lastFixT?.let { gapsByTier.getOrPut(tier ?: "none") { ArrayList() } += (t - it) }
                        lastFixT = t
                        ages += j.optLong("ageMs")
                    }
                }
                "fb_set" -> fbSets++
                "fb_fire" -> {
                    fbFires++
                    out.append("fallback fired: ").append(j.toString()).append('\n')
                }
                "ring" -> if (firstAlarm == null) firstAlarm = "ring t=$t ${j.optString("source")} ${j.optString("reason")}"
                "idle" -> idle = "deep=${j.optBoolean("deep")} light=${j.optBoolean("light")}"
            }
        }
        out.append("wake-ups (").append(wakes.size).append("):\n")
        wakes.forEach { out.append(it).append('\n') }
        out.append("fix gaps by tier (s): max / p90 / count\n")
        for ((k, v) in gapsByTier) {
            val s = v.sorted()
            out.append("  ").append(k).append(": ").append(s.last() / 1000.0).append(" / ").append(s[(s.size * 9) / 10].div(1000.0)).append(" / ").append(s.size).append('\n')
        }
        if (ages.isNotEmpty()) {
            val fresh = ages.count { it <= 60_000 } * 100.0 / ages.size
            out.append("fix age ≤ 60 s: ").append("%.1f".format(fresh)).append(" % of ").append(ages.size).append('\n')
        }
        out.append("fallback set: ").append(fbSets).append(", fired: ").append(fbFires).append('\n')
        out.append("first alarm: ").append(firstAlarm ?: "none").append('\n')
        return out.toString()
    }
}
