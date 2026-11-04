package app.napstop.core.alarm.ring

import android.content.Context
import android.util.Log
import app.napstop.BuildConfig

/**
 * Measurement journal of `:ring` (spec T16 §11 file list, debug builds only: `RingJournal` in src/debug writes
 * `no_backup/napstop_ring/journal_ring.ndjson`). Fields: enums, ids, times, class names — never a destination, a
 * distance or a coordinate. Release builds: [NoOp] (the class does not exist there).
 */
fun interface RingJournalSink {
    fun log(event: String, fields: Map<String, Any?>)

    companion object {
        val NoOp = RingJournalSink { _, _ -> }

        fun create(ctx: Context): RingJournalSink {
            if (!BuildConfig.DEBUG) return NoOp
            return try {
                val cls = Class.forName("app.napstop.core.alarm.ring.RingJournal")
                cls.getMethod("create", Context::class.java).invoke(null, ctx) as RingJournalSink
            } catch (e: Exception) {
                Log.w("NapStopRing", "ring journal unavailable (${e.javaClass.simpleName})")
                NoOp
            }
        }
    }
}
