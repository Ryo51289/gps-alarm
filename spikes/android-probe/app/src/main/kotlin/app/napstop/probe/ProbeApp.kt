package app.napstop.probe

import android.app.ActivityManager
import android.app.Application
import android.os.Build
import androidx.annotation.RequiresApi
import app.napstop.probe.analysis.AndroidNames
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/** Process start: event log, `proc_start`, ApplicationExitInfo scan, notification channels, alarm tone (S1 §5.4). */
class ProbeApp : Application() {

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun onCreate() {
        super.onCreate()
        EventLog.init(this)
        val store = RunStore(this)
        // Captured now: the service may end the run (e.g. alarm interrupted) before the async exit scan below runs,
        // and the exit must still land in this run, not in orphan.jsonl (S1 5.4).
        val runIdAtStart = store.activeRun()?.runId ?: ""
        EventLog.currentRunId = runIdAtStart

        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        EventLog.log("proc_start", "importance" to state.importance)

        AlarmNotifier.createChannels(this)

        appScope.launch(Dispatchers.IO) {
            if (Build.VERSION.SDK_INT >= 30) logExitReasons(store, runIdAtStart)
            runCatching { AlarmPlayer.ensureWav(this@ProbeApp) }
                .onFailure { EventLog.log("alarm_error", "step" to "wav", "ex" to it.javaClass.name, "msg" to it.message) }
        }
    }

    /** Logs every ApplicationExitInfo newer than the last one already logged (API 30+) [A7]. */
    @RequiresApi(30)
    private fun logExitReasons(store: RunStore, runId: String) {
        val am = getSystemService(ActivityManager::class.java)
        val infos = runCatching { am.getHistoricalProcessExitReasons(packageName, 0, 16) }.getOrNull() ?: return
        val lastTs = store.lastExitTs
        val fresh = infos.filter { it.timestamp > lastTs }.sortedBy { it.timestamp }
        for (info in fresh) {
            EventLog.logTo(
                runId,
                "exit_info",
                linkedMapOf(
                    "reason" to info.reason,
                    "reasonName" to AndroidNames.exitReason(info.reason),
                    "exitTs" to info.timestamp,
                    "desc" to info.description,
                    "importance" to info.importance,
                    "status" to info.status,
                ),
            )
        }
        fresh.maxOfOrNull { it.timestamp }?.let { store.lastExitTs = it }
    }
}
