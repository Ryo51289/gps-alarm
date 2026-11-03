package app.napstop.core.bridge.permission

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * Alarm of the screen 9 background check (spec T21 §5): records when it ran and whether the
 * screen was on, then vibrates once with the alarm usage (background apps must use an
 * alarm, notification or ringtone usage to vibrate, A-VIB). No notification, no sound.
 * Not exported.
 */
class BackgroundCheckReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        val pending = goAsync()
        val scheduledAt = intent.getLongExtra(EXTRA_SCHEDULED_AT, -1L)
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val now = System.currentTimeMillis()
                val interactive = appContext.getSystemService(PowerManager::class.java)?.isInteractive ?: false
                val store = BackgroundCheckStore(appContext)
                val updated = BackgroundCheckLogic.onFired(store.read(), scheduledAt, now, interactive)
                if (updated != null) {
                    store.write(updated)
                    vibrate(appContext)
                }
            } catch (e: Exception) {
                Log.w(TAG, "background check: ${e.javaClass.simpleName}")
            } finally {
                pending.finish()
            }
        }
    }

    private fun vibrate(context: Context) {
        val vibrator =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(VibratorManager::class.java)?.defaultVibrator
            } else {
                context.getSystemService(Vibrator::class.java)
            } ?: return
        val effect = VibrationEffect.createWaveform(longArrayOf(0, 400, 200, 400), -1)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            vibrator.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
        } else {
            @Suppress("DEPRECATION")
            vibrator.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
        }
    }

    companion object {
        const val EXTRA_SCHEDULED_AT = "app.napstop.extra.BG_CHECK_SCHEDULED_AT"
        private const val TAG = "NapStopBridge"
    }
}
