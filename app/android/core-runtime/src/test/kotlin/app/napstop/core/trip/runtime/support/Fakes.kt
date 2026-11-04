package app.napstop.core.trip.runtime.support

import app.napstop.core.alarm.AlarmPort
import app.napstop.core.alarm.PreAlertRequest
import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.runtime.AppVisibility
import app.napstop.core.trip.runtime.BatteryReading
import app.napstop.core.trip.runtime.DeviceEnv
import app.napstop.core.trip.runtime.FallbackLedger
import app.napstop.core.trip.runtime.FinishedRecord
import app.napstop.core.trip.runtime.FixSink
import app.napstop.core.trip.runtime.FlpRequestSpec
import app.napstop.core.trip.runtime.ForegroundResult
import app.napstop.core.trip.runtime.LocationAccess
import app.napstop.core.trip.runtime.LocationSource
import app.napstop.core.trip.runtime.OsAlarmScheduler
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.RingConfig
import app.napstop.core.trip.runtime.RuntimeCodec
import app.napstop.core.trip.runtime.RuntimeJournal
import app.napstop.core.trip.runtime.RuntimeStore
import app.napstop.core.trip.runtime.StartReason
import app.napstop.core.trip.runtime.StoredTrip
import app.napstop.core.trip.runtime.TimeSource
import app.napstop.core.trip.runtime.TrackingController
import app.napstop.core.trip.runtime.TrackingNotice
import app.napstop.core.trip.runtime.TripNotice
import app.napstop.core.trip.runtime.TripNotifier
import app.napstop.core.trip.runtime.TripRuntime
import app.napstop.core.trip.runtime.WakeMechanism
import app.napstop.core.trip.runtime.KeepAwake
import app.napstop.core.trip.runtime.TraceStore
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

/** Ordered log shared by fakes, so tests can check the order of platform calls across ports. */
class OpLog {
    val ops = ArrayList<String>()

    fun add(op: String) {
        ops += op
    }

    fun indexOf(prefix: String): Int = ops.indexOfFirst { it.startsWith(prefix) }

    fun count(prefix: String): Int = ops.count { it.startsWith(prefix) }
}

/** Wall and elapsed move with [virtual] (the test scheduler's time); [wallOffset] models a changed system clock. */
class FakeTime(
    var wallBase: Long = 1_700_000_000_000L,
    var elapsedBase: Long = 50_000L,
    var bootCountValue: Int? = 7,
    private val virtual: () -> Long = { 0L },
) : TimeSource {
    var wallOffset = 0L

    override fun wallMs(): Long = wallBase + virtual() + wallOffset

    override fun elapsedMs(): Long = elapsedBase + virtual()

    override fun elapsedNanos(): Long = elapsedMs() * 1_000_000L

    override fun bootCount(): Int? = bootCountValue
}

class FakeLocationSource(private val log: OpLog? = null) : LocationSource {
    var spec: FlpRequestSpec? = null
        private set
    var sink: FixSink? = null
        private set
    val requests = ArrayList<FlpRequestSpec>()
    var lastKnownFix: RawFix? = null
    var throwOnRequest: Exception? = null

    /** Fixes handed out / reported processed by the runtime (review T15 #4: wake lock released per Step). */
    var emitted = 0
    var processed = 0

    override fun request(spec: FlpRequestSpec, sink: FixSink) {
        throwOnRequest?.let { throw it }
        this.spec = spec
        this.sink = sink
        requests += spec
        log?.add("location.request(${spec.intervalMs})")
    }

    override fun stop() {
        spec = null
        sink = null
        log?.add("location.stop")
    }

    override suspend fun lastKnown(): RawFix? = lastKnownFix

    fun emit(raw: RawFix) {
        val s = sink ?: return
        emitted++
        s.onFix(raw) { processed++ }
    }
}

/**
 * TrackingController fake. [autoResult] non-null: start() answers through runtime.onForegroundResult synchronously
 * (as LocationService.onStartCommand would, a moment later).
 */
class FakeTracking(private val log: OpLog? = null) : TrackingController {
    var runtime: TripRuntime? = null
    var autoResult: ForegroundResult? = ForegroundResult.Started
    var throwOnStart: Exception? = null
    val starts = ArrayList<Pair<String, StartReason>>()
    val notices = ArrayList<TrackingNotice>()

    /** T18 SM15b: wall time of each notice update (set by World). */
    var wallNow: (() -> Long)? = null
    val noticeWallMs = ArrayList<Long>()
    var stops = 0
    override var isForeground: Boolean = false

    override fun start(tripId: String, reason: StartReason) {
        starts += tripId to reason
        log?.add("tracking.start($reason)")
        throwOnStart?.let { throw it }
        val r = autoResult ?: return
        if (r == ForegroundResult.Started) isForeground = true
        runtime?.onForegroundResult(tripId, r)
    }

