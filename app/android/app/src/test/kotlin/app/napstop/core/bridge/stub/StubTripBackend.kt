package app.napstop.core.bridge.stub

import android.util.Log
import app.napstop.core.bridge.ActiveTripMsg
import app.napstop.core.bridge.BatteryChoiceMsg
import app.napstop.core.bridge.BridgeErrors
import app.napstop.core.bridge.FinishedTripMsg
import app.napstop.core.bridge.FlutterError
import app.napstop.core.bridge.ListenerHandle
import app.napstop.core.bridge.ListenerHub
import app.napstop.core.bridge.SimulationMsg
import app.napstop.core.bridge.TripBackend
import app.napstop.core.bridge.TripConfigMsg
import app.napstop.core.bridge.TripPhaseMsg
import app.napstop.core.bridge.TripUpdateMsg
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.max
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Test double since T18 (D13): the scripted trip backend of T14 (spec T14 §5.2), kept in src/test for the
 * channel tests of T14/T14.1; not in the APK. One trip at a time,
 * snapshot via [store] so currentTrip() works after process death, ended trips queued
 * until acked (D12). Never receives or stores coordinates.
 *
 * Threading: API methods run on the caller's (main) dispatcher, disk IO on [io]; the
 * tick loop runs in [scope] (prod: MainScope), so listeners are always called on the
 * main thread, and [listeners] is only touched there. Ticks only while at least one
 * listener is attached and a trip is running.
 *
 * Persistence is write-then-commit (review T14 M2): a Step that must be written is only
 * committed to memory and sent after the write succeeded. Ticks without events are not
 * written (§5.2), so memory can be ahead of disk only by such quiet Steps, which the
 * next call after a process death recomputes from the snapshot anyway. Failures inside
 * the tick loop are logged and retried on the next tick instead of crashing the app
 * (review T14 M3). Listeners sit in a [ListenerHub] (T15 D13): one that throws never starves the others and never
 * fails a committed call.
 */
