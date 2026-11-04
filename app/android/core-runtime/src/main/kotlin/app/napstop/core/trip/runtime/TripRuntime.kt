package app.napstop.core.trip.runtime

import app.napstop.core.alarm.AlarmPort
import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmSilenced
import app.napstop.core.trip.AvailabilityCause
import app.napstop.core.trip.BatterySample
import app.napstop.core.trip.EngineInput
import app.napstop.core.trip.EngineParamsFactory
import app.napstop.core.trip.EngineState
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackRestoreStatus
import app.napstop.core.trip.FallbackScheduled
import app.napstop.core.trip.LocationAvailability
import app.napstop.core.trip.Step
import app.napstop.core.trip.Tick
import app.napstop.core.trip.TripConfig
import app.napstop.core.trip.TripEngine
import app.napstop.core.trip.TripPhase
import app.napstop.core.trip.TripView
import app.napstop.core.trip.UserAction
import app.napstop.core.trip.UserActionKind
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

enum class TrackingMode { IDLE, STARTING, TRACKING_FGS, HEADLESS, ENDING }

sealed interface StartOutcome {
    data object Started : StartOutcome

    /** [code] is a BridgeErrors wire code (T14 §4); [message] / [details] never hold trip data. */
    data class Rejected(val code: String, val message: String? = null, val details: List<String>? = null) : StartOutcome
}

/** Wire codes of T14 §4 that the runtime emits (same strings as :app BridgeErrors). */
object StartCodes {
    const val INVALID_CONFIG = "invalid-config"
    const val TRIP_ACTIVE = "trip-active"
    const val PERMISSION_MISSING = "permission-missing"
    const val NOT_FOREGROUND = "not-foreground"
    const val START_FAILED = "start-failed"
}

/** What a fallback alarm receiver did (journal, tests L24–L27). */
enum class FallbackFireAction {
    RANG,
    RING_FAILED,

    /** ENGINE / SAFETY slot while a ring of the trip is on: FallbackFired, no second sound. */
    ALREADY_RINGING,

    /** Evidence the alarm is stale (trip ended / another trip runs); journal action IGNORED_ENDED. */
    IGNORED,

    /** GUARD slot while the trip's ring is live: dropped, nothing recorded (designer "sau test" G1). */
    SUPPRESSED_LIVE,

    /** The user dismissed / snoozed in the native alarm UI and the runtime has not handled it yet. */
    SUPPRESSED_DISMISS,
    SUPPRESSED_SNOOZE,
}

/** What one load attempt concluded (designer "sau test" B1). */
enum class LoadOutcome { LOADED, NO_TRIP, CORRUPT, TIMEOUT }

/** Platform ports of one runtime (§4.1). */
class RuntimePorts(
    val time: TimeSource,
    val location: LocationSource,
    val tracking: TrackingController,
    val scheduler: OsAlarmScheduler,
    val alarm: AlarmPort,
    val notifier: TripNotifier,
    val store: RuntimeStore,
    val visibility: AppVisibility,
    val env: DeviceEnv,
    val journal: RuntimeJournal = RuntimeJournal.NoOp,
)

/**
 * The trip coordinator of spec T15 (D2, D3): one per process, owns the engine state of the running trip. It is an
 * actor — every engine call and state change runs in one coroutine on [actorDispatcher] (prod:
 * `Dispatchers.Default.limitedParallelism(1)`), reading a queue of jobs; internal feedback ([Effect.Feed],
 * FallbackScheduled) runs right after the Step that produced it, before the next outside job. Disk work runs on [io],
 * listeners on [main]. Nothing here blocks the main thread.
 *
 * Invariants worth knowing when reading the code:
 * - [TrackingController.start] is called only from [start] and [maybeResume], both after `visibility.isVisible()`
 *   (ADR-001, D9). Receivers, alarms and boot never start the location service.
 * - A Step is committed to memory before its effects run; disk writes are best-effort and never delay a ring (D4).
 * - Each effect runs in its own try/catch; a failure is logged with the exception class name only.
 */
