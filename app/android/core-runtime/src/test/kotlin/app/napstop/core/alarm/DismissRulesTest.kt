package app.napstop.core.alarm

import java.util.Random
import kotlin.math.PI
import kotlin.math.sin
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T16 A23 (shake), A24 (math), A25 (swipe), A26 (focus). */
class DismissRulesTest {
    private val g = AlarmConstants.G

    /** 50 Hz samples of a vertical acceleration magnitude (in g) from [fromMs] for [durMs]. */
    private fun feed(d: ShakeDetector, fromMs: Long, durMs: Long, gOf: (tS: Double) -> Double): ShakeDetector.Progress {
        var p = ShakeDetector.Progress(0, 20, false)
        var t = fromMs
        while (t < fromMs + durMs) {
            p = d.onSample(0f, 0f, (gOf(t / 1000.0) * g).toFloat(), t)
            t += 20
        }
        return p
    }

    private fun shake(tS: Double) = 1.0 + 1.6 * sin(2 * PI * 4.0 * tS) // peaks 2.6 g at 4 Hz

    @Test
    fun a23_shakeDetector() {
        assertEquals(0, feed(ShakeDetector(), 0, 10_000) { 1.0 }.count)
        val bus = ShakeDetector()
        assertFalse(feed(bus, 0, 30_000) { 1.0 + 0.6 * sin(2 * PI * 2.0 * it) }.done) // 1.6 g bumps
        // Continuous shaking: done within [4.5, 6] s.
        val d = ShakeDetector()
        var doneAt: Long? = null
        var t = 0L
        while (t < 8_000 && doneAt == null) {
            if (d.onSample(0f, 0f, (shake(t / 1000.0) * g).toFloat(), t).done) doneAt = t
            t += 20
        }
        assertTrue(doneAt != null && doneAt in 4_500..6_000, "done at $doneAt")
        // Shake 3 s, rest 3 s: the count drops by 5.
        val r = ShakeDetector()
        val after3 = feed(r, 0, 3_000, ::shake).count
        val rested = feed(r, 3_000, 3_000) { 1.0 }.count
        assertEquals(after3 - 5, rested)
        assertFalse(r.onSample(0f, 0f, g, 6_000).done)
        r.reset()
        assertEquals(0, r.onSample(0f, 0f, g, 6_020).count)
    }

    @Test
    fun a24_mathChallenge() {
        val c = AlarmConstants()
        val rnd = Random(42)
        repeat(1_000) {
            val p = MathChallenge(rnd).current
            assertTrue(p.a in 12..59 && p.b in 12..39, "$p")
        }
        val m = MathChallenge(Random(42))
        assertEquals(MathChallenge.Result.Solved, m.check(m.current.answer.toString()))
        val w = MathChallenge(Random(7))
        val first = w.current
        assertEquals(MathChallenge.Result.Wrong, w.check(""))
        assertEquals(MathChallenge.Result.Wrong, w.check("  "))
        assertEquals(MathChallenge.Result.Wrong, w.check("abc"))
        assertEquals(MathChallenge.Result.Wrong, w.check((first.answer + 1).toString()))
        val third = w.check("0") // empty inputs did not count: this is the 3rd miss
        assertTrue(third is MathChallenge.Result.NewProblem, "$third")
        assertEquals((third as MathChallenge.Result.NewProblem).p, w.current)
        assertEquals(MathChallenge.Result.Solved, w.check(" ${w.current.answer} "))
        assertEquals(3, c.mathMaxWrong)
    }

    @Test
    fun a25_swipeRule() {
        assertEquals(0f, SwipeRule.fraction(-10f, 300f, 72f))
        assertEquals(1f, SwipeRule.fraction(500f, 300f, 72f))
        assertEquals(0.5f, SwipeRule.fraction(114f, 300f, 72f), 1e-4f)
        assertEquals(0f, SwipeRule.fraction(10f, 72f, 72f))
        assertFalse(SwipeRule.isComplete(0.94f))
        assertTrue(SwipeRule.isComplete(0.95f))
        assertTrue(SwipeRule.isComplete(1.2f))
        assertFalse(SwipeRule.isComplete(-0.1f))
    }

    @Test
    fun a26_focusPolicy() {
        for (call in CallState.entries) {
            assertTrue(FocusPolicy.shouldPlay(FocusState.GRANTED, call))
            assertTrue(FocusPolicy.shouldPlay(FocusState.FAILED, call))
            assertFalse(FocusPolicy.shouldPlay(FocusState.DELAYED, call))
        }
        assertFalse(FocusPolicy.shouldPlay(FocusState.LOST, CallState.IN_CALL))
        assertTrue(FocusPolicy.shouldPlay(FocusState.LOST, CallState.NONE))
    }
}
