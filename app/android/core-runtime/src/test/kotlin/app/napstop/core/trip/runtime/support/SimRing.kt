package app.napstop.core.trip.runtime.support

import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.AlarmControllerCore
import app.napstop.core.alarm.AlarmPort
import app.napstop.core.alarm.FakeRing
import app.napstop.core.alarm.FakeTransport
import app.napstop.core.alarm.MemoryFacts
import app.napstop.core.alarm.PreAlertRequest
import app.napstop.core.alarm.RingClock
import app.napstop.core.alarm.RingCommand
import app.napstop.core.alarm.RingContent
import app.napstop.core.alarm.RingCopy
import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingFx
import app.napstop.core.alarm.RingInput
import app.napstop.core.alarm.RingPhase
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingStart
import app.napstop.core.alarm.RingStartDenied
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.runtime.RingEvent
import app.napstop.core.trip.runtime.RingEventKind
import java.util.Locale
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope

/** A device clock for the ring book from a world's [FakeTime] (seqs = elapsed ns, strictly increasing within a ms). */
class SimRingClock(private val time: FakeTime) : RingClock {
    private var bump = 0L

    override fun wallMs() = time.wallMs()

    override fun elapsedMs() = time.elapsedMs()

    override fun elapsedNanos() = time.elapsedMs() * 1_000_000L + (++bump % 900_000L)

    override fun bootCount() = time.bootCount()
}

/**
 * The `:ring` process of T16 AT1–AT6 in memory: the real ring session machine ([FakeRing]) over the ring book [facts], a
 * RING_START confirmed [confirmMs] later, a heartbeat every HEARTBEAT_MS, the auto-stop after RING_MAX, and a "user" who
 * dismisses / snoozes. It outlives a death of the main process ([World.kill]); [kill] is a death of `:ring` itself. The
 * backup notification (system-held, D4) is modelled here too: it shows until RING_MAX after the ring start.
 */
class SimRingProcess(
    private val scope: TestScope,
    var time: FakeTime,
    val c: AlarmConstants = AlarmConstants(),
    val facts: MemoryFacts = MemoryFacts(),
    private val confirmMs: Long = 500L,
) {
    var clock = SimRingClock(time)
        private set
    var ring = FakeRing(facts, clock, c)
        private set

    /** RING_EVENT receiver of the current main process. */
    var onEvent: (RingEvent) -> Unit = {}

    /** Dismiss each new session this long after it started (null: never). */
    var dismissAfterMs: Long? = 30_000L

    /** Snooze the first session this long after it started (null: never). */
    var snoozeFirstAfterMs: Long? = null

    /** `:ring` cannot run (killed again at every start): starts are never confirmed. */
    var dead = false

    /** Sessions that started a sound: (wall start, start payload). */
    val sessions = ArrayList<Pair<Long, RingStart>>()

    /** What each session showed (last content seen while it rang: overshoot updates included). */
    val sessionContent = ArrayList<RingContent?>()
    val userAt = ArrayList<Long>()
    var overlaps = 0
    var kills = 0
    private var sessionNo = 0
    private var eventsSent = 0
    private var job: Job = SupervisorJob(scope.backgroundScope.coroutineContext[Job])
    private var pscope = CoroutineScope(scope.backgroundScope.coroutineContext + job)

    /** Backup notifications showing (tripId → until wall ms). */
    val backups = HashMap<String, Long>()

    init {
        heartbeatLoop()
    }

    private fun heartbeatLoop() {
        pscope.launch {
            while (true) {
                delay(c.heartbeatMs)
                ring.heartbeat()
            }
        }
    }

    /** After a reboot: a new process on the new boot's clock; the book stays. */
    fun reboot(newTime: FakeTime) {
        kill()
        kills--
        time = newTime
        clock = SimRingClock(newTime)
        ring = FakeRing(facts, clock, c)
        eventsSent = 0
    }

    /** `:ring` dies: no sound, no heartbeat, its memory and timers are gone. */
    fun kill() {
        kills++
        job.cancel()
        ring.kill()
        sessionNo++
        job = SupervisorJob(scope.backgroundScope.coroutineContext[Job])
        pscope = CoroutineScope(scope.backgroundScope.coroutineContext + job)
        heartbeatLoop()
    }

    fun deliverStart(s: RingStart) {
        pscope.launch {
            delay(confirmMs)
            if (dead) return@launch
            follow { ring.pending += s; ring.processStarts() }
        }
    }

    fun command(cmd: RingCommand) {
        pscope.launch {
            if (dead) return@launch
            follow {
                when (cmd) {
                    is RingCommand.Update -> ring.input(RingInput.Update(cmd.start))
                    is RingCommand.Overshoot -> ring.input(RingInput.Overshoot(cmd.tripId, cmd.pastM))
                    is RingCommand.Stop -> ring.input(RingInput.Stop(cmd.tripId, cmd.cause, cmd.stopSeq))
                    is RingCommand.Snooze -> ring.input(RingInput.UserSnooze(cmd.atWallMs))
                }
            }
        }
    }

    fun postBackup(s: RingStart): Boolean {
        backups[s.request.tripId] = (s.resumeStartedAtWallMs ?: clock.wallMs()) + c.ringMaxMs
        return true
    }

    fun backupShowing(tripId: String): Boolean = (backups[tripId] ?: Long.MIN_VALUE) > clock.wallMs()

    /** Runs [block] on the fake `:ring`, then follows up a new session (auto-stop, user) and sends its events. */
    private fun follow(block: () -> Unit) {
        val before = ring.state
        val soundsBefore = ring.sounds
        block()
        if (ring.sounds > soundsBefore) {
            if (before.phase == RingPhase.RINGING && before.tripId == ring.state.tripId) overlaps++
            val no = ++sessionNo
            val st = ring.state
            val started = st.startedAtWallMs ?: clock.wallMs()
            sessions += started to st.start!!
            sessionContent += null
            pscope.launch {
                delay(c.ringMaxMs - (clock.wallMs() - started))
                if (sessionNo == no && ring.state.phase == RingPhase.RINGING) follow { ring.input(RingInput.Timeout(started + c.ringMaxMs)) }
            }
            val snooze = snoozeFirstAfterMs?.takeIf { sessions.size == 1 }
            val after = snooze ?: dismissAfterMs
            if (after != null) {
                pscope.launch {
                    delay(after)
                    if (sessionNo == no && ring.state.phase == RingPhase.RINGING) {
                        userAt += clock.wallMs()
                        follow { ring.input(if (snooze != null) RingInput.UserSnooze(clock.wallMs()) else RingInput.UserDismiss(clock.wallMs(), false)) }
                    }
                }
            }
        }
        val now = ring.state
        if (now.phase == RingPhase.RINGING && sessionContent.isNotEmpty()) {
            sessionContent[sessionContent.size - 1] = RingCopy.content(now.start!!.request, now.overshootPastM, now.start.snoozeS, Locale.ENGLISH)
        }
        val ev: List<RingFx.SendEvent> = ring.events.drop(eventsSent)
        eventsSent = ring.events.size
        val trip = ring.state.tripId ?: ring.state.start?.request?.tripId ?: sessions.lastOrNull()?.second?.request?.tripId ?: return
        for (e in ev) onEvent(RingEvent(trip, e.kind, e.atWallMs))
    }
}

