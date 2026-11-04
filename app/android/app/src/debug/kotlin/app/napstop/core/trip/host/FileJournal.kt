package app.napstop.core.trip.host

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import app.napstop.core.trip.runtime.FileRuntimeStore
import app.napstop.core.trip.runtime.RuntimeJournal
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONArray
import org.json.JSONObject

/**
 * Debug-only measurement journal (spec T15 §5.14): noBackupFilesDir/napstop_trip/journal.ndjson, rotated at 5 MB
 * (journal.1.ndjson keeps the previous part). Lines are written on their own thread, never on the runtime actor.
 * Fields come from the runtime and hold no coordinates, distances or names (L43). Each wake-up / fallback line is
 * followed by an `idle` line with the Doze state.
 * Pull: `adb exec-out run-as app.napstop.dev cat no_backup/napstop_trip/journal.ndjson > journal.ndjson`.
 */
class FileJournal(context: Context) : RuntimeJournal {
    private val ctx = context.applicationContext
    private val dir = File(ctx.noBackupFilesDir, FileRuntimeStore.DIR_NAME)
    private val file = File(dir, FILE_NAME)
    private val executor = Executors.newSingleThreadExecutor { r -> Thread(r, "napstop-journal").apply { isDaemon = true } }
    override val enabled = true

    override fun log(tripMs: Long?, wallMs: Long, ev: String, fields: Map<String, Any?>) {
        val line = JSONObject()
        line.put("t", tripMs ?: JSONObject.NULL)
        line.put("w", wallMs)
        line.put("ev", ev)
        for ((k, v) in fields) line.put(k, json(v))
        val idle = if (ev == "wake_fire" || ev == "fb_fire") idleLine(tripMs, wallMs) else null
        executor.execute { append(line.toString()); idle?.let { append(it) } }
    }

    private fun idleLine(tripMs: Long?, wallMs: Long): String {
        val pm = ctx.getSystemService(PowerManager::class.java)
        val deep = pm?.isDeviceIdleMode ?: false
        val light = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) pm?.isDeviceLightIdleMode ?: false else false
        return JSONObject().put("t", tripMs ?: JSONObject.NULL).put("w", wallMs).put("ev", "idle").put("deep", deep).put("light", light).toString()
    }

    private fun json(v: Any?): Any =
        when (v) {
            null -> JSONObject.NULL
            is List<*> -> JSONArray(v.map { json(it) })
            else -> v
        }

    private fun append(line: String) {
        try {
            if (!dir.isDirectory) dir.mkdirs()
            if (file.length() > MAX_BYTES) file.renameTo(File(dir, "journal.1.ndjson"))
            file.appendText(line + "\n")
        } catch (e: Exception) {
            Log.w(TAG, "journal write failed (${e.javaClass.simpleName})")
        }
    }

    fun clear() {
        executor.execute {
            file.delete()
            File(dir, "journal.1.ndjson").delete()
        }
    }

    companion object {
        private const val TAG = "NapStopDebug"
        const val FILE_NAME = "journal.ndjson"
        private const val MAX_BYTES = 5L * 1024 * 1024
    }
}

/** Looked up by RuntimeHost (reflection, debug builds only): release builds have no journal at all. */
object DebugRuntimeHooks {
    @Volatile
    var journal: FileJournal? = null
        private set

    @JvmStatic
    fun journal(context: Context): RuntimeJournal = FileJournal(context).also { journal = it }
}
