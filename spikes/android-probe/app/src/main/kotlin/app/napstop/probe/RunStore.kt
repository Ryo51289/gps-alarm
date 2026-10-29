package app.napstop.probe

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/** Location sampling phase (S1 §4.3). */
enum class Phase(val key: String, val priorityName: String, val intervalMs: Long, val minIntervalMs: Long) {
    SPARSE("sparse", "BALANCED", 180_000L, 90_000L),
    DENSE("dense", "HIGH", 10_000L, 5_000L),
}

/**
 * The run in progress. Pure Kotlin (unit-tested); persisted by [RunStore].
 * S2 runs use durationMin = densePhaseMin = delayMin, so they are dense for the whole run.
 */
data class RunConfig(
    val runId: String,
    val kind: String,
    val label: String,
    val durationMin: Int,
    val densePhaseMin: Int,
    val alarmAtEnd: Boolean,
    val watchdog: Boolean,
    val delayMin: Int?,
    val scenario: String?,
    val startWallMs: Long,
    val startElapsed: Long,
    val bootCount: Int,
) {
    val alarmEnabled: Boolean get() = kind == KIND_S2 || alarmAtEnd

    val plannedEndWallMs: Long get() = startWallMs + durationMin * 60_000L

    /** True if the run starts with a sparse phase (S2 and "dense = duration" runs are dense from the start). */
    val hasSparsePhase: Boolean get() = densePhaseMin < durationMin

    /** Planned sparse → dense boundary, ms after start (meaningful only if [hasSparsePhase]). */
    val boundaryOffsetMs: Long get() = (durationMin - densePhaseMin) * 60_000L

    val boundaryWallMs: Long get() = startWallMs + boundaryOffsetMs

    /**
     * elapsedRealtime of the boundary for an ELAPSED_REALTIME_WAKEUP alarm (S1 §5.4): from startElapsed in the same boot,
     * otherwise `nowElapsed + (boundaryWall − now)`.
     */
    fun boundaryElapsed(nowElapsed: Long, nowWallMs: Long, currentBootCount: Int): Long =
        if (bootCount >= 0 && bootCount == currentBootCount) {
            startElapsed + boundaryOffsetMs
        } else {
            nowElapsed + (boundaryWallMs - nowWallMs)
        }

    /** Alarm deadline (wall clock), or null when the run has no alarm. */
    val deadlineWallMs: Long?
        get() = when {
            kind == KIND_S2 -> startWallMs + (delayMin ?: durationMin) * 60_000L
            alarmAtEnd -> plannedEndWallMs
            else -> null
        }

    /**
     * Time since run start. Uses elapsedRealtime while still in the same boot (immune to clock changes);
     * after a reboot elapsedRealtime restarts, so fall back to wall clock (S1 §5.4).
     */
    fun elapsedMs(nowElapsed: Long, nowWallMs: Long, currentBootCount: Int): Long =
        if (bootCount >= 0 && bootCount == currentBootCount) nowElapsed - startElapsed else nowWallMs - startWallMs

    /** Phase by the clock only (the service switches on the first source that sees this, see ProbeService). */
    fun phaseAt(elapsedMs: Long): Phase =
        if (elapsedMs >= boundaryOffsetMs) Phase.DENSE else Phase.SPARSE

    /** Runs without an alarm stop by themselves at the planned end (`run_stop by=auto`). */
    fun shouldAutoStop(elapsedMs: Long): Boolean = !alarmEnabled && elapsedMs >= durationMin * 60_000L

    companion object {
        const val KIND_S1 = "S1"
        const val KIND_S2 = "S2"
        private val ID_TIME: DateTimeFormatter = DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")

        /** `yyyyMMdd-HHmmss-<kind>-<label>`; an S2 label "S2-3" gives "...-S2-3" (no doubled kind). */
        fun makeRunId(localTime: LocalDateTime, kind: String, label: String): String {
            val cleanLabel = label.removePrefix("$kind-").replace(Regex("[^A-Za-z0-9_-]"), "_")
            return "${localTime.format(ID_TIME)}-$kind-$cleanLabel"
        }
    }
}

/** SharedPreferences store for the active run and a few counters that must survive process death. */
class RunStore(context: Context) {
    private val prefs: SharedPreferences = context.getSharedPreferences("probe_run", Context.MODE_PRIVATE)

