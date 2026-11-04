package app.napstop.core.trip.runtime.support

import app.napstop.core.trip.Alarm
import app.napstop.core.trip.TripEvent
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserActionKind
import app.napstop.core.trip.runtime.RingEvent
import app.napstop.core.trip.runtime.RingEventKind
import app.napstop.core.trip.runtime.RuntimeConstants
import app.napstop.core.trip.runtime.RuntimeJournal
import app.napstop.core.trip.runtime.RuntimeListener
import app.napstop.core.trip.runtime.RuntimePorts
import app.napstop.core.trip.runtime.TripRuntime
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent

/** One recorded Step as a listener saw it (wall/trip time = virtual time). */
class Seen(val atMs: Long, val view: TripView, val choice: UserActionKind?, val events: List<TripEvent>)

/**
 * A runtime plus fakes inside a [TestScope] with virtual time: wall = [startWall] + virtual time, elapsed =
 * [elapsedBase] + virtual time. Every dispatcher of the runtime is the test dispatcher, so everything is
 * deterministic. Fakes can be handed over from a previous "process" ([store], [scheduler], [alarm]).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class World(
    val scope: TestScope,
    val startWall: Long = 1_700_000_000_000L,
    val elapsedBase: Long = 1_000_000L,
    val constants: RuntimeConstants = RuntimeConstants(),
    val log: OpLog = OpLog(),
    val store: FakeStore = FakeStore(log),
    scheduler: FakeScheduler? = null,
    alarm: FakeAlarmPort? = null,
    val journal: RuntimeJournal = RuntimeJournal.NoOp,
    /** Disk dispatcher; L45 passes Dispatchers.IO so a blocking (hung) store does not block the test thread. */
    io: kotlinx.coroutines.CoroutineDispatcher? = null,
    /** Ledger lane; default = the runtime's own (serial view of [io]). L46 holds it separately. */
    ledgerIo: kotlinx.coroutines.CoroutineDispatcher? = null,
    /** T16 AT1–AT6: the alarm port the runtime uses instead of [alarm] (SimRing: real AlarmControllerCore + ring machine). */
    ringPort: ((World) -> app.napstop.core.alarm.AlarmPort)? = null,
) {
    val time = FakeTime(wallBase = startWall, elapsedBase = elapsedBase, virtual = { scope.testScheduler.currentTime })
    val scheduler: FakeScheduler = scheduler ?: FakeScheduler(log, time)
    val alarm: FakeAlarmPort = alarm ?: FakeAlarmPort(log, time)
    val location = FakeLocationSource(log)
    val tracking = FakeTracking(log)
    val notifier = FakeNotifier()
    val visibility = FakeVisibility(true)
    val env = FakeEnv()
    val warnings = ArrayList<String>()
    val seen = ArrayList<Seen>()

    /** Checked at every published Step (L30): phase ACQUIRING/TRACKING ⇒ at least one fallback slot. */
    var slotViolations = 0
    var checkSlots = false
    private val dispatcher = StandardTestDispatcher(scope.testScheduler)

    /** T16 AT4: this "process"; [kill] cancels everything the runtime runs (actor, timers), as a process death. */
    private val processJob = kotlinx.coroutines.SupervisorJob(scope.backgroundScope.coroutineContext[kotlinx.coroutines.Job])

    /** Coroutines of this process (runtime, and the main-process side of SimRing). */
    val processScope = kotlinx.coroutines.CoroutineScope(scope.backgroundScope.coroutineContext + processJob)

    fun kill() = processJob.cancel()

    /** T16 AT6: told true before / false after the fake OS delivers an alarm to a receiver (FGS start exemption). */
    var deliveryHook: ((Boolean) -> Unit)? = null

    val runtime: TripRuntime =
        TripRuntime(
            ports = RuntimePorts(time, location, tracking, this.scheduler, ringPort?.invoke(this) ?: this.alarm, notifier, store, visibility, env, journal),
            scope = processScope,
            actorDispatcher = dispatcher,
            io = io ?: dispatcher,
            main = dispatcher,
            constants = constants,
            warn = { warnings += it },
            ledgerIo = ledgerIo ?: @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class) (io ?: dispatcher).limitedParallelism(1),
        ).also { tracking.runtime = it }

    val nowMs: Long get() = time.wallMs()

    fun listen() {
        runtime.addListener(
            RuntimeListener { _, view, choice, events ->
                seen += Seen(view.atMs, view, choice, events)
                if (checkSlots && (view.phase == TripPhase.ACQUIRING || view.phase == TripPhase.TRACKING) && this.scheduler.slots.isEmpty()) {
                    slotViolations++
                }
            },
        )
    }

    val events: List<Pair<Long, TripEvent>> get() = seen.flatMap { s -> s.events.map { s.atMs to it } }

    fun firstAlarm(): Alarm? = events.map { it.second }.firstOrNull { it is Alarm } as Alarm?

    /** Runs [block] on the test scope and lets the runtime finish what it queued. */
    fun <T> now(block: suspend () -> T): T {
        var out: Result<T>? = null
        scope.launch { out = runCatching { block() } }
        scope.runCurrent()
        return out!!.getOrThrow()
    }

    fun settle() = scope.runCurrent()

    fun advance(ms: Long) {
        scope.advanceTimeBy(ms)
        scope.runCurrent()
    }

    /** Delivers whatever the fake OS has due at the current virtual time (wake, fallback, auto-silence). */
    fun deliverDue(silenceAfterMs: Long?, tripId: String?, beforeWake: (() -> Unit)? = null): Boolean {
        var any = false
        val elapsed = time.elapsedMs()
        val f = scheduler.nextFallback()
        if (f != null && f.triggerWallMs <= time.wallMs()) {
            scheduler.slots.remove(f.slot)
            deliveryHook?.invoke(true)
            now { runtime.onFallbackFired(f.tripId, f.slot, f.generation, f.targetAtMs, f.kind) }
            deliveryHook?.invoke(false)
            any = true
        }
        val w = scheduler.wakeDeliveryElapsed()
        if (w != null && w <= elapsed) {
            val wk = scheduler.wake!!
            scheduler.consumeWake(elapsed)
            beforeWake?.invoke()
            deliveryHook?.invoke(true)
            now { runtime.onWake(wk.wakeAtMs.takeIf { it >= 0 }, wk.triggerWallMs.takeIf { wk.wakeAtMs >= 0 }) }
            deliveryHook?.invoke(false)
            any = true
        }
        val rr = scheduler.restoreRetry
        if (rr != null && rr.triggerElapsedMs <= elapsed) {
            scheduler.restoreRetry = null
            // A RestoreLoop takes (virtual) time: started here, the caller's clock steps let it run.
            scope.launch { runtime.onRestoreRetry(rr.attempt, rr.cause, rr.sinceWallMs) }
            scope.runCurrent()
            any = true
        }
        if (silenceAfterMs != null && tripId != null) {
            val x = alarm.facts[tripId]
            val started = x?.startedAtWall
            if (x != null && x.ringing && started != null && time.wallMs() >= started + silenceAfterMs) {
                alarm.silence(tripId, started + silenceAfterMs)
                now { runtime.onRingEvent(RingEvent(tripId, RingEventKind.SILENCED, started + silenceAfterMs)) }
                any = true
            }
        }
        return any
    }

    /** Virtual time of the next fake OS delivery, or null. */
    fun nextOsDeliveryMs(silenceAfterMs: Long?, tripId: String?): Long? {
        val c = ArrayList<Long>()
        scheduler.nextFallback()?.let { c += it.triggerWallMs - startWall }
        scheduler.wakeDeliveryElapsed()?.let { c += it - elapsedBase }
        scheduler.restoreRetry?.let { c += it.triggerElapsedMs - elapsedBase }
        if (silenceAfterMs != null && tripId != null) {
            val x = alarm.facts[tripId]
            val s = x?.startedAtWall
            if (x != null && x.ringing && s != null) c += s + silenceAfterMs - startWall
        }
        return c.minOrNull()
    }
}
