package app.napstop.core.alarm

import kotlin.math.sqrt

/**
 * "Lắc máy để tắt" (spec T16 D16). Counts acceleration peaks ≥ SHAKE_G (magnitude incl. gravity, in g), each peak a new
 * rise above the threshold at least SHAKE_MIN_GAP_MS after the last one; SHAKE_PEAKS_REQUIRED peaks stop the alarm. One
 * peak is lost per SHAKE_DECAY_MS without a peak, so only ≈ 5 s of continuous shaking counts, not bumps on a bus.
 * Samples in m/s² as from Sensor.TYPE_ACCELEROMETER. Pure; not thread-safe (one sensor thread).
 */
class ShakeDetector(private val c: AlarmConstants = AlarmConstants()) {
    data class Progress(val count: Int, val required: Int, val done: Boolean)

    private var count = 0
    private var above = false
    private var lastPeakMs: Long? = null
    private var lastActivityMs: Long? = null
    private var done = false

    fun onSample(ax: Float, ay: Float, az: Float, tMs: Long): Progress {
        if (done) return progress()
        decay(tMs)
        val g = sqrt(ax * ax + ay * ay + az * az) / AlarmConstants.G
        if (g >= c.shakeG) {
            val last = lastPeakMs
            if (!above && (last == null || tMs - last >= c.shakeMinGapMs)) {
                count++
                lastPeakMs = tMs
                lastActivityMs = tMs
                if (count >= c.shakePeaksRequired) done = true
            }
            above = true
        } else {
            above = false
        }
        return progress()
    }

    fun reset() {
        count = 0
        above = false
        lastPeakMs = null
        lastActivityMs = null
        done = false
    }

    private fun decay(tMs: Long) {
        var last = lastActivityMs ?: return
        while (count > 0 && tMs - last >= c.shakeDecayMs) {
            count--
            last += c.shakeDecayMs
        }
        lastActivityMs = if (count == 0) tMs else last
    }

    private fun progress() = Progress(count, c.shakePeaksRequired, done)
}