class StubTripBackend(
    private val store: StubStore,
    private val clock: () -> Long,
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher,
    private val tickMs: Long = 1_000,
    private val warn: (String) -> Unit = { Log.w(TAG, it) },
) : TripBackend {
    private val mutex = Mutex()
    private var loaded = false
    private var state: StubTripState? = null
    private val listeners = ListenerHub(warn)
    private var tickJob: Job? = null

    override suspend fun startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) {
        mutex.withLock {
            advanceLocked()
            if (state != null) throw FlutterError(BridgeErrors.TRIP_ACTIVE, null, null)
            val scenario =
                if (simulation == null) {
                    StubScenario.NORMAL
                } else {
                    StubScenario.fromAsset(simulation.traceAsset)
                        ?: throw FlutterError(BridgeErrors.SIMULATION_UNAVAILABLE, "unknown stub scenario", null)
                }
            // destLat/destLng are deliberately dropped: the stub never keeps coordinates.
            val step =
                StubTripModel.start(
                    config = config,
                    scenario = scenario,
                    speedFactor = simulation?.speedFactor ?: 1.0,
                    simulated = simulation != null,
                    nowMs = clock(),
                )
            applyLocked(step, persist = true)
        }
        ensureTicking()
    }

    override suspend fun stopTrip(tripId: String) = action(tripId, StubAction.STOP)

    override suspend fun currentTrip(): ActiveTripMsg? =
        mutex.withLock {
            advanceLocked()
            state?.let { s ->
                ActiveTripMsg(
                    config = s.config,
                    state = StubTripModel.view(s),
                    // Exactly what startTrip received (review T14 M4).
                    simulation = if (s.simulated) SimulationMsg(s.scenario.asset, s.speedFactor) else null,
                )
            }
        }

    override suspend fun setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) =
        action(
            tripId,
            when (choice) {
                BatteryChoiceMsg.MAX_SAVING -> StubAction.BATTERY_MAX_SAVING
                BatteryChoiceMsg.ALARM_AT5 -> StubAction.BATTERY_ALARM_AT_5
                BatteryChoiceMsg.ALARM_EARLIER -> StubAction.BATTERY_ALARM_EARLIER
            },
        )

    override suspend fun dismiss(tripId: String) = action(tripId, StubAction.DISMISS)

    override suspend fun snooze(tripId: String) = action(tripId, StubAction.SNOOZE)

    override suspend fun pendingFinishedTrips(): List<FinishedTripMsg> =
        mutex.withLock {
            // Advance first so a trip that expired meanwhile is recorded.
            advanceLocked()
            withContext(io) { store.readFinished() }
        }

    override suspend fun ackFinishedTrips(tripIds: List<String>) {
        mutex.withLock { withContext(io) { store.deleteFinished(tripIds) } }
    }

    override fun addListener(listener: (TripUpdateMsg) -> Unit): ListenerHandle {
        var replay: Job? = null
        val handle =
            listeners.add(listener) {
                replay?.cancel()
                if (listeners.isEmpty) {
                    tickJob?.cancel()
                    tickJob = null
                }
            }
        // Replay: one Step now (the latest view plus whatever this Step itself produces),
        // sent to every listener; then make sure the tick loop runs.
        replay = scope.launch { if (stepFromScope()) ensureTicking() }
        return handle
    }

    // ---------------------------------------------------------------- internals

    private suspend fun action(tripId: String, action: StubAction) {
        mutex.withLock {
            val s = loadLocked() ?: return
            if (s.config.tripId != tripId) {
                // Late command for another trip: no-op (D10), but keep the clock moving.
                advanceLocked()
                return
            }
            applyLocked(StubTripModel.act(s, action, now(s)), persist = true)
        }
    }

    private fun ensureTicking() {
        if (!listeners.isEmpty && tickJob?.isActive != true) {
            tickJob = scope.launch { tickLoop() }
        }
    }

    private suspend fun tickLoop() {
        while (true) {
            delay(tickMs)
            if (!stepFromScope()) return
        }
    }

    /**
     * One Step for the tick loop or a replay. Nothing launched in [scope] may throw: a
     * failure (e.g. IOException writing the snapshot on a full disk) is logged with the
     * class name only, nothing is committed or sent, and the next tick retries the Step.
     * Returns true while a trip is running.
     */
    private suspend fun stepFromScope(): Boolean =
        mutex.withLock {
            try {
                advanceLocked()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                warn("stub step failed (${e.javaClass.simpleName})")
                state != null
            }
        }

    /** Advances the trip (if any) to now and sends the Step. Returns true if a trip is still running. */
    private suspend fun advanceLocked(): Boolean {
        val s = loadLocked() ?: return false
        val step = StubTripModel.advance(s, now(s))
        applyLocked(step, persist = step.updates.size > 1)
        return state != null
    }

    private suspend fun loadLocked(): StubTripState? {
        if (!loaded) {
            state = withContext(io) { store.readActive() }
            loaded = true
        }
        return state?.takeIf { it.phase != TripPhaseMsg.ENDED }
    }

    /**
     * Write-then-commit: persist the Step (end: finished record first, then drop the
     * snapshot), then commit it to memory, then send it, as one non-cancellable unit. A
     * caller cancelled during the write (listener removed mid-tick) still commits what is
     * already on disk: withContext(NonCancellable) keeps the dispatcher, so unlike
     * withContext(io + NonCancellable) it does not throw on return (review T14 M2). A
     * failed write throws before anything is committed or sent.
     */
    private suspend fun applyLocked(step: StubStep, persist: Boolean) {
        withContext(NonCancellable) {
            val finished = step.finished
            if (finished != null) {
                withContext(io) {
                    store.writeFinished(finished)
                    store.deleteActive()
                }
                state = null
            } else {
                if (persist) withContext(io) { store.writeActive(step.state) }
                state = step.state
            }
            listeners.publish(step.updates)
        }
    }

    /** Trip clock never goes backwards (T10 §2.6). */
    private fun now(s: StubTripState): Long = max(s.nowMs, clock())

    private companion object {
        const val TAG = "NapStopStub"
    }
}
