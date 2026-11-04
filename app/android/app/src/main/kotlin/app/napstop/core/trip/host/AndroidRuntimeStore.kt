package app.napstop.core.trip.host

import android.content.Context
import app.napstop.BuildConfig
import app.napstop.core.trip.runtime.FallbackLedger
import app.napstop.core.trip.runtime.FileRuntimeStore
import app.napstop.core.trip.runtime.RuntimeStore
import app.napstop.core.trip.runtime.StoredTrip
import java.io.File
import java.io.IOException

/** Debug-only fault switches (set by DebugCommandReceiver over adb, spec T15 §5.14). Never set in release builds. */
object RuntimeDebugFlags {
    /** `snapshot_fail on`: every snapshot write throws IOException (protocol LM7). */
    @Volatile
    var snapshotFail = false

    /** `ring_fail on`: AlarmController.ringNow throws (protocol LM7, ring guard). */
    @Volatile
    var ringFail = false
}

/**
 * The runtime store in noBackupFilesDir/napstop_trip (spec T15 §5.7): excluded from Auto Backup and device transfer
 * by the platform even with an include rule [A-BAK]. The debug fault switch wraps only the snapshot write.
 */
class AndroidRuntimeStore private constructor(private val files: FileRuntimeStore, private val slowReadFile: File?) : RuntimeStore by files {
    override fun writeActive(t: StoredTrip) {
        if (RuntimeDebugFlags.snapshotFail) throw IOException("debug snapshot_fail")
        files.writeActive(t)
    }

    override fun readActive(): StoredTrip? {
        slowRead()
        return files.readActive()
    }

    override fun readLedger(): FallbackLedger {
        slowRead()
        return files.readLedger()
    }

    /**
     * Debug `slow_read <ms>` (protocol LM6, reboot on a slow disk): the delay is kept in a file so it applies right after a
     * reboot, before anything else can set it. Release builds pass no file.
     */
    private fun slowRead() {
        val f = slowReadFile ?: return
        val ms = if (f.isFile) f.readText().trim().toLongOrNull() ?: 0L else 0L
        if (ms > 0) Thread.sleep(ms)
    }

    companion object {
        const val SLOW_READ_FILE = "debug_slow_read_ms"

        fun create(context: Context, warn: (String) -> Unit): AndroidRuntimeStore {
            val dir = File(context.noBackupFilesDir, FileRuntimeStore.DIR_NAME)
            return AndroidRuntimeStore(FileRuntimeStore(dir, warn), if (BuildConfig.DEBUG) File(dir, SLOW_READ_FILE) else null)
        }
    }
}