/**
 * The main-process side of T16 in the runtime tests: the real [AlarmControllerCore] wired to a [SimRingProcess] (start →
 * delivered after the confirm delay, commands → at once), with the watchdog running on the world's process scope (it
 * dies with [World.kill]). [allowStart] models the FGS start rules (AT6).
 */
class SimRing(private val world: World, val proc: SimRingProcess) : AlarmPort {
    val c: AlarmConstants get() = proc.c
    val transport = FakeTransport()
    val warnings = ArrayList<String>()
    val ringCalls = ArrayList<RingRequest>()
    val lost = ArrayList<Pair<String, Long>>()

    /** null: every start allowed; else asked at each startRingService. */
    var allowStart: (() -> Boolean)? = null
    var denied = 0
    private val watching = HashSet<String>()

    private val core =
        AlarmControllerCore(
            transport, proc.facts, SimRingClock(world.time), { null },
            onRingLost = { t, at ->
                lost += t to at
                world.scope.launch { world.runtime.onRingEvent(RingEvent(t, RingEventKind.SILENCED, at)) }
            },
            onWatch = ::watch, c = proc.c, warn = { warnings += it }, locale = { Locale.ENGLISH },
        )

    init {
        proc.onEvent = { e -> world.scope.launch { world.runtime.onRingEvent(e) } }
        transport.onStart = { s -> proc.deliverStart(s) }
        transport.startHook = {
            val ok = allowStart?.invoke() ?: true
            if (!ok) {
                denied++
                throw RingStartDenied("ForegroundServiceStartNotAllowedException")
            }
        }
        transport.commandHook = { cmd -> proc.command(cmd) }
        transport.backupHook = { s -> proc.postBackup(s) }
        transport.showingHook = { t -> proc.backupShowing(t) }
    }

    private fun watch(tripId: String) {
        if (!watching.add(tripId)) return
        world.processScope.launch {
            try {
                while (true) {
                    delay(proc.c.watchdogMs)
                    if (!core.watchTick(tripId)) break
                }
            } finally {
                watching.remove(tripId)
            }
        }
    }

    override fun ringNow(request: RingRequest) {
        ringCalls += request
        core.ringNow(request)
    }

    override fun ringFallback(request: RingRequest) {
        ringCalls += request
        core.ringFallback(request)
    }

    override fun stopRinging(tripId: String, cause: StopCause) = core.stopRinging(tripId, cause)

    override fun preAlert(request: PreAlertRequest) = core.preAlert(request)

    override fun overshoot(tripId: String, pastM: Int) = core.overshoot(tripId, pastM)

    override fun ringFacts(tripId: String): RingFacts = core.ringFacts(tripId)

    override fun clearTrip(tripId: String) = core.clearTrip(tripId)
}