    override fun updateTrackingNotification(content: TrackingNotice) {
        notices += content
        wallNow?.let { noticeWallMs += it() }
    }

    override fun stop() {
        stops++
        isForeground = false
        log?.add("tracking.stop")
    }
}

/**
 * AlarmManager model. Alarms survive "process death" (the same instance is handed to the next runtime).
 * Doze ([doze] = true): allow-while-idle alarms (EXACT_IDLE, INEXACT_IDLE) at most once per [dozeQuotaMs] per app
 * [A-DOZE]; setAlarmClock (fallback with exact, ALARM_CLOCK wakes) on time.
 */
class FakeScheduler(private val log: OpLog? = null, private val time: TimeSource? = null) : OsAlarmScheduler {
    /** [wakeAtMs] = the PendingIntent extra (F5); -1 when set without it. */
    data class Wake(val triggerElapsedMs: Long, val mechanism: WakeMechanism, val triggerWallMs: Long, val wakeAtMs: Long = -1L)

    data class Fallback(
        val slot: Int,
        val tripId: String,
        val generation: Long,
        val targetAtMs: Long,
        val triggerWallMs: Long,
        val exact: Boolean,
        val kind: SlotKind = SlotKind.ENGINE,
    )

    /** Restore retry alarm (designer "sau test" B3). */
    data class RestoreRetry(val triggerElapsedMs: Long, val attempt: Int, val cause: RestoreCause, val sinceWallMs: Long)

    var canExact = true
    var wake: Wake? = null
    var restoreRetry: RestoreRetry? = null
    val restoreRetries = ArrayList<RestoreRetry>()
    val slots = HashMap<Int, Fallback>()
    var throwOnSetFallback: ((Int) -> Exception?)? = null

    /** Called right after a successful setFallback (L24: an old slot fires in between). */
    var afterSetFallback: ((Fallback) -> Unit)? = null
    var doze = false
    var dozeQuotaMs = 540_000L
    var lastAllowWhileIdleElapsed: Long? = null
    val setFallbackCount get() = log?.count("setFallback") ?: 0

    override fun canScheduleExact(): Boolean = canExact

    override fun setWake(triggerElapsedMs: Long, mechanism: WakeMechanism, triggerWallMs: Long, wakeAtMs: Long) {
        wake = Wake(triggerElapsedMs, mechanism, triggerWallMs, wakeAtMs)
        log?.add("setWake($mechanism)")
    }

    override fun cancelWake() {
        wake = null
        log?.add("cancelWake")
    }

    override fun setFallback(slot: Int, tripId: String, generation: Long, targetAtMs: Long, triggerWallMs: Long, exact: Boolean, kind: SlotKind) {
        throwOnSetFallback?.invoke(slot)?.let { throw it }
        val f = Fallback(slot, tripId, generation, targetAtMs, triggerWallMs, exact, kind)
        slots[slot] = f
        log?.add("setFallback($slot,$targetAtMs)")
        afterSetFallback?.invoke(f)
    }

    override fun cancelFallback(slot: Int) {
        slots.remove(slot)
        log?.add("cancelFallback($slot)")
    }

    override fun setRestoreRetry(triggerElapsedMs: Long, attempt: Int, cause: RestoreCause, sinceWallMs: Long, exact: Boolean) {
        val r = RestoreRetry(triggerElapsedMs, attempt, cause, sinceWallMs)
        restoreRetry = r
        restoreRetries += r
    }

    override fun cancelRestoreRetry() {
        restoreRetry = null
    }

    /** Elapsed time at which the wake alarm is delivered under the current Doze model. */
    fun wakeDeliveryElapsed(): Long? {
        val w = wake ?: return null
        if (!doze || w.mechanism == WakeMechanism.ALARM_CLOCK) return w.triggerElapsedMs
        val last = lastAllowWhileIdleElapsed ?: return w.triggerElapsedMs
        return maxOf(w.triggerElapsedMs, last + dozeQuotaMs)
    }

    fun consumeWake(atElapsed: Long) {
        val w = wake ?: return
        if (doze && w.mechanism != WakeMechanism.ALARM_CLOCK) lastAllowWhileIdleElapsed = atElapsed
        wake = null
    }

    fun nextFallback(): Fallback? = slots.values.minByOrNull { it.triggerWallMs }

    fun copy(): FakeScheduler =
        FakeScheduler(null, time).also { c ->
            c.canExact = canExact
            c.wake = wake
            c.restoreRetry = restoreRetry
            c.slots.putAll(slots)
            c.doze = doze
            c.dozeQuotaMs = dozeQuotaMs
            c.lastAllowWhileIdleElapsed = lastAllowWhileIdleElapsed
        }
}

