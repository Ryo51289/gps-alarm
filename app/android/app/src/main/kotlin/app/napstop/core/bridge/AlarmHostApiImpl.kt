package app.napstop.core.bridge

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.AlarmSounds
import app.napstop.core.alarm.SoundPreview

/**
 * The real AlarmHostApi (spec T16 §4.7): "Nghe thử" plays the alarm sound on the alarm stream for at most
 * PREVIEW_MAX_MS; never over a ring that is on. Errors: `internal` + class name via [BridgeGuard.callSync].
 */
class AlarmHostApiImpl(
    private val preview: SoundPreview,
    private val ringActive: () -> Boolean,
    private val previewMaxMs: Long = AlarmConstants().previewMaxMs,
) : AlarmHostApi {
    override fun previewSound(soundId: String, volume: Double) =
        BridgeGuard.callSync {
            if (ringActive()) return@callSync
            val v = volume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 1.0
            if (v == 0.0) preview.stop() else preview.play(AlarmSounds.resolve(soundId), v.toFloat(), previewMaxMs)
        }

    override fun stopPreview() = BridgeGuard.callSync { preview.stop() }
}

/** No sound (JVM tests of the registrar). */
object NoSoundPreview : SoundPreview {
    override fun play(soundId: String, volume: Float, maxMs: Long) = Unit

    override fun stop() = Unit
}
