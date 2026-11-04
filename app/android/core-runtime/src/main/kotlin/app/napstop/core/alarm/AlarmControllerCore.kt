package app.napstop.core.alarm

import app.napstop.core.trip.AlarmReason
import app.napstop.core.trip.runtime.RingConfig
import java.util.Locale

/** Ring start payload sent to `:ring` (Intent extras via [RingStartCodec]). No coordinates. */
data class RingStart(
    val request: RingRequest,
    val ringSeq: Long,
    val snoozeS: Int,
    val launchUi: Boolean,
    /** Watchdog restart / adopt: keep the original start. */
    val resumeStartedAtWallMs: Long?,
) {
    override fun toString(): String = "RingStart(tripId=${request.tripId}, seq=$ringSeq, source=${request.source}, launchUi=$launchUi)"
}

sealed interface RingCommand {
    val tripId: String

    data class Update(val start: RingStart) : RingCommand {
        override val tripId: String get() = start.request.tripId
    }

    data class Overshoot(override val tripId: String, val pastM: Int) : RingCommand {
        override fun toString(): String = "Overshoot(tripId=$tripId)"
    }

    data class Stop(override val tripId: String, val cause: StopCause, val stopSeq: Long) : RingCommand

    /** "Báo lại" on the notification. */
    data class Snooze(override val tripId: String, val atWallMs: Long) : RingCommand
}

/** Map form of [RingStart] for Intent extras (spec T16 §4.5). Anything missing / unknown → null. */
object RingStartCodec {
    private val TRIP_ID = Regex("^[A-Za-z0-9_-]{1,64}$")

    fun toMap(s: RingStart): Map<String, Any?> {
        val r = s.request
        val m = LinkedHashMap<String, Any?>()
        m["tripId"] = r.tripId
        m["ringSeq"] = s.ringSeq
        m["source"] = r.source.name
        m["reason"] = r.reason?.name
        m["snoozeAllowed"] = r.snoozeAllowed
        m["distanceM"] = r.distanceM
        m["etaS"] = r.etaS
        m["batteryPct"] = r.batteryPct
        m["destinationName"] = r.destinationName
        r.settings?.let { st ->
            m["s.soundId"] = st.soundId
            m["s.volume"] = st.volume
            m["s.rampUp"] = st.rampUp
            m["s.vibration"] = st.vibration
            m["s.flash"] = st.flash
            m["s.preferHeadphones"] = st.preferHeadphones
            m["s.dismissMethod"] = st.dismissMethod
        }
        m["snoozeS"] = s.snoozeS
        m["atWallMs"] = r.atWallMs
        m["launchUi"] = s.launchUi
        m["resumeStartedAtWallMs"] = s.resumeStartedAtWallMs
        return m
    }

    fun fromMap(m: Map<String, Any?>): RingStart? =
        try {
            val settings =
                if (m["s.soundId"] == null) {
                    null
                } else {
                    RingSettings(
                        soundId = str(m, "s.soundId"),
                        volume = (m["s.volume"] as? Number)?.toDouble() ?: throw Invalid(),
                        rampUp = bool(m, "s.rampUp"),
                        vibration = str(m, "s.vibration"),
                        flash = bool(m, "s.flash"),
                        preferHeadphones = bool(m, "s.preferHeadphones"),
                        dismissMethod = str(m, "s.dismissMethod"),
                    )
                }
            val tripId = str(m, "tripId").also { if (!TRIP_ID.matches(it)) throw Invalid() }
            RingStart(
                request =
                    RingRequest(
                        tripId = tripId,
                        source = RingSource.entries.firstOrNull { it.name == m["source"] } ?: throw Invalid(),
                        reason = (m["reason"] as String?)?.let { r -> AlarmReason.entries.firstOrNull { it.name == r } ?: throw Invalid() },
                        snoozeAllowed = bool(m, "snoozeAllowed"),
                        distanceM = optInt(m, "distanceM"),
                        etaS = optInt(m, "etaS"),
                        batteryPct = optInt(m, "batteryPct"),
                        destinationName = m["destinationName"] as String?,
                        settings = settings,
                        atWallMs = long(m, "atWallMs"),
                    ),
                ringSeq = long(m, "ringSeq"),
                snoozeS = optInt(m, "snoozeS")?.takeIf { it > 0 } ?: throw Invalid(),
                launchUi = bool(m, "launchUi"),
                resumeStartedAtWallMs = (m["resumeStartedAtWallMs"] as Number?)?.toLong(),
            )
        } catch (e: Invalid) {
            null
        } catch (e: ClassCastException) {
            null
        }

