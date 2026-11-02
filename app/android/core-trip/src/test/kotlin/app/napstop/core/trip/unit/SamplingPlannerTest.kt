package app.napstop.core.trip.unit

import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.SamplingTier.DENSE
import app.napstop.core.trip.SamplingTier.MEDIUM
import app.napstop.core.trip.SamplingTier.SPARSE
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.targetTier
import app.napstop.core.trip.tierOf
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class SamplingPlannerTest {
    private val p = EngineParams()

    @Test
    fun `U39 tiers with hysteresis, phase rules, emitted only on change`() {
        assertEquals(SPARSE, tierOf(4000.0, SPARSE, p))
        assertEquals(MEDIUM, tierOf(4000.0, MEDIUM, p))
        assertEquals(MEDIUM, tierOf(3500.0, SPARSE, p))
        assertEquals(DENSE, tierOf(800.0, SPARSE, p))
        assertEquals(DENSE, tierOf(1100.0, DENSE, p))
        assertEquals(MEDIUM, tierOf(1200.0, DENSE, p))
        assertEquals(DENSE, targetTier(TripPhase.ACQUIRING, 99_999.0, null, false, GpsStatus.NO_FIX_YET, p))
        assertEquals(DENSE, targetTier(TripPhase.ALARMING, 99_999.0, SPARSE, true, GpsStatus.OK, p))
        assertEquals(MEDIUM, targetTier(TripPhase.TRACKING, 99_999.0, SPARSE, false, GpsStatus.OK, p))
        assertEquals(null, targetTier(TripPhase.ENDED, 1.0, SPARSE, true, GpsStatus.OK, p))
        val e = EngineDriver(cfg())
        assertEquals(1, e.last.events.filterIsInstance<SamplingPolicyChanged>().size)
        assertEquals(0, e.tick(5).events.filterIsInstance<SamplingPolicyChanged>().size)
        val far = driverFrom(trackingState(d = 500_000.0, inStop = true, tier = MEDIUM))
        assertEquals(SPARSE, far.tick(1).events.filterIsInstance<SamplingPolicyChanged>().single().policy.tier)
        assertEquals(0, far.tick(2).events.size)
    }

    @Test
    fun `U62 tierOf without prediction keeps the tier, lost GPS never lowers`() {
        assertEquals(MEDIUM, tierOf(null, MEDIUM, p))
        assertEquals(DENSE, targetTier(TripPhase.TRACKING, 5000.0, DENSE, true, GpsStatus.LOST, p))
        assertEquals(DENSE, targetTier(TripPhase.TRACKING, 300.0, SPARSE, true, GpsStatus.LOST, p))
    }
}
