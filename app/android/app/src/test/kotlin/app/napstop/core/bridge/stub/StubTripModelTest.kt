package app.napstop.core.bridge.stub

import app.napstop.core.bridge.AlarmModeMsg
import app.napstop.core.bridge.AlarmMsg
import app.napstop.core.bridge.AlarmReasonMsg
import app.napstop.core.bridge.ArrivedMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.EndReasonMsg
import app.napstop.core.bridge.FallbackStatusMsg
import app.napstop.core.bridge.GpsLostCauseMsg
import app.napstop.core.bridge.GpsLostMsg
import app.napstop.core.bridge.GpsRecoveredMsg
import app.napstop.core.bridge.GpsStatusMsg
import app.napstop.core.bridge.LowBatteryRiskMsg
import app.napstop.core.bridge.OvershootMsg
import app.napstop.core.bridge.PreAlertMsg
import app.napstop.core.bridge.SnoozedMsg
import app.napstop.core.bridge.TripConfigMsg
import app.napstop.core.bridge.TripEndedMsg
import app.napstop.core.bridge.TripOutcomeMsg
import app.napstop.core.bridge.TripPhaseMsg
import app.napstop.core.bridge.TripStateMsg
import app.napstop.core.bridge.TripStateUpdateMsg
import app.napstop.core.bridge.TripUpdateMsg
import kotlin.math.floor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** K04-K13 (spec T14 §5.4). */
class StubTripModelTest {
    private val t0 = 1_700_000_000_000L

    private class Run(val config: TripConfigMsg, val scenario: StubScenario, val speed: Double, val t0: Long) {
        var state: StubTripState = StubTripModel.start(config, scenario, speed, simulated = true, nowMs = t0).state

        /** Real clock at virtual second [v]. */
        fun at(v: Double): Long = t0 + floor(v * 1000.0 / speed + 0.5).toLong()

        fun advanceTo(v: Double): StubStep = StubTripModel.advance(state, at(v)).also { state = it.state }

        fun advanceAt(ms: Long): StubStep = StubTripModel.advance(state, ms).also { state = it.state }

        fun act(action: StubAction, ms: Long = state.nowMs): StubStep =
            StubTripModel.act(state, action, ms).also { state = it.state }
    }

    private fun StubStep.view(): TripStateMsg = (updates.first() as TripStateUpdateMsg).state

    private fun StubStep.events(): List<TripUpdateMsg> = updates.drop(1)

    private inline fun <reified T> StubStep.only(): List<T> = updates.filterIsInstance<T>()

    private fun assertStartsWithState(step: StubStep) {
        assertTrue("step must start with TripStateUpdateMsg", step.updates.first() is TripStateUpdateMsg)
        assertEquals(1, step.updates.count { it is TripStateUpdateMsg })
    }

    /** Runs K04 up to the main alarm; returns the alarm step. */
    private fun smartRunToAlarm(run: Run): StubStep {
        var ms = t0
        while (true) {
            ms += 100
            val step = run.advanceAt(ms)
            assertStartsWithState(step)
            if (step.only<AlarmMsg>().isNotEmpty()) return step
            check(ms - t0 < 60_000) { "no alarm" }
        }
    }

    @Test
    fun k04_normalSmartTimeline() {
        val run = Run(config(mode = AlarmModeMsg.SMART), StubScenario.NORMAL, 60.0, t0)
        val first = StubTripModel.view(run.state)
        assertEquals(TripPhaseMsg.ACQUIRING, first.phase)
        assertEquals(GpsStatusMsg.NO_FIX_YET, first.gps)
        assertNull(first.distanceM)
        val vAlarm = 5 + 11_000.0 / 15
        val predicted = t0 + floor(vAlarm * 1000 / 60 + 0.5).toLong()
        assertEquals(predicted, first.predictedAlarmAtMs)
        assertEquals(predicted + 500, first.fallbackAtMs)
        assertEquals(FallbackStatusMsg.CONFIRMED, first.fallbackStatus)

        // Every 100 ms real = 6 s virtual: v = 6 is the first tracking step.
        val tracking = run.advanceAt(t0 + 100)
        assertStartsWithState(tracking)
        assertEquals(TripPhaseMsg.TRACKING, tracking.view().phase)
        assertEquals(1, tracking.only<PreAlertMsg>().size)
        assertEquals(predicted, tracking.view().predictedAlarmAtMs)
        assertEquals(54.0, tracking.view().speedKmh!!, 0.0)

        var ms = t0 + 100
        var alarmStep: StubStep? = null
        while (alarmStep == null) {
            ms += 100
            val step = run.advanceAt(ms)
            assertStartsWithState(step)
            assertTrue(step.only<PreAlertMsg>().isEmpty())
            if (step.only<AlarmMsg>().isNotEmpty()) alarmStep = step
        }
        val v = (ms - t0) * 60 / 1000.0
        assertTrue(v >= vAlarm && v - 6 < vAlarm)
        val alarm = alarmStep.only<AlarmMsg>().single()
        assertEquals(AlarmReasonMsg.SMART_TIME, alarm.reason)
        assertTrue(alarm.ringNow)
        assertTrue(alarm.snoozeAllowed)
        assertEquals(ms, alarm.atMs)
        assertNull(alarm.batteryPct)
        val view = alarmStep.view()
        assertEquals(TripPhaseMsg.ALARMING, view.phase)
        assertTrue(view.alarmRinging)
        assertEquals(ms, view.alarmAtMs)
        assertEquals(AlarmReasonMsg.SMART_TIME, view.alarmReason)
        assertNull(view.predictedAlarmAtMs)
        assertEquals(alarm.distanceM, view.distanceM)
    }

