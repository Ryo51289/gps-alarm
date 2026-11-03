package app.napstop.core.bridge.permission

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Small persistent flags of status() (spec T21 §4.1): Android has no "never asked" state,
 * so the app remembers whether it showed each prompt. Excluded from backup and device
 * transfer (§13): restored flags would show `denied` on a new phone.
 */
interface PermissionFlags {
    suspend fun read(): Flags

    suspend fun markLocationRequested()

    suspend fun markNotificationsRequested()

    suspend fun countPreciseAttempt()

    suspend fun resetPreciseAttempts()

    data class Flags(
        val locationRequested: Boolean,
        val notificationsRequested: Boolean,
        val preciseUpgradeAttempts: Int,
    ) {
        companion object {
            val NONE = Flags(locationRequested = false, notificationsRequested = false, preciseUpgradeAttempts = 0)
        }
    }
}

/** [PermissionFlags] in SharedPreferences [PREFS]; every read/write runs on [io] (`commit()`). */
class SharedPrefsPermissionFlags(
    context: Context,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) : PermissionFlags {
    private val appContext = context.applicationContext

    // getSharedPreferences reads the file: only touched on [io].
    private val prefs: SharedPreferences by lazy { appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

    override suspend fun read(): PermissionFlags.Flags =
        withContext(io) {
            PermissionFlags.Flags(
                locationRequested = prefs.getBoolean(KEY_LOCATION, false),
                notificationsRequested = prefs.getBoolean(KEY_NOTIFICATIONS, false),
                preciseUpgradeAttempts = prefs.getInt(KEY_PRECISE, 0),
            )
        }

    override suspend fun markLocationRequested() = edit { putBoolean(KEY_LOCATION, true) }

    override suspend fun markNotificationsRequested() = edit { putBoolean(KEY_NOTIFICATIONS, true) }

    override suspend fun countPreciseAttempt() =
        withContext(io) {
            prefs.edit().putInt(KEY_PRECISE, prefs.getInt(KEY_PRECISE, 0) + 1).commit()
            Unit
        }

    override suspend fun resetPreciseAttempts() = edit { remove(KEY_PRECISE) }

    private suspend fun edit(block: SharedPreferences.Editor.() -> Unit) =
        withContext(io) {
            prefs.edit().apply(block).commit()
            Unit
        }

    companion object {
        /** Also named in res/xml/backup_rules.xml and data_extraction_rules.xml. */
        const val PREFS = "napstop_permissions"
        private const val KEY_LOCATION = "locationRequested"
        private const val KEY_NOTIFICATIONS = "notificationsRequested"
        private const val KEY_PRECISE = "preciseUpgradeAttempts"
    }
}
