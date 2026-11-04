package app.napstop.core.alarm

import app.napstop.core.trip.runtime.RingEventKind
import java.util.Locale

enum class RingPhase { IDLE, RINGING, ENDED }

/** One ring session of the `:ring` process (spec T16 §4.4). */
data class RingState(
    val phase: RingPhase = RingPhase.IDLE,
    val start: RingStart? = null,
    val plan: RingPlan? = null,
    val route: AudioRoute? = null,
    val overshootPastM: Int? = null,
    val startedAtWallMs: Long? = null,
    val headphonesUnplugged: Boolean = false,
    val endedBy: RingEnd? = null,
    /** Last record this session wrote (base of the next write). */
    val record: RingFactsRecord? = null,
    /** Stops seen per trip in this process: a RING_START with ringSeq ≤ the stop never sounds (§8 "STOP before RING_START"). */
    val stopSeqs: Map<String, Long> = emptyMap(),
    /**
     * OVERSHOOT commands that came while no session rang the trip: the engine's Step sends Ring then Overshoot, and the
     * broadcast can overtake the service start. The next start of the trip shows the overshoot screen with them.
     */
    val pendingOvershoot: Map<String, Int> = emptyMap(),
) {
    val tripId: String? get() = start?.request?.tripId
}

sealed interface RingInput {
    data class Start(
        val s: RingStart,
        val headphonesConnected: Boolean,
        val stored: RingFactsRecord?,
        val nowWallMs: Long,
        val nowElapsedMs: Long = 0L,
        val bootCount: Int? = null,
    ) : RingInput

    data class Update(val s: RingStart) : RingInput

    data class Overshoot(val tripId: String, val pastM: Int) : RingInput

    data class UserDismiss(val atWallMs: Long, val routeBack: Boolean) : RingInput

    data class UserSnooze(val atWallMs: Long) : RingInput

    data class Stop(val tripId: String, val cause: StopCause, val stopSeq: Long) : RingInput

    data class Timeout(val atWallMs: Long) : RingInput

    data object HeadphonesGone : RingInput
}

sealed interface RingFx {
    /** Read-modify-write of the book under the file lock ([RingFactsMerge]); fsync when [sync]. */
    data class WriteFacts(val record: RingFactsRecord, val sync: Boolean) : RingFx

    /** Stop seen while idle: stopSeq = max(stopSeq, [stopSeq]) if the book of the trip exists. */
    data class WriteStopSeq(val tripId: String, val stopSeq: Long) : RingFx

    data object AcquireWakeLock : RingFx

    data object ReleaseWakeLock : RingFx

    /** Focus + player + the part of the ramp still to play ([elapsedMs] since the ring started). */
    data class StartAudio(val route: AudioRoute, val plan: RingPlan, val elapsedMs: Long) : RingFx

    data object StopAudio : RingFx

    data class StartVibration(val spec: VibrationSpec) : RingFx

    data object StopVibration : RingFx

    data object StartFlash : RingFx

    data object StopFlash : RingFx

    data class WatchHeadphones(val on: Boolean) : RingFx

    data class ScheduleTimeout(val inMs: Long) : RingFx

    data object CancelTimeout : RingFx

    data class Heartbeat(val on: Boolean) : RingFx

    /** [banner] = ARB key of the banner (alarmHeadphonesUnplugged) or null. */
    data class PublishUi(val content: RingContent, val method: DismissMethod, val banner: String?) : RingFx

    data class PostNotification(val content: RingContent) : RingFx

    data object LaunchUi : RingFx

    /** RING_EVENT to the main process. */
    data class SendEvent(val kind: RingEventKind, val atWallMs: Long) : RingFx

    /** Keyguard → MainActivity with the launch action overshootRoute. */
    data class OpenRouteBack(val tripId: String) : RingFx

    /** stopForeground(REMOVE) + stopSelf; the session goes back to IDLE. */
    data object StopService : RingFx
}

/** Pure reducer of the ring session (spec T16 §5.5). Effects in the order they must run. */
object RingSessionMachine {
    const val BANNER_HEADPHONES_UNPLUGGED = "alarmHeadphonesUnplugged"

