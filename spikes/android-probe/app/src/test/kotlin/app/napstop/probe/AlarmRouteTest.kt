package app.napstop.probe

import org.junit.Assert.assertEquals
import org.junit.Test

/** U39 (docs/spikes/S2.md "Vòng 4" V4-3). */
class AlarmRouteTest {

    @Test
    fun `U39 fallback route`() {
        assertEquals(AlarmRoute.Fallback.NONE, AlarmRoute.forFallback(alarmFired = true, probeAlive = true))
        assertEquals(AlarmRoute.Fallback.NONE, AlarmRoute.forFallback(alarmFired = true, probeAlive = false))
        assertEquals(AlarmRoute.Fallback.PROBE_SERVICE, AlarmRoute.forFallback(alarmFired = false, probeAlive = true))
        assertEquals(AlarmRoute.Fallback.RING_SERVICE, AlarmRoute.forFallback(alarmFired = false, probeAlive = false))
    }

    @Test
    fun `U39 ring service FGS types by API level`() {
        val both = listOf("systemExempted", "mediaPlayback")
        assertEquals(both, AlarmRoute.ringFgsTypes(36))
        assertEquals(both, AlarmRoute.ringFgsTypes(34))
        assertEquals(listOf("mediaPlayback"), AlarmRoute.ringFgsTypes(33))
        assertEquals(listOf("mediaPlayback"), AlarmRoute.ringFgsTypes(29))
        assertEquals(listOf("none"), AlarmRoute.ringFgsTypes(28))
        assertEquals(listOf("none"), AlarmRoute.ringFgsTypes(26))
    }
}
