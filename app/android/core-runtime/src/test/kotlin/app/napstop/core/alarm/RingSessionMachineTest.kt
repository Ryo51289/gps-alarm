package app.napstop.core.alarm

import app.napstop.core.alarm.AlarmData.record
import app.napstop.core.alarm.AlarmData.request
import app.napstop.core.alarm.AlarmData.start
import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.runtime.RingEventKind
import java.util.Locale
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/** T16 A11–A20: the ring session reducer (spec §5.5). */
class RingSessionMachineTest {
    private val c = AlarmConstants()
    private val now = 1_700_000_000_000L
    private val vi = Locale.forLanguageTag("vi-VN")

    private fun reduce(s: RingState, i: RingInput) = RingSessionMachine.reduce(s, i, c, vi)

    private fun startInput(s: RingStart = start(), hp: Boolean = false, stored: RingFactsRecord? = null, at: Long = now) =
        RingInput.Start(s, hp, stored, at, 9_000L, 7)

    private fun ringing(s: RingStart = start()): RingState = reduce(RingState(), startInput(s)).first

    private inline fun <reified T : RingFx> List<RingFx>.idx(): Int = indexOfFirst { it is T }

    @Test
    fun a11_startEffectsInOrder() {
        val (s, fx) = reduce(RingState(), startInput())
        assertEquals(RingPhase.RINGING, s.phase)
        val w = fx[0] as RingFx.WriteFacts
        assertTrue(w.sync)
        assertTrue(w.record.ringing)
        assertEquals(RingMode.SERVICE, w.record.mode)
        assertEquals(now, w.record.startedAtWallMs)
        assertEquals(9_000L, w.record.heartbeatElapsedMs)
        val kinds = fx.map { it::class.simpleName }
        assertEquals(
            listOf(
                "WriteFacts", "AcquireWakeLock", "StartAudio", "StartVibration", "StartFlash", "WatchHeadphones", "ScheduleTimeout",
                "Heartbeat", "PublishUi", "PostNotification", "LaunchUi",
            ),
            kinds,
        )
        assertEquals(AudioRoute.SPEAKER, (fx[2] as RingFx.StartAudio).route)
        assertEquals(c.ringMaxMs, (fx.first { it is RingFx.ScheduleTimeout } as RingFx.ScheduleTimeout).inMs)
        // Vibrate only: no audio, strong vibration.
        val vib = start(request(settings = AlarmData.SETTINGS.copy(volume = 0.0, vibration = "off", flash = false)), launchUi = false)
        val (_, fx2) = reduce(RingState(), startInput(vib))
        assertEquals(-1, fx2.idx<RingFx.StartAudio>())
        assertEquals(VibrationPatterns.STRONG, (fx2.first { it is RingFx.StartVibration } as RingFx.StartVibration).spec)
        assertEquals(-1, fx2.idx<RingFx.LaunchUi>())
    }

    @Test
    fun a12_dismissWritesBeforeTheEvent() {
        val (s, fx) = reduce(ringing(), RingInput.UserDismiss(now + 5_000, routeBack = false))
        assertEquals(RingPhase.ENDED, s.phase)
        val w = fx[fx.idx<RingFx.WriteFacts>()] as RingFx.WriteFacts
        assertEquals(now + 5_000, w.record.pendingDismissAtWallMs)
        assertFalse(w.record.ringing)
        assertEquals(RingEnd.DISMISSED, w.record.endedBy)
        assertTrue(w.sync)
        assertTrue(fx.idx<RingFx.WriteFacts>() < fx.idx<RingFx.StopAudio>())
        assertTrue(fx.idx<RingFx.StopAudio>() < fx.idx<RingFx.SendEvent>())
        assertTrue(fx.idx<RingFx.SendEvent>() < fx.idx<RingFx.StopService>())
        assertEquals(RingFx.SendEvent(RingEventKind.DISMISSED, now + 5_000), fx[fx.idx<RingFx.SendEvent>()])
        assertEquals(-1, fx.idx<RingFx.OpenRouteBack>())
        val (_, fx2) = reduce(ringing(), RingInput.UserDismiss(now + 5_000, routeBack = true))
        assertEquals(RingFx.OpenRouteBack(AlarmData.TRIP), fx2[fx2.idx<RingFx.OpenRouteBack>()])
    }