    private class Invalid : RuntimeException()

    private fun str(m: Map<String, Any?>, k: String): String = m[k] as? String ?: throw Invalid()

    private fun bool(m: Map<String, Any?>, k: String): Boolean = m[k] as? Boolean ?: throw Invalid()

    private fun long(m: Map<String, Any?>, k: String): Long = (m[k] as? Number)?.toLong() ?: throw Invalid()

    private fun optInt(m: Map<String, Any?>, k: String): Int? = (m[k] as Number?)?.toInt()
}

/** startForegroundService was refused (ForegroundServiceStartNotAllowedException…); [errorClass] = simple class name. */
class RingStartDenied(val errorClass: String) : Exception(errorClass)

/** Neither the ring service nor the backup notification could start (T15 keeps / arms its fallback alarm). */
class RingStartException(val errorClass: String) : IllegalStateException(errorClass)

/** Platform side of [AlarmControllerCore] (binder calls only; never blocks on disk). */
interface RingTransport {
    /** startForegroundService(AlarmRingService). Throws [RingStartDenied] (or IllegalStateException / SecurityException). */
    fun startRingService(s: RingStart)

    /** Explicit broadcast to RingCommandReceiver (`:ring`); never throws. */
    fun sendToRing(c: RingCommand)

    /** false: notifications disabled / failed. */
    fun postBackup(s: RingStart, content: RingContent): Boolean

    fun cancelBackup(tripId: String)

    fun backupShowing(tripId: String): Boolean

    fun postPreAlert(r: PreAlertRequest)

    fun cancelPreAlert(tripId: String)

    fun appVisible(): Boolean
}

/** The ring book (file + FileLock on Android, [CachedRingFacts] in the main process). */
interface RingFactsSource {
    fun read(tripId: String): RingFactsRecord?

    /** Read-modify-write under the lock; a null result deletes. Returns what was stored. */
    fun update(tripId: String, f: (RingFactsRecord?) -> RingFactsRecord?): RingFactsRecord?

    fun delete(tripId: String)

    fun listRinging(): List<RingFactsRecord>
}

interface RingClock {
    fun wallMs(): Long

    fun elapsedMs(): Long

    fun elapsedNanos(): Long

    fun bootCount(): Int?
}

/**
 * The real [AlarmPort] (spec T16 §4.3, §5.1, §5.3), platform-free. One ring per trip: the sound plays in `:ring`; the
 * book ([RingFactsSource]) is the one truth of "ringing"; a STARTING marker covers the ≤ RING_CONFIRM_MS before `:ring`
 * confirms (T15 contract: `ringingNow` from the moment ringNow / ringFallback returned). Thread-safe (one lock); every
 * call is short (binder calls, bounded reads of [facts]).
 */
