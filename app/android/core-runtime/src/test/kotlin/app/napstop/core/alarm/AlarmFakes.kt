package app.napstop.core.alarm

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.runtime.RingConfig

/** Shared fakes of the T16 alarm tests (JVM). */
class FakeRingClock(var wall: Long = 1_700_000_000_000L, var elapsed: Long = 5_000_000L, var boot: Int? = 7) : RingClock {
    private var nanoBump = 0L

    override fun wallMs() = wall

    override fun elapsedMs() = elapsed

    /** Strictly increasing, even when the clock did not move. */
    override fun elapsedNanos(): Long = elapsed * 1_000_000L + (++nanoBump)

    override fun bootCount() = boot

    fun advance(ms: Long) {
        wall += ms
        elapsed += ms
    }
}

class MemoryFacts : RingFactsSource {
    val records = HashMap<String, RingFactsRecord>()
    var reads = 0

    override fun read(tripId: String): RingFactsRecord? {
        reads++
        return records[tripId]
    }

    override fun update(tripId: String, f: (RingFactsRecord?) -> RingFactsRecord?): RingFactsRecord? {
        val n = f(records[tripId])
        if (n == null) records.remove(tripId) else records[tripId] = n
        return n
    }

    override fun delete(tripId: String) {
        records.remove(tripId)
    }

    override fun listRinging(): List<RingFactsRecord> = records.values.filter { it.ringing }
}

class FakeTransport : RingTransport {
    val started = ArrayList<RingStart>()
    val commands = ArrayList<RingCommand>()
    val backups = ArrayList<Pair<RingStart, RingContent>>()
    val cancelledBackups = ArrayList<String>()
    val preAlerts = ArrayList<PreAlertRequest>()
    val cancelledPreAlerts = ArrayList<String>()
    var startError: Exception? = null
    var backupOk = true
    var backupShowing = HashMap<String, Boolean>()
    var visible = true

    /** Called after a successful startRingService (the fake `:ring`). */
    var onStart: ((RingStart) -> Unit)? = null

    /** SimRing hooks (T16 trace tests): FGS start rule, command delivery, backup notification model. */
    var startHook: (() -> Unit)? = null
    var commandHook: ((RingCommand) -> Unit)? = null
    var backupHook: ((RingStart) -> Boolean)? = null
    var showingHook: ((String) -> Boolean)? = null

    override fun startRingService(s: RingStart) {
        startError?.let { throw it }
        startHook?.invoke()
        started += s
        onStart?.invoke(s)
    }

    override fun sendToRing(c: RingCommand) {
        commands += c
        commandHook?.invoke(c)
    }

    override fun postBackup(s: RingStart, content: RingContent): Boolean {
        if (!backupOk) return false
        backupHook?.let { if (!it(s)) return false }
        backups += s to content
        backupShowing[s.request.tripId] = true
        return true
    }

    override fun cancelBackup(tripId: String) {
        cancelledBackups += tripId
        backupShowing[tripId] = false
    }

    override fun backupShowing(tripId: String): Boolean = showingHook?.invoke(tripId) ?: (backupShowing[tripId] == true)

    override fun postPreAlert(r: PreAlertRequest) {
        preAlerts += r
    }

    override fun cancelPreAlert(tripId: String) {
        cancelledPreAlerts += tripId
    }

    override fun appVisible(): Boolean = visible
}

object AlarmData {
    const val TRIP = "t1"
    const val DEST = "Ga Đồng Hới"

    val SETTINGS = RingSettings("default", 0.8, true, "medium", true, false, "swipe")

    fun request(
        tripId: String = TRIP,
        source: RingSource = RingSource.ENGINE,
        reason: AlarmReason? = AlarmReason.DISTANCE,
        snoozeAllowed: Boolean = true,
        distanceM: Int? = 1200,
        etaS: Int? = 130,
        batteryPct: Int? = 12,
        destinationName: String? = DEST,
        settings: RingSettings? = SETTINGS,
        atWallMs: Long = 1_700_000_000_000L,
    ) = RingRequest(tripId, source, reason, snoozeAllowed, distanceM, etaS, batteryPct, destinationName, settings, atWallMs)

    fun start(
        req: RingRequest = request(),
        ringSeq: Long = 100L,
        snoozeS: Int = 60,
        launchUi: Boolean = true,
        resume: Long? = null,
    ) = RingStart(req, ringSeq, snoozeS, launchUi, resume)

    fun ringConfig(tripId: String = TRIP, snoozeS: Int = 60) = RingConfig(tripId, DEST, SETTINGS, 0, 1, snoozeS)

    fun record(
        tripId: String = TRIP,
        ringSeq: Long = 100L,
        ringing: Boolean = true,
        mode: RingMode = RingMode.SERVICE,
        source: RingSource = RingSource.ENGINE,
        startedAt: Long = 1_700_000_000_000L,
        heartbeatElapsed: Long? = 5_000_000L,
        heartbeatWall: Long? = 1_700_000_000_000L,
        bootCount: Int? = 7,
        pendingDismiss: Long? = null,
        snoozedAt: Long? = null,
        silencedAt: Long? = null,
        endedBy: RingEnd? = null,
        stopSeq: Long? = null,
        restarts: Int = 0,
    ) = RingFactsRecord(
        tripId = tripId, ringSeq = ringSeq, ringing = ringing, mode = mode, source = source, reason = AlarmReason.DISTANCE,
        startedAtWallMs = startedAt, heartbeatElapsedMs = heartbeatElapsed, heartbeatWallMs = heartbeatWall, bootCount = bootCount,
        pendingDismissAtWallMs = pendingDismiss, snoozedAtWallMs = snoozedAt, silencedAtWallMs = silencedAt, endedBy = endedBy,
        stopSeq = stopSeq, restarts = restarts,
    )
}
