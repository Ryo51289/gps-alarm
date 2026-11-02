package app.napstop.core.trip.unit

import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.support.EngineDriver
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class FixFilterTest {
    @Test
    fun `U04 fix age 60000 ms accepted, 60001 ms dropped`() {
        val a = EngineDriver()
        a.fix(10, 50_000.0, ageMs = 60_000)
        assertTrue(a.state.last != null) // accepted (then immediately past lostAfterS: a 60 s old fix is not a live GPS)
        assertEquals(0, a.view.droppedFixes)
        val b = EngineDriver()
        b.fix(10, 50_000.0, ageMs = 60_001)
        assertEquals(GpsStatus.NO_FIX_YET, b.view.gps)
        assertEquals(1, b.view.droppedFixes)
        assertTrue(b.all<GpsRecovered>().isEmpty())
    }

    @Test
    fun `U05 accuracy gate drop accept drop`() {
        EngineDriver().apply { fix(0, 1000.0, acc = 150.0); assertEquals(1, view.droppedFixes) }
        EngineDriver().apply { fix(0, 50_000.0, acc = 1500.0); assertEquals(0, view.droppedFixes); assertEquals(GpsStatus.OK, view.gps) }
        EngineDriver().apply { fix(0, 50_000.0, acc = 2500.0); assertEquals(1, view.droppedFixes) }
    }

    @Test
    fun `U06 three 3_3 km jumps in 10 s are dropped and dSmooth does not jump`() {
        val e = EngineDriver()
        e.fix(0, 20_000.0)
        e.fix(5, 19_980.0)
        for (t in listOf(10, 15, 20)) {
            e.fix(t, 16_700.0)
            assertTrue(e.state.dSmooth!! > 19_000.0)
        }
        e.fix(25, 19_900.0)
        assertEquals(3, e.view.droppedFixes)
        assertEquals(19_900.0, e.state.dSmooth!!, 1e-6)
        assertTrue(e.state.rejects.isEmpty())
    }

    @Test
    fun `U07 four consistent far fixes re-anchor at the third`() {
        val e = EngineDriver()
        e.fix(0, 20_000.0)
        e.fix(15, 15_000.0)
        e.fix(30, 15_010.0)
        assertEquals(2, e.view.droppedFixes)
        e.fix(45, 15_020.0)
        assertEquals(2, e.view.droppedFixes)
        assertEquals(1, e.state.recent.size)
        assertEquals(15_020.0, e.state.minD!!, 1e-6)
        assertEquals(15_020.0, e.state.recent[0].d, 1e-6)
        e.fix(60, 15_030.0)
        assertEquals(2, e.view.droppedFixes)
        assertEquals(15_030.0, e.state.last!!.d, 1e-6)
    }

    @Test
    fun `U59 sliding reject window, implausible pair blocks re-anchor, re-anchor while stopped`() {
        val e = EngineDriver()
        e.fix(0, 20_000.0)
        e.fix(5, 10_000.0)
        e.fix(30, 15_000.0)
        e.fix(35, 15_010.0) // window [5, 30, 35]: span 30 but pair (5, 30) implausible -> no re-anchor
        assertEquals(3, e.view.droppedFixes)
        e.fix(40, 15_020.0)
        assertEquals(listOf(30_000L, 35_000L, 40_000L), e.state.rejects.map { it.fixAtMs - e.startMs })
        e.fix(60, 15_030.0)
        assertEquals(5, e.view.droppedFixes)
        e.fix(70, 15_040.0) // window [40, 60, 70]: span 30, both pairs plausible -> re-anchor
        assertEquals(5, e.view.droppedFixes)
        assertTrue(e.state.rejects.isEmpty())

        val s = EngineDriver()
        s.fix(0, 21_000.0, spd = 10.0)
        s.fix(5, 20_950.0, spd = 10.0)
        s.fix(10, 20_950.0, spd = 0.0)
        val g = s.state.ground
        val samples = s.state.movingSamples
        assertTrue(s.state.stopStartMs != null)
        for (t in listOf(15, 30, 45)) s.fix(t, 15_000.0 + t)
        assertNull(s.state.stopStartMs)
        assertNull(s.state.stopAnchor)
        assertEquals(listOf(15_045.0), s.state.last3.map { Math.round(it * 1e6) / 1e6 })
        assertEquals(g, s.state.ground)
        assertEquals(samples, s.state.movingSamples)
        assertTrue(s.state.rejects.isEmpty())
    }
}
