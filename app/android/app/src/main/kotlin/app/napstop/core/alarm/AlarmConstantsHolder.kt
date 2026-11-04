package app.napstop.core.alarm

import android.content.Context
import app.napstop.BuildConfig
import java.io.File

/**
 * [AlarmConstants] of a process. Debug builds only: `ring_max_override --ei seconds N` (DebugCommandReceiver) writes
 * `no_backup/napstop_ring/debug_ring_max_s`, read by each process when it builds its controller / ring session (both
 * processes see the same value). Release builds never read the file.
 */
object AlarmConstantsHolder {
    const val RING_MAX_OVERRIDE_FILE = "debug_ring_max_s"

    fun load(context: Context): AlarmConstants {
        if (!BuildConfig.DEBUG) return AlarmConstants()
        return try {
            val f = overrideFile(context)
            val s = if (f.isFile) f.readText().trim().toLongOrNull() ?: 0L else 0L
            if (s > 0) AlarmConstants(ringMaxMs = s * 1000L) else AlarmConstants()
        } catch (e: Exception) {
            AlarmConstants()
        }
    }

    fun overrideFile(context: Context): File = File(File(context.noBackupFilesDir, RingFactsStore.DIR_NAME), RING_MAX_OVERRIDE_FILE)
}