    fun reduce(s: RingState, i: RingInput, c: AlarmConstants, locale: Locale = Locale.getDefault()): Pair<RingState, List<RingFx>> =
        when (i) {
            is RingInput.Start -> onStart(s, i, c, locale)
            is RingInput.Update -> onUpdate(s, i.s, locale)
            is RingInput.Overshoot -> onOvershoot(s, i, locale)
            is RingInput.UserDismiss -> onDismiss(s, i)
            is RingInput.UserSnooze -> onSnooze(s, i)
            is RingInput.Stop -> onStop(s, i)
            is RingInput.Timeout -> if (s.phase == RingPhase.RINGING) end(s, s.record!!.copy(silencedAtWallMs = i.atWallMs), RingEnd.SILENCED, RingEventKind.SILENCED, i.atWallMs) else s to emptyList()
            RingInput.HeadphonesGone -> onHeadphonesGone(s, locale)
        }

    // ------------------------------------------------------------------ start / update

    private fun onStart(s: RingState, i: RingInput.Start, c: AlarmConstants, locale: Locale): Pair<RingState, List<RingFx>> {
        val trip = i.s.request.tripId
        if (s.phase == RingPhase.RINGING) {
            if (s.tripId == trip) return onUpdate(s, i.s, locale)
            // Another trip: the old ring stops (no event), the new one starts.
            val (stopped, fx) = stopOutputs(s, s.record!!.copy(ringing = false, endedBy = RingEnd.STOPPED), RingEnd.STOPPED)
            val sane = RingBoot.sanitize(i.stored, i.bootCount, RingBoot.nanosBound(i.nowElapsedMs))
            val (started, fx2) = startFresh(stopped.copy(phase = RingPhase.IDLE), i.copy(stored = sane), c, locale)
            return started to fx + fx2
        }
        // A book of an older boot has seqs that do not compare with this boot's (review T16 #1).
        val stored = RingBoot.sanitize(i.stored, i.bootCount, RingBoot.nanosBound(i.nowElapsedMs))
        val stopSeq = maxOfNullable(stored?.stopSeq, s.stopSeqs[trip])
        val dismissed = stored?.pendingDismissAtWallMs != null
        if ((stopSeq != null && stopSeq >= i.s.ringSeq) || dismissed) {
            return s.copy(phase = RingPhase.IDLE, start = null) to listOf(RingFx.StopService)
        }
        return startFresh(s, i.copy(stored = stored), c, locale)
    }

    private fun startFresh(s: RingState, i: RingInput.Start, c: AlarmConstants, locale: Locale): Pair<RingState, List<RingFx>> {
        val start = i.s
        val req = start.request
        val plan = RingPlanner.plan(req.settings, c)
        val route = OutputRouter.initial(plan, i.headphonesConnected)
        val started = start.resumeStartedAtWallMs ?: i.nowWallMs
        val elapsed = (i.nowWallMs - started).coerceAtLeast(0L)
        val left = c.ringMaxMs - elapsed
        val stored = i.stored?.takeIf { it.tripId == req.tripId }
        val record =
            RingFactsRecord(
                tripId = req.tripId,
                ringSeq = maxOf(start.ringSeq, stored?.ringSeq ?: Long.MIN_VALUE),
                ringing = true,
                mode = RingMode.SERVICE,
                source = req.source,
                reason = req.reason,
                startedAtWallMs = started,
                heartbeatElapsedMs = i.nowElapsedMs,
                heartbeatWallMs = i.nowWallMs,
                bootCount = i.bootCount,
                pendingDismissAtWallMs = null,
                snoozedAtWallMs = stored?.snoozedAtWallMs,
                silencedAtWallMs = null,
                endedBy = null,
                stopSeq = maxOfNullable(stored?.stopSeq, s.stopSeqs[req.tripId]),
                restarts = stored?.restarts ?: 0,
            )
        val overshoot = s.pendingOvershoot[req.tripId]
        val state =
            s.copy(
                phase = RingPhase.RINGING, start = start, plan = plan, route = route, overshootPastM = overshoot, startedAtWallMs = started,
                headphonesUnplugged = false, endedBy = null, record = record,
            )
        if (left <= 0L) {
            // Resumed after RING_MAX: it already stopped by itself.
            val at = started + c.ringMaxMs
            return state.copy(phase = RingPhase.ENDED, endedBy = RingEnd.SILENCED) to
                listOf(
                    RingFx.WriteFacts(record.copy(ringing = false, silencedAtWallMs = at, endedBy = RingEnd.SILENCED), sync = true),
                    RingFx.SendEvent(RingEventKind.SILENCED, at),
                    RingFx.StopService,
                )
        }
        val content = RingCopy.content(req, overshoot, start.snoozeS, locale)
        val fx = ArrayList<RingFx>()
        fx += RingFx.WriteFacts(record, sync = true)
        fx += RingFx.AcquireWakeLock
        if (plan.playSound && route != AudioRoute.VIBRATE_ONLY) fx += RingFx.StartAudio(route, plan, elapsed)
        val vib = plan.vibration ?: if (route == AudioRoute.VIBRATE_ONLY) VibrationPatterns.STRONG else null
        if (vib != null) fx += RingFx.StartVibration(vib)
        if (plan.flash) fx += RingFx.StartFlash
        fx += RingFx.WatchHeadphones(plan.headphonesOnly)
        fx += RingFx.ScheduleTimeout(left)
        fx += RingFx.Heartbeat(true)
        fx += RingFx.PublishUi(content, plan.dismissMethod, null)
        fx += RingFx.PostNotification(content)
        if (start.launchUi) fx += RingFx.LaunchUi
        return state to fx
    }