class TripRuntime(
    private val ports: RuntimePorts,
    private val scope: CoroutineScope,
    private val actorDispatcher: CoroutineDispatcher,
    private val io: CoroutineDispatcher,
    private val main: CoroutineDispatcher,
    private val constants: RuntimeConstants = RuntimeConstants(),
    private val warn: (String) -> Unit,
    /** Ledger reads/writes in order, on their own lane: a hung snapshot read does not block them (tests inject it). */
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    private val ledgerIo: CoroutineDispatcher = io.limitedParallelism(1),
) {
    /** Running trip, actor-confined. */
    private class Active(val meta: TripMeta, val clock: TripClock, var engine: EngineState, var view: TripView) {
        var scheduledWakeAtMs: Long? = null
    }

    private class PendingStart(val tripId: String) {
        val result = CompletableDeferred<ForegroundResult>()
    }

    private val queue = Channel<suspend () -> Unit>(Channel.UNLIMITED)
    private val modeFlow = MutableStateFlow(TrackingMode.IDLE)
    val mode: StateFlow<TrackingMode> = modeFlow.asStateFlow()
    private val listeners = CopyOnWriteArrayList<RuntimeListener>()
    private val startGate = AtomicBoolean(false)

    @Volatile
    private var liveTripId: String? = null

    @Volatile
    private var pendingStart: PendingStart? = null

    private val fallbacks = FallbackScheduler(ports.scheduler, warn)
    private val writer =
        SnapshotWriter(scope, io, ports.store, constants.snapshotRetryMs, ports.time::wallMs, warn) { ok, ms ->
            journal("persist", mapOf("ok" to ok, "ms" to ms))
        }

    // ---- actor state ----
    private var loaded = false

    /** The ledger was read in this process (or written from memory): memory is newer than the disk from then on. */
    private var ledgerRead = false

    /** Reads still running after their budget, awaited again by the next attempt (designer "sau test" B1). */
    private var pendingSnapshotRead: kotlinx.coroutines.Deferred<Result<StoredTrip?>>? = null
    private var pendingLedgerRead: kotlinx.coroutines.Deferred<Result<FallbackLedger>>? = null
    private var interruptedShown = false
    private var active: Active? = null
    private var ledger = FallbackLedger.EMPTY
    private var consumedGeneration: Long? = null
    private val feedback = ArrayDeque<EngineInput>()
    private val memoryFinished = ArrayList<FinishedRecord>()
    private var currentSpec: FlpRequestSpec? = null
    private var lastBattery: BatteryReading? = null
    private var lastAvailability: AvailabilityCause? = null
    private var lastPersistWallMs = Long.MIN_VALUE / 2
    private var lastNotice: TrackingNotice? = null
    private var lastNoticeWallMs = Long.MIN_VALUE / 2
    private var tickJob: Job? = null

    /** A fallback ring that failed (port threw): retried at later Steps while the engine is ALARMING and silent. */
    private var ringRetry: RingRequest? = null
    private var lastRingRetryWall = Long.MIN_VALUE / 2

    /** "Interrupted" notice waiting for the foreground service (review T15 #1): shown only if it does not come back. */
    private var interruptedJob: Job? = null

    /** D11 resume asked for and not answered yet (wall ms): no second startForegroundService meanwhile. */
    private var resumeRequestedAtWall: Long? = null

    /** Platform fixes without a usable accuracy (§5.4). */
    var droppedPlatformFixes: Int = 0
        private set

    /** Debug `force_tier` (LM1): replaces the request sent to the location source; the engine is unchanged. */
    @Volatile
    var debugSpecOverride: FlpRequestSpec? = null

    /** Debug `gps_drop`: drop every platform fix. */
    @Volatile
    var debugDropFixes: Boolean = false

    init {
        scope.launch(actorDispatcher) {
            for (job in queue) {
                try {
                    job()
                } catch (e: Throwable) {
                    if (e is CancellationException && !isActive) throw e
                    // Last line of defence (§7): the actor lives on, the app does not crash.
                    warn("runtime job failed (${e.javaClass.simpleName})")
                }
            }
        }
    }

    // =================================================================== public API

    /**
     * Loads the snapshot once per process and restores (§5.8). Idempotent; every entry point does it first.
     *
     * RestoreLoop (designer "sau test" B1, F1): a load that times out on a slow disk is retried with back-off (250 ms
     * doubling, ≤ 1 s) until RECEIVER_BUDGET_MS − 500 ms after the call; each attempt is one short actor job, so a
     * fallback ring is never queued behind the loop. While only the ledger is readable after a reboot / app update, a
     * SAFETY slot is armed from it (B2). Out of budget: a restoreRetry alarm (B3) and, if the ledger names a trip,
     * "Interrupted" once.
     */
    suspend fun ensureLoaded(cause: RestoreCause = RestoreCause.PROCESS_START) {
        restoreLoop(cause, nextAttempt = 0, sinceWallMs = ports.time.wallMs())
    }

    /** The restoreRetry alarm (WakeAlarmReceiver with the retry extras): one more RestoreLoop, then the next retry. */
    suspend fun onRestoreRetry(attempt: Int, cause: RestoreCause, sinceWallMs: Long) {
        call { journal("wake_fire", mapOf("at" to null, "lateMs" to null, "kind" to "RESTORE_RETRY")) }
        restoreLoop(cause, nextAttempt = attempt + 1, sinceWallMs = sinceWallMs)
    }

    private suspend fun restoreLoop(cause: RestoreCause, nextAttempt: Int, sinceWallMs: Long): LoadOutcome {
        val deadline = ports.time.elapsedMs() + constants.receiverBudgetMs - RuntimeConstants.RESTORE_DEADLINE_MARGIN_MS
        var backoff = RuntimeConstants.RESTORE_BACKOFF_MS
        while (true) {
            val r = call { loadIfNeeded(cause, armSafety = true) }
            if (r != LoadOutcome.TIMEOUT) return r
            if (ports.time.elapsedMs() + constants.ioBudgetMs >= deadline) break
            delay(backoff)
            backoff = minOf(backoff * 2, RuntimeConstants.RESTORE_BACKOFF_MAX_MS)
        }
        call { afterRestoreBudget(cause, nextAttempt, sinceWallMs) }
        return LoadOutcome.TIMEOUT
    }

    /** §5.1. Called from Main after TripConfigValidator. */
    suspend fun start(meta: TripMeta, destLat: Double, destLng: Double): StartOutcome {
        // D12: a second start while the first has not answered is refused at once, never queued.
        if (!startGate.compareAndSet(false, true)) return StartOutcome.Rejected(StartCodes.TRIP_ACTIVE)
        var started = false
        try {
            // One bounded attempt (not the receiver loop): a trip started after it supersedes what is on disk (R2-1).
            call { loadIfNeeded(RestoreCause.PROCESS_START) }
            if (liveTripId != null) return StartOutcome.Rejected(StartCodes.TRIP_ACTIVE)
            val a = ports.env.locationAccess()
            val missing = ArrayList<String>()
            if (!a.fineGranted && !a.coarseGranted) missing += "location" else if (!a.fineGranted) missing += "precise"
            if (!a.servicesEnabled) missing += "locationServices"
            if (missing.isNotEmpty()) return StartOutcome.Rejected(StartCodes.PERMISSION_MISSING, null, missing)
            if (!a.playServicesAvailable) return StartOutcome.Rejected(StartCodes.START_FAILED, "PlayServicesUnavailable")
            if (!ports.visibility.isVisible()) return StartOutcome.Rejected(StartCodes.NOT_FOREGROUND)
            val params = EngineParamsFactory.fromOverrides(meta.engineParamsJson)
            val clock = TripClock(TripClock.anchorNow(ports.time), ports.time)
            val config =
                TripConfig(
                    meta.tripId, destLat, destLng, meta.mode, meta.distanceThresholdM, meta.timeThresholdMin,
                    meta.preAlertEnabled, meta.vehicleHint,
                )
            val step0 =
                try {
                    TripEngine.start(config, params, clock.now())
                } catch (e: IllegalArgumentException) {
                    return StartOutcome.Rejected(StartCodes.INVALID_CONFIG, e.message)
                }
            setMode(TrackingMode.STARTING)
            val pending = PendingStart(meta.tripId)
            pendingStart = pending
            try {
                ports.tracking.start(meta.tripId, StartReason.USER_START)
            } catch (e: Exception) {
                return StartOutcome.Rejected(StartCodes.START_FAILED, e.javaClass.simpleName)
            }
            val r = withTimeoutOrNull(constants.fgsStartTimeoutMs) { pending.result.await() }
            if (r !is ForegroundResult.Started) {
                stopTrackingQuietly()
                return StartOutcome.Rejected(
                    StartCodes.START_FAILED,
                    (r as? ForegroundResult.Failed)?.errorClass ?: "ForegroundTimeout",
                )
            }
            // From here the trip exists. Nothing was committed or scheduled before the FGS was up (§5.1).
            try {
                call { commitStart(meta, clock, step0) }
            } catch (e: Exception) {
                stopTrackingQuietly()
                throw e
            }
            started = true
            scope.launch { submitLastKnown() }
            return StartOutcome.Started
        } finally {
            pendingStart = null
            if (!started && modeFlow.value == TrackingMode.STARTING) setMode(TrackingMode.IDLE)
            startGate.set(false)
        }
    }

    /** Unknown tripId or no trip: no-op (T14 D10). Returns once the Step is committed. */
    suspend fun userAction(tripId: String, kind: UserActionKind) =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            val a = active ?: return@call
            if (a.meta.tripId != tripId) return@call
            process(UserAction(a.clock.now(), kind))
        }

    /** null = no trip (or ENDED). */
    suspend fun current(): Pair<TripMeta, TripView>? =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            active?.takeIf { it.engine.phase != TripPhase.ENDED }?.let { it.meta to it.view }
        }

    suspend fun batteryChoice(): UserActionKind? = call { active?.engine?.battery?.choice }

    suspend fun pendingFinished(): List<FinishedRecord> =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            retryMemoryFinished()
            val disk = ioCall("finished read", io) { ports.store.readFinished() }?.getOrNull() ?: emptyList()
            (memoryFinished + disk).distinctBy { it.tripId }.sortedWith(compareBy<FinishedRecord> { it.endedAtMs }.thenBy { it.tripId })
        }

    suspend fun ackFinished(ids: List<String>) =
        call {
            memoryFinished.removeAll { it.tripId in ids }
            ioCall("finished delete", io) { ports.store.deleteFinished(ids) }
            Unit
        }

    /** Non-blocking; [input].atMs is used as given (the engine never goes back in time). */
    fun submit(input: EngineInput) {
        post { if (active != null) process(input) }
    }

    /** Replays the latest view to every listener (T14 §2 rule 2) as one Tick Step. */
    fun requestReplay() {
        post { active?.let { process(Tick(it.clock.now())) } }
    }

    /**
     * A platform fix (any thread, non-blocking). [processed] runs once the Step of this fix is done (or the fix was
     * dropped), so the source can release its wake lock early (review T15 #4).
     */
    fun onRawFix(raw: RawFix, processed: () -> Unit = {}) {
        if (!queue.trySend { try { handleFix(raw) } finally { processed() } }.isSuccess) processed()
    }

    /**
     * WakeAlarmReceiver (§5.5): battery and location checks, then Tick at the delivery time (T10.4). [wakeAtMs] /
     * [wakeAtWallMs] come from the PendingIntent extras of the alarm that fired; logged before any restore (F5).
     */
    suspend fun onWake(wakeAtMs: Long? = null, wakeAtWallMs: Long? = null) =
        call {
            val nowWall = ports.time.wallMs()
            journal("wake_fire", mapOf("at" to wakeAtMs, "lateMs" to wakeAtWallMs?.let { nowWall - it }, "kind" to "WAKE"))
            loadIfNeeded(RestoreCause.PROCESS_START)
            val a = active ?: return@call
            a.scheduledWakeAtMs = null // consumed: the next Step sets it again even if the time is the same
            pollEnv(a)
            if (active === a) process(Tick(a.clock.now()))
        }

    /**
     * FallbackAlarmReceiver (§5.6, D8): record "rang" (synchronously), ring through [AlarmPort.ringFallback] unless a
     * ring of the trip is already on, cancel the other slot, then load the trip and feed `FallbackFired`. Runs before
     * the snapshot is read so a slow or corrupt snapshot never delays the ring.
     *
     * Ignored (and its slot cancelled) only with evidence that the alarm is stale (orchestrator decision, review T15
     * #2): the ledger lists the trip as ended, or the runtime runs a *different* trip. Anything uncertain — unreadable
     * or empty ledger, an `activeTripId` that a failed write left behind, runtime not loaded — rings: one needless
     * ring is better than a missed stop.
     *
     * Designer "sau test" G1: for every kind, a pending dismiss / snooze from the native alarm UI suppresses it; a GUARD
     * slot is dropped when the trip's ring is live (no lastFired, no FallbackFired). [kind] comes from the ledger record
     * of this slot, else from the PendingIntent extra.
     */
    suspend fun onFallbackFired(tripId: String, slot: Int, generation: Long, targetAtMs: Long, kind: SlotKind? = null): FallbackFireAction =
        call {
            val nowWall = ports.time.wallMs()
            if (!ledgerRead) readLedgerSafe()?.let { ledger = it; ledgerRead = true }
            val rec = listOfNotNull(ledger.current, ledger.stale).firstOrNull { it.slot == slot && it.generation == generation }
            val k = rec?.kind ?: kind ?: SlotKind.ENGINE
            val running = active
            val a = running?.takeIf { it.meta.tripId == tripId }

            suspend fun skip(action: FallbackFireAction, journalAction: String): FallbackFireAction {
                safely("fallback cancel") { ports.scheduler.cancelFallback(slot) }
                if (rec != null) saveLedger(ledger.copy(current = ledger.current.takeUnless { it == rec }, stale = ledger.stale.takeUnless { it == rec }))
                journal("fb_fire", mapOf("slot" to slot, "gen" to generation, "at" to targetAtMs, "lateMs" to null, "action" to journalAction, "kind" to k.name))
                return action
            }

            val endedBefore = tripId in ledger.endedTripIds && running?.meta?.tripId != tripId
            val otherTripRuns = running != null && running.meta.tripId != tripId
            if (endedBefore || otherTripRuns) return@call skip(FallbackFireAction.IGNORED, "IGNORED_ENDED")
            val facts = factsOf(tripId)
            if (facts.pendingDismissAtWallMs != null) return@call skip(FallbackFireAction.SUPPRESSED_DISMISS, "SUPPRESSED_DISMISS")
            val snooze = facts.pendingSnoozeAtWallMs
            if (snooze != null && snooze >= (rec?.setAtWallMs ?: Long.MIN_VALUE)) {
                return@call skip(FallbackFireAction.SUPPRESSED_SNOOZE, "SUPPRESSED_SNOOZE")
            }
            if (k == SlotKind.GUARD && facts.ringingNow) return@call skip(FallbackFireAction.SUPPRESSED_LIVE, "SUPPRESSED_LIVE")
            saveLedger(ledger.copy(lastFired = FiredRec(generation, targetAtMs, a?.clock?.toTrip(nowWall), nowWall)))
            var request: RingRequest? = null
            val action =
                if (facts.ringingNow) {
                    // At most one ring per trip: the ring already on is this alarm.
                    FallbackFireAction.ALREADY_RINGING
                } else {
                    val rc = readRingConfigSafe()?.takeIf { it.tripId == tripId }
                    val r =
                        RingRequest(
                            tripId = tripId,
                            source = RingSource.FALLBACK,
                            reason = null,
                            snoozeAllowed = rc?.let { it.snoozeCount < it.maxSnoozes } ?: false,
                            distanceM = a?.view?.distanceM,
                            etaS = a?.view?.etaS,
                            batteryPct = a?.view?.batteryPct,
                            destinationName = rc?.destinationName,
                            settings = rc?.settings,
                            atWallMs = nowWall,
                        )
                    request = r
                    try {
                        ports.alarm.ringFallback(r)
                        FallbackFireAction.RANG
                    } catch (e: Exception) {
                        warn("fallback ring failed (${e.javaClass.simpleName})")
                        FallbackFireAction.RING_FAILED
                    }
                }
            ledger = fallbacks.cancelAll(ledger, ::saveLedger)
            journal(
                "fb_fire",
                mapOf("slot" to slot, "gen" to generation, "at" to targetAtMs, "lateMs" to a?.let { it.clock.now() - targetAtMs }, "action" to action.name, "kind" to k.name),
            )
            journal("ring", mapOf("source" to "FALLBACK", "reason" to null, "ok" to (action == FallbackFireAction.RANG)))
            loadIfNeeded(RestoreCause.PROCESS_START)
            val b = active
            if (b != null && b.meta.tripId == tripId && consumedGeneration != generation) {
                process(FallbackFired(b.clock.now(), b.clock.toTrip(nowWall)))
            }
            // The restore just above may already have rung (G3); only a ring that is still silent goes into the retry path.
            if (action == FallbackFireAction.RING_FAILED && b != null && b.meta.tripId == tripId && !factsOf(tripId).ringingNow) {
                // Nothing is sounding: tell the engine (ALARMING, ringing = false, so the UI is right and an overshoot can
                // ring again), retry in the process (review T15 #3) and arm a new GUARD slot (designer "sau test" G2).
                process(AlarmSilenced(b.clock.now(), b.clock.now()))
                ringRetry = request
                lastRingRetryWall = nowWall
                if (b.engine.phase == TripPhase.ALARMING || b.engine.phase == TripPhase.OVERSHOT) {
                    armGuard(b, nowWall + b.engine.params.fallbackLagS * 1000L)
                }
            }
            action
        }

    /** T16 ring events (§4.4). Wrong tripId or no trip: no-op. */
    suspend fun onRingEvent(e: RingEvent) =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            val a = active
            if (a == null) {
                // F2: the ring of an orphan ledger trip (snapshot lost) was dismissed → that trip is over.
                if (loaded && e.kind == RingEventKind.DISMISSED) dismissOrphan(e.tripId)
                return@call
            }
            if (a.meta.tripId != e.tripId) return@call
            val now = a.clock.now()
            val input =
                when (e.kind) {
                    RingEventKind.DISMISSED -> UserAction(now, UserActionKind.DISMISS)
                    RingEventKind.SNOOZED -> UserAction(now, UserActionKind.SNOOZE)
                    RingEventKind.SILENCED -> AlarmSilenced(now, a.clock.toTrip(e.atWallMs))
                    RingEventKind.FALLBACK_RINGING -> FallbackFired(now, a.clock.toTrip(e.atWallMs))
                }
            process(input)
        }

    /** MainActivity visible (D11): a HEADLESS trip goes back to the foreground service. */
    suspend fun onAppVisible() =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            maybeResume(StartReason.APP_VISIBLE)
        }

    /** Tap on the "interrupted" notification (MainActivity extra napstop.resumeTripId). */
    suspend fun onNotificationResume(tripId: String) =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            if (active?.meta?.tripId == tripId) {
                maybeResume(StartReason.NOTIFICATION_TAP)
            } else if (loaded) {
                // F2: "Interrupted" of a trip that no longer exists: just remove it (no FGS, slots unchanged).
                safely("notice") { ports.notifier.clear(tripId, TripNotice.Interrupted) }
            }
        }

    /** From LocationService.onStartCommand (start, sticky restart or resume). Any thread. */
    fun onForegroundResult(tripId: String, r: ForegroundResult) {
        val p = pendingStart
        if (p != null && p.tripId == tripId) {
            p.result.complete(r)
            return
        }
        post { handleForegroundResume(tripId, r) }
    }

    /** LocationService destroyed without the runtime asking (system / OEM): FLP is gone. */
    fun onForegroundLost() {
        post {
            val a = active ?: return@post
            if (modeFlow.value != TrackingMode.TRACKING_FGS) return@post
            setMode(TrackingMode.HEADLESS)
            stopLocation()
            tickJob?.cancel()
            // A sticky restart may follow: same deferral as after a process death.
            armInterrupted(a)
        }
    }

    /** Battery or location settings changed (LocationService receivers, §5.12). */
    fun onDeviceStateChanged() {
        post { active?.let { pollEnv(it) } }
    }

    /** ACTION_TIME_CHANGED (§5.3): re-set the current fallback alarm at the same trip time. */
    fun onTimeChanged() {
        post {
            val a = active ?: return@post
            val cur = ledger.current ?: return@post
            scheduleFallback(a, cur.targetAtMs)
            drainFeedback()
        }
    }

    /** Adds a listener (called on [main]); attaching enqueues a replay Tick. Returns the remover. */
    fun addListener(l: RuntimeListener): () -> Unit {
        listeners += l
        requestReplay()
        return { listeners.remove(l) }
    }

    /** Debug `dump` (no coordinates, no distances, no names). */
    suspend fun debugDump(): String =
        call {
            val a = active
            "mode=${modeFlow.value} trip=${a?.meta?.tripId} phase=${a?.engine?.phase} gps=${a?.engine?.gps} " +
                "tier=${a?.engine?.policy?.tier} fb=${a?.engine?.fallback?.targetAtMs} fbStatus=${a?.engine?.fallback?.status} " +
                "wake=${a?.scheduledWakeAtMs} slot=${ledger.current?.slot} gen=${ledger.current?.generation} " +
                "spec=${currentSpec?.intervalMs} dropped=$droppedPlatformFixes"
        }

    private companion object {
        /** Retry interval of a fallback ring that failed (review T15 #3). */
        const val RING_RETRY_MS = 30_000L

        /** Ended trip ids kept in the ledger as evidence for stale fallback alarms (review T15 #2). */
        const val ENDED_KEPT = 5
    }

    /**
     * Debug `fb_test` (protocol LM4): with no trip running, mark [tripId] as the ledger's active trip so the real
     * fallback receiver path rings and cancels the other slot for test alarms of that id; null clears it.
     */
    suspend fun debugArmFallbackTest(tripId: String?): Boolean =
        call {
            loadIfNeeded(RestoreCause.PROCESS_START)
            if (active != null) return@call false
            saveLedger(ledger.copy(activeTripId = tripId, current = null, stale = null, lastFired = null))
            true
        }

    /** The trip id while a trip is live in this process (after [ensureLoaded]). */
    fun liveTrip(): String? = liveTripId

    // =================================================================== actor plumbing

    private suspend fun <T> call(block: suspend () -> T): T {
        val d = CompletableDeferred<T>()
        queue.send {
            try {
                d.complete(block())
            } catch (e: Throwable) {
                d.completeExceptionally(e)
            }
        }
        return d.await()
    }

    private fun post(block: suspend () -> Unit) {
        queue.trySend(block)
    }

    private fun setMode(m: TrackingMode) {
        val from = modeFlow.value
        if (from == m) return
        modeFlow.value = m
        journal("mode", mapOf("from" to from.name, "to" to m.name))
    }

    private fun journal(ev: String, fields: Map<String, Any?>) {
        val j = ports.journal
        if (!j.enabled) return
        try {
            j.log(active?.clock?.now(), ports.time.wallMs(), ev, fields)
        } catch (e: Exception) {
            warn("journal failed (${e.javaClass.simpleName})")
        }
    }

    private inline fun safely(what: String, block: () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            warn("$what failed (${e.javaClass.simpleName})")
        }
    }

    // =================================================================== load / restore (§5.8)

    private suspend fun loadIfNeeded(cause: RestoreCause, armSafety: Boolean = false): LoadOutcome {
        // Never restore over a live trip (review T15 R2-1): a trip started after a load that timed out supersedes
        // whatever was on disk.
        if (loaded || active != null) return LoadOutcome.LOADED
        if (!ledgerRead) readLedgerSafe()?.let { ledger = it; ledgerRead = true }
        // Bounded (review T15 #5): a hung disk delays the next job (maybe a fallback ring) by <= ioBudgetMs. On timeout
        // the trip is not loaded in this call; RestoreLoop / the next entry point tries again.
        // The read in flight is reused by the next attempt (a disk constantly slower than ioBudgetMs still loads).
        val d = pendingSnapshotRead ?: scope.async(io) { runCatching { ports.store.readActive() } }.also { pendingSnapshotRead = it }
        val read = withTimeoutOrNull(constants.ioBudgetMs) { d.await() }
        if (read == null) warn("snapshot read over budget") else pendingSnapshotRead = null
        if (read == null) {
            if (armSafety && ledgerRead && (cause == RestoreCause.BOOT || cause == RestoreCause.PACKAGE_REPLACED)) armSafetySlot()
            return LoadOutcome.TIMEOUT
        }
        loaded = true
        safely("restore retry cancel") { ports.scheduler.cancelRestoreRetry() }
        val failure = read.exceptionOrNull()
        if (failure != null) warn("snapshot read failed (${failure.javaClass.simpleName})")
        val stored = read.getOrNull()
        if (stored == null) {
            handleOrphan()
            return if (failure != null) LoadOutcome.CORRUPT else LoadOutcome.NO_TRIP
        }
        if (stored.engine.phase == TripPhase.ENDED) {
            // The trip ended but its record was not written (§5.7): rebuild it from the state.
            val record = FinishedRecordBuilder.fromEnded(stored.engine)
            if (record != null) {
                if (!finishFiles(record)) memoryFinished += record
            }
            ledger = fallbacks.cancelAll(ledger.copy(activeTripId = null, endedTripIds = ended(stored.meta.tripId)), ::saveLedger)
            ioCall("ring config delete", io) { ports.store.deleteRingConfig() }
            return LoadOutcome.NO_TRIP
        }
        var effective = cause
        var anchor = stored.anchor
        if (!TripClock.anchorValid(anchor, ports.time)) {
            effective = RestoreCause.BOOT
            anchor = TripClock.anchorNow(ports.time)
        }
        val clock = TripClock(anchor, ports.time, floorMs = stored.engine.nowMs)
        if (ledger.activeTripId != stored.meta.tripId) saveLedger(ledger.copy(activeTripId = stored.meta.tripId))
        val facts = factsOf(stored.meta.tripId)
        val now = clock.now()
        val info = RestorePlanner.plan(stored.engine, ledger, facts, effective, now, clock::toTrip)
        if (info.status == FallbackRestoreStatus.RANG) consumedGeneration = ledger.lastFired?.generation
        val step = TripEngine.restore(stored.engine, now, info)
        val a = Active(stored.meta, clock, step.state, step.view)
        active = a
        liveTripId = stored.meta.tripId
        lastAvailability = stored.engine.locationCause
        lastBattery = stored.engine.battery.levelPct?.let { BatteryReading(it, stored.engine.battery.charging) }
        setMode(if (safeIsForeground()) TrackingMode.TRACKING_FGS else TrackingMode.HEADLESS)
        journal("restore", mapOf("cause" to effective.name, "status" to info.status.name))
        // prev = null: notices of the restored state are shown again in the new process.
        applyStep(a, step, prev = null)
        if (active !== a) {
            drainFeedback()
            return LoadOutcome.LOADED
        }
        val view = a.view
        val fb = a.engine.fallback.targetAtMs
        val scheduledInStep = step.events.any { it is FallbackAlarmChanged && it.fallbackAtMs != null }
        if (info.status == FallbackRestoreStatus.PENDING && fb != null && !scheduledInStep) {
            // Same time again (new slot first, old one after): gets the alarm back if the OS dropped it (force-stop).
            scheduleFallback(a, fb)
        }
        val rang = step.events.any { it is Alarm && it.ringNow }
        if ((view.phase == TripPhase.ALARMING || view.phase == TripPhase.OVERSHOT) && view.alarmRinging && !facts.ringingNow && !rang) {
            restoreRing(a, facts)
        }
        if (modeFlow.value == TrackingMode.HEADLESS) {
            // After a reboot / app update nothing restarts the service: say so now. After a process death a sticky
            // restart or the app may bring the FGS back within FGS_START_TIMEOUT_MS: wait for that (review T15 #1).
            if (effective == RestoreCause.PROCESS_START) armInterrupted(a) else showInterrupted(a)
        }
        if (modeFlow.value == TrackingMode.TRACKING_FGS) applyCurrentSampling(a)
        drainFeedback()
        return LoadOutcome.LOADED
    }

    /**
     * G3 (designer "sau test", replaces step 3 of §5.8): the engine believes it is ringing but the port does not ring.
     * If the engine's last ring never reached the speaker (no ring start / silence recorded at or after it) → ring now
     * (with a guard); else it rang and stopped by itself → AlarmSilenced, as before. No new Alarm: I1 holds.
     */
    private suspend fun restoreRing(a: Active, facts: RingFacts) {
        val clock = a.clock
        // The user snoozed in the native UI and RING_EVENT SNOOZED is on its way: neither ring nor silence.
        if (facts.pendingSnoozeAtWallMs != null) return
        val rangAtWall = facts.ringStartedAtWallMs ?: facts.silencedAtWallMs
        val lastRing = a.engine.alarm.lastRingAtMs
        val neverRang = rangAtWall == null || (lastRing != null && clock.toTrip(rangAtWall) < lastRing - RuntimeConstants.WAKE_GUARD_MS)
        if (!neverRang) {
            feedback.addLast(AlarmSilenced(clock.now(), facts.silencedAtWallMs?.let(clock::toTrip) ?: clock.now()))
            return
        }
        val nowWall = ports.time.wallMs()
        val v = a.view
        val request =
            RingRequest(
                tripId = a.meta.tripId,
                source = RingSource.ENGINE,
                reason = a.engine.alarm.lastReason,
                snoozeAllowed = a.engine.phase == TripPhase.ALARMING && a.engine.alarm.snoozeCount < a.engine.params.maxSnoozes,
                distanceM = v.distanceM,
                etaS = v.etaS,
                batteryPct = v.batteryPct,
                destinationName = a.meta.destinationName,
                settings = a.meta.alarm,
                atWallMs = nowWall,
            )
        armGuard(a, nowWall + a.engine.params.fallbackLagS * 1000L)
        ringOrRetry(a, request, nowWall)
    }

    /** "now" ring; on failure G2: AlarmSilenced, in-process retry, a GUARD slot ≤ now + fallbackLagS. */
    private suspend fun ringOrRetry(a: Active, request: RingRequest, nowWall: Long): Boolean =
        try {
            ports.alarm.ringNow(request)
            journal("ring", mapOf("source" to "ENGINE", "reason" to request.reason?.name, "ok" to true))
            true
        } catch (e: Exception) {
            journal("ring", mapOf("source" to "ENGINE", "reason" to request.reason?.name, "ok" to false))
            warn("ring failed (${e.javaClass.simpleName})")
            feedback.addLast(AlarmSilenced(a.clock.now(), a.clock.now()))
            ringRetry = request
            lastRingRetryWall = nowWall
            armGuard(a, nowWall + a.engine.params.fallbackLagS * 1000L)
            false
        }

    /**
     * G1: a slot that rings no later than [atWall]: the current slot if it is that close (marked GUARD), else a new
     * GUARD slot (A/B: new first, old cancelled after). No FallbackScheduled (the engine does not know this slot).
     */
    private suspend fun armGuard(a: Active, atWall: Long) {
        val nowWall = ports.time.wallMs()
        val cur = ledger.current
        if (cur != null && cur.targetAtWallMs in nowWall..atWall) {
            if (cur.kind != SlotKind.GUARD) saveLedger(ledger.copy(current = cur.copy(kind = SlotKind.GUARD)))
            return
        }
        val target = a.clock.now() + (atWall - nowWall)
        val res = fallbacks.schedule(ledger, a.meta.tripId, target, atWall, nowWall, SlotKind.GUARD, ::saveLedger)
        ledger = res.ledger
        journal("fb_set", mapOf("slot" to res.ledger.current?.slot, "gen" to res.ledger.current?.generation, "at" to target, "ok" to res.ok, "kind" to "GUARD"))
    }

    /**
     * B2: while the snapshot is not readable after a reboot / app update, set a SAFETY slot from the ledger at
     * max(old fallback, now + safetyLagMs). PROCESS_START never: the OS still holds the trip's alarms.
     */
    private suspend fun armSafetySlot() {
        val l = ledger
        val tripId = l.activeTripId ?: return
        if (tripId in l.endedTripIds) return
        val cur = l.current ?: return
        if (cur.kind == SlotKind.SAFETY) return
        val nowWall = ports.time.wallMs()
        val target = maxOf(cur.targetAtWallMs, nowWall + constants.safetyLagMs)
        val res = fallbacks.schedule(l, tripId, target, target, nowWall, SlotKind.SAFETY, ::saveLedger)
        ledger = res.ledger
        journal("fb_set", mapOf("slot" to res.ledger.current?.slot, "gen" to res.ledger.current?.generation, "at" to target, "ok" to res.ok, "kind" to "SAFETY"))
    }

    /**
     * B3: the receiver budget ran out without a load. Hence a restoreRetry alarm (30 s, 60 s, 120 s, 240 s, then every
     * 300 s, up to restoreRetryMaxMs) and, if the ledger names a trip, "Interrupted" alerting once.
     */
    private suspend fun afterRestoreBudget(cause: RestoreCause, attempt: Int, sinceWallMs: Long) {
        if (loaded || active != null) return
        val nowWall = ports.time.wallMs()
        val giveUp = nowWall - sinceWallMs >= constants.restoreRetryMaxMs
        if (!giveUp) {
            val inMs = constants.restoreRetryDelaysMs.getOrElse(attempt) { constants.restoreRetryEveryMs }
            val exact =
                try {
                    ports.scheduler.canScheduleExact()
                } catch (e: Exception) {
                    false
                }
            safely("restore retry") { ports.scheduler.setRestoreRetry(ports.time.elapsedMs() + inMs, attempt, cause, sinceWallMs, exact) }
            journal("restore_retry", mapOf("attempt" to attempt, "inMs" to inMs, "cause" to cause.name))
        }
        val tripId = ledger.activeTripId
        if (ledgerRead && tripId != null && tripId !in ledger.endedTripIds && (!ledger.interruptedAlerted || giveUp)) {
            safely("notice") { ports.notifier.show(tripId, TripNotice.Interrupted, null, true) }
            if (!ledger.interruptedAlerted) saveLedger(ledger.copy(interruptedAlerted = true))
        }
    }

    /**
     * F2: the ledger names a trip but its snapshot is gone / corrupt: "Interrupted" (no name) alerting once, then the
     * ledger forgets the trip (no re-alert in later processes). Its fallback slot is kept: it rings ("uncertain → ring").
     */
    private suspend fun handleOrphan() {
        val tripId = ledger.activeTripId ?: return
        if (tripId in ledger.endedTripIds) {
            saveLedger(ledger.copy(activeTripId = null))
            return
        }
        safely("notice") { ports.notifier.show(tripId, TripNotice.Interrupted, null, !ledger.interruptedAlerted) }
        saveLedger(ledger.copy(activeTripId = null, interruptedAlerted = false))
    }

    /** F2: the user dismissed the ring of a trip the runtime does not have: it is over. */
    private suspend fun dismissOrphan(tripId: String) {
        safely("ring stop") { ports.alarm.stopRinging(tripId, StopCause.DISMISSED) }
        ledger = fallbacks.cancelAll(ledger, ::saveLedger)
        saveLedger(ledger.copy(endedTripIds = ended(tripId), activeTripId = ledger.activeTripId.takeUnless { it == tripId }))
        safely("alarm clear") { ports.alarm.clearTrip(tripId) }
        safely("notice") { ports.notifier.clear(tripId, TripNotice.Interrupted) }
    }

    /** Last trip ids that ended in this install: evidence that their fallback alarms are stale (review T15 #2). */
    private fun ended(tripId: String): List<String> = (ledger.endedTripIds - tripId + tripId).takeLast(ENDED_KEPT)

    /**
     * Shows "Interrupted" while the trip is ACQUIRING / TRACKING (§5.8 step 4). It alerts (sound, heads-up) exactly once
     * per HEADLESS period, also across processes (orchestrator decision R2-3): the "alerted" flag lives in the ledger
     * and is cleared when the FGS is back or the trip ends; later posts in a new process are silent.
     */
    private suspend fun showInterrupted(a: Active) {
        interruptedJob?.cancel()
        interruptedJob = null
        if (active !== a || modeFlow.value != TrackingMode.HEADLESS || interruptedShown) return
        if (a.engine.phase != TripPhase.ACQUIRING && a.engine.phase != TripPhase.TRACKING) return
        interruptedShown = true
        val alert = !ledger.interruptedAlerted
        safely("notice") { ports.notifier.show(a.meta.tripId, TripNotice.Interrupted, a.meta.destinationName, alert) }
        if (alert) saveLedger(ledger.copy(interruptedAlerted = true))
    }

    /** "Interrupted" only if the FGS is still not back after FGS_START_TIMEOUT_MS (sticky restart / app resume). */
    private fun armInterrupted(a: Active) {
        interruptedJob?.cancel()
        interruptedJob =
            scope.launch(actorDispatcher) {
                delay(constants.fgsStartTimeoutMs)
                post { showInterrupted(a) }
            }
    }

    /**
     * Receivers call this before they finish (inside their budget): if an "Interrupted" decision is pending, wait for
     * it, so a process that only woke for an alarm still shows the notice when no FGS comes back.
     */
    suspend fun awaitNotices() {
        interruptedJob?.join()
        call { }
    }

    /**
     * Disk work on [dispatcher], awaited at most `ioBudgetMs` (review T15 #5). On timeout the work goes on in the
     * background and null is returned; failures come back as a failed Result.
     */
    private suspend fun <T> ioCall(what: String, dispatcher: CoroutineDispatcher, block: () -> T): Result<T>? {
        val d = scope.async(dispatcher) { runCatching(block) }
        val r = withTimeoutOrNull(constants.ioBudgetMs) { d.await() }
        if (r == null) warn("$what over budget")
        return r
    }

    /** Finished record first, then the snapshot (§5.7), through the writer; false on failure or timeout. */
    private suspend fun finishFiles(record: FinishedRecord): Boolean {
        val ok =
            withTimeoutOrNull(constants.ioBudgetMs) {
                try {
                    writer.exclusive {
                        ports.store.writeFinished(record)
                        ports.store.deleteActive()
                    }
                    true
                } catch (e: Exception) {
                    warn("finished write failed (${e.javaClass.simpleName})")
                    false
                }
            }
        if (ok == null) warn("finished write over budget")
        return ok == true
    }

    /**
     * null when unreadable or too slow: no evidence, so a fallback alarm then rings (review T15 #2). Once read, the
     * in-memory ledger is the truth for the process (it may hold writes the disk has not taken yet).
     */
    private suspend fun readLedgerSafe(): FallbackLedger? {
        val d = pendingLedgerRead ?: scope.async(ledgerIo) { runCatching { ports.store.readLedger() } }.also { pendingLedgerRead = it }
        val r = withTimeoutOrNull(constants.ioBudgetMs) { d.await() }
        if (r == null) {
            warn("ledger read over budget")
            return null
        }
        pendingLedgerRead = null
        return r.getOrElse { e ->
            warn("ledger read failed (${e.javaClass.simpleName})")
            null
        }
    }

    private suspend fun readRingConfigSafe(): RingConfig? =
        ioCall("ring config read", io) { ports.store.readRingConfig() }?.getOrElse { e ->
            warn("ring config read failed (${e.javaClass.simpleName})")
            null
        }

    /** Ledger writes keep their order (one serial lane) and never hold the actor longer than ioBudgetMs. */
    private suspend fun saveLedger(l: FallbackLedger) {
        ledger = l
        ioCall("ledger write", ledgerIo) { ports.store.writeLedger(l) }?.onFailure { e ->
            // The alarm is set anyway; restore falls back on the engine snapshot, the receiver rings when unsure.
            warn("ledger write failed (${e.javaClass.simpleName})")
        }
    }

    private fun factsOf(tripId: String): RingFacts =
        try {
            ports.alarm.ringFacts(tripId)
        } catch (e: Exception) {
            warn("ring facts failed (${e.javaClass.simpleName})")
            RingFacts.NONE
        }

    private fun safeIsForeground(): Boolean =
        try {
            ports.tracking.isForeground
        } catch (e: Exception) {
            false
        }

    // =================================================================== start / resume

    private suspend fun commitStart(meta: TripMeta, clock: TripClock, step0: Step) {
        val a = Active(meta, clock, step0.state, step0.view)
        // The user started a new trip: from now on memory is the truth (review T15 R2-1). If the first load timed out,
        // a trip still on disk is superseded: its alarms are cancelled below and its id goes to endedTripIds.
        loaded = true
        ledgerRead = true
        pendingSnapshotRead = null // a late read of an older trip is never used (R2-1)
        pendingLedgerRead = null
        safely("restore retry cancel") { ports.scheduler.cancelRestoreRetry() }
        val superseded = ledger.activeTripId?.takeIf { it != meta.tripId }
        active = a
        liveTripId = meta.tripId
        consumedGeneration = null
        interruptedShown = false
        lastNotice = null
        lastBattery = null
        lastAvailability = AvailabilityCause.AVAILABLE
        setMode(TrackingMode.TRACKING_FGS)
        ioCall("ring config write", io) {
            ports.store.writeRingConfig(RingConfig(meta.tripId, meta.destinationName, meta.alarm, 0, step0.state.params.maxSnoozes))
        }?.onFailure { e -> warn("ring config write failed (${e.javaClass.simpleName})") }
        // Both slots, always: if the ledger could not be read (slow disk), a superseded trip's alarms are unknown.
        ledger = fallbacks.cancelAll(ledger, ::saveLedger)
        var endedIds = ledger.endedTripIds - meta.tripId // R2-2: a reused id is not "ended" any more
        if (superseded != null) endedIds = (endedIds - superseded + superseded).takeLast(ENDED_KEPT)
        saveLedger(
            ledger.copy(
                activeTripId = meta.tripId, current = null, stale = null, lastFired = null, endedTripIds = endedIds,
                interruptedAlerted = false,
            ),
        )
        applyStep(a, step0, prev = null, persistBudgetMs = constants.startPersistBudgetMs)
        if (active === a) pollEnv(a)
        drainFeedback()
    }

    private suspend fun submitLastKnown() {
        try {
            ports.location.lastKnown()?.let { onRawFix(it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            warn("last known location failed (${e.javaClass.simpleName})")
        }
    }

    private fun stopTrackingQuietly() {
        try {
            ports.tracking.stop()
        } catch (e: Exception) {
            warn("tracking stop failed (${e.javaClass.simpleName})")
        }
    }

    /** D11: only while the app is visible (ADR-001 #2) and the trip has not ended. */
    private fun maybeResume(reason: StartReason) {
        val a = active ?: return
        if (modeFlow.value != TrackingMode.HEADLESS) return
        if (a.engine.phase == TripPhase.ENDED) return
        if (!ports.visibility.isVisible()) return
        val acc =
            try {
                ports.env.locationAccess()
            } catch (e: Exception) {
                return
            }
        if ((!acc.fineGranted && !acc.coarseGranted) || !acc.servicesEnabled) return
        val now = ports.time.wallMs()
        val asked = resumeRequestedAtWall
        if (asked != null && now - asked < constants.fgsStartTimeoutMs) return
        resumeRequestedAtWall = now
        try {
            ports.tracking.start(a.meta.tripId, reason)
        } catch (e: Exception) {
            resumeRequestedAtWall = null
            warn("foreground restart failed (${e.javaClass.simpleName})")
        }
    }

    private suspend fun handleForegroundResume(tripId: String, r: ForegroundResult) {
        resumeRequestedAtWall = null
        val a = active
        if (a == null || a.meta.tripId != tripId || a.engine.phase == TripPhase.ENDED) {
            // Late Started of a refused start, or a sticky restart without a trip.
            if (r is ForegroundResult.Started) stopTrackingQuietly()
            return
        }
        when (r) {
            ForegroundResult.Started ->
                if (modeFlow.value != TrackingMode.TRACKING_FGS) {
                    interruptedJob?.cancel()
                    interruptedJob = null
                    setMode(TrackingMode.TRACKING_FGS)
                    if (interruptedShown || ledger.interruptedAlerted) {
                        safely("notice") { ports.notifier.clear(tripId, TripNotice.Interrupted) }
                    }
                    interruptedShown = false
                    if (ledger.interruptedAlerted) saveLedger(ledger.copy(interruptedAlerted = false))
                    applyCurrentSampling(a)
                    lastNotice = null
                    updateTracking(a, NoticeFormatter.notice(a.meta, a.view), ports.time.wallMs())
                    scheduleAwakeTick(a)
                }
            is ForegroundResult.Failed -> {
                warn("foreground restart failed (${r.errorClass})")
                if (modeFlow.value != TrackingMode.HEADLESS) setMode(TrackingMode.HEADLESS)
                // startForeground really failed (sticky restart without location access, §5.8): tell the user now.
                showInterrupted(a)
            }
        }
    }

    // =================================================================== Steps

    private suspend fun process(input: EngineInput) {
        val a = active ?: return
        applyStep(a, TripEngine.reduce(a.engine, input), input = input)
        drainFeedback()
    }

    private suspend fun drainFeedback() {
        while (feedback.isNotEmpty()) {
            val input = feedback.removeFirst()
            val a = active ?: continue
            applyStep(a, TripEngine.reduce(a.engine, input), input = input)
        }
    }

    private suspend fun handleFix(raw: RawFix) {
        val a = active ?: return
        if (debugDropFixes) return
        val now = a.clock.now()
        val nanos = ports.time.elapsedNanos()
        val fix = FixMapper.map(raw, now, nanos)
        journal(
            "fix",
            mapOf("ageMs" to FixMapper.ageMs(raw, nanos), "accM" to raw.accuracyM?.toDouble(), "hasSpd" to (raw.speedMps != null), "dropped" to (fix == null)),
        )
        if (fix == null) {
            droppedPlatformFixes++
            return
        }
        process(fix)
    }

    /** §5.12: battery and location availability, sent only when they change. */
    private suspend fun pollEnv(a: Active) {
        val battery =
            try {
                ports.env.battery()
            } catch (e: Exception) {
                null
            }
        if (battery != null && battery != lastBattery) {
            lastBattery = battery
            process(BatterySample(a.clock.now(), battery.levelPct, battery.charging))
        }
        if (active !== a) return
        val acc =
            try {
                ports.env.locationAccess()
            } catch (e: Exception) {
                null
            } ?: return
        // Coarse only (precise revoked mid-trip) is not PERMISSION_REVOKED: the engine drops coarse fixes itself.
        val cause =
            when {
                !acc.fineGranted && !acc.coarseGranted -> AvailabilityCause.PERMISSION_REVOKED
                !acc.servicesEnabled -> AvailabilityCause.SERVICES_OFF
                else -> AvailabilityCause.AVAILABLE
            }
        if (cause != lastAvailability) {
            lastAvailability = cause
            process(LocationAvailability(a.clock.now(), cause))
        }
    }

    /** Commit [step] (memory first), then run its effects in plan order. */
    private suspend fun applyStep(
        a: Active,
        step: Step,
        prev: TripView? = a.view,
        persistBudgetMs: Long? = null,
        input: EngineInput? = null,
    ) {
        a.engine = step.state
        a.view = step.view
        val nowWall = ports.time.wallMs()
        val nowTrip = a.clock.now()
        val ringNow = step.events.any { it is Alarm && it.ringNow }
        val facts = if (ringNow) factsOf(a.meta.tripId) else RingFacts.NONE
        val canExact =
            try {
                ports.scheduler.canScheduleExact()
            } catch (e: Exception) {
                false
            }
        val plan =
            EffectPlanner.plan(
                PlanInput(
                    prev, step, a.meta, modeFlow.value, facts, a.scheduledWakeAtMs, step.state.params, nowWall, nowTrip,
                    canExact, constants.nearWakeUsesAlarmClock, constants.preRingPersistBudgetMs,
                ),
            )
        if (ports.journal.enabled) {
            val v = step.view
            journal(
                "step",
                mapOf(
                    "phase" to v.phase.name, "gps" to v.gps.name, "tier" to v.samplingPolicy?.tier?.name, "predicted" to v.predictedAlarmAtMs,
                    "fb" to v.fallbackAtMs, "fbStatus" to v.fallbackStatus.name, "wake" to v.wakeAtMs,
                    "events" to step.events.map { it.javaClass.simpleName }, "input" to input?.javaClass?.simpleName,
                ),
            )
        }
        val ctx = ExecContext(a, step, nowWall, persistBudgetMs)
        for (fx in plan) {
            try {
                execute(ctx, fx)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (fx is Effect.Ring) ctx.ringOk = false
                warn("effect ${fx.javaClass.simpleName} failed (${e.javaClass.simpleName})")
            }
        }
        if (active === a) {
            retryRing(a, nowWall)
            scheduleAwakeTick(a)
        }
    }

    /**
     * Retry of a ring that failed (review T15 #3, designer G2): every RING_RETRY_MS while ALARMING and silent; each
     * failure arms a new GUARD slot (the path that works while the process sleeps or dies).
     */
    private suspend fun retryRing(a: Active, nowWall: Long) {
        val r = ringRetry ?: return
        val phase = a.engine.phase
        if (r.tripId != a.meta.tripId || (phase != TripPhase.ALARMING && phase != TripPhase.OVERSHOT) || a.view.alarmRinging) {
            ringRetry = null
            return
        }
        if (nowWall - lastRingRetryWall < RING_RETRY_MS) return
        lastRingRetryWall = nowWall
        try {
            val retry = r.copy(atWallMs = nowWall)
            if (r.source == RingSource.ENGINE) ports.alarm.ringNow(retry) else ports.alarm.ringFallback(retry)
            ringRetry = null
            journal("ring", mapOf("source" to r.source.name, "reason" to r.reason?.name, "ok" to true))
            feedback.addLast(FallbackFired(a.clock.now(), a.clock.now()))
        } catch (e: Exception) {
            warn("ring retry failed (${e.javaClass.simpleName})")
            armGuard(a, nowWall + a.engine.params.fallbackLagS * 1000L)
        }
    }

    private class ExecContext(val a: Active, val step: Step, val nowWall: Long, val persistBudgetMs: Long?) {
        var ringOk = true
        var persisted = false
    }

    private suspend fun execute(c: ExecContext, fx: Effect) {
        val a = c.a
        val tripId = a.meta.tripId
        when (fx) {
            is Effect.PersistNow -> {
                // D4: bounded; a failure or timeout never stops the ring that follows.
                writer.persistNow(stored(a, c.nowWall), fx.budgetMs)
                lastPersistWallMs = c.nowWall
                c.persisted = true
            }
            is Effect.ArmRingGuard -> armGuard(a, fx.guardAtWallMs)
            is Effect.Ring ->
                // G2: a failure keeps the guard slot (≤ now + fallbackLagS), tells the engine it is silent, retries.
                if (!ringOrRetry(a, fx.request, c.nowWall)) c.ringOk = false
            is Effect.Feed -> feedback.addLast(fx.input)
            is Effect.StopRinging -> ports.alarm.stopRinging(tripId, fx.cause)
            is Effect.PreAlertFx -> ports.alarm.preAlert(fx.request)
            is Effect.OvershootFx -> ports.alarm.overshoot(tripId, fx.pastM)
            is Effect.ApplySampling -> requestLocation(fx.spec)
            is Effect.ScheduleFallback -> scheduleFallback(a, fx.targetAtMs)
            Effect.CancelFallback -> {
                if (ledger.current != null || ledger.stale != null) journal("fb_cancel", mapOf("slot" to ledger.current?.slot))
                ledger = fallbacks.cancelAll(ledger, ::saveLedger)
            }
            is Effect.ScheduleWake -> {
                ports.scheduler.setWake(a.clock.toElapsed(fx.wakeAtMs), fx.mechanism, a.clock.toWall(fx.wakeAtMs), fx.wakeAtMs)
                a.scheduledWakeAtMs = fx.wakeAtMs
                journal("wake_set", mapOf("at" to fx.wakeAtMs, "mech" to fx.mechanism.name))
            }
            Effect.CancelWake -> {
                a.scheduledWakeAtMs = null
                ports.scheduler.cancelWake()
            }
            is Effect.Notice -> {
                fx.show?.let { ports.notifier.show(tripId, it, a.meta.destinationName) }
                fx.clear?.let { ports.notifier.clear(tripId, it) }
            }
            Effect.ClearNotices -> ports.notifier.clearAll(tripId)
            is Effect.Tracking -> updateTracking(a, fx.content, c.nowWall)
            is Effect.UpdateRingConfig ->
                ioCall("ring config write", io) {
                    ports.store.writeRingConfig(RingConfig(tripId, a.meta.destinationName, a.meta.alarm, fx.snoozeCount, a.engine.params.maxSnoozes))
                }?.getOrThrow()
            Effect.Persist -> {
                val budget = c.persistBudgetMs
                if (budget != null) {
                    writer.persistNow(stored(a, c.nowWall), budget)
                    lastPersistWallMs = c.nowWall
                } else if (!c.persisted && (c.step.events.isNotEmpty() || c.nowWall - lastPersistWallMs >= constants.snapshotMinIntervalMs)) {
                    writer.submit(stored(a, c.nowWall))
                    lastPersistWallMs = c.nowWall
                }
            }
            Effect.Publish -> publish(a, c.step)
            is Effect.Finish -> finishTrip(a, fx.record, c.nowWall)
        }
    }

    private fun stored(a: Active, nowWall: Long) = StoredTrip(StoredTrip.VERSION, a.meta, a.clock.anchor, a.engine, nowWall)

    private suspend fun publish(a: Active, step: Step) {
        if (listeners.isEmpty()) return
        val choice = a.engine.battery.choice
        withContext(main) {
            for (l in listeners) {
                try {
                    l.onStep(a.meta.tripId, step.view, choice, step.events)
                } catch (e: Exception) {
                    // D13: one listener never blocks another or fails a committed call.
                    warn("listener failed (${e.javaClass.simpleName})")
                }
            }
        }
    }

    private fun updateTracking(a: Active, content: TrackingNotice, nowWall: Long) {
        if (modeFlow.value != TrackingMode.TRACKING_FGS) return
        val last = lastNotice
        if (content == last) return
        if (last != null && last.phase == content.phase && nowWall - lastNoticeWallMs < constants.notifMinIntervalMs) return
        ports.tracking.updateTrackingNotification(content)
        lastNotice = content
        lastNoticeWallMs = nowWall
    }

    private suspend fun scheduleFallback(a: Active, targetAtMs: Long) {
        val res = fallbacks.schedule(ledger, a.meta.tripId, targetAtMs, a.clock.toWall(targetAtMs), ports.time.wallMs(), save = ::saveLedger)
        ledger = res.ledger
        journal("fb_set", mapOf("slot" to res.ledger.current?.slot, "gen" to res.ledger.current?.generation, "at" to targetAtMs, "ok" to res.ok, "kind" to "ENGINE"))
        feedback.addLast(FallbackScheduled(a.clock.now(), targetAtMs, res.ok))
    }

    private fun requestLocation(spec: FlpRequestSpec) {
        if (modeFlow.value != TrackingMode.TRACKING_FGS) return
        val effective = debugSpecOverride ?: spec
        if (effective == currentSpec) return
        try {
            ports.location.request(effective) { raw, processed -> onRawFix(raw, processed) }
            currentSpec = effective
        } catch (e: SecurityException) {
            warn("location request refused (SecurityException)")
            active?.let { feedback.addLast(LocationAvailability(it.clock.now(), AvailabilityCause.PERMISSION_REVOKED)) }
        } catch (e: Exception) {
            warn("location request failed (${e.javaClass.simpleName})")
        }
    }

    private fun applyCurrentSampling(a: Active) {
        currentSpec = null
        a.view.samplingPolicy?.let { requestLocation(FlpMapper.spec(it, a.engine.params)) }
    }

    /** Debug `force_tier`: apply the override (or drop it) right away. */
    fun debugReapplySampling() {
        post { active?.let { applyCurrentSampling(it) } }
    }

    private fun stopLocation() {
        if (currentSpec == null) return
        currentSpec = null
        safely("location stop") { ports.location.stop() }
    }

    /** T10 §2.6: Tick at min(wakeAtMs, last Step + AWAKE_TICK_MAX_MS) while the CPU is awake and the FGS runs (I14). */
    private fun scheduleAwakeTick(a: Active) {
        tickJob?.cancel()
        val max = constants.awakeTickMaxMs ?: return
        if (modeFlow.value != TrackingMode.TRACKING_FGS) return
        val now = a.clock.now()
        val target = minOf(a.view.wakeAtMs ?: Long.MAX_VALUE, now + max)
        val d = maxOf(0L, target - now)
        tickJob =
            scope.launch(actorDispatcher) {
                delay(d)
                post {
                    if (active === a) {
                        pollEnv(a)
                        if (active === a) process(Tick(a.clock.now()))
                    }
                }
            }
    }

    // =================================================================== end of trip (§5.7)

    private suspend fun finishTrip(a: Active, record: FinishedRecord, nowWall: Long) {
        setMode(TrackingMode.ENDING)
        if (!finishFiles(record)) {
            // Keep the record in memory and an ENDED snapshot on disk; both are retried (§5.7).
            memoryFinished += record
            writer.submit(stored(a, nowWall))
        }
        ioCall("ring config delete", io) { ports.store.deleteRingConfig() }
        saveLedger(ledger.copy(activeTripId = null, current = null, stale = null, endedTripIds = ended(a.meta.tripId), interruptedAlerted = false))
        safely("alarm clear") { ports.alarm.clearTrip(a.meta.tripId) }
        stopLocation()
        tickJob?.cancel()
        tickJob = null
        stopTrackingQuietly()
        feedback.clear()
        active = null
        liveTripId = null
        consumedGeneration = null
        lastNotice = null
        lastBattery = null
        lastAvailability = null
        ringRetry = null
        interruptedJob?.cancel()
        interruptedJob = null
        interruptedShown = false
        setMode(TrackingMode.IDLE)
    }

    private suspend fun retryMemoryFinished() {
        if (memoryFinished.isEmpty()) return
        val written = ArrayList<FinishedRecord>()
        for (r in memoryFinished) {
            val ok =
                withTimeoutOrNull(constants.ioBudgetMs) {
                    try {
                        writer.exclusive { ports.store.writeFinished(r) }
                        true
                    } catch (e: Exception) {
                        warn("finished write failed (${e.javaClass.simpleName})")
                        false
                    }
                }
            if (ok == true) written += r
        }
        if (written.isNotEmpty() && active == null) {
            safely("snapshot delete") { writer.exclusive { ports.store.deleteActive() } }
        }
        memoryFinished.removeAll(written.toSet())
    }
}
