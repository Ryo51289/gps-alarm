package app.napstop.probe

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Exact alarms of a run: watchdog every 15 min (S1 §5.4), sparse → dense phase boundary (S1 §5.4) and the alarm fallback at
 * deadline + 60 s (S2 §5.1). Exact alarms are exempt from the FGS background-start restriction [A6], but not from the
 * while-in-use rule of a `location` FGS [A2]: restarts from here fail without background location (that is R2 data).
 */
class WatchdogReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val store = RunStore(context)
        val cfg = store.activeRun() ?: return
        when (intent.action) {
            ACTION_WATCHDOG -> onWatchdog(context, store, cfg)
            ACTION_PHASE_BOUNDARY -> onPhaseBoundary(context, cfg)
            ACTION_ALARM_FALLBACK -> onFallback(context, store)
        }
    }

    private fun onWatchdog(context: Context, store: RunStore, cfg: RunConfig) {
        if (!cfg.watchdog) return
        val alive = ProbeService.running
        val now = System.currentTimeMillis()
        val lastFixAgeS = ((now - (store.lastFixWallMs ?: cfg.startWallMs)) / 1000L).coerceAtLeast(0L)
        val phase = if (store.phaseSwitched || !cfg.hasSparsePhase) Phase.DENSE else Phase.SPARSE
        val stalled = alive && lastFixAgeS * 1000L > 3 * phase.intervalMs
        val action = when {
            !alive -> "restart"
            stalled -> "reregister"
            else -> "none"
        }
        EventLog.log("wd_tick", "alive" to alive, "lastFixAgeS" to lastFixAgeS, "action" to action)
        when (action) {
            "restart" -> startService(context, ProbeService.SRC_WATCHDOG, FOR_WATCHDOG)
            "reregister" -> {
                EventLog.log("fix_stall", "ageS" to lastFixAgeS)
                ProbeService.requestReregister()
            }
        }
        if (alive) ProbeService.watchdogTick()
        scheduleWatchdog(context)
    }

    /**
     * PHASE_BOUNDARY (S1 §5.4): goAsync() so the switch can finish on `probe-loc`; the system expects broadcasts to complete
     * in under 10 s [A14], so a 5 s safety timer finishes the broadcast in any case. Service dead: restart with
     * src=phase_alarm only if the run has the watchdog on (a run without watchdog must measure "no rescue but sticky/boot").
     */
    private fun onPhaseBoundary(context: Context, cfg: RunConfig) {
        val alive = ProbeService.running
        val action = when {
            alive -> "switch"
            cfg.watchdog -> "restart"
            else -> "none"
        }
        EventLog.log(
            "phase_alarm",
            "lateMs" to System.currentTimeMillis() - cfg.boundaryWallMs,
            "alive" to alive,
            "action" to action,
        )
        if (!alive) {
            // A fresh service starts directly in the dense phase (via=start).
            if (action == "restart") startService(context, ProbeService.SRC_PHASE_ALARM, FOR_PHASE_BOUNDARY)
            return
        }
        val pending = goAsync()
        val finished = AtomicBoolean(false)
        val finish = Runnable { if (finished.compareAndSet(false, true)) pending.finish() }
        Handler(Looper.getMainLooper()).postDelayed(finish, PHASE_FINISH_TIMEOUT_MS)
        if (!ProbeService.phaseTick(finish)) finish.run()
    }

    /**
     * ALARM_FALLBACK (S2 §5.1, Vòng 4 V4-1). Always, even with the watchdog off: this is the alarm's own safety net. A dead
     * ProbeService is **not** restarted from here (a `location` FGS cannot start from the background without background
     * location [A1][A2]); AlarmRingService rings without location instead.
     */
    private fun onFallback(context: Context, store: RunStore) {
        when (AlarmRoute.forFallback(store.alarmFired, ProbeService.running)) {
            AlarmRoute.Fallback.NONE -> Unit
            AlarmRoute.Fallback.PROBE_SERVICE -> if (!ProbeService.triggerFallback()) startRingService(context)
            AlarmRoute.Fallback.RING_SERVICE -> startRingService(context)
        }
    }

    private fun startRingService(context: Context) {
        try {
            ContextCompat.startForegroundService(context, AlarmRingService.ringIntent(context))
        } catch (e: Exception) {
            EventLog.log("wd_restart_fail", "for" to FOR_ALARM_FALLBACK, "ex" to e.javaClass.name, "msg" to e.message)
        }
    }

    /** Each restart mechanism has its own src (S1 §5.4); [forWhat] only labels a failure in `wd_restart_fail`. */
    private fun startService(context: Context, src: String, forWhat: String) {
        try {
            ContextCompat.startForegroundService(context, ProbeService.startIntent(context, src))
        } catch (e: Exception) {
            EventLog.log("wd_restart_fail", "for" to forWhat, "ex" to e.javaClass.name, "msg" to e.message)
        }
    }

    companion object {
        const val ACTION_WATCHDOG = "app.napstop.probe.action.WATCHDOG"
        const val ACTION_PHASE_BOUNDARY = "app.napstop.probe.action.PHASE_BOUNDARY"
        const val ACTION_ALARM_FALLBACK = "app.napstop.probe.action.ALARM_FALLBACK"
        const val FOR_WATCHDOG = "watchdog"
        const val FOR_PHASE_BOUNDARY = "phase_boundary"
        const val FOR_ALARM_FALLBACK = "alarm_fallback"
        private const val REQ_WATCHDOG = 20
        private const val REQ_FALLBACK = 21
        private const val REQ_PHASE = 22
        private const val WATCHDOG_INTERVAL_MS = 15 * 60_000L
        private const val FALLBACK_DELAY_MS = 60_000L
        private const val PHASE_FINISH_TIMEOUT_MS = 5_000L

        private fun pendingIntent(context: Context, action: String, requestCode: Int): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                requestCode,
                Intent(context, WatchdogReceiver::class.java).setAction(action),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        private fun canExact(am: AlarmManager) = Build.VERSION.SDK_INT < 31 || am.canScheduleExactAlarms()

        /** Returns true if an exact alarm was set, false if it fell back to an inexact one. */
        private fun setWakeup(context: Context, triggerElapsed: Long, pi: PendingIntent): Boolean {
            val am = context.getSystemService(AlarmManager::class.java)
            return if (canExact(am)) {
                am.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsed, pi)
                true
            } else {
                am.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerElapsed, pi)
                false
            }
        }

        fun scheduleWatchdog(context: Context) {
            val pi = pendingIntent(context, ACTION_WATCHDOG, REQ_WATCHDOG)
            val exact = setWakeup(context, SystemClock.elapsedRealtime() + WATCHDOG_INTERVAL_MS, pi)
            if (!exact) EventLog.log("wd_inexact")
        }

        /**
         * Exact alarm at the sparse → dense boundary (S1 §5.4). Only if the run has a sparse phase, has not switched yet
         * and the boundary is still in the future. Not setAlarmClock (it would show as a user alarm).
         */
        fun schedulePhaseBoundary(context: Context, cfg: RunConfig, phaseSwitched: Boolean) {
            if (!cfg.hasSparsePhase || phaseSwitched) return
            val now = System.currentTimeMillis()
            if (cfg.boundaryWallMs <= now) return
            val triggerElapsed = cfg.boundaryElapsed(SystemClock.elapsedRealtime(), now, DeviceSnapshot.bootCount(context))
            val exact = setWakeup(context, triggerElapsed, pendingIntent(context, ACTION_PHASE_BOUNDARY, REQ_PHASE))
            EventLog.log("phase_alarm_scheduled", "boundary" to EventLog.iso(cfg.boundaryWallMs), "exact" to exact)
            if (!exact) EventLog.log("phase_alarm_inexact")
        }

        /** Fallback alarm at deadline + 60 s; deadline is wall clock, converted to elapsedRealtime now. */
        fun scheduleFallback(context: Context, cfg: RunConfig) {
            val deadline = cfg.deadlineWallMs ?: return
            val delay = (deadline + FALLBACK_DELAY_MS - System.currentTimeMillis()).coerceAtLeast(0L)
            val pi = pendingIntent(context, ACTION_ALARM_FALLBACK, REQ_FALLBACK)
            val exact = setWakeup(context, SystemClock.elapsedRealtime() + delay, pi)
            EventLog.log("alarm_scheduled", "deadline" to EventLog.iso(deadline), "fallbackExact" to exact)
            if (!exact) EventLog.log("alarm_fallback_inexact")
        }

        fun cancelAll(context: Context) {
            val am = context.getSystemService(AlarmManager::class.java)
            am.cancel(pendingIntent(context, ACTION_WATCHDOG, REQ_WATCHDOG))
            am.cancel(pendingIntent(context, ACTION_PHASE_BOUNDARY, REQ_PHASE))
            am.cancel(pendingIntent(context, ACTION_ALARM_FALLBACK, REQ_FALLBACK))
        }
    }
}