    @Test
    fun a13_snoozeOnlyWhenAllowed() {
        val (s, fx) = reduce(ringing(), RingInput.UserSnooze(now + 20_000))
        assertEquals(RingPhase.ENDED, s.phase)
        val w = fx[0] as RingFx.WriteFacts
        assertEquals(now + 20_000, w.record.snoozedAtWallMs)
        assertEquals(RingEnd.SNOOZED, w.record.endedBy)
        assertTrue(fx.idx<RingFx.StopAudio>() < fx.idx<RingFx.SendEvent>())
        assertEquals(RingFx.SendEvent(RingEventKind.SNOOZED, now + 20_000), fx[fx.idx<RingFx.SendEvent>()])
        val no = ringing(start(request(snoozeAllowed = false)))
        val (s2, fx2) = reduce(no, RingInput.UserSnooze(now + 20_000))
        assertEquals(RingPhase.RINGING, s2.phase)
        assertTrue(fx2.isEmpty())
    }

    @Test
    fun a14_timeoutSilences() {
        val at = now + c.ringMaxMs
        val (s, fx) = reduce(ringing(), RingInput.Timeout(at))
        assertEquals(RingPhase.ENDED, s.phase)
        assertEquals(at, (fx[0] as RingFx.WriteFacts).record.silencedAtWallMs)
        assertEquals(RingEnd.SILENCED, (fx[0] as RingFx.WriteFacts).record.endedBy)
        assertEquals(RingFx.SendEvent(RingEventKind.SILENCED, at), fx[fx.idx<RingFx.SendEvent>()])
    }

    @Test
    fun a15_stopFromTheMainProcess() {
        val (s, fx) = reduce(ringing(), RingInput.Stop(AlarmData.TRIP, StopCause.TRIP_ENDED, 300L))
        assertEquals(RingPhase.ENDED, s.phase)
        assertEquals(-1, fx.idx<RingFx.SendEvent>())
        assertEquals(300L, (fx[0] as RingFx.WriteFacts).record.stopSeq)
        assertTrue(fx.last() is RingFx.StopService)
        val (s2, fx2) = reduce(RingState(), RingInput.Stop(AlarmData.TRIP, StopCause.TRIP_ENDED, 300L))
        assertEquals(RingPhase.IDLE, s2.phase)
        assertEquals(listOf(RingFx.WriteStopSeq(AlarmData.TRIP, 300L), RingFx.StopService), fx2)
        assertEquals(300L, s2.stopSeqs[AlarmData.TRIP])
    }

    @Test
    fun a16_secondStartOnlyUpdates() {
        val first = ringing(start(request(source = RingSource.FALLBACK, reason = null)))
        val (s, fx) = reduce(first, startInput(start(request(snoozeAllowed = false), ringSeq = 400), at = now + 10_000))
        assertEquals(-1, fx.idx<RingFx.StartAudio>())
        assertTrue(fx.idx<RingFx.PublishUi>() >= 0)
        assertEquals(now, s.startedAtWallMs)
        assertEquals(RingSource.FALLBACK, s.start!!.request.source)
        assertEquals(400L, s.record!!.ringSeq)
        assertEquals(null, (fx[fx.idx<RingFx.PublishUi>()] as RingFx.PublishUi).content.snoozeLabel)
        val (_, fx2) = reduce(s, RingInput.Update(start(request(), ringSeq = 500)))
        assertEquals(-1, fx2.idx<RingFx.StartAudio>())
        assertTrue(fx2.idx<RingFx.PostNotification>() >= 0)
    }

