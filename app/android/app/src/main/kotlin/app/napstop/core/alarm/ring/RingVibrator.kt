package app.napstop.core.alarm.ring

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import app.napstop.core.alarm.VibrationSpec

/** Repeating alarm vibration (spec T16 D14): USAGE_ALARM attributes so it is an alarm vibration for the system. */
class RingVibrator(context: Context) {
    private val ctx = context.applicationContext
    private var on = false

    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ctx.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            ctx.getSystemService(Vibrator::class.java)
        }
    }

    fun start(spec: VibrationSpec) {
        val v = vibrator ?: return
        try {
            if (!v.hasVibrator()) return
            val effect =
                if (v.hasAmplitudeControl()) {
                    VibrationEffect.createWaveform(spec.timingsMs, spec.amplitudes, spec.repeatIndex)
                } else {
                    VibrationEffect.createWaveform(spec.timingsMs, spec.repeatIndex)
                }
            if (on) v.cancel()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
            }
            on = true
        } catch (e: Exception) {
            Log.w(TAG, "vibration failed (${e.javaClass.simpleName})")
        }
    }

    fun stop() {
        if (!on) return
        on = false
        try {
            vibrator?.cancel()
        } catch (e: Exception) {
            Log.w(TAG, "vibration stop failed (${e.javaClass.simpleName})")
        }
    }

    private companion object {
        const val TAG = "NapStopRing"
    }
}
