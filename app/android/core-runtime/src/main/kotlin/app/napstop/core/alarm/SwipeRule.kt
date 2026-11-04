package app.napstop.core.alarm

/** "Vuốt hết thanh để tắt" (spec T16 D16): released at ≥ SWIPE_COMPLETE_FRACTION of the track → stop. Pure. */
object SwipeRule {
    /** Thumb travel fraction, [thumbX] = left edge of the thumb inside the track, clamped to [0, 1]. */
    fun fraction(thumbX: Float, trackWidth: Float, thumbWidth: Float): Float {
        val travel = trackWidth - thumbWidth
        if (travel <= 0f || thumbX.isNaN()) return 0f
        return (thumbX / travel).coerceIn(0f, 1f)
    }

    fun isComplete(f: Float, c: AlarmConstants = AlarmConstants()): Boolean = f >= c.swipeCompleteFraction
}
