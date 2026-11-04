package app.napstop.core.alarm.ring

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.util.Log
import androidx.core.content.ContextCompat
import app.napstop.core.alarm.HeadphoneTypes

/**
 * Headphones (spec T16 D13, §5.7): what is plugged now, and "unplugged while ringing" via AudioDeviceCallback +
 * ACTION_AUDIO_BECOMING_NOISY (a system broadcast). Callbacks on the ring thread ([handler]).
 */
class HeadsetMonitor(context: Context, private val handler: Handler) {
    private val ctx = context.applicationContext
    private val am: AudioManager? get() = ctx.getSystemService(AudioManager::class.java)
    private var onGone: (() -> Unit)? = null
    private var registered = false

    private val deviceCallback =
        object : AudioDeviceCallback() {
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>) {
                if (removedDevices.any { HeadphoneTypes.isHeadphone(it.type) } && !connectedNow()) fire()
            }
        }

    private val noisy =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) fire()
            }
        }

    fun connectedNow(): Boolean = headset() != null

    fun headset(): AudioDeviceInfo? =
        try {
            am?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)?.firstOrNull { HeadphoneTypes.isHeadphone(it.type) }
        } catch (e: Exception) {
            null
        }

    fun watch(on: Boolean, gone: () -> Unit) {
        if (on == registered) return
        try {
            if (on) {
                onGone = gone
                am?.registerAudioDeviceCallback(deviceCallback, handler)
                ContextCompat.registerReceiver(
                    ctx, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), null, handler, ContextCompat.RECEIVER_NOT_EXPORTED,
                )
            } else {
                onGone = null
                am?.unregisterAudioDeviceCallback(deviceCallback)
                ctx.unregisterReceiver(noisy)
            }
            registered = on
        } catch (e: Exception) {
            Log.w("NapStopRing", "headset watch failed (${e.javaClass.simpleName})")
        }
    }

    private fun fire() {
        onGone?.invoke()
    }
}