/** AlarmPort fake keeping RingFacts like T16 would (durable across "process death" when the instance is reused). */
class FakeAlarmPort(private val log: OpLog? = null, private val time: TimeSource? = null) : AlarmPort {
    class Facts {
        var ringing = false
        var source: RingSource? = null
        var startedAtWall: Long? = null
        var pendingDismiss: Long? = null
        var silencedAt: Long? = null
        var pendingSnooze: Long? = null
    }

    val facts = HashMap<String, Facts>()
    val ringNowCalls = ArrayList<RingRequest>()
    val ringFallbackCalls = ArrayList<RingRequest>()
    val stops = ArrayList<StopCause>()
    val preAlerts = ArrayList<PreAlertRequest>()
    val overshoots = ArrayList<Int>()
    var throwOnRingNow: Exception? = null

    /** ringFallback throws while > 0 (decremented per call). */
    var ringFallbackFailures = 0
    val cleared = ArrayList<String>()

    /** A second sound started while a ring of the trip was on (must stay 0: "one ring per trip"). */
    var doubleRings = 0

    private fun f(tripId: String) = facts.getOrPut(tripId) { Facts() }

    override fun ringNow(request: RingRequest) {
        log?.add("ringNow(${request.reason})")
        throwOnRingNow?.let { throw it }
        ringNowCalls += request
        val x = f(request.tripId)
        if (x.ringing) doubleRings++
        if (!x.ringing) {
            x.ringing = true
            x.source = RingSource.ENGINE
            x.startedAtWall = request.atWallMs
        }
    }

    override fun ringFallback(request: RingRequest) {
        log?.add("ringFallback")
        if (ringFallbackFailures > 0) {
            ringFallbackFailures--
            throw IllegalStateException("cannot ring")
        }
        ringFallbackCalls += request
        val x = f(request.tripId)
        if (x.ringing) doubleRings++
        if (!x.ringing) {
            x.ringing = true
            x.source = RingSource.FALLBACK
            x.startedAtWall = request.atWallMs
        }
    }

    override fun stopRinging(tripId: String, cause: StopCause) {
        log?.add("stopRinging($cause)")
        stops += cause
        f(tripId).ringing = false
        if (cause == StopCause.SNOOZED) f(tripId).pendingSnooze = null
    }

    override fun preAlert(request: PreAlertRequest) {
        preAlerts += request
    }

    override fun overshoot(tripId: String, pastM: Int) {
        overshoots += pastM
    }

    override fun ringFacts(tripId: String): RingFacts {
        val x = facts[tripId] ?: return RingFacts.NONE
        // ringStartedAtWallMs = last ring start, also after it stopped (G3 uses it to tell "rang" from "never rang").
        return RingFacts(x.ringing, if (x.ringing) x.source else null, x.startedAtWall, x.pendingDismiss, x.silencedAt, x.pendingSnooze)
    }

    override fun clearTrip(tripId: String) {
        facts.remove(tripId)
        cleared += tripId
    }

    /** The ring stops by itself (T16 auto-stop); the caller sends RING_EVENT SILENCED. */
    fun silence(tripId: String, atWall: Long) {
        val x = f(tripId)
        x.ringing = false
        x.silencedAt = atWall
    }

    fun copy(): FakeAlarmPort =
        FakeAlarmPort(null, time).also { c ->
            for ((k, v) in facts) {
                c.facts[k] =
                    Facts().apply {
                        ringing = v.ringing
                        source = v.source
                        startedAtWall = v.startedAtWall
                        pendingDismiss = v.pendingDismiss
                        silencedAt = v.silencedAt
                        pendingSnooze = v.pendingSnooze
                    }
            }
        }
}

class FakeNotifier : TripNotifier {
    val shown = LinkedHashSet<TripNotice>()
    val history = ArrayList<String>()
    val names = ArrayList<String?>()

    /** Per show(): whether it alerted (sound / heads-up) — R2-3. */
    val alerts = ArrayList<Pair<TripNotice, Boolean>>()

    override fun show(tripId: String, notice: TripNotice, destinationName: String?, alert: Boolean) {
        shown += notice
        names += destinationName
        alerts += notice to alert
        history += "show:$notice"
    }

    override fun clear(tripId: String, notice: TripNotice) {
        shown -= notice
        history += "clear:$notice"
    }

    override fun clearAll(tripId: String) {
        shown.clear()
        history += "clearAll"
    }
}

/** In-memory store; every write goes through RuntimeCodec (encode + decode) so the codec is exercised too. */
class FakeStore(private val log: OpLog? = null) : RuntimeStore {
    var active: StoredTrip? = null
    var ledger: FallbackLedger = FallbackLedger.EMPTY
    var ringConfig: RingConfig? = null
    val finished = LinkedHashMap<String, FinishedRecord>()

