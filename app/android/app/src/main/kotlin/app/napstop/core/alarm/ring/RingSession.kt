package app.napstop.core.alarm.ring

import android.annotation.SuppressLint
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.HandlerThread
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import app.napstop.core.alarm.AlarmChannels
import app.napstop.core.alarm.AlarmConstants
import app.napstop.core.alarm.AlarmConstantsHolder
import app.napstop.core.alarm.AndroidRingClock
import app.napstop.core.alarm.BackupRingNotifier
import app.napstop.core.alarm.DismissMethod
import app.napstop.core.alarm.RingBoot
import app.napstop.core.alarm.RingContent
import app.napstop.core.alarm.RingFactsMerge
import app.napstop.core.alarm.RingFactsRecord
import app.napstop.core.alarm.RingFactsStore
import app.napstop.core.alarm.RingFx
import app.napstop.core.alarm.RingInput
import app.napstop.core.alarm.RingIntents
import app.napstop.core.alarm.RingPhase
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSessionMachine
import app.napstop.core.alarm.RingStart
import app.napstop.core.alarm.RingState
import app.napstop.core.alarm.StopCause
import app.napstop.core.alarm.VibrationPatterns
import app.napstop.core.trip.runtime.FileRuntimeStore
import app.napstop.core.trip.runtime.RingConfig
import java.io.File
import java.util.Locale
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** What AlarmActivity shows (main thread reads it). */
data class RingUiState(
    val phase: RingPhase = RingPhase.IDLE,
    val tripId: String? = null,
    val content: RingContent? = null,
    val method: DismissMethod = DismissMethod.SWIPE,
    /** ARB key of the banner, or null. */
    val banner: String? = null,
    /** "Xem đường quay lại" was pressed: the activity dismisses the keyguard and opens MainActivity. */
    val routeBack: Boolean = false,
    val startedAtElapsedMs: Long = 0L,
)

/**
 * The ring session of the `:ring` process (spec T16 §2, §5.4–§5.7): one per process, one thread ("napstop-ring"). Every
 * input runs through [RingSessionMachine] on that thread, then its effects in order (no locks needed in the process).
 * The UI reads [state]. Nothing here imports the main process runtime, Flutter or Firebase (D18).
 */
class RingSession private constructor(context: Context) {
    private val ctx = context.applicationContext
    private val thread = HandlerThread("napstop-ring").apply { start() }
    val handler = Handler(thread.looper)
    private val store = RingFactsStore(File(ctx.noBackupFilesDir, RingFactsStore.DIR_NAME))
    private val clock = AndroidRingClock(ctx)
    private val journal = RingJournalSink.create(ctx)
    private val c: AlarmConstants = AlarmConstantsHolder.load(ctx)
    private val headset = HeadsetMonitor(ctx, handler)
    private val audio = RingAudio(ctx, handler, headset, journal)
    private val vibrator = RingVibrator(ctx)
    private val torch = RingTorch(ctx, handler, c.flashOnMs, c.flashOffMs)
    private val backup = BackupRingNotifier(ctx) { c.ringMaxMs }
    private val heartbeat =
        RingHeartbeat(
            handler, store, c.heartbeatMs, clock::bootCount,
            onStale = { trip, seq -> applyInput(RingInput.Stop(trip, StopCause.TRIP_ENDED, seq ?: Long.MIN_VALUE)) },
            onBackupTakenOver = { trip -> backup.cancel(trip) },
        )
    private var machine = RingState()
    private var wakeLock: PowerManager.WakeLock? = null
    private var service: AlarmRingService? = null
    private var handledStartId = 0

    /** The ring notification of the current session was posted once (later posts do not alert). */
    private var notificationPosted = false
    private var startRequestedAtElapsed: Long? = null
    private val timeout = Runnable { machine.startedAtWallMs?.let { applyInput(RingInput.Timeout(it + c.ringMaxMs)) } }
    private val ui = MutableStateFlow(RingUiState())
    val state: StateFlow<RingUiState> = ui.asStateFlow()

    // ------------------------------------------------------------------ entry points (any thread)

    fun post(input: RingInput) {
        handler.post { applyInput(input) }
    }

    fun attach(s: AlarmRingService) = handler.post { service = s }

    /** The service got start [id]; posted before that start's work, so the ring thread sees them in order. */
    fun noteStartId(id: Int) = handler.post { handledStartId = id }