    /** Same trip while ringing: content only (T15 §4.2 "only updates its content"), start time and source kept. */
    private fun onUpdate(s: RingState, n: RingStart, locale: Locale): Pair<RingState, List<RingFx>> {
        if (s.phase != RingPhase.RINGING || s.tripId != n.request.tripId) return s to emptyList()
        val old = s.start!!
        val merged = n.copy(request = n.request.copy(source = old.request.source), resumeStartedAtWallMs = s.startedAtWallMs)
        val record = s.record!!.copy(ringSeq = maxOf(s.record.ringSeq, n.ringSeq))
        val state = s.copy(start = merged, record = record)
        val content = content(state, locale)
        return state to
            listOf(
                RingFx.WriteFacts(record, sync = false),
                RingFx.PublishUi(content, s.plan!!.dismissMethod, banner(state)),
                RingFx.PostNotification(content),
            )
    }

    private fun onOvershoot(s: RingState, i: RingInput.Overshoot, locale: Locale): Pair<RingState, List<RingFx>> {
        if (s.phase != RingPhase.RINGING || s.tripId != i.tripId) return s.copy(pendingOvershoot = s.pendingOvershoot + (i.tripId to i.pastM)) to emptyList()
        val state = s.copy(overshootPastM = i.pastM)
        val content = content(state, locale)
        return state to listOf(RingFx.PublishUi(content, s.plan!!.dismissMethod, banner(state)), RingFx.PostNotification(content))
    }

    // ------------------------------------------------------------------ user / timeout / stop

    private fun onDismiss(s: RingState, i: RingInput.UserDismiss): Pair<RingState, List<RingFx>> {
        if (s.phase != RingPhase.RINGING) return s to emptyList()
        val rec = s.record!!.copy(ringing = false, pendingDismissAtWallMs = i.atWallMs, endedBy = RingEnd.DISMISSED)
        val (state, fx) = stopOutputs(s, rec, RingEnd.DISMISSED)
        val out = ArrayList(fx)
        out += RingFx.SendEvent(RingEventKind.DISMISSED, i.atWallMs)
        if (i.routeBack) out += RingFx.OpenRouteBack(s.tripId!!)
        out += RingFx.ReleaseWakeLock
        out += RingFx.StopService
        return state to out
    }

    private fun onSnooze(s: RingState, i: RingInput.UserSnooze): Pair<RingState, List<RingFx>> {
        if (s.phase != RingPhase.RINGING || !RingCopy.snoozeShown(s.start!!.request, s.overshootPastM)) return s to emptyList()
        return end(s, s.record!!.copy(snoozedAtWallMs = i.atWallMs), RingEnd.SNOOZED, RingEventKind.SNOOZED, i.atWallMs)
    }

