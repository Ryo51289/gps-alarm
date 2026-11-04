package app.napstop.core.alarm

import android.content.Context
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log

/** What [app.napstop.core.bridge.AlarmHostApiImpl] needs (JVM-tested with a fake). */
interface SoundPreview {
    fun play(soundId: String, volume: Float, maxMs: Long)

    fun stop()
}

/**
 * "Nghe thử" of screen 12 (spec T16 §4.7) in the main process: the alarm stream (USAGE_ALARM), transient focus,
 * prepareAsync (never blocks the main thread), looped until [maxMs], then stopped. No ramp, no vibration. Main thread.
 */
class SoundPreviewPlayer(context: Context) : SoundPreview {
    private val ctx = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val audio: AudioManager? get() = ctx.getSystemService(AudioManager::class.java)
    private var player: MediaPlayer? = null
    private var focus: AudioFocusRequest? = null
    private val timeout = Runnable { stop() }

    override fun play(soundId: String, volume: Float, maxMs: Long) {
        stop()
        val sources = RingSounds.sourceChain(ctx, soundId)
        if (sources.isEmpty()) return
        val attrs = AlarmChannels.alarmAttributes()
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attrs).build()
        focus = req
        try {
            audio?.requestAudioFocus(req)
        } catch (e: Exception) {
            Log.w(TAG, "preview focus failed (${e.javaClass.simpleName})")
        }
        start(sources, 0, volume)
        main.postDelayed(timeout, maxMs)
    }

    private fun start(sources: List<Uri>, index: Int, volume: Float) {
        val uri = sources.getOrNull(index) ?: return
        val mp = MediaPlayer()
        player = mp
        try {
            mp.setAudioAttributes(AlarmChannels.alarmAttributes())
            mp.setDataSource(ctx, uri)
            mp.isLooping = true
            mp.setVolume(volume, volume)
            mp.setOnPreparedListener { if (player === it) it.start() }
            mp.setOnErrorListener { p, _, _ ->
                if (player === p) {
                    p.release()
                    player = null
                    start(sources, index + 1, volume)
                }
                true
            }
            mp.prepareAsync()
        } catch (e: Exception) {
            Log.w(TAG, "preview source failed (${e.javaClass.simpleName})")
            mp.release()
            if (player === mp) player = null
            start(sources, index + 1, volume)
        }
    }

    override fun stop() {
        main.removeCallbacks(timeout)
        player?.let {
            try {
                it.stop()
            } catch (e: IllegalStateException) {
                // not prepared yet
            }
            it.release()
        }
        player = null
        focus?.let {
            try {
                audio?.abandonAudioFocusRequest(it)
            } catch (e: Exception) {
                Log.w(TAG, "preview focus abandon failed (${e.javaClass.simpleName})")
            }
        }
        focus = null
    }

    companion object {
        private const val TAG = "NapStopAlarm"

        @Volatile
        private var instance: SoundPreviewPlayer? = null

        /** One player per process (MainActivity.onStop stops it). */
        fun get(context: Context): SoundPreviewPlayer =
            instance ?: synchronized(this) { instance ?: SoundPreviewPlayer(context.applicationContext).also { instance = it } }
    }
}