    /** Non-null → writeActive throws it. */
    var failWriteActive: (() -> Exception?)? = null
    var failWriteFinished: Exception? = null

    /** Blocks writeActive (L18: a slow disk). */
    var writeGate: java.util.concurrent.CountDownLatch? = null

    /** Blocks readActive (L45: a hung disk). */
    var readGate: java.util.concurrent.CountDownLatch? = null

    /** writeLedger / readLedger throw (review T15 #2: the ledger is lost or stale). */
    var failWriteLedger: Exception? = null
    var failReadLedger: Exception? = null
    var writeActiveCalls = 0
    var writeActiveOk = 0

    override fun readActive(): StoredTrip? {
        readGate?.await()
        return active
    }

    /** Called after each successful snapshot write (L51: "the process dies right after PersistNow"). */
    var onWriteActive: ((StoredTrip) -> Unit)? = null

    override fun writeActive(t: StoredTrip) {
        writeActiveCalls++
        log?.add("writeActive")
        writeGate?.await()
        failWriteActive?.invoke()?.let { throw it }
        active = RuntimeCodec.decodeTrip(RuntimeCodec.encodeTrip(t))
        writeActiveOk++
        onWriteActive?.invoke(t)
    }

    override fun deleteActive() {
        active = null
        log?.add("deleteActive")
    }

    override fun readLedger(): FallbackLedger {
        failReadLedger?.let { throw it }
        return ledger
    }

    override fun writeLedger(l: FallbackLedger) {
        failWriteLedger?.let { throw it }
        ledger = RuntimeCodec.decodeLedger(RuntimeCodec.encodeLedger(l))
    }

    override fun writeRingConfig(c: RingConfig) {
        ringConfig = RuntimeCodec.decodeRingConfig(RuntimeCodec.encodeRingConfig(c))
        log?.add("writeRingConfig(${c.snoozeCount})")
    }

    override fun readRingConfig(): RingConfig? = ringConfig

    override fun deleteRingConfig() {
        ringConfig = null
    }

    override fun writeFinished(r: FinishedRecord) {
        log?.add("writeFinished")
        failWriteFinished?.let { throw it }
        finished[r.tripId] = RuntimeCodec.decodeFinished(RuntimeCodec.encodeFinished(r))
    }

    override fun readFinished(): List<FinishedRecord> = finished.values.sortedBy { it.endedAtMs }

    override fun deleteFinished(ids: List<String>) {
        ids.forEach { finished.remove(it) }
    }

    fun copy(): FakeStore =
        FakeStore().also { c ->
            c.active = active
            c.ledger = ledger
            c.ringConfig = ringConfig
            c.finished.putAll(finished)
        }

    companion object {
        fun ioFailure() = IOException("disk full")
    }
}

class FakeVisibility(var visible: Boolean = true) : AppVisibility {
    override fun isVisible(): Boolean = visible
}

class FakeEnv(
    var access: LocationAccess = LocationAccess(fineGranted = true, coarseGranted = true, servicesEnabled = true, playServicesAvailable = true),
    var batteryReading: BatteryReading? = null,
) : DeviceEnv {
    override fun locationAccess(): LocationAccess = access

    override fun battery(): BatteryReading? = batteryReading
}

/** Journal that keeps every line (L43). */
class RecordingJournal : RuntimeJournal {
    data class Line(val tripMs: Long?, val wallMs: Long, val ev: String, val fields: Map<String, Any?>)

    val lines = ArrayList<Line>()
    override val enabled = true

    override fun log(tripMs: Long?, wallMs: Long, ev: String, fields: Map<String, Any?>) {
        lines += Line(tripMs, wallMs, ev, fields)
    }
}

/**
 * T18: trace store over fixtures/traces (system property napstop.fixturesDir). [bytes] replaces a trace (broken GPX
 * tests); [allowed] non-null = only those ids exist (the app bundles six).
 */
class FakeTraceStore(private val dir: File? = System.getProperty("napstop.fixturesDir")?.let(::File), var allowed: Set<String>? = null) : TraceStore {
    val bytes = HashMap<String, ByteArray>()
    val opened = ArrayList<String>()

    override fun open(traceId: String): InputStream? {
        opened += traceId
        bytes[traceId]?.let { return ByteArrayInputStream(it) }
        if (allowed?.contains(traceId) == false) return null
        val f = File(dir ?: return null, "$traceId.gpx")
        return if (f.isFile) f.inputStream() else null
    }
}

/** T18: records hold / release of the simulation wake lock. */
class FakeKeepAwake : KeepAwake {
    val holds = ArrayList<Long>()
    var releases = 0
    var held = false

    override fun hold(capMs: Long) {
        holds += capMs
        held = true
    }

    override fun release() {
        releases++
        held = false
    }
}
