package app.napstop.core.trip.runtime

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.runtime.support.TestData
import app.napstop.core.trip.runtime.support.World
import app.napstop.core.trip.runtime.support.fixNorth
import app.napstop.core.trip.runtime.support.startTrip
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * Tester T16 (out of spec): the snooze end when NO fix arrives after "Báo lại" (phone face down, GPS lost, or the process
 * restored HEADLESS after a reboot). Emulator 04/11/2026 (RB1): right after Snoozed the scheduled wake was the ALARMING tick
 * (wakeAt = snoozeUntil − 239 ms, EXACT_IDLE); ALARM_CLOCK (D17) only came with the next fix. Whatever mechanism is used, the
 * snooze-end ring must come on time: this test pins the timing (± 1 s of snoozeUntil) and records the mechanisms seen.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TesterT16SnoozeWakeTest {
    @Test
    fun snoozeEndRingsOnTimeWithoutAnyFixAfterTheSnooze() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(TestData.meta())
            var m = 1_300.0
            while (m >= 900.0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            assertEquals(TripPhase.ALARMING, w.seen.last().view.phase)
            w.advance(7_000) // the user looks at the screen for a few seconds
            w.alarm.facts["t1"]!!.ringing = false
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SNOOZED, w.nowMs)) }
            val snoozed = w.events.map { it.second }.filterIsInstance<Snoozed>().single()
            assertEquals(TripPhase.SNOOZED, w.seen.last().view.phase)
            val mechanisms = ArrayList<Pair<WakeMechanism, Long>>()
            w.scheduler.wake?.let { mechanisms += it.mechanism to it.wakeAtMs }
            val ringsBefore = w.alarm.ringNowCalls.size
            // No more fixes: only the fake OS delivers (wake / fallback), 250 ms steps up to snoozeUntil + 40 s.
            while (w.nowMs < snoozed.untilMs + 40_000 && w.alarm.ringNowCalls.size == ringsBefore) {
                w.advance(250)
                w.deliverDue(null, "t1")
                w.scheduler.wake?.let { if (mechanisms.lastOrNull() != (it.mechanism to it.wakeAtMs)) mechanisms += it.mechanism to it.wakeAtMs }
            }
            val ring = w.alarm.ringNowCalls.drop(ringsBefore).firstOrNull()
            assertTrue(ring != null, "a ring after the snooze (wakes seen: $mechanisms)")
            assertEquals(AlarmReason.SNOOZE_END, ring!!.reason, "wakes seen: $mechanisms")
            assertTrue(w.nowMs - snoozed.untilMs in 0..1_000, "snooze end ${w.nowMs - snoozed.untilMs} ms after snoozeUntil (wakes: $mechanisms)")
        }

    /**
     * Same, phone in Doze after the snooze, the allow-while-idle quota (9 min, [A-DOZE]) used by the ALARMING tick that
     * just fired. D17 wants the snooze end "đúng giờ cả khi Doze"; the T15 net is the fallback setAlarmClock at
     * snoozeUntil + 30 s. Asserts D17 (± 1 s).
     */
    @Test
    fun snoozeEndInDozeWithoutAnyFix() =
        runTest {
            val w = World(this)
            w.listen()
            w.startTrip(TestData.meta())
            var m = 1_300.0
            while (m >= 900.0) {
                w.fixNorth(m)
                w.advance(5_000)
                m -= 75.0
            }
            w.advance(7_000)
            w.alarm.facts["t1"]!!.ringing = false
            w.now { w.runtime.onRingEvent(RingEvent("t1", RingEventKind.SNOOZED, w.nowMs)) }
            val snoozed = w.events.map { it.second }.filterIsInstance<Snoozed>().single()
            w.scheduler.doze = true
            w.scheduler.lastAllowWhileIdleElapsed = w.time.elapsedMs() - 60_000 // an allow-while-idle alarm fired 1 min ago
            val mechanisms = ArrayList<Pair<WakeMechanism, Long>>()
            w.scheduler.wake?.let { mechanisms += it.mechanism to it.wakeAtMs }
            val ringsBefore = w.alarm.ringNowCalls.size + w.alarm.ringFallbackCalls.size
            while (w.nowMs < snoozed.untilMs + 120_000 && w.alarm.ringNowCalls.size + w.alarm.ringFallbackCalls.size == ringsBefore) {
                w.advance(250)
                w.deliverDue(null, "t1")
                w.scheduler.wake?.let { if (mechanisms.lastOrNull() != (it.mechanism to it.wakeAtMs)) mechanisms += it.mechanism to it.wakeAtMs }
            }
            val late = w.nowMs - snoozed.untilMs
            assertTrue(w.alarm.ringNowCalls.size + w.alarm.ringFallbackCalls.size > ringsBefore, "a ring after the snooze (wakes: $mechanisms)")
            assertTrue(late in 0..1_000, "snooze end in Doze $late ms after snoozeUntil; wakes $mechanisms; fallbacks ${w.alarm.ringFallbackCalls.size}")
        }
}
