package app.napstop.probe

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Alarm sound + vibration (S2 §5.2 step 3). Must be used from one thread with a Looper (`probe-loc` or `probe-ring`).
 * Does not change system volume. Every step logs; a failing step logs `alarm_error` and the next steps still run.
 */
class AlarmPlayer(private val context: Context, private val handler: Handler) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val attributes: AudioAttributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ALARM)
        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
        .build()
    private var player: MediaPlayer? = null
    private var focusRequest: AudioFocusRequest? = null
    private var vibrator: Vibrator? = null
    private var soundCheck: Runnable? = null

    fun start() {
        var focus = "failed"
        step("focus") {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener({ /* keep playing whatever happens */ }, handler)
                .build()
            focusRequest = request
            focus = when (audio.requestAudioFocus(request)) {
                AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> "granted"
                AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> "delayed"
                else -> "failed"
            }
        }
        // Play even if focus failed.
        step("sound") {
            val mp = MediaPlayer()
            player = mp
            mp.setAudioAttributes(attributes) // before setDataSource
            mp.setDataSource(wavFile(context).absolutePath)
            mp.isLooping = true
            mp.setVolume(1f, 1f)
            mp.prepare() // local file, fast
            mp.start()
        }
        val check = Runnable {
            val zen = runCatching { notifications.currentInterruptionFilter }.getOrNull()
            val (zenActive, zenActiveErr) = activeAllowsAlarms(zen)
            EventLog.log(
                "alarm_sound_start",
                "ok" to (runCatching { player?.isPlaying }.getOrNull() == true),
                "focus" to focus,
                "alarmVol" to audio.getStreamVolume(AudioManager.STREAM_ALARM),
                "alarmVolMax" to audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),
                "muted" to audio.isStreamMute(AudioManager.STREAM_ALARM),
                "zen" to zen,
                "zenAlarms" to zenAllowsAlarms(zen),
                "zenAlarmsActive" to zenActive,
                "zenActiveErr" to zenActiveErr,
            )
        }
        soundCheck = check
        handler.postDelayed(check, 1_000L)
        step("vibrate") {
            val v = if (Build.VERSION.SDK_INT >= 31) {
                context.getSystemService(VibratorManager::class.java).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Vibrator::class.java)
            }
            vibrator = v
            val hasVibrator = v.hasVibrator()
            val effect = VibrationEffect.createWaveform(longArrayOf(0L, 800L, 400L), 0)
            if (hasVibrator) {
                if (Build.VERSION.SDK_INT >= 33) {
                    v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM))
                } else {
                    @Suppress("DEPRECATION")
                    v.vibrate(effect, attributes)
                }
            }
            EventLog.log("alarm_vibrate", "ok" to hasVibrator, "hasVibrator" to hasVibrator)
        }
    }

    /**
     * S2 Vòng 4 V4-2: only for DND PRIORITY (API 28+), whether the user's DND policy lets alarms through; null otherwise or
     * when the policy cannot be read [N7]. This is the user's *default* policy (S2 Vòng 5 V5-1), kept for reading only.
     */
    private fun zenAllowsAlarms(zen: Int?): Boolean? {
        if (zen != NotificationManager.INTERRUPTION_FILTER_PRIORITY || Build.VERSION.SDK_INT < 28) return null
        return runCatching {
            (notifications.notificationPolicy.priorityCategories and
                NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS) != 0
        }.getOrNull()
    }

    /**
     * S2 Vòng 5 V5-1: only for DND PRIORITY on API 30+, whether the currently applied (consolidated) policy lets alarms
     * through, so a schedule/mode with its own policy is seen [N8][N10]. Returns (allowed, null), or (null, exception class
     * name) when the policy cannot be read, or (null, null) when it does not apply.
     */
    private fun activeAllowsAlarms(zen: Int?): Pair<Boolean?, String?> {
        if (zen != NotificationManager.INTERRUPTION_FILTER_PRIORITY || Build.VERSION.SDK_INT < 30) return null to null
        return try {
            ((notifications.consolidatedNotificationPolicy.priorityCategories and
                NotificationManager.Policy.PRIORITY_CATEGORY_ALARMS) != 0) to null
        } catch (e: Exception) {
            null to e.javaClass.simpleName
        }
    }

    fun stop() {
        soundCheck?.let { handler.removeCallbacks(it) }
        soundCheck = null
        step("stop_sound") {
            player?.let {
                runCatching { it.stop() }
                it.release()
            }
            player = null
        }
        step("stop_vibrate") { vibrator?.cancel() }
        step("abandon_focus") { focusRequest?.let { audio.abandonAudioFocusRequest(it) } }
    }

    private inline fun step(name: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            EventLog.log("alarm_error", "step" to name, "ex" to e.javaClass.name, "msg" to e.message)
        }
    }

    companion object {
        private const val WAV_NAME = "probe_alarm.wav"

        fun wavFile(context: Context) = File(context.filesDir, WAV_NAME)

        /** Generates the alarm tone once (called from ProbeApp on a background thread). */
        fun ensureWav(context: Context) {
            val file = wavFile(context)
            if (file.exists() && file.length() == AlarmTone.TOTAL_BYTES.toLong()) return
            val tmp = File(context.filesDir, "$WAV_NAME.tmp")
            tmp.writeBytes(AlarmTone.build())
            tmp.renameTo(file)
        }
    }
}

/**
 * 1 s PCM 16-bit mono 44 100 Hz WAV: 500 ms of 880 Hz sine at 0.8 FS with 10 ms fades, then 500 ms silence (S2 §5.2).
 * Pure; unit-tested.
 */
object AlarmTone {
    const val SAMPLE_RATE = 44_100
    const val HEADER_BYTES = 44
    const val SAMPLES = SAMPLE_RATE // 1 second
    const val TOTAL_BYTES = HEADER_BYTES + SAMPLES * 2
    private const val TONE_SAMPLES = SAMPLE_RATE / 2
    private const val FADE_SAMPLES = SAMPLE_RATE / 100
    private const val FREQ_HZ = 880.0
    private const val AMPLITUDE = 0.8

    fun build(): ByteArray {
        val buf = ByteBuffer.allocate(TOTAL_BYTES).order(ByteOrder.LITTLE_ENDIAN)
        val dataBytes = SAMPLES * 2
        buf.put("RIFF".toByteArray(Charsets.US_ASCII))
        buf.putInt(36 + dataBytes)
        buf.put("WAVE".toByteArray(Charsets.US_ASCII))
        buf.put("fmt ".toByteArray(Charsets.US_ASCII))
        buf.putInt(16) // PCM fmt chunk size
        buf.putShort(1) // PCM
        buf.putShort(1) // mono
        buf.putInt(SAMPLE_RATE)
        buf.putInt(SAMPLE_RATE * 2) // byte rate
        buf.putShort(2) // block align
        buf.putShort(16) // bits per sample
        buf.put("data".toByteArray(Charsets.US_ASCII))
        buf.putInt(dataBytes)
        for (i in 0 until SAMPLES) {
            val value = if (i < TONE_SAMPLES) {
                val fade = min(1.0, min(i, TONE_SAMPLES - 1 - i).toDouble() / FADE_SAMPLES)
                AMPLITUDE * fade * sin(2.0 * PI * FREQ_HZ * i / SAMPLE_RATE)
            } else {
                0.0
            }
            buf.putShort((value * Short.MAX_VALUE).roundToInt().toShort())
        }
        return buf.array()
    }
}