    @Test
    fun a17_staleStartsNeverSound() {
        val stored = record(ringing = false, ringSeq = 50, stopSeq = 100)
        val (s, fx) = reduce(RingState(), startInput(start(ringSeq = 90), stored = stored))
        assertEquals(listOf(RingFx.StopService), fx)
        assertEquals(RingPhase.IDLE, s.phase)
        val (s2, _) = reduce(RingState(), startInput(start(ringSeq = 110), stored = stored))
        assertEquals(RingPhase.RINGING, s2.phase)
        assertEquals(100L, s2.record!!.stopSeq)
        val dismissed = record(ringing = false, pendingDismiss = now)
        assertEquals(listOf(RingFx.StopService), reduce(RingState(), startInput(start(ringSeq = 900), stored = dismissed)).second)
        // A stop seen in this process while idle also blocks an older start.
        val idle = reduce(RingState(), RingInput.Stop(AlarmData.TRIP, StopCause.TRIP_ENDED, 120L)).first
        assertEquals(listOf(RingFx.StopService), reduce(idle, startInput(start(ringSeq = 110))).second)
    }

    @Test
    fun a18_headphonesGone() {
        val hpStart = start(request(settings = AlarmData.SETTINGS.copy(preferHeadphones = true)))
        val hp = reduce(RingState(), startInput(hpStart, hp = true)).first
        assertEquals(AudioRoute.HEADPHONES, hp.route)
        val (s, fx) = reduce(hp, RingInput.HeadphonesGone)
        assertEquals(AudioRoute.VIBRATE_ONLY, s.route)
        assertEquals(RingFx.StopAudio, fx[0])
        assertTrue(fx[1] is RingFx.StartVibration)
        assertEquals(RingSessionMachine.BANNER_HEADPHONES_UNPLUGGED, (fx[2] as RingFx.PublishUi).banner)
        assertTrue(reduce(ringing(), RingInput.HeadphonesGone).second.isEmpty())
    }

    @Test
    fun a19_overshootVariant() {
        val (s, fx) = reduce(ringing(), RingInput.Overshoot(AlarmData.TRIP, 1_200))
        assertEquals(1_200, s.overshootPastM)
        val ui = fx[0] as RingFx.PublishUi
        assertEquals(RingVariant.OVERSHOOT, ui.content.variant)
        assertNotNull(ui.content.pastLine)
        assertEquals(null, ui.content.snoozeLabel)
        assertTrue(fx[1] is RingFx.PostNotification)
        // Snooze is not honoured on the overshoot screen.
        assertTrue(reduce(s, RingInput.UserSnooze(now)).second.isEmpty())
        assertTrue(reduce(RingState(), RingInput.Overshoot(AlarmData.TRIP, 1_200)).second.isEmpty())
    }

    @Test
    fun a20_resumeKeepsTheFirstStart() {
        val (s, fx) = reduce(RingState(), startInput(start(resume = now - 4 * 60_000L)))
        assertEquals(RingPhase.RINGING, s.phase)
        assertEquals(RingFx.ScheduleTimeout(c.ringMaxMs - 240_000L), fx.first { it is RingFx.ScheduleTimeout })
        assertEquals(240_000L, (fx.first { it is RingFx.StartAudio } as RingFx.StartAudio).elapsedMs)
        assertEquals(now - 240_000L, (fx[0] as RingFx.WriteFacts).record.startedAtWallMs)
        val (s2, fx2) = reduce(RingState(), startInput(start(resume = now - 11 * 60_000L)))
        assertEquals(RingPhase.ENDED, s2.phase)
        val at = now - 11 * 60_000L + c.ringMaxMs
        assertEquals(RingFx.SendEvent(RingEventKind.SILENCED, at), fx2.first { it is RingFx.SendEvent })
        assertEquals(-1, fx2.idx<RingFx.StartAudio>())
    }

