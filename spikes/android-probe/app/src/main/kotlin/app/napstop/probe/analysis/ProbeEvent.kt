package app.napstop.probe.analysis

import java.time.OffsetDateTime

/**
 * One line of `events.jsonl`. [fields] holds the whole decoded object (common fields included).
 * [seq] is an addition to the S1 §5.8 signature: needed for the (t, seq) ordering.
 */
data class ProbeEvent(
    val ev: String,
    val et: Long,
    val t: String,
    val pid: Int,
    val fields: Map<String, Any?>,
    val seq: Long = 0,
) {
    /** Wall-clock time of [t] in epoch ms (offset-aware, so lines with different offsets compare correctly). */
    val wallMs: Long = OffsetDateTime.parse(t).toInstant().toEpochMilli()

    fun str(key: String): String? = fields[key] as? String

    fun long(key: String): Long? = (fields[key] as? Number)?.toLong()

    fun int(key: String): Int? = (fields[key] as? Number)?.toInt()

    fun bool(key: String): Boolean? = fields[key] as? Boolean
}

data class ParsedLog(val events: List<ProbeEvent>, val corruptLines: Int)

/** Pure parser for JSON Lines event logs; corrupt lines (e.g. a line cut by a process kill) are skipped. */
object ProbeEventParser {

    fun parse(lines: Sequence<String>): ParsedLog {
        val events = ArrayList<ProbeEvent>()
        var corrupt = 0
        for (line in lines) {
            if (line.isBlank()) continue
            val event = runCatching { toEvent(FlatJson.decode(line)) }.getOrNull()
            if (event == null) corrupt++ else events += event
        }
        return ParsedLog(events, corrupt)
    }

    fun toEvent(map: Map<String, Any?>): ProbeEvent? {
        val ev = map["ev"] as? String ?: return null
        val t = map["t"] as? String ?: return null
        return ProbeEvent(
            ev = ev,
            et = (map["et"] as? Number)?.toLong() ?: 0L,
            t = t,
            pid = (map["pid"] as? Number)?.toInt() ?: 0,
            fields = map,
            seq = (map["seq"] as? Number)?.toLong() ?: 0L,
        )
    }
}
