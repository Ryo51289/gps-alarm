package app.napstop.core.trip.unit

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.BatteryState
import app.napstop.core.trip.EngineParams
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.GpsStatus
import app.napstop.core.trip.LowBatteryRisk
import app.napstop.core.trip.SamplingTier
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.observedRate
import app.napstop.core.trip.policyFor
import app.napstop.core.trip.support.EngineDriver
import app.napstop.core.trip.support.S
import app.napstop.core.trip.support.cfg
import app.napstop.core.trip.support.driverFrom
import app.napstop.core.trip.support.trackingState
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class BatteryRuleTest {
    private val p = EngineParams()

    /** TRACKING, stopped 406 km away at closingV 12.5 m/s: predicted (no battery) = now + 9 h; far zone (SPARSE). */
    private fun farState(): EngineState =
        trackingState(cfg(), d = 406_000.0, ground = 15.0, closing = 12.5, inStop = true, tier = SamplingTier.SPARSE)

    private fun alarmReasons(e: EngineDriver) = e.all<Alarm>().map { it.reason }

    @Test
    fun `U29 risk event once with available 450 min and needed 555 min`() {
        val e = driverFrom(farState())
        val s = e.battery(0, 20)
        assertEquals(LowBatteryRisk(S, 20, 450, 555), s.events.filterIsInstance<LowBatteryRisk>().single())
        assertTrue(s.view.batteryRisk)
        assertTrue(e.battery(60, 20).events.none { it is LowBatteryRisk })
    }

    @Test
    fun `U30 charging never risks nor alarms`() {
        val e = driverFrom(farState())
        e.battery(0, 6, charging = true)
        e.battery(60, 5, charging = true)
        assertTrue(e.all<LowBatteryRisk>().isEmpty())
        assertTrue(e.all<Alarm>().isEmpty())
    }

    @Test
    fun `U31 alarm at 5 percent, also after choosing AT_5 at 20 percent (test report 2)`() {
        val e = driverFrom(farState())
        e.battery(0, 6)
        assertTrue(e.all<Alarm>().isEmpty())
        val a = e.battery(60, 5).events.filterIsInstance<Alarm>().single()
        assertEquals(AlarmReason.LOW_BATTERY, a.reason)
        assertEquals(5, a.batteryPct)
        val b = driverFrom(farState())
        b.battery(0, 20)
        b.user(1, UserActionKind.BATTERY_ALARM_AT_5)
        b.battery(60, 6)
        assertEquals(5, b.battery(120, 5).events.filterIsInstance<Alarm>().single().batteryPct)
    }

    @Test
    fun `U32 alarm earlier at 15 percent, max saving doubles SPARSE and MEDIUM`() {
        val e = driverFrom(farState())
        e.battery(0, 18)
        e.user(1, UserActionKind.BATTERY_ALARM_EARLIER)
        e.battery(60, 16)
        assertTrue(e.all<Alarm>().isEmpty())
        assertEquals(listOf(AlarmReason.LOW_BATTERY), alarmReasons(e.also { it.battery(120, 15) }))
        assertEquals(360, policyFor(SamplingTier.SPARSE, p, true).intervalS)
        assertEquals(60, policyFor(SamplingTier.MEDIUM, p, true).intervalS)
        assertEquals(5, policyFor(SamplingTier.DENSE, p, true).intervalS)
        val m = driverFrom(farState())
        assertEquals(360, m.user(0, UserActionKind.BATTERY_MAX_SAVING).view.samplingPolicy!!.intervalS)
    }

    @Test
    fun `U32 b choosing AT_5 before any risk suppresses LowBatteryRisk and keeps the policy (C8)`() {
        val chosen = driverFrom(farState())
        chosen.user(0, UserActionKind.BATTERY_ALARM_AT_5)
        val plain = driverFrom(farState())
        for (t in listOf(10, 600, 1200)) {
            val a = chosen.battery(t, 20)
            val b = plain.battery(t, 20)
            assertEquals(b.view.samplingPolicy, a.view.samplingPolicy)
        }
        assertTrue(chosen.all<LowBatteryRisk>().isEmpty())
        assertEquals(1, plain.all<LowBatteryRisk>().size)
    }

    @Test
    fun `U32 c max saving then alarm earlier returns SPARSE to 180 s (C8)`() {
        val e = driverFrom(farState())
        e.battery(0, 30)
        assertEquals(360, e.user(1, UserActionKind.BATTERY_MAX_SAVING).view.samplingPolicy!!.intervalS)
        assertEquals(180, e.user(2, UserActionKind.BATTERY_ALARM_EARLIER).view.samplingPolicy!!.intervalS)
    }

    @Test
    fun `U33 observed drain rate`() {
        val b = BatteryState(20, false, S, 21, true, false, null, null)
        assertEquals(2.0, observedRate(b, S + 1_800_000, p))
        assertNull(observedRate(b.copy(levelPct = 21), S + 1_800_000, p))
    }

    @Test
    fun `U65 rate window boundary`() {
        val b = BatteryState(20, false, S, 21, true, false, null, null)
        assertNull(observedRate(b, S + 1_199_999, p))
        assertEquals(3.0, observedRate(b, S + 1_200_000, p))
    }

    @Test
    fun `U79 low battery keeps its own reason when GPS is lost, earlier threshold 12, not armed at start`() {
        val lost = trackingState(cfg(), now = S + 60_000, lastFixAt = S, d = 406_000.0, ground = 15.0, closing = 12.5, gps = GpsStatus.LOST, tier = SamplingTier.SPARSE,
            battery = BatteryState(6, false, S, 6, true, false, null, null))
        val a = driverFrom(lost)
        assertEquals(AlarmReason.LOW_BATTERY, a.battery(61, 5).events.filterIsInstance<Alarm>().single().reason)
        val b = driverFrom(farState())
        b.battery(0, 13)
        b.user(1, UserActionKind.BATTERY_ALARM_EARLIER)
        assertEquals(12, b.state.battery.choicePct)
        b.battery(60, 13)
        assertTrue(b.all<Alarm>().isEmpty())
        assertEquals(AlarmReason.LOW_BATTERY, b.battery(120, 12).events.filterIsInstance<Alarm>().single().reason)
        val c = driverFrom(farState())
        c.battery(0, 4)
        c.battery(60, 3)
        assertTrue(c.all<Alarm>().isEmpty())
    }
}