    @Test
    fun anotherTripReplacesTheRing() {
        val (s, fx) = reduce(ringing(), startInput(start(request(tripId = "t2"), ringSeq = 300)))
        assertEquals("t2", s.tripId)
        assertEquals(RingPhase.RINGING, s.phase)
        val first = fx[0] as RingFx.WriteFacts
        assertEquals(AlarmData.TRIP, first.record.tripId)
        assertEquals(RingEnd.STOPPED, first.record.endedBy)
        assertTrue(fx.any { it is RingFx.StartAudio })
        assertEquals(-1, fx.idx<RingFx.SendEvent>())
    }

    @Test
    fun mergeNeverResurrectsAStoppedRing() {
        val disk = record(ringing = false, stopSeq = 500L, heartbeatElapsed = 9_999L, restarts = 2)
        val (m, stop) = RingFactsMerge.merge(disk, record(ringSeq = 400L, heartbeatElapsed = 1L))
        assertFalse(m.ringing)
        assertTrue(stop)
        assertEquals(9_999L, m.heartbeatElapsedMs)
        assertEquals(2, m.restarts)
        val (m2, stop2) = RingFactsMerge.merge(disk, record(ringSeq = 600L))
        assertTrue(m2.ringing)
        assertFalse(stop2)
        assertEquals(500L, m2.stopSeq)
    }

    @Test
    fun overshootReasonHasNoSnooze() {
        val s = ringing(start(request(reason = AlarmReason.OVERSHOOT, snoozeAllowed = true)))
        assertTrue(reduce(s, RingInput.UserSnooze(now)).second.isEmpty())
    }

    /** Review T16 #1: after a reboot the old book (stopSeq of the old boot, huge) must not silence the new ring. */
    @Test
    fun aRebootNeverSilencesTheNextRing() {
        val old = record(ringing = false, ringSeq = 900_000_000_000_000L, stopSeq = 900_000_000_000_000L, endedBy = RingEnd.SNOOZED, bootCount = 1)
        val (s, fx) = reduce(RingState(), startInput(start(ringSeq = 100), stored = old))
        assertEquals(RingPhase.RINGING, s.phase)
        val w = fx[0] as RingFx.WriteFacts
        assertEquals(null, w.record.stopSeq)
        assertEquals(7, w.record.bootCount)
        // Boot count unknown on both sides: a stopSeq later than now is of an older boot too.
        val unknown = old.copy(bootCount = null)
        val (s2, _) = reduce(RingState(), RingInput.Start(start(ringSeq = 100), false, unknown, now, 9_000L, null))
        assertEquals(RingPhase.RINGING, s2.phase)
        // The merge of :ring's write over that book keeps the ring.
        val (m, stop) = RingFactsMerge.merge(old, w.record, nowNanos = 9_000_000_000L)
        assertTrue(m.ringing)
        assertFalse(stop)
        assertEquals(RingEnd.SNOOZED, old.endedBy)
    }

    /** The engine's Step sends Ring then Overshoot; the OVERSHOOT broadcast may reach :ring before the service starts. */
    @Test
    fun anOvershootBeforeTheStartIsKept() {
        val (idle, fx) = reduce(RingState(), RingInput.Overshoot(AlarmData.TRIP, 1_300))
        assertTrue(fx.isEmpty())
        val (s, fx2) = reduce(idle, startInput(start(request(reason = AlarmReason.OVERSHOOT, snoozeAllowed = false))))
        assertEquals(1_300, s.overshootPastM)
        val ui = fx2.first { it is RingFx.PublishUi } as RingFx.PublishUi
        assertEquals(RingVariant.OVERSHOOT, ui.content.variant)
        assertEquals(CopyLine(CopyKeys.OVERSHOOT_PAST, mapOf("distance" to "1,3 km")), ui.content.pastLine)
        // A trip end clears it.
        val (cleared, _) = reduce(idle, RingInput.Stop(AlarmData.TRIP, StopCause.TRIP_ENDED, 1L))
        assertTrue(cleared.pendingOvershoot.isEmpty())
    }
}