    @Test
    fun k05_snoozeThenSnoozeEndThenNoSecondSnooze() {
        val run = Run(config(), StubScenario.NORMAL, 60.0, t0)
        smartRunToAlarm(run)
        val tA = run.state.nowMs

        val snoozed = run.act(StubAction.SNOOZE, tA)
        val msg = snoozed.only<SnoozedMsg>().single()
        assertEquals(tA + 1000, msg.untilMs)
        assertEquals(TripPhaseMsg.SNOOZED, snoozed.view().phase)
        assertFalse(snoozed.view().alarmRinging)
        assertEquals(1L, snoozed.view().snoozeCount)
        assertEquals(tA + 1000, snoozed.view().snoozeUntilMs)
        assertEquals(msg.untilMs + 500, snoozed.view().fallbackAtMs)

        assertTrue(run.advanceAt(tA + 999).only<AlarmMsg>().isEmpty())
        val again = run.advanceAt(tA + 1000)
        val alarm = again.only<AlarmMsg>().single()
        assertEquals(AlarmReasonMsg.SNOOZE_END, alarm.reason)
        assertFalse(alarm.snoozeAllowed)
        assertEquals(TripPhaseMsg.ALARMING, again.view().phase)

        val second = run.act(StubAction.SNOOZE, tA + 1100)
        assertTrue(second.only<SnoozedMsg>().isEmpty())
        assertEquals(TripPhaseMsg.ALARMING, second.view().phase)
        assertEquals(1L, second.view().snoozeCount)
    }

    @Test
    fun k06_dismissAfterSnoozeEndsSnoozed() {
        val run = Run(config(), StubScenario.NORMAL, 60.0, t0)
        smartRunToAlarm(run)
        val tA = run.state.nowMs
        run.act(StubAction.SNOOZE, tA)
        run.advanceAt(tA + 1000)

        val end = run.act(StubAction.DISMISS, tA + 1200)
        assertStartsWithState(end)
        val ended = end.updates.last() as TripEndedMsg
        assertEquals(TripOutcomeMsg.SNOOZED, ended.trip.outcome)
        assertEquals(EndReasonMsg.DISMISSED, ended.trip.endReason)
        assertEquals(tA + 1200, ended.trip.dismissedAtMs)
        assertEquals(tA + 1200, ended.trip.endedAtMs)
        assertEquals(tA, ended.trip.alarmAtMs)
        assertEquals(AlarmReasonMsg.SMART_TIME, ended.trip.alarmReason)
        assertEquals(1L, ended.trip.snoozeCount)
        assertEquals(ended.trip, end.finished)
        assertEquals(TripPhaseMsg.ENDED, end.view().phase)
        assertEquals(TripOutcomeMsg.SNOOZED, end.view().outcome)
        assertNull(end.view().samplingTier)

        // Nothing after TripEnded (§2 rule 5).
        assertTrue(run.advanceAt(tA + 5000).updates.isEmpty())
        assertTrue(run.act(StubAction.DISMISS, tA + 5000).updates.isEmpty())
    }

