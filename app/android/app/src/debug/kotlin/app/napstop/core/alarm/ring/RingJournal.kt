package app.napstop.core.alarm.ring

import android.content.Context
import android.util.Log
import app.napstop.core.alarm.RingFactsStore
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONObject

/**
 * Debug-only journal of process `:ring` (spec T16 file list): `no_backup/napstop_ring/journal_ring.ndjson`, rotated at
 * 1 MB. Enums, ids, times, class names only — no destination name, no distance, no coordinate.
 * Pull: `adb exec-out run-as app.napstop.dev cat no_backup/napstop_ring/journal_ring.ndjson`.
 */
class RingJournal private constructor(context: Context) : RingJournalSink {
    private val dir = File(context.applicationContext.noBackupFilesDir, RingFactsStore.DIR_NAME)
    private val file = File(dir, FILE_NAME)
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "napstop-ring-journal").apply { isDaemon = true } }

    override fun log(event: String, fields: Map<String, Any?>) {
        val line = JSONObject().put("w", System.currentTimeMillis()).put("ev", event)
        for ((k, v) in fields) line.put(k, v ?: JSONObject.NULL)
        executor.execute {
            try {
                if (!dir.isDirectory) dir.mkdirs()
                if (file.length() > MAX_BYTES) file.renameTo(File(dir, "journal_ring.1.ndjson"))
                file.appendText(line.toString() + "\n")
            } catch (e: Exception) {
                Log.w("NapStopDebug", "ring journal write failed (${e.javaClass.simpleName})")
            }
        }
    }

    companion object {
        const val FILE_NAME = "journal_ring.ndjson"
        private const val MAX_BYTES = 1L * 1024 * 1024

        @Volatile
        private var instance: RingJournal? = null

        /** Looked up by RingJournalSink.create (reflection, debug builds only). */
        @JvmStatic
        fun create(context: Context): RingJournalSink =
            instance ?: synchronized(this) { instance ?: RingJournal(context).also { instance = it } }
    }
}