    fun onServiceDestroyed(s: AlarmRingService) =
        handler.post {
            if (service === s) service = null
            // The service died (or was stopped): outputs off; no RING_EVENT (watchdog / restore handle a lost ring).
            notificationPosted = false
            if (machine.phase == RingPhase.RINGING) {
                stopOutputs()
                releaseWakeLock()
                machine = RingState(stopSeqs = machine.stopSeqs, pendingOvershoot = machine.pendingOvershoot)
                publish(null)
            }
        }

    /** RING_START from the main process. */
    fun start(s: RingStart) =
        handler.post {
            startRequestedAtElapsed = SystemClock.elapsedRealtime()
            applyInput(startInput(s, store.readQuiet(s.request.tripId)))
        }

    /** AlarmActivity opened from the backup notification: this process takes the ring over (D4). */
    fun adopt(tripId: String, backupStart: RingStart? = null) =
        handler.post {
            if (machine.phase == RingPhase.RINGING && machine.tripId == tripId) return@post
            val r = RingBoot.sanitize(store.readQuiet(tripId), clock.bootCount(), SystemClock.elapsedRealtimeNanos())
            if (r == null || !r.ringing || r.pendingDismissAtWallMs != null) {
                stopServiceIfIdle()
                return@post
            }
            startRequestedAtElapsed = SystemClock.elapsedRealtime()
            // The request the backup notification carried (copy, settings, snooze); else rebuilt from the book.
            val s =
                backupStart?.copy(ringSeq = SystemClock.elapsedRealtimeNanos(), launchUi = false, resumeStartedAtWallMs = r.startedAtWallMs)
                    ?: rebuild(r, launchUi = false)
            applyInput(startInput(s, r))
        }

    /** START_STICKY restart (intent null): the newest live ring of the book plays on with its first start time. */
    fun stickyRestart() =
        handler.post {
            if (machine.phase == RingPhase.RINGING) return@post
            val now = System.currentTimeMillis()
            val boot = clock.bootCount()
            val r =
                try {
                    store.listRinging()
                } catch (e: Exception) {
                    emptyList()
                }.filter { it.pendingDismissAtWallMs == null && (it.bootCount == null || boot == null || it.bootCount == boot) && now < it.startedAtWallMs + c.ringMaxMs }
                    .maxByOrNull { it.startedAtWallMs }
            if (r == null) {
                stopServiceIfIdle()
                return@post
            }
            applyInput(startInput(rebuild(r, launchUi = false), r))
        }

    /** RING_START that could not be parsed etc.: stop the service unless a ring is on. */
    fun stopServiceIfIdle() =
        handler.post { if (machine.phase != RingPhase.RINGING) service?.stopRing(handledStartId) }

    fun userDismiss(routeBack: Boolean) = post(RingInput.UserDismiss(System.currentTimeMillis(), routeBack))

    fun userSnooze() = post(RingInput.UserSnooze(System.currentTimeMillis()))

