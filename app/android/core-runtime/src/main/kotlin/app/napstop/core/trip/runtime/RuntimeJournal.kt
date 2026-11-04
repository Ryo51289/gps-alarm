package app.napstop.core.trip.runtime

/**
 * Measurement journal of the debug build (spec T15 §5.14): one ndjson line per event, `{"t":<trip ms>,"w":<wall ms>,
 * "ev":"…",…}`. Fields are enums, times, counters and slot numbers only: **never** lat/lng, distances or the
 * destination name (L43). Release builds use [NoOp].
 */
interface RuntimeJournal {
    val enabled: Boolean

    /** [fields] values: String, Number, Boolean, null or List of those. */
    fun log(tripMs: Long?, wallMs: Long, ev: String, fields: Map<String, Any?>)

    object NoOp : RuntimeJournal {
        override val enabled = false

        override fun log(tripMs: Long?, wallMs: Long, ev: String, fields: Map<String, Any?>) = Unit
    }

    companion object {
        /** Every field name the runtime writes, per event (L43 checks against it). */
        val FIELDS: Map<String, Set<String>> =
            mapOf(
                "step" to setOf("phase", "gps", "tier", "predicted", "fb", "fbStatus", "wake", "events", "input"),
                "fix" to setOf("ageMs", "accM", "hasSpd", "dropped"),
                "wake_set" to setOf("at", "mech"),
                "wake_fire" to setOf("at", "lateMs", "kind"),
                "restore_retry" to setOf("attempt", "inMs", "cause"),
                "fb_set" to setOf("slot", "gen", "at", "ok", "kind"),
                "fb_cancel" to setOf("slot"),
                "fb_fire" to setOf("slot", "gen", "at", "lateMs", "action", "kind"),
                "ring" to setOf("source", "reason", "ok"),
                "persist" to setOf("ok", "ms"),
                "idle" to setOf("deep", "light"),
                "mode" to setOf("from", "to"),
                "restore" to setOf("cause", "status"),
            )
    }
}
