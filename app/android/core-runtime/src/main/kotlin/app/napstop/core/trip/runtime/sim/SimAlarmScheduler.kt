package app.napstop.core.trip.runtime.sim

import app.napstop.core.trip.runtime.OsAlarmScheduler
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SimTimeline
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.TimeSource
import app.napstop.core.trip.runtime.WakeMechanism
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * In-process timers of a simulated trip (T18 §5, D5): the wake alarm and the two fallback slots wait for the **trip
 * time** of their mark ([timeline]), so they stay right after a rebase, then call the same runtime entry points as the
 * receivers ([onWake] = `TripRuntime.onWake`, [onFallback] = `TripRuntime.onFallbackFired`). Nothing is set at the OS.
 * Timers die with the process (D9).
 */
class SimAlarmScheduler(
    private val scope: CoroutineScope,
    private val dispatcher: CoroutineDispatcher,
    private val time: TimeSource,
    private val pollMaxMs: Long,
    private val onWake: suspend (wakeAtMs: Long, wakeAtWallMs: Long) -> Unit,
    private val onFallback: suspend (tripId: String, slot: Int, generation: Long, targetAtMs: Long, kind: SlotKind) -> Unit,
    private val warn: (String) -> Unit = {},
) : OsAlarmScheduler {
    /** Trip clock of the simulated trip; set at commit, null when none runs. */
    @Volatile
    var timeline: SimTimeline? = null

    private val lock = Any()
    private var wakeJob: Job? = null
    private val slotJobs = HashMap<Int, Job>()

    override fun canScheduleExact() = true

    override fun setWake(triggerElapsedMs: Long, mechanism: WakeMechanism, triggerWallMs: Long, wakeAtMs: Long) {
        synchronized(lock) {
            wakeJob?.cancel()
            val tl = timeline
            wakeJob =
                scope.launch(dispatcher) {
                    if (tl != null && wakeAtMs >= 0) tl.awaitTrip(wakeAtMs, pollMaxMs) else delay(maxOf(0L, triggerElapsedMs - time.elapsedMs()))
                    guarded("sim wake") { onWake(wakeAtMs, triggerWallMs) }
                }
        }
    }

    override fun cancelWake() {
        synchronized(lock) {
            wakeJob?.cancel()
            wakeJob = null
        }
    }

    override fun setFallback(slot: Int, tripId: String, generation: Long, targetAtMs: Long, triggerWallMs: Long, exact: Boolean, kind: SlotKind) {
        synchronized(lock) {
            slotJobs.remove(slot)?.cancel()
            val tl = timeline
            slotJobs[slot] =
                scope.launch(dispatcher) {
                    if (tl != null) tl.awaitTrip(targetAtMs, pollMaxMs) else delay(maxOf(0L, triggerWallMs - time.wallMs()))
                    guarded("sim fallback") { onFallback(tripId, slot, generation, targetAtMs, kind) }
                }
        }
    }

    override fun cancelFallback(slot: Int) {
        synchronized(lock) { slotJobs.remove(slot)?.cancel() }
    }

    /** Never routed here (RoutingAlarmScheduler sends restore retries to the OS). */
    override fun setRestoreRetry(triggerElapsedMs: Long, attempt: Int, cause: RestoreCause, sinceWallMs: Long, exact: Boolean): Unit =
        throw UnsupportedOperationException()

    override fun cancelRestoreRetry() = Unit

    /** The trip ended: every timer. */
    fun cancelAll() {
        synchronized(lock) {
            wakeJob?.cancel()
            wakeJob = null
            slotJobs.values.forEach { it.cancel() }
            slotJobs.clear()
        }
    }

    /** Whether a wake timer is pending (tests, debug dump). */
    val wakePending: Boolean get() = synchronized(lock) { wakeJob?.isActive == true }

    /** Slots with a pending timer (tests, debug dump). */
    val pendingSlots: Set<Int> get() = synchronized(lock) { slotJobs.filterValues { it.isActive }.keys.toSet() }

    private suspend fun guarded(what: String, block: suspend () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            warn("$what failed (${e.javaClass.simpleName})")
        }
    }
}