class AlarmControllerCore(
    private val transport: RingTransport,
    private val facts: RingFactsSource,
    private val clock: RingClock,
    /** T15 ring_config.properties of the trip (null: unreadable / other trip). */
    private val ringConfig: (tripId: String) -> RingConfig?,
    /** The ring is gone for good (watchdog Silence / backup swiped) → runtime.onRingEvent(SILENCED). */
    private val onRingLost: (tripId: String, atWallMs: Long) -> Unit,
    /** Adapter schedules watchTick every WATCHDOG_MS (idempotent per trip). */
    private val onWatch: (tripId: String) -> Unit,
    private val c: AlarmConstants,
    private val warn: (String) -> Unit,
    private val locale: () -> Locale = { Locale.getDefault() },
) : AlarmPort {
    private val lock = Any()
    private val starting = HashMap<String, StartingMarker>()
    private val lastStart = HashMap<String, RingStart>()
    private val restartsNoBook = HashMap<String, Int>()

    override fun ringNow(request: RingRequest) = ring(request)

    override fun ringFallback(request: RingRequest) = ring(request)

    private fun ring(req: RingRequest) {
        val trip = req.tripId
        quietly("pre-alert cancel") { transport.cancelPreAlert(trip) }
        synchronized(lock) {
            val rec = readQuiet(trip)
            if (rec?.pendingDismissAtWallMs != null) {
                // The user already stopped this trip's alarm; RING_EVENT DISMISSED ends the trip (T15 §5.8).
                warn("ring ignored: dismiss pending")
                return
            }
            val cur = factsLocked(trip, rec)
            val snoozeS = ringConfigQuiet(trip)?.snoozeS?.takeIf { it > 0 } ?: c.snoozeSDefault
            val s = RingStart(req, clock.elapsedNanos(), snoozeS, launchUi = quietBool { transport.appVisible() }, resumeStartedAtWallMs = null)
            if (cur.ringingNow) {
                // At most one ring per trip (T15 §4.2, T10 #6): the ring on only gets its content updated.
                if (rec?.ringing == true && rec.mode == RingMode.BACKUP && starting[trip] == null) {
                    quietly("backup update") { transport.postBackup(s.copy(resumeStartedAtWallMs = rec.startedAtWallMs), content(s)) }
                } else {
                    transport.sendToRing(RingCommand.Update(s))
                }
                lastStart[trip] = s
                return
            }
            lastStart[trip] = s
            starting[trip] = StartingMarker(trip, s.ringSeq, req.source, clock.elapsedMs(), clock.wallMs())
            try {
                transport.startRingService(s)
                onWatch(trip)
                return
            } catch (e: Exception) {
                val name = e.javaClass.simpleName.ifEmpty { "Exception" }.let { if (e is RingStartDenied) e.errorClass else it }
                warn("ring service start failed ($name)")
                starting.remove(trip)
                if (startBackupLocked(s)) {
                    onWatch(trip)
                    return
                }
                throw RingStartException(name)
            }
        }
    }

    override fun stopRinging(tripId: String, cause: StopCause) {
        try {
            synchronized(lock) {
                val rec = readQuiet(tripId)
                val st = starting.remove(tripId)
                val seq = listOfNotNull(st?.ringSeq, rec?.ringSeq).maxOrNull() ?: clock.elapsedNanos()
                // Never wakes :ring when nothing rings there.
                if (rec?.ringing == true || st != null) transport.sendToRing(RingCommand.Stop(tripId, cause, seq))
                quietly("backup cancel") { transport.cancelBackup(tripId) }
                restartsNoBook.remove(tripId)
                updateBook(tripId) { r ->
                    val base = r ?: RingFactsRecord.stub(tripId, seq, clock.wallMs(), clock.bootCount())
                    base.copy(
                        bootCount = base.bootCount ?: clock.bootCount(),
                        ringing = false,
                        endedBy = if (r?.ringing == true || r == null) RingEnd.STOPPED else r.endedBy ?: RingEnd.STOPPED,
                        stopSeq = maxOf(seq, r?.stopSeq ?: Long.MIN_VALUE),
                        // The runtime handled the snooze: the pending snooze of G1 is cleared.
                        snoozedAtWallMs = if (cause == StopCause.SNOOZED) null else base.snoozedAtWallMs,
                    )
                }
            }
        } catch (e: Exception) {
            warn("stop ringing failed (${e.javaClass.simpleName})")
        }
    }

    override fun preAlert(request: PreAlertRequest) = quietly("pre-alert") { transport.postPreAlert(request) }

    override fun overshoot(tripId: String, pastM: Int) =
        quietly("overshoot") {
            synchronized(lock) {
                val rec = readQuiet(tripId)
                if (!factsLocked(tripId, rec).ringingNow) return@quietly // not ringing: dropped (T15 §5.2)
                if (rec?.ringing == true && rec.mode == RingMode.BACKUP && starting[tripId] == null) {
                    val s = lastStart[tripId] ?: rebuild(rec)
                    transport.postBackup(s.copy(resumeStartedAtWallMs = rec.startedAtWallMs), RingCopy.content(s.request, pastM, s.snoozeS, locale()))
                } else {
                    transport.sendToRing(RingCommand.Overshoot(tripId, pastM))
                }
            }
        }

    override fun ringFacts(tripId: String): RingFacts =
        try {
            synchronized(lock) { factsLocked(tripId, readQuiet(tripId)) }
        } catch (e: Exception) {
            warn("ring facts failed (${e.javaClass.simpleName})")
            RingFacts.NONE
        }

    override fun clearTrip(tripId: String) =
        quietly("clear trip") {
            synchronized(lock) {
                starting.remove(tripId)
                lastStart.remove(tripId)
                restartsNoBook.remove(tripId)
                quietly("backup cancel") { transport.cancelBackup(tripId) }
                quietly("pre-alert cancel") { transport.cancelPreAlert(tripId) }
                facts.delete(tripId)
            }
        }

    /** Called by the adapter every WATCHDOG_MS while watching; false = stop watching (spec §5.3). */
    fun watchTick(tripId: String): Boolean =
        try {
            var lost: Long? = null
            val keep =
                synchronized(lock) {
                    val r = readQuiet(tripId)
                    val st = starting[tripId]
                    val action = RingWatchdogPolicy.decide(r, st, env(tripId, r), c)
                    when (action) {
                        WatchAction.None -> true
                        WatchAction.StopWatching -> {
                            if (st != null && r != null && (st.ringSeq <= r.ringSeq || (r.stopSeq ?: Long.MIN_VALUE) >= st.ringSeq)) starting.remove(tripId)
                            false
                        }
                        is WatchAction.Restart -> {
                            val n = if (r == null) (restartsNoBook[tripId] ?: 0) + 1 else action.restartNo
                            if (n > c.ringRestartMax) {
                                backupOrSilence(tripId, r, st).also { lost = it }
                                lost == null
                            } else {
                                restart(tripId, r, st, n).also { if (!it) lost = backupOrSilence(tripId, r, st) }
                                lost == null
                            }
                        }
                        WatchAction.Backup -> {
                            lost = backupOrSilence(tripId, r, st)
                            lost == null
                        }
                        is WatchAction.Silence -> {
                            lost = silenceLocked(tripId, action.atWallMs)
                            false
                        }
                    }
                }
            lost?.let { at -> quietly("ring lost") { onRingLost(tripId, at) } }
            keep
        } catch (e: Exception) {
            warn("ring watchdog failed (${e.javaClass.simpleName})")
            true
        }

    /** MainActivity visible: trips whose ring is live (the adapter opens AlarmActivity). */
    fun liveRings(): List<String> =
        try {
            facts.listRinging().filter { RingLiveness.alive(it, env(it.tripId, it), c) }.map { it.tripId }
        } catch (e: Exception) {
            warn("live rings failed (${e.javaClass.simpleName})")
            emptyList()
        }

    /** The backup notification was swiped away (BACKUP_RING_DELETED): the ring ended by itself. */
    fun onBackupDeleted(tripId: String) {
        val at =
            synchronized(lock) {
                val r = readQuiet(tripId)
                if (r == null || !r.ringing || r.mode != RingMode.BACKUP) return
                silenceLocked(tripId, clock.wallMs(), RingEnd.SILENCED)
            }
        quietly("ring lost") { onRingLost(tripId, at) }
    }

    // ------------------------------------------------------------------ internals (under lock)

    private fun factsLocked(tripId: String, rec: RingFactsRecord?): RingFacts {
        // `:ring` confirmed the ring (or a stop overtook it): the book alone tells from now on.
        val st = starting[tripId]
        if (st != null && rec != null && (rec.ringSeq >= st.ringSeq || (rec.stopSeq ?: Long.MIN_VALUE) >= st.ringSeq)) starting.remove(tripId)
        val f = RingLiveness.facts(rec, starting[tripId], env(tripId, rec), c)
        if (f.ringingNow) quietly("watch") { onWatch(tripId) }
        return f
    }

    private fun env(tripId: String, r: RingFactsRecord?): LivenessEnv =
        LivenessEnv(
            nowWallMs = clock.wallMs(),
            nowElapsedMs = clock.elapsedMs(),
            bootCount = clock.bootCount(),
            backupShowing = r != null && r.ringing && r.mode == RingMode.BACKUP && quietBool { transport.backupShowing(tripId) },
        )

    private fun restart(tripId: String, r: RingFactsRecord?, st: StartingMarker?, n: Int): Boolean {
        val base = lastStart[tripId] ?: r?.let(::rebuild) ?: return false
        val seq = clock.elapsedNanos()
        val resume = r?.startedAtWallMs ?: st?.atWallMs ?: base.resumeStartedAtWallMs
        val s = base.copy(ringSeq = seq, launchUi = false, resumeStartedAtWallMs = resume)
        if (r != null) updateBook(tripId) { it?.copy(restarts = maxOf(it.restarts, n)) } else restartsNoBook[tripId] = n
        starting[tripId] = StartingMarker(tripId, seq, (r?.source ?: st?.source ?: base.request.source), clock.elapsedMs(), resume ?: clock.wallMs())
        warn("ring restart $n")
        return try {
            transport.startRingService(s)
            true
        } catch (e: Exception) {
            warn("ring restart failed (${e.javaClass.simpleName})")
            starting.remove(tripId)
            false
        }
    }

    /** Backup notification; null when it is up, else the time of the silence. */
    private fun backupOrSilence(tripId: String, r: RingFactsRecord?, st: StartingMarker?): Long? {
        val base = lastStart[tripId] ?: r?.let(::rebuild)
        starting.remove(tripId)
        val resume = r?.startedAtWallMs ?: st?.atWallMs
        if (base != null && startBackupLocked(base.copy(ringSeq = clock.elapsedNanos(), resumeStartedAtWallMs = resume))) return null
        return silenceLocked(tripId, clock.wallMs())
    }

    private fun silenceLocked(tripId: String, at: Long, by: RingEnd = RingEnd.LOST): Long {
        starting.remove(tripId)
        restartsNoBook.remove(tripId)
        quietly("backup cancel") { transport.cancelBackup(tripId) }
        quietly("ring book") { updateBook(tripId) { it?.copy(ringing = false, silencedAtWallMs = at, endedBy = by) } }
        return at
    }

    private fun startBackupLocked(s: RingStart): Boolean {
        val ok = quietBool { transport.postBackup(s, content(s)) }
        if (!ok) return false
        val trip = s.request.tripId
        quietly("ring book") {
            updateBook(trip) { old ->
                RingFactsRecord(
                    tripId = trip,
                    ringSeq = s.ringSeq,
                    ringing = true,
                    mode = RingMode.BACKUP,
                    source = old?.takeIf { it.ringing }?.source ?: s.request.source,
                    reason = s.request.reason ?: old?.reason,
                    startedAtWallMs = s.resumeStartedAtWallMs ?: clock.wallMs(),
                    heartbeatElapsedMs = null,
                    heartbeatWallMs = null,
                    bootCount = clock.bootCount(),
                    pendingDismissAtWallMs = null,
                    snoozedAtWallMs = old?.snoozedAtWallMs,
                    silencedAtWallMs = null,
                    endedBy = null,
                    stopSeq = old?.stopSeq,
                    restarts = old?.restarts ?: 0,
                )
            }
        }
        warn("ring backup notification")
        return true
    }

    /** A start rebuilt from the book + ring_config when this process has no request in memory (§5.3). */
    private fun rebuild(r: RingFactsRecord): RingStart {
        val rc = ringConfigQuiet(r.tripId)
        return RingStart(
            request =
                RingRequest(
                    tripId = r.tripId,
                    source = r.source,
                    reason = r.reason,
                    snoozeAllowed = rc?.let { it.snoozeCount < it.maxSnoozes } ?: false,
                    distanceM = null,
                    etaS = null,
                    batteryPct = null,
                    destinationName = rc?.destinationName,
                    settings = rc?.settings,
                    atWallMs = clock.wallMs(),
                ),
            ringSeq = clock.elapsedNanos(),
            snoozeS = rc?.snoozeS?.takeIf { it > 0 } ?: c.snoozeSDefault,
            launchUi = false,
            resumeStartedAtWallMs = r.startedAtWallMs,
        )
    }

    private fun content(s: RingStart): RingContent = RingCopy.content(s.request, null, s.snoozeS, locale())

    /** Read-modify-write of the book; the record handed to [f] is already of this boot ([RingBoot]). */
    private fun updateBook(tripId: String, f: (RingFactsRecord?) -> RingFactsRecord?): RingFactsRecord? =
        facts.update(tripId) { raw -> f(RingBoot.sanitize(raw, clock.bootCount(), nowNanos())) }

    private fun nowNanos(): Long = RingBoot.nanosBound(clock.elapsedMs())

    /** The book as seen from this boot (review T16 #1: seqs of an older boot are dropped). */
    private fun readQuiet(tripId: String): RingFactsRecord? =
        try {
            RingBoot.sanitize(facts.read(tripId), clock.bootCount(), nowNanos())
        } catch (e: Exception) {
            warn("ring book read failed (${e.javaClass.simpleName})")
            null
        }

    private fun ringConfigQuiet(tripId: String): RingConfig? =
        try {
            ringConfig(tripId)?.takeIf { it.tripId == tripId }
        } catch (e: Exception) {
            warn("ring config read failed (${e.javaClass.simpleName})")
            null
        }

    private inline fun quietly(what: String, block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            warn("$what failed (${e.javaClass.simpleName})")
        }
    }

    private inline fun quietBool(block: () -> Boolean): Boolean =
        try {
            block()
        } catch (e: Exception) {
            false
        }
}
