package app.napstop.core.alarm.ring

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.VolumeShaper
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import app.napstop.core.alarm.AlarmChannels
import app.napstop.core.alarm.AudioRoute
import app.napstop.core.alarm.CallState
import app.napstop.core.alarm.FocusPolicy
import app.napstop.core.alarm.FocusState
import app.napstop.core.alarm.RingPlan
import app.napstop.core.alarm.RingSounds
import app.napstop.core.alarm.VolumeRamp

/**
 * The ring sound (spec T16 D11, D12, §5.6), on the ring thread ([handler]). USAGE_ALARM (passes silent mode and DND
 * "alarms allowed"), looping MediaPlayer with a partial wake lock, relative volume (plan.targetVolume × the alarm stream,
 * the system volume is never changed — Q2 = A), linear ramp with VolumeShaper. Focus GAIN_TRANSIENT with delayed gain:
 * during a call the ring only vibrates until the call ends; a failed focus request still plays. No source plays →
 * [onNoSound] (strong vibration).
 */
class RingAudio(
    context: Context,
    private val handler: Handler,
    private val headset: HeadsetMonitor,
    private val journal: RingJournalSink,
) {
    private val ctx = context.applicationContext
    private val am: AudioManager? get() = ctx.getSystemService(AudioManager::class.java)
    private var player: MediaPlayer? = null
    private var shaper: VolumeShaper? = null
    private var focus: AudioFocusRequest? = null
    private var plan: RingPlan? = null
    private var route: AudioRoute? = null
    private var startedAtElapsed = 0L
    private var sources: List<Uri> = emptyList()
    private var sourceIndex = 0
    private var retriedOnError = false
    private var waitingForGain = false
    private var paused = false
    private var onNoSound: (() -> Unit)? = null
    private var onSoundBack: (() -> Unit)? = null

    /** First sound start of the session, for ring_start.latencyMs (debug journal). */
    var firstSoundAtElapsed: Long? = null
        private set

    private val focusListener =
        AudioManager.OnAudioFocusChangeListener { change ->
            when (change) {
                AudioManager.AUDIOFOCUS_GAIN -> {
                    if (waitingForGain) {
                        waitingForGain = false
                        onSoundBack?.invoke()
                        play()
                    } else if (paused) {
                        paused = false
                        onSoundBack?.invoke()
                        try {
                            player?.start()
                        } catch (e: IllegalStateException) {
                            Log.w(TAG, "resume failed")
                        }
                    }
                }
                AudioManager.AUDIOFOCUS_LOSS, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    // D12: only a call pauses the alarm; another app taking focus never mutes it.
                    if (!FocusPolicy.shouldPlay(FocusState.LOST, callState())) {
                        paused = true
                        // Silent while the call lasts: at least a strong vibration (review T16 #4).
                        onNoSound?.invoke()
                        try {
                            player?.pause()
                        } catch (e: IllegalStateException) {
                            Log.w(TAG, "pause failed")
                        }
                    }
                }
            }
        }

    /**
     * [onNoSound]: nothing sounds (no source, or a call holds the focus) → the session vibrates strongly; [onSoundBack]: the
     * sound plays again after a call → the plan's own vibration.
     */
    fun start(route: AudioRoute, plan: RingPlan, elapsedMs: Long, onNoSound: () -> Unit, onSoundBack: () -> Unit = {}) {
        stop()
        firstSoundAtElapsed = null
        this.onSoundBack = onSoundBack
        this.plan = plan
        this.route = route
        this.onNoSound = onNoSound
        startedAtElapsed = SystemClock.elapsedRealtime() - elapsedMs
        sources = RingSounds.sourceChain(ctx, plan.soundId)
        sourceIndex = 0
        retriedOnError = false
        logZen()
        val req =
            AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                .setAudioAttributes(attributes(route))
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(focusListener, handler)
                .build()
        focus = req
        val state =
            try {
                when (am?.requestAudioFocus(req)) {
                    AudioManager.AUDIOFOCUS_REQUEST_GRANTED -> FocusState.GRANTED
                    AudioManager.AUDIOFOCUS_REQUEST_DELAYED -> FocusState.DELAYED
                    else -> FocusState.FAILED
                }
            } catch (e: Exception) {
                FocusState.FAILED
            }
        journal.log("ring_focus", mapOf("res" to state.name))
        if (!FocusPolicy.shouldPlay(state, callState())) {
            waitingForGain = true
            onNoSound()
            return
        }
        play()
    }

    fun stop() {
        waitingForGain = false
        paused = false
        try {
            shaper?.close()
        } catch (e: Exception) {
            // ignore
        }
        shaper = null
        player?.let {
            try {
                it.stop()
            } catch (e: IllegalStateException) {
                // not started
            }
            it.release()
        }
        player = null
        focus?.let {
            try {
                am?.abandonAudioFocusRequest(it)
            } catch (e: Exception) {
                // ignore
            }
        }
        focus = null
    }

    private fun play() {
        val p = plan ?: return
        val r = route ?: return
        while (sourceIndex < sources.size) {
            val src = sources[sourceIndex]
            val mp = MediaPlayer()
            try {
                // Attributes before the data source (§5.6).
                mp.setAudioAttributes(attributes(r))
                mp.setDataSource(ctx, src)
                mp.isLooping = true
                mp.setWakeMode(ctx, PowerManager.PARTIAL_WAKE_LOCK)
                if (r == AudioRoute.HEADPHONES && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    headset.headset()?.let { d: AudioDeviceInfo -> mp.setPreferredDevice(d) }
                }
                mp.setOnErrorListener { failed, _, _ -> onPlayerError(failed) }
                mp.prepare() // local file / content uri, on the ring thread
                mp.setVolume(p.targetVolume, p.targetVolume)
                val elapsed = SystemClock.elapsedRealtime() - startedAtElapsed
                VolumeRamp.remaining(p, elapsed)?.let { seg ->
                    val cfg =
                        VolumeShaper.Configuration.Builder()
                            .setDuration(seg.durationMs)
                            .setCurve(floatArrayOf(0f, 1f), floatArrayOf(seg.startFraction, 1f))
                            .setInterpolatorType(VolumeShaper.Configuration.INTERPOLATOR_TYPE_LINEAR)
                            .build()
                    shaper = mp.createVolumeShaper(cfg).also { it.apply(VolumeShaper.Operation.PLAY) }
                }
                mp.start()
                player = mp
                if (firstSoundAtElapsed == null) firstSoundAtElapsed = SystemClock.elapsedRealtime()
                journal.log("ring_sound", mapOf("ok" to true, "src" to sourceKind(src)))
                return
            } catch (e: Exception) {
                Log.w(TAG, "sound source failed (${e.javaClass.simpleName})")
                try {
                    shaper?.close()
                } catch (x: Exception) {
                    // ignore
                }
                shaper = null
                mp.release()
                sourceIndex++
            }
        }
        journal.log("ring_sound", mapOf("ok" to false, "src" to null))
        onNoSound?.invoke()
    }

    /** OnError while playing: the next source, once. */
    private fun onPlayerError(failed: MediaPlayer): Boolean {
        if (failed !== player) return true
        player = null
        failed.release()
        if (!retriedOnError) {
            retriedOnError = true
            sourceIndex++
            play()
        } else {
            onNoSound?.invoke()
        }
        return true
    }

    private fun attributes(r: AudioRoute): AudioAttributes =
        AlarmChannels.alarmAttributes(if (r == AudioRoute.HEADPHONES) HEADPHONES_USAGE else AudioAttributes.USAGE_ALARM)

    private fun callState(): CallState =
        when (am?.mode) {
            AudioManager.MODE_RINGTONE, AudioManager.MODE_IN_CALL, AudioManager.MODE_IN_COMMUNICATION -> CallState.IN_CALL
            else -> CallState.NONE
        }

    private fun logZen() {
        try {
            val nm = ctx.getSystemService(android.app.NotificationManager::class.java)
            val a = am
            journal.log(
                "ring_zen",
                mapOf(
                    "filter" to nm?.currentInterruptionFilter,
                    "muted" to a?.isStreamMute(AudioManager.STREAM_ALARM),
                    "vol" to a?.getStreamVolume(AudioManager.STREAM_ALARM),
                ),
            )
        } catch (e: Exception) {
            // journal only
        }
    }

    private fun sourceKind(u: Uri): String = if (u.scheme == "android.resource") "raw" else "system"

    companion object {
        private const val TAG = "NapStopRing"

        /** D13: USAGE_ALARM; AM4 decides whether "Chỉ tai nghe" must use USAGE_MEDIA (RK-T16-5/6). */
        const val HEADPHONES_USAGE = AudioAttributes.USAGE_ALARM
    }
}
