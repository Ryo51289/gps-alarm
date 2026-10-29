package app.napstop.probe

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.ServiceCompat

/**
 * Fallback alarm without the `location` FGS (docs/spikes/S2.md "Vòng 4" V4-1). Started by WatchdogReceiver on ALARM_FALLBACK
 * when ProbeService is not alive: an exact alarm may start an FGS from the background, but not one that needs a
 * while-in-use permission such as `location` [A1][A2]. Tries `systemExempted` (app holds USE_EXACT_ALARM) then
 * `mediaPlayback`; which one works is data for T16/S5. START_NOT_STICKY: a death while ringing is cleaned up at the next run.
 * Mutable state lives on the `probe-ring` HandlerThread; onStartCommand only calls startForeground and posts.
 */
class AlarmRingService : Service() {

    private lateinit var store: RunStore
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler

    // probe-ring thread only
    private var player: AlarmPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var alarmStartElapsed = 0L

    private val alarmTimeout = Runnable { stop(ProbeService.BY_TIMEOUT) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = RunStore(this)
        thread = HandlerThread("probe-ring").also { it.start() }
        handler = Handler(thread.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_RING -> startRing()
            ProbeService.ACTION_DISMISS -> {
                val by = intent.getStringExtra(ProbeService.EXTRA_BY) ?: ProbeService.BY_ACTIVITY
                EventLog.log("svc_cmd", "action" to "dismiss", "by" to by, "startId" to startId)
                handler.post { stop(by) }
            }
            ProbeService.ACTION_STOP -> {
                EventLog.log("svc_cmd", "action" to "stop", "startId" to startId)
                handler.post { stop(BY_USER_STOP) }
            }
            else -> handler.post { stop(ProbeService.BY_AUTO) }
        }
        return START_NOT_STICKY
    }

    /** startForeground is the very first thing (FGS start deadline), one type after the other. */
    private fun startRing() {
        val deadline = store.activeRun()?.deadlineWallMs ?: System.currentTimeMillis()
        val notif = AlarmNotifier.alarmNotification(
            this, ProbeService.clock(deadline), ProbeService.SRC_FALLBACK, AlarmRingService::class.java,
        )
        var fgType: String? = null
        var lastError: Exception? = null
        for (name in AlarmRoute.ringFgsTypes(Build.VERSION.SDK_INT)) {
            try {
                ServiceCompat.startForeground(this, AlarmNotifier.ID_ALARM, notif, typeConst(name))
                EventLog.log("alarm_ring_fg", "type" to name, "ok" to true)
                fgType = name
                break
            } catch (e: Exception) {
                lastError = e
                EventLog.log("alarm_ring_fg", "type" to name, "ok" to false, "ex" to e.javaClass.name, "msg" to e.message)
            }
        }
        // The FGS notification (with its full-screen intent) is already posted: mark the alarm active before
        // AlarmActivity can start, or its onStart would close it at once. ring() clears it if the alarm is ignored.
        if (fgType != null) AlarmState.claim(AlarmState.OWNER_RING)
        val failure = lastError
        handler.post { ring(fgType, failure, notif, deadline) }
    }

