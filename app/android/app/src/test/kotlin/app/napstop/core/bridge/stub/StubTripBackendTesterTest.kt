package app.napstop.core.bridge.stub

import app.napstop.core.bridge.AlarmModeMsg
import app.napstop.core.bridge.AlarmMsg
import app.napstop.core.bridge.AlarmReasonMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.BridgeTestData.config
import app.napstop.core.bridge.EndReasonMsg
import app.napstop.core.bridge.GpsLostCauseMsg
import app.napstop.core.bridge.GpsLostMsg
import app.napstop.core.bridge.GpsRecoveredMsg
import app.napstop.core.bridge.LowBatteryRiskMsg
import app.napstop.core.bridge.OvershootMsg
import app.napstop.core.bridge.PreAlertMsg
import app.napstop.core.bridge.SimulationMsg
import app.napstop.core.bridge.TripEndedMsg
import app.napstop.core.bridge.TripOutcomeMsg
import app.napstop.core.bridge.TripPhaseMsg
import app.napstop.core.bridge.TripStateUpdateMsg
import app.napstop.core.bridge.TripUpdateMsg
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Tester additions for T14 (beyond K14-K20): snapshot corruption and old versions,
 * process death at awkward moments, clock jumps, the finished queue, scenarios through
 * the backend's tick loop, and a listener that throws (review R2-3; expectation changed by T15 L44).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class StubTripBackendTesterTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val t0 = 1_700_000_000_000L
    private var nowMs = t0
    private val warnings = mutableListOf<String>()
    private val sim60 = SimulationMsg(StubScenario.NORMAL.asset, 60.0)

    private fun TestScope.backend(
        dir: File = tmp.root,
        scope: CoroutineScope = backgroundScope,
        clock: () -> Long = { nowMs },
    ) = StubTripBackend(
        store = StubStore(dir, warn = { warnings += it }),
        clock = clock,
        scope = scope,
        io = StandardTestDispatcher(testScheduler),
        warn = { warnings += it },
    )

    private val activeFile get() = File(tmp.root, StubStore.ACTIVE_FILE)
    private val finishedDir get() = File(tmp.root, StubStore.FINISHED_DIR)

    private fun List<TripUpdateMsg>.states() = filterIsInstance<TripStateUpdateMsg>().map { it.state }

    // ------------------------------------------------------------ snapshot files

    @Test
    fun snapshotFromTheRound1StubWithoutSimulatedKeyIsDropped() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            val text = activeFile.readText()
            assertTrue(text.contains("simulated="))
            activeFile.writeText(text.lines().filterNot { it.startsWith("simulated=") }.joinToString("\n"))

            assertNull(backend().currentTrip())
            assertFalse(activeFile.exists())
            assertEquals(listOf("stub snapshot: invalid (IllegalArgumentException)"), warnings)
            // The slot is free again.
            backend().startTrip(config("t2"), 16.8, 107.1, null)
        }

    @Test
    fun emptyMissingOrOtherVersionSnapshotsAreDropped() =
        runTest {
            for (content in listOf("", "phase=TRACKING\n", "version=0\n", "version=\n", "version=1.0\n", "version=v1\n")) {
                activeFile.writeText(content)
                assertNull("content '$content'", backend().currentTrip())
                assertFalse(activeFile.exists())
            }
            assertTrue(warnings.all { it == "stub snapshot: unsupported version" })
            assertEquals(6, warnings.size)
        }

    @Test
    fun truncatedSnapshotIsDroppedAndNeverCrashes() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            val full = activeFile.readText()
            // Every prefix that keeps `version=1` but loses keys (a torn write without the
            // temp file + move would look like this).
            val lines = full.lines()
            val versionAt = lines.indexOfFirst { it.startsWith("version=") }
            for (cut in (versionAt + 1) until lines.size - 1 step 3) {
                activeFile.writeText(lines.take(cut).joinToString("\n"))
                warnings.clear()
                val trip = backend().currentTrip()
                if (trip == null) {
                    assertFalse(activeFile.exists())
                    assertEquals(1, warnings.size)
                    assertTrue(warnings.single().startsWith("stub snapshot: "))
                }
            }
        }

    @Test
    fun leftoverTempFilesFromACrashedWriteAreIgnored() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            File(tmp.root, StubStore.ACTIVE_FILE + ".tmp").writeText("garbage \u0000")
            finishedDir.mkdirs()
            File(finishedDir, "t9.properties.tmp").writeText("garbage")
            val revived = backend()
            assertEquals("t1", revived.currentTrip()!!.config.tripId)
            assertTrue(revived.pendingFinishedTrips().isEmpty())
            assertTrue(warnings.isEmpty())
        }

    @Test
    fun corruptFinishedRecordsAreDroppedOthersKept() =
        runTest {
            val b = backend()
            for (id in listOf("t1", "t2", "t3")) {
                b.startTrip(config(id), 16.8, 107.1, sim60)
                nowMs += 1_000
                b.stopTrip(id)
            }
            val t2 = File(finishedDir, "t2.properties")
            t2.writeText(t2.readText().replace("outcome=CANCELLED", "outcome=LOST"))
            val t3 = File(finishedDir, "t3.properties")
            t3.writeText(t3.readText().replace("version=1", "version=2"))

            assertEquals(listOf("t1"), backend().pendingFinishedTrips().map { it.tripId })
            assertFalse(t2.exists())
            assertFalse(t3.exists())
            assertEquals(2, warnings.size)
            assertTrue(warnings.all { it.startsWith("stub finished record: invalid (") })
            assertTrue(warnings.none { it.contains("t2") || it.contains("t3") })
        }

    @Test
    fun awkwardDestinationNamesRoundTripThroughTheSnapshot() =
        runTest {
            val name = "Ga A=B: C\nD #E !F \\ \t ü 🚆   end "
            val cfg = config(destinationName = name, mode = AlarmModeMsg.TIME, timeThresholdMin = 5)
            backend().startTrip(cfg, 16.8, 107.1, sim60)
            assertEquals(cfg, backend().currentTrip()!!.config)
        }

    @Test
    fun unknownExtraKeysAreIgnored() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            activeFile.appendText("\nfutureField=42\n")
            assertEquals("t1", backend().currentTrip()!!.config.tripId)
            assertTrue(warnings.isEmpty())
        }

    // ------------------------------------------------------------ process death

    @Test
    fun listenerAttachedFirstAfterProcessDeathStillGetsTheAlarmEvent() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000 // process dead while the alarm became due (~12.3 s)
            val revived = backend()
            val received = mutableListOf<TripUpdateMsg>()
            revived.addListener { received += it }
            runCurrent()
            assertTrue(received.first() is TripStateUpdateMsg)
            val alarm = received.filterIsInstance<AlarmMsg>().single()
            assertEquals(AlarmReasonMsg.SMART_TIME, alarm.reason)
            assertEquals(nowMs, alarm.atMs)
            assertTrue(received.states().single().alarmRinging)
        }

    @Test
    fun currentTripFirstAfterProcessDeathLeavesOnlyTheStateToTheListener() =
        runTest {
            // Review T14 decision 1: events are computed lazily; the UI must rely on
            // TripStateMsg.phase/alarmRinging, not on having received AlarmMsg.
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            val revived = backend()
            val trip = revived.currentTrip()!!
            assertEquals(TripPhaseMsg.ALARMING, trip.state.phase)
            assertTrue(trip.state.alarmRinging)
            assertEquals(AlarmReasonMsg.SMART_TIME, trip.state.alarmReason)
            val received = mutableListOf<TripUpdateMsg>()
            revived.addListener { received += it }
            runCurrent()
            assertEquals(1, received.size)
            assertTrue(received.states().single().alarmRinging)
        }

    @Test
    fun snoozeThatExpiredDuringProcessDeathRingsAgainOnTheFirstCall() =
        runTest {
            val b = backend()
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            b.snooze("t1")
            assertEquals(TripPhaseMsg.SNOOZED, b.currentTrip()!!.state.phase)
            nowMs += 5_000 // snooze is 60 s virtual = 1 s real

            val received = mutableListOf<TripUpdateMsg>()
            val revived = backend()
            revived.addListener { received += it }
            runCurrent()
            val alarm = received.filterIsInstance<AlarmMsg>().single()
            assertEquals(AlarmReasonMsg.SNOOZE_END, alarm.reason)
            assertFalse(alarm.snoozeAllowed)
            val state = revived.currentTrip()!!.state
            assertEquals(TripPhaseMsg.ALARMING, state.phase)
            assertEquals(1L, state.snoozeCount)
            assertNull(state.snoozeUntilMs)
        }

    @Test
    fun eventsAlreadySentAreNotRepeatedAfterProcessDeath() =
        runTest {
            val received = mutableListOf<TripUpdateMsg>()
            val clock = { t0 + testScheduler.currentTime }
            val b = backend(clock = clock)
            b.startTrip(config("t1"), 16.8, 107.1, SimulationMsg(StubScenario.LOW_BATTERY.asset, 60.0))
            val h = b.addListener { received += it }
            advanceTimeBy(2_000) // PreAlert (~0.1 s) and LowBatteryRisk (v = 30 s -> 0.5 s)
            runCurrent()
            assertEquals(1, received.count { it is PreAlertMsg })
            assertEquals(1, received.count { it is LowBatteryRiskMsg })
            b.setBatteryChoice("t1", BatteryChoiceMsg.ALARM_AT5)
            h.remove()

            received.clear()
            val revived = backend(clock = clock)
            revived.addListener { received += it }
            advanceTimeBy(8_000)
            runCurrent()
            assertTrue(received.none { it is PreAlertMsg || it is LowBatteryRiskMsg })
            assertEquals(BatteryChoiceMsg.ALARM_AT5, received.states().last().batteryChoice)
        }

    @Test
    fun gpsLostBeforeProcessDeathRecoversExactlyOnceAfter() =
        runTest {
            val received = mutableListOf<TripUpdateMsg>()
            val clock = { t0 + testScheduler.currentTime }
            val b = backend(clock = clock)
            b.startTrip(config("t1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000), 16.8, 107.1,
                SimulationMsg(StubScenario.GPS_LOST.asset, 60.0))
            val h = b.addListener { received += it }
            advanceTimeBy(2_000) // lost at v = 60 s -> 1 s real
            runCurrent()
            assertEquals(1, received.count { it is GpsLostMsg })
            h.remove()

            received.clear()
            val revived = backend(clock = clock)
            revived.addListener { received += it }
            advanceTimeBy(5_000) // recovered at v = 240 s -> 4 s real
            runCurrent()
            assertEquals(0, received.count { it is GpsLostMsg })
            val recovered = received.filterIsInstance<GpsRecoveredMsg>().single()
            assertEquals(180L, recovered.lostForS)
        }

    // ------------------------------------------------------------ clock jumps

    @Test
    fun clockSetBackAfterProcessDeathDoesNotRewindTheTrip() =
        runTest {
            backend().startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            assertEquals(TripPhaseMsg.ALARMING, backend().currentTrip()!!.state.phase) // persisted (alarm Step)
            nowMs = t0 + 5_000 // user sets the clock back 10 s
            val state = backend().currentTrip()!!.state
            assertEquals(TripPhaseMsg.ALARMING, state.phase)
            assertEquals(t0 + 15_000, state.atMs)
            assertTrue(state.alarmRinging)
        }

    @Test
    fun aClockJumpForwardNeverSkipsTheAlarm() =
        runTest {
            val b = backend()
            val received = mutableListOf<TripUpdateMsg>()
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            b.addListener { received += it }
            runCurrent()
            // The clock jumps one day ahead (manual change, NTP fix after a reboot).
            nowMs = t0 + 86_400_000
            val state = b.currentTrip()!!.state
            assertEquals("rings first, does not end straight away", TripPhaseMsg.ALARMING, state.phase)
            assertEquals(1, received.count { it is AlarmMsg })
            assertTrue(received.none { it is TripEndedMsg })
            // Unanswered for an hour (virtual) after that ring: only then missed.
            nowMs += 59_000
            assertEquals(TripPhaseMsg.ALARMING, b.currentTrip()!!.state.phase)
            nowMs += 2_000
            assertNull(b.currentTrip())
            val ended = received.filterIsInstance<TripEndedMsg>().single().trip
            assertEquals(EndReasonMsg.ALARM_UNANSWERED, ended.endReason)
            assertEquals(TripOutcomeMsg.MISSED, ended.outcome)
        }

    @Test
    fun aClockJumpDuringSnoozeRingsTheSnoozeEndFirst() =
        runTest {
            val b = backend()
            val received = mutableListOf<TripUpdateMsg>()
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs = t0 + 15_000
            b.snooze("t1")
            b.addListener { received += it }
            runCurrent()
            nowMs += 86_400_000
            assertEquals(TripPhaseMsg.ALARMING, b.currentTrip()!!.state.phase)
            assertEquals(AlarmReasonMsg.SNOOZE_END, received.filterIsInstance<AlarmMsg>().single().reason)
            assertTrue(received.none { it is TripEndedMsg })
        }

    // ------------------------------------------------------------ currentTrip().simulation

    @Test
    fun currentTripSimulationIsExactlyWhatStartTripReceived() =
        runTest {
            for ((i, scenario) in StubScenario.entries.withIndex()) {
                for (speed in listOf(1.0, 60.0, 600.0)) {
                    val dir = tmp.newFolder("sim-$i-${speed.toInt()}")
                    val sim = SimulationMsg(scenario.asset, speed)
                    backend(dir = dir).startTrip(config("t1"), 16.8, 107.1, sim)
                    assertEquals(sim, backend(dir = dir).currentTrip()!!.simulation)
                }
            }
            val real = tmp.newFolder("real")
            backend(dir = real).startTrip(config("t1"), 16.8, 107.1, null)
            val trip = backend(dir = real).currentTrip()!!
            assertNull(trip.simulation)
            // A real trip runs at 1x: still acquiring/tracking long before any alarm.
            assertNotNull(trip.state.predictedAlarmAtMs)
        }

    // ------------------------------------------------------------ finished queue

    @Test
    fun pendingAndAckAreIdempotent() =
        runTest {
            val b = backend()
            assertTrue("no finished dir yet", b.pendingFinishedTrips().isEmpty())
            b.ackFinishedTrips(listOf("t1"))
            b.ackFinishedTrips(emptyList())

            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs += 1_000
            b.stopTrip("t1")
            b.startTrip(config("t2"), 16.8, 107.1, sim60)

            val first = b.pendingFinishedTrips()
            assertEquals(first, b.pendingFinishedTrips())
            assertEquals(first, backend().pendingFinishedTrips())
            // Acking the running trip's id touches nothing.
            b.ackFinishedTrips(listOf("t2"))
            assertEquals("t2", b.currentTrip()!!.config.tripId)
            b.ackFinishedTrips(listOf("t1"))
            b.ackFinishedTrips(listOf("t1"))
            assertTrue(b.pendingFinishedTrips().isEmpty())
            assertEquals("t2", b.currentTrip()!!.config.tripId)
            assertTrue(warnings.isEmpty())
        }

    @Test
    fun recordsEndedAtTheSameMomentAreOrderedByTripId() =
        runTest {
            val b = backend()
            for (id in listOf("tb", "ta")) {
                b.startTrip(config(id), 16.8, 107.1, sim60)
                b.stopTrip(id) // same nowMs for both
            }
            assertEquals(listOf("ta", "tb"), backend().pendingFinishedTrips().map { it.tripId })
        }

    @Test
    fun sameTripIdEndedTwiceBeforeAckKeepsOnlyTheLatestRecord() =
        runTest {
            // Observation: records are keyed by tripId. Dart uses UUIDs (T14 §8), so this only
            // documents the stub's behaviour.
            val b = backend()
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            b.stopTrip("t1")
            nowMs += 15_000
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            nowMs += 15_000
            b.dismiss("t1")
            val pending = b.pendingFinishedTrips()
            assertEquals(1, pending.size)
            assertEquals(EndReasonMsg.DISMISSED, pending.single().endReason)
        }

    // ------------------------------------------------------------ scenarios through the tick loop

    @Test
    fun noFixAt600xNeverAcquiredThenTimeoutWithinAbout24s() =
        runTest {
            val b = backend(clock = { t0 + testScheduler.currentTime })
            val received = mutableListOf<TripUpdateMsg>()
            b.startTrip(config("t1"), 16.8, 107.1, SimulationMsg(StubScenario.NO_FIX.asset, 600.0))
            b.addListener { received += it }
            advanceTimeBy(26_000)
            runCurrent()
            val lost = received.filterIsInstance<GpsLostMsg>().single()
            assertEquals(GpsLostCauseMsg.NEVER_ACQUIRED, lost.cause)
            assertNull(lost.lastFixAgeS)
            val alarm = received.filterIsInstance<AlarmMsg>().single()
            assertEquals(AlarmReasonMsg.TIMEOUT, alarm.reason)
            // TIMEOUT_S = 14 400 s virtual = 24 s real; at most one tick late.
            assertTrue(alarm.atMs in (t0 + 24_000)..(t0 + 25_000))
            assertTrue(received.states().all { it.distanceM == null })
        }

    @Test
    fun overshootDistance1000At600xRingsOnceThenOvershoot() =
        runTest {
            val b = backend(clock = { t0 + testScheduler.currentTime })
            val received = mutableListOf<TripUpdateMsg>()
            b.startTrip(
                config("t1", mode = AlarmModeMsg.DISTANCE, distanceThresholdM = 1000),
                16.8,
                107.1,
                SimulationMsg(StubScenario.OVERSHOOT.asset, 600.0),
            )
            b.addListener { received += it }
            advanceTimeBy(4_000) // alarm v ~ 1271.7 s (2.1 s), overshoot v ~ 1405 s (2.3 s)
            runCurrent()
            val alarm = received.filterIsInstance<AlarmMsg>().single()
            assertEquals(AlarmReasonMsg.DISTANCE, alarm.reason)
            val overshoot = received.filterIsInstance<OvershootMsg>().single()
            assertTrue(overshoot.pastM >= 1000)
            assertTrue(received.indexOf(alarm) < received.indexOf(overshoot))
            assertEquals(TripPhaseMsg.OVERSHOT, received.states().last().phase)
            b.dismiss("t1")
            assertEquals(TripOutcomeMsg.MISSED, received.filterIsInstance<TripEndedMsg>().single().trip.outcome)
        }

    // ------------------------------------------------------------ R2-3: a listener that throws

    @Test
    fun r2_3_throwingListenerNoLongerStarvesTheListenersAfterIt() =
        runTest {
            // T15 L44 (spec T15 D13, §5.11): expectation changed from the T14 tester version, which
            // documented that a throwing listener aborted the Step for every later listener and made
            // committed API calls fail. With ListenerHub each listener call is isolated.
            val b = backend(clock = { t0 + testScheduler.currentTime })
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            var thrown = 0
            val bad = b.addListener {
                thrown++
                throw IllegalStateException("secret 21.0,105.8")
            }
            val good = mutableListOf<TripUpdateMsg>()
            b.addListener { good += it }
            advanceTimeBy(20_000) // past the alarm (~12.3 s)
            runCurrent()

            assertTrue(thrown > 10)
            assertTrue("the listener after the thrower gets every update", good.isNotEmpty())
            assertTrue(good.any { it is AlarmMsg })
            assertTrue(warnings.isNotEmpty())
            assertTrue(warnings.all { it == "listener failed (IllegalStateException)" })

            // The API call succeeds and is committed.
            b.dismiss("t1")
            assertTrue(good.any { it is TripEndedMsg })
            bad.remove()
            assertNull(b.currentTrip())
            val record = b.pendingFinishedTrips().single()
            assertEquals(EndReasonMsg.DISMISSED, record.endReason)
            assertNotNull(record.alarmAtMs)
        }

    @Test
    fun r2_3_listenersBeforeTheThrowerGetEveryEventOfEachStep() =
        runTest {
            // T15 L44: updates are sent listener-major with one try/catch per call, so a listener before
            // the thrower now gets each Step's events too (PreAlert, AlarmMsg), not only its state.
            val b = backend(clock = { t0 + testScheduler.currentTime })
            b.startTrip(config("t1"), 16.8, 107.1, sim60)
            val good = mutableListOf<TripUpdateMsg>()
            b.addListener { good += it }
            b.addListener { throw IllegalStateException() }
            advanceTimeBy(20_000) // past PreAlert (~0.1 s) and the alarm (~12.3 s)
            runCurrent()
            assertTrue(good.count { it is TripStateUpdateMsg } >= 20)
            assertTrue("events reach the listener", good.any { it is PreAlertMsg } && good.any { it is AlarmMsg })
            assertTrue("the alarm Step itself was committed", good.filterIsInstance<TripStateUpdateMsg>().last().state.alarmRinging)
        }
}
