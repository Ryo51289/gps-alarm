package app.napstop.core.alarm

/**
 * Native alarm constants (spec T16 §6). Not Remote Config (D21): the behaviour parameters live in `trip_engine_params`.
 * A data class so tests (and the debug `ring_max_override` command) can change single values.
 */
data class AlarmConstants(
    /** Auto-stop of one ring (PO Q1 = 5 minutes, 04/11/2026). */
    val ringMaxMs: Long = 300_000L,
    val rampMs: Long = 30_000L,
    val rampStartFraction: Float = 0.10f,
    /** How long a ring asked for in this process counts as ringing before `:ring` confirms it in the facts file. */
    val ringConfirmMs: Long = 3_000L,
    val heartbeatMs: Long = 2_000L,
    val heartbeatStaleMs: Long = 6_000L,
    val watchdogMs: Long = 2_000L,
    val ringRestartMax: Int = 2,
    /** A ring stuck past RING_MAX + this counts as stopped. */
    val livenessGraceMs: Long = 60_000L,
    val snoozeSDefault: Int = 60,
    val shakeG: Float = 2.2f,
    val shakeMinGapMs: Long = 120L,
    val shakePeaksRequired: Int = 20,
    val shakeDecayMs: Long = 600L,
    val mathARange: IntRange = 12..59,
    val mathBRange: IntRange = 12..39,
    val mathMaxWrong: Int = 3,
    val swipeCompleteFraction: Float = 0.95f,
    val flashOnMs: Long = 500L,
    val flashOffMs: Long = 500L,
    val previewMaxMs: Long = 10_000L,
) {
    /** Cap of the `napstop:ring` wakelock. */
    val ringWakelockMs: Long get() = ringMaxMs + 60_000L

    companion object {
        /** Standard gravity, m/s² (accelerometer samples are m/s²). */
        const val G = 9.80665f
    }
}