    private fun ring(fgType: String?, failure: Exception?, notif: Notification, deadline: Long) {
        val cfg = store.activeRun()
        if (cfg == null || store.alarmFired) {
            EventLog.log("svc_cmd", "action" to "ring", "ignored" to true)
            AlarmState.clear(AlarmState.OWNER_RING)
            stopService()
            return
        }
        store.alarmFired = true
        EventLog.currentRunId = cfg.runId
        val nm = getSystemService(NotificationManager::class.java)
        AlarmEvents.trigger(this, ProbeService.SRC_FALLBACK, AlarmState.OWNER_RING, deadline, System.currentTimeMillis())
        if (fgType == null) {
            // Every FGS type failed: no sound without an FGS (a background service must not play, and stopping is the
            // only way out of the startForeground deadline). Post the notification as a best effort.
            EventLog.log("alarm_error", "step" to "ring_fg", "ex" to failure?.javaClass?.name, "msg" to failure?.message)
            alarmStep("notif") {
                nm.notify(AlarmNotifier.ID_ALARM, notif)
                AlarmEvents.notifPosted(this, nm)
            }
            stopSelf()
            return
        }
        alarmStep("wakelock") {
            wakeLock = getSystemService(PowerManager::class.java)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "probe:alarm")
                .apply {
                    setReferenceCounted(false)
                    acquire(ALARM_WAKELOCK_MS)
                }
        }
        alarmStartElapsed = SystemClock.elapsedRealtime()
        player = AlarmPlayer(this, handler).also { it.start() }
        AlarmState.set(AlarmState.OWNER_RING)
        alarmStep("notif") { AlarmEvents.notifPosted(this, nm) }
        handler.postDelayed(alarmTimeout, ALARM_TIMEOUT_MS)
    }

    private fun stop(by: String) {
        val p = player
        if (p == null) {
            // Not ringing (stale notification, ignored ring): only clean up.
            alarmStep("cancel_notif") { getSystemService(NotificationManager::class.java).cancel(AlarmNotifier.ID_ALARM) }
            stopService()
            return
        }
        handler.removeCallbacks(alarmTimeout)
        p.stop()
        player = null
        releaseWakeLock()
        AlarmState.clear(AlarmState.OWNER_RING)
        EventLog.log("alarm_dismissed", "by" to by, "afterMs" to SystemClock.elapsedRealtime() - alarmStartElapsed)
        WatchdogReceiver.cancelAll(this)
        EventLog.log(
            "run_stop",
            "by" to when (by) {
                ProbeService.BY_TIMEOUT -> STOP_ALARM_TIMEOUT
                BY_USER_STOP -> ProbeService.BY_USER
                else -> STOP_ALARM_DISMISSED
            },
        )
        store.clearRun()
        EventLog.currentRunId = ""
        stopService()
        alarmStep("cancel_notif") { getSystemService(NotificationManager::class.java).cancel(AlarmNotifier.ID_ALARM) }
    }

    private fun stopService() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private inline fun alarmStep(step: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            EventLog.log("alarm_error", "step" to step, "ex" to e.javaClass.name, "msg" to e.message)
        }
    }

    /** API 35+. Not expected for systemExempted/mediaPlayback (no FGS timeout); the system requires stopping if it happens. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        EventLog.log("svc_timeout", "startId" to startId, "fgsType" to fgsType)
        handler.post { stop(ProbeService.BY_TIMEOUT) }
    }

    /** Still ringing here = the service is being torn down without a dismissal: silence only (the analyzer sees no
     * `alarm_dismissed` and reports the alarm as interrupted). */
    override fun onDestroy() {
        handler.post {
            handler.removeCallbacksAndMessages(null)
            player?.stop()
            player = null
            releaseWakeLock()
            AlarmState.clear(AlarmState.OWNER_RING)
            thread.quitSafely()
        }
        super.onDestroy()
    }

    companion object {
        const val ACTION_RING = "app.napstop.probe.action.RING"
        private const val BY_USER_STOP = ProbeService.BY_USER_STOP
        private const val STOP_ALARM_DISMISSED = "alarm_dismissed"
        private const val STOP_ALARM_TIMEOUT = "alarm_timeout"
        private const val ALARM_WAKELOCK_MS = 10 * 60_000L
        private const val ALARM_TIMEOUT_MS = 5 * 60_000L

        // Each constant is only used on the API level that has it (AlarmRoute.ringFgsTypes); on API < 29 ServiceCompat
        // ignores the type.
        @SuppressLint("InlinedApi")
        private fun typeConst(name: String): Int = when (name) {
            AlarmRoute.TYPE_SYSTEM_EXEMPTED -> ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED
            AlarmRoute.TYPE_MEDIA_PLAYBACK -> ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            else -> 0
        }

        fun ringIntent(context: Context): Intent = Intent(context, AlarmRingService::class.java).setAction(ACTION_RING)

        fun stopIntent(context: Context): Intent =
            Intent(context, AlarmRingService::class.java).setAction(ProbeService.ACTION_STOP)

        fun dismissIntent(context: Context, by: String): Intent =
            Intent(context, AlarmRingService::class.java)
                .setAction(ProbeService.ACTION_DISMISS)
                .putExtra(ProbeService.EXTRA_BY, by)
    }
}