    /** Notification "Báo lại" when no session rings this trip: the backup ring is snoozed (book + event). */
    fun snoozeFromNotification(tripId: String, atWallMs: Long) =
        handler.post {
            if (machine.phase == RingPhase.RINGING && machine.tripId == tripId) {
                applyInput(RingInput.UserSnooze(atWallMs))
                return@post
            }
            var snoozed = false
            try {
                store.update(tripId, sync = true) { r ->
                    if (r != null && r.ringing && r.mode == app.napstop.core.alarm.RingMode.BACKUP) {
                        snoozed = true
                        r.copy(ringing = false, snoozedAtWallMs = atWallMs, endedBy = app.napstop.core.alarm.RingEnd.SNOOZED)
                    } else {
                        r
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "backup snooze failed (${e.javaClass.simpleName})")
            }
            if (snoozed) {
                backup.cancel(tripId)
                RingEventSender.send(ctx, tripId, app.napstop.core.trip.runtime.RingEventKind.SNOOZED, atWallMs)
            }
        }

    // ------------------------------------------------------------------ machine (ring thread)

    private fun startInput(s: RingStart, stored: RingFactsRecord?): RingInput.Start =
        RingInput.Start(
            s = s,
            headphonesConnected = headset.connectedNow(),
            stored = stored,
            nowWallMs = System.currentTimeMillis(),
            nowElapsedMs = SystemClock.elapsedRealtime(),
            bootCount = clock.bootCount(),
        )

    private fun applyInput(input: RingInput) {
        val (next, fx) =
            try {
                RingSessionMachine.reduce(machine, input, c, locale())
            } catch (e: Exception) {
                Log.w(TAG, "ring session failed (${e.javaClass.simpleName})")
                return
            }
        val before = machine
        machine = next
        if (input is RingInput.UserDismiss && before.phase == RingPhase.RINGING) {
            journal.log(
                "dismiss",
                mapOf("method" to before.plan?.dismissMethod?.name, "afterMs" to (before.startedAtWallMs?.let { System.currentTimeMillis() - it })),
            )
        }
        var routeBack = false
        for (f in fx) {
            try {
                if (f is RingFx.OpenRouteBack) routeBack = true
                run(f)
            } catch (e: Exception) {
                Log.w(TAG, "ring effect ${f.javaClass.simpleName} failed (${e.javaClass.simpleName})")
            }
        }
        if (next.phase != RingPhase.RINGING) publish(routeBack)
    }

    private fun run(f: RingFx) {
        when (f) {
            is RingFx.WriteFacts -> writeFacts(f.record, f.sync)
            is RingFx.WriteStopSeq ->
                store.update(f.tripId, sync = true) { raw ->
                    RingBoot.sanitize(raw, clock.bootCount(), SystemClock.elapsedRealtimeNanos())
                        ?.let { r -> r.copy(stopSeq = maxOf(f.stopSeq, r.stopSeq ?: Long.MIN_VALUE), bootCount = r.bootCount ?: clock.bootCount()) }
                }
            RingFx.AcquireWakeLock -> acquireWakeLock()
            RingFx.ReleaseWakeLock -> releaseWakeLock()
            is RingFx.StartAudio ->
                audio.start(
                    f.route, f.plan, f.elapsedMs,
                    onNoSound = { vibrator.start(VibrationPatterns.STRONG) },
                    onSoundBack = { f.plan.vibration?.let { vibrator.start(it) } ?: vibrator.stop() },
                )
            RingFx.StopAudio -> audio.stop()
            is RingFx.StartVibration -> vibrator.start(f.spec)
            RingFx.StopVibration -> vibrator.stop()
            RingFx.StartFlash -> torch.start()
            RingFx.StopFlash -> torch.stop()
            is RingFx.WatchHeadphones -> headset.watch(f.on) { post(RingInput.HeadphonesGone) }
            is RingFx.ScheduleTimeout -> {
                handler.removeCallbacks(timeout)
                handler.postDelayed(timeout, f.inMs)
            }
            RingFx.CancelTimeout -> handler.removeCallbacks(timeout)
            is RingFx.Heartbeat -> if (f.on) machine.tripId?.let { heartbeat.start(it) } else heartbeat.stop()
            is RingFx.PublishUi -> {
                ui.value =
                    RingUiState(
                        phase = machine.phase, tripId = machine.tripId, content = f.content, method = f.method, banner = f.banner,
                        startedAtElapsedMs = ui.value.startedAtElapsedMs.takeIf { ui.value.tripId == machine.tripId && it > 0 } ?: SystemClock.elapsedRealtime(),
                    )
            }
            is RingFx.PostNotification -> {
                val trip = machine.tripId ?: return
                RingNotifications.post(ctx, RingNotifications.ringing(ctx, trip, f.content, firstOfSession = !notificationPosted))
                notificationPosted = true
                // This process plays now: the backup notification of the trip (if any) goes.
                backup.cancel(trip)
                journalStart()
            }
            RingFx.LaunchUi -> launchUi()
            is RingFx.SendEvent -> machine.tripId?.let { RingEventSender.send(ctx, it, f.kind, f.atWallMs) }
                ?: machine.start?.request?.tripId?.let { RingEventSender.send(ctx, it, f.kind, f.atWallMs) }
            is RingFx.OpenRouteBack -> Unit // the activity does it when it sees routeBack (needs the activity)
            RingFx.StopService -> {
                journal.log("ring_end", mapOf("by" to machine.endedBy?.name, "afterMs" to machine.startedAtWallMs?.let { System.currentTimeMillis() - it }))
                notificationPosted = false
                service?.stopRing(handledStartId)
                val ended = machine
                machine = RingState(stopSeqs = ended.stopSeqs, pendingOvershoot = ended.pendingOvershoot, endedBy = ended.endedBy, start = ended.start, phase = RingPhase.ENDED)
            }
        }
    }

    private fun writeFacts(record: RingFactsRecord, sync: Boolean) {
        var stopNow = false
        store.update(record.tripId, sync) { disk ->
            val (m, stop) = RingFactsMerge.merge(disk, record, SystemClock.elapsedRealtimeNanos())
            stopNow = stop
            m
        }
        if (stopNow && machine.phase == RingPhase.RINGING && machine.tripId == record.tripId) {
            // The main process stopped this ring before it started (stopSeq ≥ ringSeq): stop at once.
            handler.post { applyInput(RingInput.Stop(record.tripId, StopCause.TRIP_ENDED, Long.MIN_VALUE)) }
        }
    }

    private fun journalStart() {
        val req = startRequestedAtElapsed ?: return
        startRequestedAtElapsed = null
        val start = machine.start ?: return
        handler.postDelayed({
            val sound = audio.firstSoundAtElapsed
            journal.log(
                "ring_start",
                mapOf(
                    "source" to start.request.source.name, "reason" to start.request.reason?.name, "fg" to service?.fgType?.name,
                    "route" to machine.route?.name, "latencyMs" to sound?.let { it - req },
                ),
            )
        }, 500)
    }

    private fun publish(routeBack: Boolean?) {
        ui.value = ui.value.copy(phase = machine.phase, routeBack = routeBack ?: false)
    }

    private fun stopOutputs() {
        audio.stop()
        vibrator.stop()
        torch.stop()
        headset.watch(false) {}
        handler.removeCallbacks(timeout)
        heartbeat.stop()
    }

    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = ctx.getSystemService(PowerManager::class.java) ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "napstop:ring").apply { acquire(c.ringWakelockMs) }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun launchUi() {
        val trip = machine.tripId ?: return
        try {
            ctx.startActivity(RingIntents.activity(ctx, trip))
        } catch (e: Exception) {
            Log.w(TAG, "alarm activity failed (${e.javaClass.simpleName})")
        }
    }