    fun activeRun(): RunConfig? {
        val runId = prefs.getString(K_RUN_ID, null) ?: return null
        return RunConfig(
            runId = runId,
            kind = prefs.getString(K_KIND, RunConfig.KIND_S1) ?: RunConfig.KIND_S1,
            label = prefs.getString(K_LABEL, "") ?: "",
            durationMin = prefs.getInt(K_DURATION, 0),
            densePhaseMin = prefs.getInt(K_DENSE, 0),
            alarmAtEnd = prefs.getBoolean(K_ALARM_AT_END, false),
            watchdog = prefs.getBoolean(K_WATCHDOG, true),
            delayMin = if (prefs.contains(K_DELAY)) prefs.getInt(K_DELAY, 0) else null,
            scenario = prefs.getString(K_SCENARIO, null),
            startWallMs = prefs.getLong(K_START_WALL, 0L),
            startElapsed = prefs.getLong(K_START_ELAPSED, 0L),
            bootCount = prefs.getInt(K_BOOT_COUNT, -1),
        )
    }

    /** Saves a new run and resets the per-run counters. */
    fun startRun(cfg: RunConfig) {
        prefs.edit {
            putString(K_RUN_ID, cfg.runId)
            putString(K_KIND, cfg.kind)
            putString(K_LABEL, cfg.label)
            putInt(K_DURATION, cfg.durationMin)
            putInt(K_DENSE, cfg.densePhaseMin)
            putBoolean(K_ALARM_AT_END, cfg.alarmAtEnd)
            putBoolean(K_WATCHDOG, cfg.watchdog)
            if (cfg.delayMin != null) putInt(K_DELAY, cfg.delayMin) else remove(K_DELAY)
            putString(K_SCENARIO, cfg.scenario)
            putLong(K_START_WALL, cfg.startWallMs)
            putLong(K_START_ELAPSED, cfg.startElapsed)
            putInt(K_BOOT_COUNT, cfg.bootCount)
            putBoolean(K_ALARM_FIRED, false)
            putBoolean(K_PHASE_SWITCHED, false)
            putInt(K_FIX_COUNT, 0)
            remove(K_LAST_FIX_WALL)
        }
    }

    /** Clears the active run. Synchronous commit: callers run off the main thread or right before exit. */
    fun clearRun() {
        prefs.edit(commit = true) {
            listOf(
                K_RUN_ID, K_KIND, K_LABEL, K_DURATION, K_DENSE, K_ALARM_AT_END, K_WATCHDOG, K_DELAY, K_SCENARIO,
                K_START_WALL, K_START_ELAPSED, K_BOOT_COUNT, K_ALARM_FIRED, K_PHASE_SWITCHED, K_FIX_COUNT,
                K_LAST_FIX_WALL,
            ).forEach { remove(it) }
        }
    }

    var alarmFired: Boolean
        get() = prefs.getBoolean(K_ALARM_FIRED, false)
        set(value) {
            // commit(): must be durable before the alarm starts (no double alarm after process death, S2 §5.1).
            prefs.edit(commit = true) { putBoolean(K_ALARM_FIRED, value) }
        }

    /** Sparse → dense switch done (S1 §5.4); durable so a restarted service knows the phase and never switches twice. */
    var phaseSwitched: Boolean
        get() = prefs.getBoolean(K_PHASE_SWITCHED, false)
        set(value) {
            prefs.edit(commit = true) { putBoolean(K_PHASE_SWITCHED, value) }
        }

    val fixCount: Int get() = prefs.getInt(K_FIX_COUNT, 0)

    val lastFixWallMs: Long? get() = if (prefs.contains(K_LAST_FIX_WALL)) prefs.getLong(K_LAST_FIX_WALL, 0L) else null

    fun recordFixes(count: Int, lastWallMs: Long) {
        prefs.edit {
            putInt(K_FIX_COUNT, fixCount + count)
            putLong(K_LAST_FIX_WALL, lastWallMs)
        }
    }

    /** Timestamp of the newest ApplicationExitInfo already logged (global, not per run). */
    var lastExitTs: Long
        get() = prefs.getLong(K_LAST_EXIT_TS, 0L)
        set(value) {
            prefs.edit { putLong(K_LAST_EXIT_TS, value) }
        }

    private companion object {
        const val K_RUN_ID = "runId"
        const val K_KIND = "kind"
        const val K_LABEL = "label"
        const val K_DURATION = "durationMin"
        const val K_DENSE = "densePhaseMin"
        const val K_ALARM_AT_END = "alarmAtEnd"
        const val K_WATCHDOG = "watchdog"
        const val K_DELAY = "delayMin"
        const val K_SCENARIO = "scenario"
        const val K_START_WALL = "startWallMs"
        const val K_START_ELAPSED = "startElapsed"
        const val K_BOOT_COUNT = "bootCount"
        const val K_ALARM_FIRED = "alarmFired"
        const val K_PHASE_SWITCHED = "phaseSwitched"
        const val K_FIX_COUNT = "fixCount"
        const val K_LAST_FIX_WALL = "lastFixWallMs"
        const val K_LAST_EXIT_TS = "lastExitTs"
    }
}
