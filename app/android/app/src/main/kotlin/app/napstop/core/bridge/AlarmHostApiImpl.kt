package app.napstop.core.bridge

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.AlarmSounds
import app.napstop.core.alarm.AppLocale
import app.napstop.core.alarm.LaunchActions
import app.napstop.core.alarm.RingIntents
import app.napstop.core.alarm.SoundPreview
import kotlin.coroutines.cancellation.CancellationException

/**
 * The real AlarmHostApi (spec T16 §4.7): "Nghe thử" plays the alarm sound on the alarm stream for at most
 * PREVIEW_MAX_MS; never over a ring that is on. Errors: `internal` + class name via [BridgeGuard.callSync].
 * [setLocale] receives the language of the native strings already parsed ("vi" | "en" | null, T28); production passes
 * `AppLocale.set` (memory at once, file and channel names on IO), so the call returns at once.
 *
 * T27 §9: [consumeLaunch] is the [LaunchActions] slot (taken once); [showAlarm] brings the native alarm screen of a trip
 * whose ring is live to the front (false when it cannot). Defaults: nothing (JVM tests of the registrar).
 */
class AlarmHostApiImpl(
    private val preview: SoundPreview,
    private val ringActive: () -> Boolean,
    private val previewMaxMs: Long = AlarmConstants().previewMaxMs,
    private val setLocale: (String?) -> Unit = {},
    private val consumeLaunch: () -> LaunchActions.Action? = { null },
    private val showAlarm: suspend (tripId: String) -> Boolean = { false },
) : AlarmHostApi {
    override fun previewSound(soundId: String, volume: Double) =
        BridgeGuard.callSync {
            if (ringActive()) return@callSync
            val v = volume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 1.0
            if (v == 0.0) preview.stop() else preview.play(AlarmSounds.resolve(soundId), v.toFloat(), previewMaxMs)
        }

    override fun stopPreview() = BridgeGuard.callSync { preview.stop() }

    /** T27 D4: the launch action of MainActivity, once; null when none or expired (D5). No coordinates (T14 D5). */
    override suspend fun consumeLaunchAction(): LaunchActionMsg? =
        BridgeGuard.call {
            consumeLaunch()
                ?.takeIf { it.action == LaunchActions.OVERSHOOT_ROUTE }
                ?.let { LaunchActionMsg(kind = LaunchActionKindMsg.OVERSHOOT_ROUTE, tripId = it.tripId, pastM = it.pastM?.toLong()) }
        }

    /** T27 D1: never an error for "cannot" — an invalid id or a failing start answers false. */
    override suspend fun showAlarmScreen(tripId: String): Boolean =
        BridgeGuard.call {
            val id = RingIntents.validTripId(tripId) ?: return@call false
            try {
                showAlarm(id)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                false
            }
        }

    override fun setAppLocale(languageTag: String?) = BridgeGuard.callSync { setLocale(AppLocale.parse(languageTag)) }
}

/** No sound (JVM tests of the registrar). */
object NoSoundPreview : SoundPreview {
    override fun play(soundId: String, volume: Float, maxMs: Long) = Unit

    override fun stop() = Unit
}
