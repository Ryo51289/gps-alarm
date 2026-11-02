package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.Arrived
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.LocationFix
import app.napstop.core.trip.LowBatteryRisk
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.SnapshotFormatException
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripSummary
import app.napstop.core.trip.TripView
import app.napstop.core.trip.support.LatLng
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test

class PrivacyTest {
    @Test
    fun `U56 events and view have no coordinate fields`() {
        val classes = listOf(
            PreAlert::class.java, Alarm::class.java, Snoozed::class.java, GpsLost::class.java, GpsRecovered::class.java,
            LowBatteryRisk::class.java, Overshoot::class.java, Arrived::class.java, FallbackAlarmChanged::class.java,
            SamplingPolicyChanged::class.java, TripEnded::class.java, TripSummary::class.java, TripView::class.java,
        )
        val banned = setOf("lat", "lng", "latitude", "longitude")
        for (c in classes) for (f in c.declaredFields) assertFalse(f.name.lowercase() in banned, "${c.simpleName}.${f.name}")
    }

    @Test
    fun `U80 toString and error messages never contain coordinates or values`() {
        val c = cfg(AlarmMode.DISTANCE, dest = LatLng(21.0285123, 105.8))
        val fix = LocationFix(S, S, 16.4637211, 107.1, 8.0, 3.0)
        val step0 = TripEngine.start(c, EngineParams(), S)
        val step = TripEngine.reduce(step0.state, fix)
        val texts = listOf(c.toString(), fix.toString(), step.state.toString(), step.toString(), step.state.last.toString())
        for (t in texts) {
            assertFalse(t.contains("21.0285"), t)
            assertFalse(t.contains("16.4637"), t)
        }
        val e = assertThrows(IllegalArgumentException::class.java) { TripEngine.start(c.copy(destLat = 95.0), EngineParams(), S) }
        assertFalse(e.message!!.contains("95"))
        val snap = TripEngine.encodeSnapshot(step.state).replace("\"accM\":8.0", "\"accM\":\"16.4637\"")
        val se = assertThrows(SnapshotFormatException::class.java) { TripEngine.decodeSnapshot(snap) }
        assertFalse(se.message!!.contains("16.4637"))
    }
}
