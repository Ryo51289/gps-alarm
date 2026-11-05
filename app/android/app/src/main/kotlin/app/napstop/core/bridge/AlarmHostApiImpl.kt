package app.napstop.core.bridge

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.AlarmSounds
import app.napstop.core.alarm.AppLocale
import app.napstop.core.alarm.SoundPreview

/**
 * The real AlarmHostApi (spec T16 §4.7): "Nghe thử" plays the alarm sound on the alarm stream for at most
 * PREVIEW_MAX_MS; never over a ring that is on. Errors: `internal` + class name via [BridgeGuard.callSync].
 * [setLocale] receives the language of the native strings already parsed ("vi" | "en" | null, T28); production passes
 * `AppLocale.set` (memory at once, file and channel names on IO), so the call returns at once.
 */
class AlarmHostApiImpl(
    private val preview: SoundPreview,
    private val ringActive: () -> Boolean,
    private val previewMaxMs: Long = AlarmConstants().previewMaxMs,
    private val setLocale: (String?) -> Unit = {},
) : AlarmHostApi {
    override fun previewSound(soundId: String, volume: Double) =
        BridgeGuard.callSync {
            if (ringActive()) return@callSync
            val v = volume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 1.0
            if (v == 0.0) preview.stop() else preview.play(AlarmSounds.resolve(soundId), v.toFloat(), previewMaxMs)
        }

    override fun stopPreview() = BridgeGuard.callSync { preview.stop() }

    // TODO(T27): LaunchActions.consume() -> LaunchActionMsg.
    override suspend fun consumeLaunchAction(): LaunchActionMsg? = null

    // TODO(T27): AlarmController.showAlarmScreen.
    override suspend fun showAlarmScreen(tripId: String): Boolean = false

    override fun setAppLocale(languageTag: String?) = BridgeGuard.callSync { setLocale(AppLocale.parse(languageTag)) }
}

/** No sound (JVM tests of the registrar). */
object NoSoundPreview : SoundPreview {
    override fun play(soundId: String, volume: Float, maxMs: Long) = Unit

    override fun stop() = Unit
}