    /** RingStart from the book + ring_config.properties (adopt / sticky restart, §5.4). */
    private fun rebuild(r: RingFactsRecord, launchUi: Boolean): RingStart {
        val rc: RingConfig? =
            try {
                FileRuntimeStore(File(ctx.noBackupFilesDir, FileRuntimeStore.DIR_NAME)) { Log.w(TAG, it) }.readRingConfig()?.takeIf { it.tripId == r.tripId }
            } catch (e: Exception) {
                null
            }
        return RingStart(
            request =
                RingRequest(
                    tripId = r.tripId, source = r.source, reason = r.reason,
                    snoozeAllowed = rc?.let { it.snoozeCount < it.maxSnoozes } ?: false,
                    distanceM = null, etaS = null, batteryPct = null,
                    destinationName = rc?.destinationName, settings = rc?.settings, atWallMs = System.currentTimeMillis(),
                ),
            ringSeq = SystemClock.elapsedRealtimeNanos(),
            snoozeS = rc?.snoozeS?.takeIf { it > 0 } ?: c.snoozeSDefault,
            launchUi = launchUi,
            resumeStartedAtWallMs = r.startedAtWallMs,
        )
    }

    private fun locale(): Locale = ctx.resources.configuration.locales[0] ?: Locale.getDefault()

    private fun RingFactsStore.readQuiet(tripId: String): RingFactsRecord? =
        try {
            read(tripId)
        } catch (e: Exception) {
            null
        }

    /** Debug: current machine phase (adb ring_facts runs in the main process; this is for the activity). */
    fun phase(): RingPhase = machine.phase

    companion object {
        private const val TAG = "NapStopRing"

        @Volatile
        private var instance: RingSession? = null

        fun get(context: Context): RingSession =
            instance ?: synchronized(this) { instance ?: RingSession(context.applicationContext).also { instance = it } }

        /** Notification manager check used by the service for the FGS notification (no-op helper). */
        internal fun ensureChannels(ctx: Context) {
            AlarmChannels.ensure(ctx)
            ctx.getSystemService(NotificationManager::class.java)
        }

        internal fun activityIntent(ctx: Context, tripId: String): Intent = RingIntents.activity(ctx, tripId)
    }
}
