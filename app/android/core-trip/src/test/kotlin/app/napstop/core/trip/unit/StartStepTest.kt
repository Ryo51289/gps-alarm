package app.napstop.core.trip.unit

import app.napstop.core.trip.AccuracyLevel
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.SamplingPolicy
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** C3, C4, C5 of T12 §5 (no T10 U-ID: helper class for the canonical readings). */
class StartStepTest {
    @Test
    fun `C3 start emits DENSE then the deadline fallback`() {
        val e = EngineDriver()
        assertEquals(
            listOf(
                SamplingPolicyChanged(S, SamplingPolicy(SamplingTier.DENSE, 5, 2, AccuracyLevel.HIGH)),
                FallbackAlarmChanged(S, S + 10_980_000, FallbackCause.ETA),
            ),
            e.last.events,
        )
        assertEquals(TripPhase.ACQUIRING, e.view.phase)
        assertEquals(S + 120_000, e.view.wakeAtMs)
    }

    @Test
    fun `C4 alarm numeric fields equal the view of the same Step`() {
        val e = EngineDriver()
        e.battery(0, 50)
        val s = e.fix(5, 800.0)
        val a = s.events.filterIsInstance<Alarm>().single()
        assertEquals(s.view.distanceM, a.distanceM)
        assertEquals(s.view.etaS, a.etaS)
        assertEquals(50, a.batteryPct)
        assertEquals(s.view.batteryPct, a.batteryPct)
    }

    @Test
    fun `C5 lost and recovered fields`() {
        val e = EngineDriver()
        val never = e.tick(120).events.filterIsInstance<GpsLost>().single()
        assertEquals(GpsLost(S + 120_000, GpsLostCause.NEVER_ACQUIRED, null), never)
        assertEquals(S + 120_000, e.state.gpsLostAtMs)
        assertEquals(GpsRecovered(S + 130_500, 11), e.feed(app.napstop.core.trip.LocationFix(S + 130_500, S + 130_500, -0.4, 106.0, 8.0, null)).events.filterIsInstance<GpsRecovered>().single())
        val l = e.avail(140, AvailabilityCause.SERVICES_OFF).events.filterIsInstance<GpsLost>().single()
        assertEquals(GpsLost(S + 140_000, GpsLostCause.SERVICES_OFF, 10), l)
        assertTrue(e.state.gpsLostAtMs == S + 140_000)
    }
}