    @Test
    fun k07_stopWhileTrackingIsCancelled() {
        val run = Run(config(), StubScenario.NORMAL, 60.0, t0)
        run.advanceTo(100.0)
        assertEquals(TripPhaseMsg.TRACKING, run.state.phase)
        val end = run.act(StubAction.STOP)
        val trip = end.only<TripEndedMsg>().single().trip
        assertEquals(TripOutcomeMsg.CANCELLED, trip.outcome)
        assertEquals(EndReasonMsg.USER_STOP, trip.endReason)
        assertNull(trip.alarmAtMs)
        assertNull(trip.dismissedAtMs)
        assertEquals(t0, trip.startedAtMs)
    }

    @Test
    fun k08_alarmUnansweredForAnHourIsMissed() {
        val run = Run(config(), StubScenario.NORMAL, 60.0, t0)
        smartRunToAlarm(run)
        val tA = run.state.lastRingAtMs!!
        assertTrue(run.advanceAt(tA + 59_999).only<TripEndedMsg>().isEmpty())
        val end = run.advanceAt(tA + 60_000)
        val trip = end.only<TripEndedMsg>().single().trip
        assertEquals(EndReasonMsg.ALARM_UNANSWERED, trip.endReason)
        assertEquals(TripOutcomeMsg.MISSED, trip.outcome)
        assertEquals(TripPhaseMsg.ENDED, end.view().phase)
    }

    @Test
    fun k09_gpsLostAndRecovered() {
        val run = Run(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), StubScenario.GPS_LOST, 60.0, t0)
        run.advanceTo(10.0)
        assertTrue(run.advanceTo(59.9).only<GpsLostMsg>().isEmpty())
        val lost = run.advanceTo(60.0)
        val msg = lost.only<GpsLostMsg>().single()
        assertEquals(GpsLostCauseMsg.NO_FIX_TIMEOUT, msg.cause)
        assertEquals(15L, msg.lastFixAgeS)
        assertEquals(GpsStatusMsg.LOST, lost.view().gps)
        assertTrue(lost.view().isEstimated)
        assertEquals(30L, lost.view().distanceErrorM)
        assertNull(lost.view().speedKmh)

        val mid = run.advanceTo(120.0)
        assertTrue(mid.only<GpsLostMsg>().isEmpty())
        assertEquals(150L, mid.view().distanceErrorM)