    private fun onStop(s0: RingState, i: RingInput.Stop): Pair<RingState, List<RingFx>> {
        // A stop from the runtime ends what an early overshoot command announced (the trip ended / snoozed).
        val s = if (i.cause == StopCause.TRIP_ENDED) s0.copy(pendingOvershoot = s0.pendingOvershoot - i.tripId) else s0
        val seqs = s.stopSeqs + (i.tripId to maxOf(i.stopSeq, s.stopSeqs[i.tripId] ?: Long.MIN_VALUE))
        if (s.phase == RingPhase.RINGING && s.tripId == i.tripId) {
            val rec = s.record!!.copy(ringing = false, endedBy = RingEnd.STOPPED, stopSeq = maxOfNullable(s.record.stopSeq, i.stopSeq))
            val (state, fx) = stopOutputs(s.copy(stopSeqs = seqs), rec, RingEnd.STOPPED)
            return state to fx + RingFx.ReleaseWakeLock + RingFx.StopService
        }
        val fx = ArrayList<RingFx>()
        fx += RingFx.WriteStopSeq(i.tripId, i.stopSeq)
        if (s.phase == RingPhase.IDLE) fx += RingFx.StopService
        return s.copy(stopSeqs = seqs) to fx
    }

    private fun end(s: RingState, base: RingFactsRecord, by: RingEnd, kind: RingEventKind, at: Long): Pair<RingState, List<RingFx>> {
        val (state, fx) = stopOutputs(s, base.copy(ringing = false, endedBy = by), by)
        return state to fx + RingFx.SendEvent(kind, at) + RingFx.ReleaseWakeLock + RingFx.StopService
    }

    /** ENDED + the book write first (sync), then every output stopped. */
    private fun stopOutputs(s: RingState, rec: RingFactsRecord, by: RingEnd): Pair<RingState, List<RingFx>> =
        s.copy(phase = RingPhase.ENDED, endedBy = by, record = rec) to
            listOf(
                RingFx.WriteFacts(rec, sync = true),
                RingFx.StopAudio,
                RingFx.StopVibration,
                RingFx.StopFlash,
                RingFx.WatchHeadphones(false),
                RingFx.CancelTimeout,
                RingFx.Heartbeat(false),
            )

    private fun onHeadphonesGone(s: RingState, locale: Locale): Pair<RingState, List<RingFx>> {
        if (s.phase != RingPhase.RINGING || s.route != AudioRoute.HEADPHONES) return s to emptyList()
        val plan = s.plan!!
        val state = s.copy(route = OutputRouter.onHeadphonesGone(AudioRoute.HEADPHONES, plan), headphonesUnplugged = true)
        return state to
            listOf(
                RingFx.StopAudio,
                RingFx.StartVibration(plan.vibration ?: VibrationPatterns.STRONG),
                RingFx.PublishUi(content(state, locale), plan.dismissMethod, BANNER_HEADPHONES_UNPLUGGED),
            )
    }

    private fun content(s: RingState, locale: Locale): RingContent = RingCopy.content(s.start!!.request, s.overshootPastM, s.start.snoozeS, locale)

    private fun banner(s: RingState): String? = if (s.headphonesUnplugged) BANNER_HEADPHONES_UNPLUGGED else null

    private fun maxOfNullable(a: Long?, b: Long?): Long? = if (a == null) b else if (b == null) a else maxOf(a, b)
}

/** How a write of `:ring` lands on the book another process may have changed (pure). */
object RingFactsMerge {
    /**
     * [written] wins, except: stopSeq, restarts and the heartbeat never go down; a ring the main process already stopped
     * (stopSeq ≥ ringSeq) is not brought back. A disk record of another boot ([RingBoot]) counts only by its user facts.
     * Returns the record to store and whether the session must stop now.
     */
    fun merge(disk: RingFactsRecord?, written: RingFactsRecord, nowNanos: Long = Long.MAX_VALUE): Pair<RingFactsRecord, Boolean> {
        // A book of another boot never stops (or feeds seqs into) a ring of this boot (review T16 #1).
        val d = RingBoot.sanitize(disk, written.bootCount, nowNanos)
        if (d == null || d.tripId != written.tripId) return written to false
        val stopSeq = listOfNotNull(d.stopSeq, written.stopSeq).maxOrNull()
        val m =
            written.copy(
                stopSeq = stopSeq,
                restarts = maxOf(d.restarts, written.restarts),
                // The heartbeat runs apart from the session's writes: never move it back.
                heartbeatElapsedMs = listOfNotNull(d.heartbeatElapsedMs, written.heartbeatElapsedMs).maxOrNull(),
                heartbeatWallMs = listOfNotNull(d.heartbeatWallMs, written.heartbeatWallMs).maxOrNull(),
            )
        if (m.ringing && stopSeq != null && stopSeq >= m.ringSeq) return m.copy(ringing = false, endedBy = RingEnd.STOPPED) to true
        return m to false
    }
}
