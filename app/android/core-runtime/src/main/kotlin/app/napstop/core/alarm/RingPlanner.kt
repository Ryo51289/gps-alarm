package app.napstop.core.alarm

import java.util.Locale

/** How the user stops the alarm (spec T16 D16). Unknown / null → [SWIPE]. */
enum class DismissMethod {
    SWIPE,
    SHAKE,
    MATH;

    companion object {
        fun parse(s: String?): DismissMethod = entries.firstOrNull { it.name == s?.trim()?.uppercase(Locale.ROOT) } ?: SWIPE
    }
}

enum class AudioRoute { SPEAKER, HEADPHONES, VIBRATE_ONLY }

/** A repeating vibration waveform (repeat from [repeatIndex]). equals / hashCode by content. */
class VibrationSpec(val timingsMs: LongArray, val amplitudes: IntArray, val repeatIndex: Int) {
    override fun equals(other: Any?): Boolean =
        other is VibrationSpec && timingsMs.contentEquals(other.timingsMs) && amplitudes.contentEquals(other.amplitudes) &&
            repeatIndex == other.repeatIndex

    override fun hashCode(): Int = (timingsMs.contentHashCode() * 31 + amplitudes.contentHashCode()) * 31 + repeatIndex

    override fun toString(): String = "VibrationSpec(timings=${timingsMs.contentToString()}, amplitudes=${amplitudes.contentToString()})"
}

/** What one ring does, from the trip's alarm settings (spec T16 §4.2). */
data class RingPlan(
    /** settings.volume > 0 */
    val playSound: Boolean,
    /** Normalised id ([AlarmSounds]). */
    val soundId: String,
    /** 0..1, multiplied with the alarm stream volume (Q2 = A: relative, the system volume is never changed). */
    val targetVolume: Float,
    /** 0 = no ramp. */
    val rampMs: Long,
    val rampStartFraction: Float,
    /** null = no vibration (only while there is sound). */
    val vibration: VibrationSpec?,
    val flash: Boolean,
    val headphonesOnly: Boolean,
    val dismissMethod: DismissMethod,
)

object RingPlanner {
    fun plan(settings: RingSettings?, c: AlarmConstants = AlarmConstants()): RingPlan {
        if (settings == null) {
            return RingPlan(
                playSound = true,
                soundId = AlarmSounds.resolve(null),
                targetVolume = 1.0f,
                rampMs = c.rampMs,
                rampStartFraction = c.rampStartFraction,
                vibration = VibrationPatterns.STRONG,
                flash = false,
                headphonesOnly = false,
                dismissMethod = DismissMethod.SWIPE,
            )
        }
        val volume = settings.volume.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0) ?: 1.0
        val playSound = volume > 0.0
        // Never silent by configuration (D14): no sound and no vibration → strong vibration.
        val vibration = VibrationPatterns.forLevel(settings.vibration) ?: if (playSound) null else VibrationPatterns.STRONG
        return RingPlan(
            playSound = playSound,
            soundId = AlarmSounds.resolve(settings.soundId),
            targetVolume = volume.toFloat(),
            rampMs = if (settings.rampUp) c.rampMs else 0L,
            rampStartFraction = c.rampStartFraction,
            vibration = vibration,
            flash = settings.flash,
            headphonesOnly = settings.preferHeadphones,
            dismissMethod = DismissMethod.parse(settings.dismissMethod),
        )
    }
}

/** Linear volume ramp of spec T16 §5.6 (fraction of [RingPlan.targetVolume]). Pure. */
object VolumeRamp {
    /** Fraction of the target volume [tMs] after the ring started: start → 1.0 over rampMs, then 1.0. */
    fun fractionAt(plan: RingPlan, tMs: Long): Float {
        if (plan.rampMs <= 0L) return 1.0f
        val t = tMs.coerceIn(0L, plan.rampMs)
        return plan.rampStartFraction + (1.0f - plan.rampStartFraction) * (t.toFloat() / plan.rampMs.toFloat())
    }

    /** The part of the ramp still to play when a ring resumes [elapsedMs] after its start; null = full volume now. */
    fun remaining(plan: RingPlan, elapsedMs: Long): Segment? {
        if (plan.rampMs <= 0L || elapsedMs >= plan.rampMs) return null
        val e = elapsedMs.coerceAtLeast(0L)
        return Segment(fractionAt(plan, e), plan.rampMs - e)
    }

    data class Segment(val startFraction: Float, val durationMs: Long)
}

/** Sound catalogue (Q3 = A): CC0 / generated raw files + the device alarm sound. */
object AlarmSounds {
    const val DEFAULT = "default"
    const val HORN = "horn"
    const val SYSTEM = "system"

    /** Display order for T28. */
    val catalog: List<String> = listOf(HORN, "bell", "beep", SYSTEM)

    /** "default" / unknown / null → "horn". */
    fun resolve(id: String?): String = id?.takeIf { it in catalog } ?: HORN

    /** "horn" → "alarm_horn"; "system" → null (RingtoneManager TYPE_ALARM). */
    fun rawName(id: String): String? = resolve(id).takeIf { it != SYSTEM }?.let { "alarm_$it" }
}

/** Vibration waveforms of spec T16 §5.7, repeating from index 0. */
object VibrationPatterns {
    val LIGHT = VibrationSpec(longArrayOf(0, 300, 1200), intArrayOf(0, 90, 0), 0)
    val MEDIUM = VibrationSpec(longArrayOf(0, 600, 600), intArrayOf(0, 170, 0), 0)
    val STRONG = VibrationSpec(longArrayOf(0, 900, 300), intArrayOf(0, 255, 0), 0)

    /** Pre-alert pattern of the `napstop_prealert` channel (one-shot). */
    val PRE_ALERT: LongArray = longArrayOf(0, 250, 200, 250)

    /** "off" → null (no vibration); null / unknown → strong (safe side). */
    fun forLevel(level: String?): VibrationSpec? =
        when (level?.trim()?.lowercase(Locale.ROOT)) {
            "off" -> null
            "light" -> LIGHT
            "medium" -> MEDIUM
            else -> STRONG
        }
}
