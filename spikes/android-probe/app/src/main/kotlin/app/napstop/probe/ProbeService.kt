package app.napstop.probe

import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.location.Location
import android.os.BatteryManager
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/**
 * Foreground service of type `location` (S1 §5.4, S2 §5): FLP sparse/dense phases, alarm trigger, self-kill.
 * All mutable state is confined to the `probe-loc` HandlerThread; onStartCommand only calls startForeground and posts.
 * No permanent wakelock (we measure real behaviour); a partial wakelock is held only while the alarm rings.
 */
class ProbeService : Service() {

    private lateinit var store: RunStore
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private lateinit var fused: FusedLocationProviderClient
    private var bootCount = -1

    // probe-loc thread only
    private var cfg: RunConfig? = null
    private var registeredPhase: Phase? = null
    private var prevLocation: Location? = null
    private var lastNotifUpdateElapsed = 0L
    private var receiverRegistered = false
    private var lastBatteryLvl = -1
    private var lastBatteryChg: Boolean? = null
    private var player: AlarmPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var alarmStartElapsed = 0L
    private var selfKillScheduled = false
    private var foreground = false

    private val alarmTimeout = Runnable { stopAlarm(BY_TIMEOUT) }
    private val timerCheck = Runnable { tick(VIA_TIMER) }

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) = onLocations(result.locations)

        override fun onLocationAvailability(availability: LocationAvailability) {
            EventLog.log("loc_avail", "avail" to availability.isLocationAvailable)
        }
    }

    private val stateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = onStateBroadcast(intent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        store = RunStore(this)
        bootCount = DeviceSnapshot.bootCount(this)
        thread = HandlerThread("probe-loc").also { it.start() }
        handler = Handler(thread.looper)
        fused = LocationServices.getFusedLocationProviderClient(this)
        instance = this
        running = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                EventLog.log("svc_cmd", "action" to "stop", "startId" to startId)
                // While ringing: dismiss from this (ringing) process first, then run_stop by=user (S2 §5.2).
                handler.post { if (player != null) stopAlarm(BY_USER_STOP) else finishRun(BY_USER) }
            }
            ACTION_SELF_KILL -> handler.post { onSelfKillCommand(startId) }
            ACTION_DISMISS -> {
                val by = intent.getStringExtra(EXTRA_BY) ?: BY_ACTIVITY
                EventLog.log("svc_cmd", "action" to "dismiss", "by" to by, "startId" to startId)
                handler.post { dismiss(by) }
            }
            else -> startCommand(intent, flags, startId)
        }
        // Always STICKY: the mode of the latest start decides whether the system restarts us after a kill (R1/R2).
        return START_STICKY
    }

    /** Start (user/watchdog/boot) or sticky restart (null intent). startForeground is the very first thing. */
    private fun startCommand(intent: Intent?, flags: Int, startId: Int) {
        val src = if (intent == null) SRC_STICKY else intent.getStringExtra(EXTRA_SRC) ?: SRC_USER
        val trigger = intent?.getStringExtra(EXTRA_TRIGGER)
        val fgError = try {
            ServiceCompat.startForeground(
                this,
                AlarmNotifier.ID_TRACKING,
                AlarmNotifier.trackingNotification(this, getString(R.string.notif_tracking_waiting)),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            )
            null
        } catch (e: Exception) {
            e
        }
        EventLog.log("svc_start_cmd", "src" to src, "flags" to flags, "startId" to startId)
        DeviceSnapshot.logPermSnapshot(this)
        if (fgError != null) {
            EventLog.log("svc_fg_fail", "src" to src, "ex" to fgError.javaClass.name, "msg" to fgError.message)
            stopSelf()
            return
        }
        EventLog.log("svc_fg_ok", "src" to src)
        foreground = true
        handler.post { onStarted(trigger) }
    }

    private fun onStarted(trigger: String?) {
        val c = store.activeRun()
        if (c == null) {
            stopService()
            return
        }
        cfg = c
        EventLog.currentRunId = c.runId
        if (store.alarmFired && player == null) {
            // The process died while the alarm was ringing: do not ring twice (S2 §5.1); end the run.
            EventLog.log("alarm_error", "step" to "interrupted", "ex" to "restart_after_fire", "msg" to null)
            finishRun(BY_AUTO)
            return
        }
        registerStateReceiver()
        if (!c.hasSparsePhase && !store.phaseSwitched) {
            // No sparse phase (S2, R runs): dense from the start; one phase_switch as a common mark for the analyzer.
            store.phaseSwitched = true
            EventLog.log(
                "phase_switch", "from" to Phase.SPARSE.key, "to" to Phase.DENSE.key,
                "boundary" to EventLog.iso(c.startWallMs), "lateMs" to 0L, "via" to VIA_START,
            )
        }
        WatchdogReceiver.schedulePhaseBoundary(this, c, store.phaseSwitched)
        if (trigger == TRIGGER_FALLBACK) triggerAlarm(SRC_FALLBACK)
        tick(VIA_START)
        updateNotification(force = true)
    }

    // ---- location ----

    private fun elapsed(c: RunConfig) = c.elapsedMs(SystemClock.elapsedRealtime(), System.currentTimeMillis(), bootCount)

    /** Registered phase follows the persisted switch, not the clock; the switch itself is logged by checkPhaseSwitch. */
    private fun currentPhase(c: RunConfig): Phase =
        if (!c.hasSparsePhase || store.phaseSwitched) Phase.DENSE else Phase.SPARSE

    /**
     * Sparse -> dense on the first source that sees now >= boundary (S1 5.4): alarm, fix, watchdog, timer or start.
     * Logs phase_switch before re-registering FLP (loc_req phase=dense).
     */
    private fun checkPhaseSwitch(c: RunConfig, via: String) {
        if (!c.hasSparsePhase || store.phaseSwitched) return
        if (c.phaseAt(elapsed(c)) != Phase.DENSE) return
        store.phaseSwitched = true
        EventLog.log(
            "phase_switch", "from" to Phase.SPARSE.key, "to" to Phase.DENSE.key,
            "boundary" to EventLog.iso(c.boundaryWallMs), "lateMs" to System.currentTimeMillis() - c.boundaryWallMs,
            "via" to via,
        )
    }

    private fun ensureLocationUpdates() {
        val c = cfg ?: return
        val phase = currentPhase(c)
        if (phase == registeredPhase) return
        if (registeredPhase != null) fused.removeLocationUpdates(locationCallback)
        registeredPhase = null
        val priority = if (phase == Phase.DENSE) Priority.PRIORITY_HIGH_ACCURACY else Priority.PRIORITY_BALANCED_POWER_ACCURACY
        val request = LocationRequest.Builder(priority, phase.intervalMs)
            .setMinUpdateIntervalMillis(phase.minIntervalMs)
            .setMaxUpdateDelayMillis(0L)
            .build()
        try {
            fused.requestLocationUpdates(request, locationCallback, thread.looper)
                .addOnFailureListener { e ->
                    EventLog.log("loc_req_fail", "ex" to e.javaClass.name, "msg" to e.message)
                    handler.post { if (registeredPhase == phase) registeredPhase = null }
                }
            registeredPhase = phase
            EventLog.log("loc_req", "priority" to phase.priorityName, "intervalMs" to phase.intervalMs, "phase" to phase.key)
        } catch (e: SecurityException) {
            EventLog.log("loc_req_fail", "ex" to e.javaClass.name, "msg" to e.message)
        }
    }

    private fun reregister() {
        if (registeredPhase != null) fused.removeLocationUpdates(locationCallback)
        registeredPhase = null
        ensureLocationUpdates()
    }

    private fun onLocations(locations: List<Location>) {
        cfg ?: return
        val nowEt = SystemClock.elapsedRealtime()
        var n = store.fixCount
        // Privacy (D4): only accuracy, speed, provider, age and distance to the previous fix. Never coordinates.
        for (loc in locations) {
            n++
            val dM = prevLocation?.let { (it.distanceTo(loc) * 10f).roundToInt() / 10.0 }
            EventLog.log(
                "fix",
                "n" to n,
                "acc" to if (loc.hasAccuracy()) loc.accuracy.toDouble() else null,
                "spd" to if (loc.hasSpeed()) loc.speed.toDouble() else null,
                "prov" to loc.provider,
                "ageMs" to nowEt - loc.elapsedRealtimeNanos / 1_000_000L,
                "dM" to dM,
            )
            prevLocation = loc
        }
        if (locations.isNotEmpty()) {
            lastFixElapsed = nowEt
            store.recordFixes(locations.size, System.currentTimeMillis())
        }
        tick(VIA_FIX)
        updateNotification(force = false)
    }

    /** Phase switch, auto stop and (from a fix only) alarm trigger. via: alarm/fix/watchdog/timer/start. */
    private fun tick(via: String) {
        val c = cfg ?: return
        val el = elapsed(c)
        if (c.shouldAutoStop(el)) {
            finishRun(BY_AUTO)
            return
        }
        checkPhaseSwitch(c, via)
        ensureLocationUpdates()
        if (via == VIA_FIX) {
            val deadline = c.deadlineWallMs
            if (deadline != null && System.currentTimeMillis() >= deadline) triggerAlarm(SRC_FIX)
        }
        // Best-effort timer for the next boundary (uptime-based, may be late in deep sleep; fixes/watchdog cover).
        handler.removeCallbacks(timerCheck)
        val boundary = c.boundaryOffsetMs
        val end = c.durationMin * 60_000L
        val next = listOf(boundary, end).filter { it > el }.minOrNull()
        if (next != null) handler.postDelayed(timerCheck, next - el + 1_000L)
    }

    // ---- alarm (S2 §5.2) ----

    private fun triggerAlarm(src: String) {
        val c = cfg ?: return
        if (store.alarmFired || player != null) return
        store.alarmFired = true
        val now = System.currentTimeMillis()
        val deadline = c.deadlineWallMs ?: now
        val pm = getSystemService(PowerManager::class.java)
        val km = getSystemService(KeyguardManager::class.java)
        val interactive = pm.isInteractive
        interactiveAtTrigger = interactive
        EventLog.log(
            "alarm_trigger",
            "src" to src,
            "planned" to EventLog.iso(deadline),
            "lateMs" to now - deadline,
            "interactive" to interactive,
            "keyguardLocked" to km.isKeyguardLocked,
            "idle" to pm.isDeviceIdleMode,
        )
        DeviceSnapshot.logPermSnapshot(this)
        alarmStep("wakelock") {
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "probe:alarm").apply {
                setReferenceCounted(false)
                acquire(ALARM_WAKELOCK_MS)
            }
        }
        alarmStartElapsed = SystemClock.elapsedRealtime()
        player = AlarmPlayer(this, handler).also { it.start() }
        alarmActiveFlow.value = true
        alarmStep("notif") {
            val nm = getSystemService(NotificationManager::class.java)
            // Never startActivity from the service (background activity start limits); FSI only (S2 §4.1 [N3]).
            nm.notify(AlarmNotifier.ID_ALARM, AlarmNotifier.alarmNotification(this, clock(deadline), src))
            EventLog.log(
                "alarm_notif_posted",
                "fsiAllowed" to DeviceSnapshot.permState(this).let { it.fsi ?: true },
                "notifEnabled" to nm.areNotificationsEnabled(),
                "chAlarmImp" to nm.getNotificationChannel(AlarmNotifier.CHANNEL_ALARM)?.importance,
            )
        }
        handler.postDelayed(alarmTimeout, ALARM_TIMEOUT_MS)
    }

    private fun dismiss(by: String) {
        if (player != null) {
            stopAlarm(by)
        } else {
            // Stale notification (alarm no longer ringing in this process).
            getSystemService(NotificationManager::class.java).cancel(AlarmNotifier.ID_ALARM)
            alarmActiveFlow.value = false
            if (store.activeRun() != null) finishRun(BY_AUTO) else stopService()
        }
    }

    private fun stopAlarm(by: String) {
        silenceAlarm()
        EventLog.log("alarm_dismissed", "by" to by, "afterMs" to SystemClock.elapsedRealtime() - alarmStartElapsed)
        finishRun(
            when (by) {
                BY_TIMEOUT -> STOP_ALARM_TIMEOUT
                BY_USER_STOP -> BY_USER
                else -> STOP_ALARM_DISMISSED
            },
        )
    }

    private fun silenceAlarm() {
        handler.removeCallbacks(alarmTimeout)
        player?.stop()
        player = null
        alarmStep("cancel_notif") {
            getSystemService(NotificationManager::class.java).cancel(AlarmNotifier.ID_ALARM)
        }
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        alarmActiveFlow.value = false
    }

    private inline fun alarmStep(step: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            EventLog.log("alarm_error", "step" to step, "ex" to e.javaClass.name, "msg" to e.message)
        }
    }

    // ---- run end, self kill ----

    /** Ends the run (ACTION_STOP, auto end, alarm dismissed/timeout) and stops the service. */
    private fun finishRun(by: String) {
        if (player != null) silenceAlarm()
        WatchdogReceiver.cancelAll(this)
        if (registeredPhase != null) fused.removeLocationUpdates(locationCallback)
        registeredPhase = null
        handler.removeCallbacks(timerCheck)
        if (store.activeRun() != null || cfg != null) {
            EventLog.log("run_stop", "by" to by)
            store.clearRun()
        }
        cfg = null
        EventLog.currentRunId = ""
        stopService()
    }

    private fun stopService() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** Ignored (logged) when no run is active or the service is not in the foreground (S1 5.5). */
    private fun onSelfKillCommand(startId: Int) {
        if (cfg == null || !foreground) {
            EventLog.log("svc_cmd", "action" to "self_kill", "startId" to startId, "ignored" to true)
            if (cfg == null && !foreground) stopSelf()
            return
        }
        EventLog.log("svc_cmd", "action" to "self_kill", "startId" to startId)
        scheduleSelfKill()
    }

    private fun scheduleSelfKill() {
        if (selfKillScheduled) return
        selfKillScheduled = true
        EventLog.log("self_kill_scheduled", "delayMs" to SELF_KILL_DELAY_MS)
        handler.postDelayed({
            EventLog.log("self_kill_now")
            EventLog.syncBlocking()
            Process.killProcess(Process.myPid())
        }, SELF_KILL_DELAY_MS)
    }

    // ---- device state broadcasts (registered only while the service runs) ----

    private fun registerStateReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            addAction(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        ContextCompat.registerReceiver(this, stateReceiver, filter, null, handler, ContextCompat.RECEIVER_NOT_EXPORTED)
        receiverRegistered = true
    }

    private fun onStateBroadcast(intent: Intent) {
        val pm = getSystemService(PowerManager::class.java)
        when (intent.action) {
            Intent.ACTION_SCREEN_ON -> EventLog.log("screen", "on" to true)
            Intent.ACTION_SCREEN_OFF -> EventLog.log("screen", "on" to false)
            PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> EventLog.log("idle", "on" to pm.isDeviceIdleMode)
            PowerManager.ACTION_POWER_SAVE_MODE_CHANGED -> EventLog.log("power_save", "on" to pm.isPowerSaveMode)
            Intent.ACTION_BATTERY_CHANGED -> {
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
                val lvl = if (level >= 0 && scale > 0) level * 100 / scale else -1
                val chg = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
                if (lvl != lastBatteryLvl || chg != lastBatteryChg) {
                    lastBatteryLvl = lvl
                    lastBatteryChg = chg
                    EventLog.log("battery", "lvl" to lvl, "chg" to chg)
                }
            }
        }
    }

    private fun updateNotification(force: Boolean) {
        val c = cfg ?: return
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastNotifUpdateElapsed < NOTIF_UPDATE_MS) return
        lastNotifUpdateElapsed = now
        val last = store.lastFixWallMs
        val text = if (last == null) {
            getString(R.string.notif_tracking_text_nofix, c.runId)
        } else {
            getString(R.string.notif_tracking_text, c.runId, store.fixCount, clock(last))
        }
        runCatching {
            getSystemService(NotificationManager::class.java)
                .notify(AlarmNotifier.ID_TRACKING, AlarmNotifier.trackingNotification(this, text))
        }
    }

    // ---- lifecycle ----

    override fun onTaskRemoved(rootIntent: Intent?) {
        EventLog.log("svc_task_removed")
        super.onTaskRemoved(rootIntent)
    }

    /** API 35+. Not expected for type `location` (no FGS timeout); the system requires stopping if it happens. */
    override fun onTimeout(startId: Int, fgsType: Int) {
        EventLog.log("svc_timeout", "startId" to startId, "fgsType" to fgsType)
        stopSelf()
    }

    override fun onDestroy() {
        EventLog.log("svc_destroy")
        running = false
        instance = null
        handler.post {
            if (player != null) silenceAlarm()
            if (registeredPhase != null) fused.removeLocationUpdates(locationCallback)
            registeredPhase = null
            if (receiverRegistered) runCatching { unregisterReceiver(stateReceiver) }
            receiverRegistered = false
            handler.removeCallbacksAndMessages(null)
            thread.quitSafely()
        }
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "app.napstop.probe.action.START"
        const val ACTION_STOP = "app.napstop.probe.action.STOP"
        const val ACTION_SELF_KILL = "app.napstop.probe.action.SELF_KILL"
        const val ACTION_DISMISS = "app.napstop.probe.action.DISMISS"
        const val EXTRA_SRC = "src"
        const val EXTRA_TRIGGER = "trigger"
        const val EXTRA_BY = "by"

        const val SRC_USER = "user"
        const val SRC_STICKY = "sticky"
        const val SRC_WATCHDOG = "watchdog"
        const val SRC_PHASE_ALARM = "phase_alarm"
        const val SRC_ALARM_FALLBACK = "alarm_fallback"
        const val SRC_BOOT = "boot"
        const val SRC_PKG_REPLACED = "pkg_replaced"
        const val SRC_FIX = "fix"
        const val SRC_FALLBACK = "fallback"
        const val TRIGGER_FALLBACK = "fallback"

        const val VIA_ALARM = "alarm"
        const val VIA_FIX = "fix"
        const val VIA_WATCHDOG = "watchdog"
        const val VIA_TIMER = "timer"
        const val VIA_START = "start"

        const val BY_USER = "user"
        const val BY_AUTO = "auto"
        const val BY_ACTIVITY = "activity"
        const val BY_NOTIF_ACTION = "notif_action"
        const val BY_TIMEOUT = "timeout"
        const val BY_USER_STOP = "user_stop"
        private const val STOP_ALARM_DISMISSED = "alarm_dismissed"
        private const val STOP_ALARM_TIMEOUT = "alarm_timeout"

        private const val ALARM_WAKELOCK_MS = 10 * 60_000L
        private const val ALARM_TIMEOUT_MS = 5 * 60_000L
        private const val SELF_KILL_DELAY_MS = 60_000L
        private const val NOTIF_UPDATE_MS = 60_000L
        private val CLOCK: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm:ss")

        /** True while a service instance exists in this process (watchdog `alive`). */
        @Volatile
        var running = false
            private set

        /** elapsedRealtime of the last fix in this process (0 = none). */
        @Volatile
        var lastFixElapsed = 0L
            private set

        /** Screen state when the alarm fired, for AlarmActivity's `viaFsi`. */
        @Volatile
        var interactiveAtTrigger: Boolean? = null
            private set

        @Volatile
        private var instance: ProbeService? = null

        private val alarmActiveFlow = MutableStateFlow(false)
        val alarmActive: StateFlow<Boolean> get() = alarmActiveFlow

        fun clock(epochMs: Long): String =
            Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault()).format(CLOCK)

        fun startIntent(context: Context, src: String, trigger: String? = null): Intent =
            Intent(context, ProbeService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_SRC, src)
                .apply { if (trigger != null) putExtra(EXTRA_TRIGGER, trigger) }

        fun stopIntent(context: Context): Intent = Intent(context, ProbeService::class.java).setAction(ACTION_STOP)

        fun selfKillIntent(context: Context): Intent =
            Intent(context, ProbeService::class.java).setAction(ACTION_SELF_KILL)

        fun dismissIntent(context: Context, by: String): Intent =
            Intent(context, ProbeService::class.java).setAction(ACTION_DISMISS).putExtra(EXTRA_BY, by)

        /**
         * Starts a run (S1 §5.5). Must be called while an activity of the app is visible: a `location` FGS needs
         * the while-in-use exemption [A1][A2].
         */
        fun startRun(context: Context, cfg: RunConfig) {
            RunStore(context).startRun(cfg)
            EventLog.currentRunId = cfg.runId
            val fields = linkedMapOf<String, Any?>(
                "kind" to cfg.kind,
                "label" to cfg.label,
                "durationMin" to cfg.durationMin,
                "densePhaseMin" to cfg.densePhaseMin,
                "alarmAtEnd" to cfg.alarmAtEnd,
                "watchdog" to cfg.watchdog,
                "delayMin" to cfg.delayMin,
                "scenario" to cfg.scenario,
            )
            fields.putAll(DeviceSnapshot.device(context))
            EventLog.log("run_start", fields)
            DeviceSnapshot.logPermSnapshot(context)
            if (cfg.watchdog) WatchdogReceiver.scheduleWatchdog(context)
            WatchdogReceiver.schedulePhaseBoundary(context, cfg, phaseSwitched = false)
            if (cfg.alarmEnabled) WatchdogReceiver.scheduleFallback(context, cfg)
            ContextCompat.startForegroundService(context, startIntent(context, SRC_USER))
        }

        /** Watchdog tick in a process where the service is alive. Returns false if there is no live service. */
        fun watchdogTick(): Boolean {
            val s = instance ?: return false
            s.handler.post { s.tick(VIA_WATCHDOG) }
            return true
        }

        /**
         * PHASE_BOUNDARY delivered to a live service: switch on probe-loc, then run done (finishes the async broadcast).
         * Returns false if there is no live service (done is then the caller's job).
         */
        fun phaseTick(done: Runnable): Boolean {
            val s = instance ?: return false
            s.handler.post {
                try {
                    s.tick(VIA_ALARM)
                } finally {
                    done.run()
                }
            }
            return true
        }

        fun requestReregister() {
            val s = instance ?: return
            s.handler.post { s.reregister() }
        }

        /** Fallback alarm (S2 §5.1) delivered to a live service. Returns false if there is no live service. */
        fun triggerFallback(): Boolean {
            val s = instance ?: return false
            s.handler.post { s.triggerAlarm(SRC_FALLBACK) }
            return true
        }
    }
}