        val back = run.advanceTo(240.0)
        assertEquals(180L, back.only<GpsRecoveredMsg>().single().lostForS)
        assertEquals(GpsStatusMsg.OK, back.view().gps)
        assertFalse(back.view().isEstimated)
        assertNull(back.view().distanceErrorM)
        assertTrue(run.advanceTo(300.0).events().none { it is GpsLostMsg || it is GpsRecoveredMsg })
    }

    @Test
    fun k10_lowBatteryOnceAndChoiceIsKept() {
        val run = Run(config(), StubScenario.LOW_BATTERY, 60.0, t0)
        run.advanceTo(10.0)
        assertFalse(run.state.lowBatteryEmitted)
        val risk = run.advanceTo(30.0)
        val msg = risk.only<LowBatteryRiskMsg>().single()
        assertEquals(30L, msg.levelPct)
        assertEquals(40L, msg.availableMin)
        assertEquals(55L, msg.neededMin)
        assertTrue(risk.view().batteryRisk)
        assertEquals(30L, risk.view().batteryPct)

        val chosen = run.act(StubAction.BATTERY_ALARM_EARLIER)
        assertEquals(BatteryChoiceMsg.ALARM_EARLIER, chosen.view().batteryChoice)
        val later = run.advanceTo(120.0)
        assertTrue(later.only<LowBatteryRiskMsg>().isEmpty())
        assertEquals(BatteryChoiceMsg.ALARM_EARLIER, later.view().batteryChoice)
        assertEquals(28L, later.view().batteryPct)
        assertEquals(BatteryChoiceMsg.MAX_SAVING, run.act(StubAction.BATTERY_MAX_SAVING).view().batteryChoice)
    }

    @Test
    fun k11a_overshootWhileRingingAddsNoAlarm() {
        val run = Run(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), StubScenario.OVERSHOOT, 60.0, t0)
        run.advanceTo(10.0)
        val alarm = run.advanceTo(1272.0)
        assertEquals(AlarmReasonMsg.DISTANCE, alarm.only<AlarmMsg>().single().reason)

        assertTrue(run.advanceTo(1404.0).only<OvershootMsg>().isEmpty())
        val over = run.advanceTo(1410.0)
        val msg = over.only<OvershootMsg>().single()
        assertTrue(msg.pastM >= 1000)
        assertTrue(over.only<AlarmMsg>().isEmpty())
        assertEquals(TripPhaseMsg.OVERSHOT, over.view().phase)
        assertEquals(msg.pastM, over.view().overshootPastM)
        assertEquals(1.0, over.view().progress!!, 0.0)
        assertNull(over.view().etaS)
    }

    @Test
    fun k11b_overshootWhileSnoozedRingsAgain() {
        val run = Run(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), StubScenario.OVERSHOOT, 60.0, t0)
        run.advanceTo(10.0)
        run.advanceTo(1272.0)
        run.act(StubAction.SNOOZE, run.at(1400.0))
        assertEquals(TripPhaseMsg.SNOOZED, run.state.phase)

        val over = run.advanceTo(1410.0)
        assertEquals(listOf(AlarmMsg::class, OvershootMsg::class), over.events().map { it::class })
        val alarm = over.only<AlarmMsg>().single()
        assertEquals(AlarmReasonMsg.OVERSHOOT, alarm.reason)
        assertTrue(alarm.ringNow)
        assertFalse(alarm.snoozeAllowed)
        assertEquals(TripPhaseMsg.OVERSHOT, over.view().phase)
        assertTrue(over.view().alarmRinging)

        val end = run.act(StubAction.DISMISS)
        assertEquals(TripOutcomeMsg.MISSED, end.only<TripEndedMsg>().single().trip.outcome)
        assertEquals(AlarmReasonMsg.DISTANCE, end.finished!!.alarmReason)
    }

    @Test
    fun k12_noFixNeverAcquiredThenTimeout() {
        val run = Run(config(), StubScenario.NO_FIX, 60.0, t0)
        assertTrue(run.advanceTo(119.0).events().isEmpty())
        val lost = run.advanceTo(120.0)
        val msg = lost.only<GpsLostMsg>().single()
        assertEquals(GpsLostCauseMsg.NEVER_ACQUIRED, msg.cause)
        assertNull(msg.lastFixAgeS)
        assertEquals(GpsStatusMsg.NO_FIX_YET, lost.view().gps)
        assertEquals(TripPhaseMsg.ACQUIRING, lost.view().phase)
        assertNull(lost.view().distanceM)
        assertNull(lost.view().alarmMarkerProgress)
        assertEquals(run.at(14_400.0), lost.view().predictedAlarmAtMs)

        assertTrue(run.advanceTo(14_399.0).only<AlarmMsg>().isEmpty())
        val timeout = run.advanceTo(14_400.0)
        assertEquals(AlarmReasonMsg.TIMEOUT, timeout.only<AlarmMsg>().single().reason)
        assertEquals(TripPhaseMsg.ALARMING, timeout.view().phase)
        assertNull(timeout.view().distanceM)
    }

    @Test
    fun k13_eventOrderWithinOneStep() {
        val run = Run(config(mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), StubScenario.NORMAL, 60.0, t0)
        val step = run.advanceTo(1400.0)
        assertEquals(
            listOf(TripStateUpdateMsg::class, ArrivedMsg::class, AlarmMsg::class),
            step.updates.map { it::class },
        )
        assertEquals(AlarmReasonMsg.DISTANCE, step.only<AlarmMsg>().single().reason)
        assertNotNull(step.view().alarmAtMs)
        assertFalse(step.view().preAlertFired)
    }

    @Test
    fun clockNeverGoesBackwards() {
        val run = Run(config(), StubScenario.NORMAL, 60.0, t0)
        run.advanceAt(t0 + 1000)
        val back = run.advanceAt(t0 + 500)
        assertEquals(t0 + 1000, back.view().atMs)
    }

    @Test
    fun timeModeTriggerDistance() {
        val cfg = config(mode = AlarmModeMsg.TIME, timeThresholdMin = 15)
        assertEquals(13_500.0, StubTripModel.dTrig(cfg), 0.0)
        assertEquals(9_000.0, StubTripModel.dTrig(config(mode = AlarmModeMsg.SMART)), 0.0)
        // dTrig >= D0: rings at the first fix.
        val far = config(mode = AlarmModeMsg.TIME, timeThresholdMin = 60)
        assertEquals(5.0, StubTripModel.vAlarm(far), 0.0)
        val run = Run(far, StubScenario.NORMAL, 60.0, t0)
        assertEquals(AlarmReasonMsg.TIME, run.advanceTo(6.0).only<AlarmMsg>().single().reason)
    }
}
