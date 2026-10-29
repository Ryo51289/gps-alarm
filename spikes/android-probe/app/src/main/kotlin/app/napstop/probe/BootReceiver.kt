package app.napstop.probe

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat

/**
 * Restores a run after reboot / app update (S1 §5.4). `location` may start from BOOT_COMPLETED on Android 15 [A3] but
 * is still subject to the while-in-use rule [A1]: whether `svc_fg_ok` or `svc_fg_fail` follows is the data.
 * MY_PACKAGE_REPLACED uses src=pkg_replaced so a reinstall is not read as a reboot.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val src = when (action) {
            Intent.ACTION_BOOT_COMPLETED -> ProbeService.SRC_BOOT
            Intent.ACTION_MY_PACKAGE_REPLACED -> ProbeService.SRC_PKG_REPLACED
            else -> return
        }
        val store = RunStore(context)
        val cfg = store.activeRun() ?: return
        EventLog.log("boot", "action" to action)
        try {
            ContextCompat.startForegroundService(context, ProbeService.startIntent(context, src))
        } catch (e: Exception) {
            EventLog.log("svc_fg_fail", "src" to src, "ex" to e.javaClass.name, "msg" to e.message)
        }
        if (cfg.watchdog) WatchdogReceiver.scheduleWatchdog(context)
        WatchdogReceiver.schedulePhaseBoundary(context, cfg, store.phaseSwitched)
        if (cfg.alarmEnabled && !store.alarmFired) WatchdogReceiver.scheduleFallback(context, cfg)
    }
}
