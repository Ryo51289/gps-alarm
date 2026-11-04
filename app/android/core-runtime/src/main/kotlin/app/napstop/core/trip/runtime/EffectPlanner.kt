package app.napstop.core.trip.runtime

import app.napstop.core.alarm.PreAlertRequest
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.RingSource
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.Alarm
import app.napstop.core.trip.AlarmMode
import app.napstop.core.trip.FallbackAlarmChanged
import app.napstop.core.trip.FallbackCause
import app.napstop.core.trip.FallbackFired
import app.napstop.core.trip.FallbackStatus
import app.napstop.core.trip.GpsLost
import app.napstop.core.trip.GpsLostCause
import app.napstop.core.trip.GpsRecovered
import app.napstop.core.trip.Overshoot
import app.napstop.core.trip.PreAlert
import app.napstop.core.trip.SamplingPolicyChanged
import app.napstop.core.trip.Snoozed
import app.napstop.core.trip.TripEnded

/**
 * Step → effects (spec T15 §5.2). Pure, fixed order following the T10 §2.3 event order: the pre-ring write and the ring
 * first, then one effect per event, then wake, notification, snapshot, publish, and the end of the trip.
 */
object EffectPlanner {
    fun plan(p: PlanInput): List<Effect> {
        val step = p.step
        val view = step.view
        val fx = ArrayList<Effect>()
        val alarm = step.events.firstOrNull { it is Alarm } as Alarm? // at most one per Step (I11)
        if (alarm != null && alarm.ringNow) {
            // G1: the guard is armed before PersistNow, so a process death right after the write is still caught.
            fx += Effect.ArmRingGuard(p.nowWallMs + p.params.fallbackLagS * 1000L)
            fx += Effect.PersistNow(p.preRingPersistBudgetMs)
            val f = p.facts
            if (f.ringingNow && f.ringingSource == RingSource.FALLBACK) {
                // Obligation 3: the only blocked case — a fallback alarm of this trip is ringing right now.
                val started = f.ringStartedAtWallMs?.let { toTrip(it, p) } ?: p.nowTripMs
                fx += Effect.Feed(FallbackFired(p.nowTripMs, started))
            } else {
                fx += Effect.Ring(ringRequest(alarm, p))
            }
        }
        for (e in step.events) {
            when (e) {
                is Snoozed -> fx += Effect.StopRinging(StopCause.SNOOZED)
                is PreAlert ->
                    fx += Effect.PreAlertFx(PreAlertRequest(p.meta.tripId, e.distanceM, e.etaS, p.meta.destinationName, byDistance = p.meta.mode == AlarmMode.DISTANCE))
                is Overshoot -> fx += Effect.OvershootFx(e.pastM)
                is SamplingPolicyChanged ->
                    if (p.mode == TrackingMode.TRACKING_FGS) fx += Effect.ApplySampling(FlpMapper.spec(e.policy, p.params))
                is GpsLost ->
                    when (e.cause) {
                        GpsLostCause.NEVER_ACQUIRED -> fx += Effect.Notice(TripNotice.NoGpsYet, null)
                        GpsLostCause.PERMISSION_REVOKED -> fx += Effect.Notice(TripNotice.PermissionRevoked, null)
                        GpsLostCause.SERVICES_OFF -> fx += Effect.Notice(TripNotice.ServicesOff, null)
                        GpsLostCause.NO_FIX_TIMEOUT -> Unit
                    }
                is GpsRecovered -> {
                    fx += Effect.Notice(null, TripNotice.NoGpsYet)
                    fx += Effect.Notice(null, TripNotice.PermissionRevoked)
                    fx += Effect.Notice(null, TripNotice.ServicesOff)
                }
                is FallbackAlarmChanged -> {
                    val at = e.fallbackAtMs
                    if (at != null) {
                        fx += Effect.ScheduleFallback(at)
                    } else if (e.cause != FallbackCause.SUPERSEDED) {
                        // SUPERSEDED: nothing at the OS level — the slot left is the ring guard (G1).
                        fx += Effect.CancelFallback
                    }
                }
                else -> Unit
            }
        }
        val prev = p.prevView
        if (view.fallbackStatus == FallbackStatus.FAILED && prev?.fallbackStatus != FallbackStatus.FAILED) {
            fx += Effect.Notice(TripNotice.FallbackFailed, null)
        }
        if (view.fallbackStatus == FallbackStatus.CONFIRMED && prev?.fallbackStatus == FallbackStatus.FAILED) {
            fx += Effect.Notice(null, TripNotice.FallbackFailed)
        }
        if (prev != null && prev.snoozeCount != view.snoozeCount) fx += Effect.UpdateRingConfig(view.snoozeCount)
        val ended = step.events.firstOrNull { it is TripEnded } as TripEnded?
        val wake = view.wakeAtMs
        if (wake != null && wake != p.scheduledWakeAtMs) {
            fx += Effect.ScheduleWake(wake, WakePolicy.mechanism(view, wake, p.canScheduleExact, p.nearWakeUsesAlarmClock))
        } else if (wake == null && p.scheduledWakeAtMs != null && ended == null) {
            fx += Effect.CancelWake
        }
        fx += Effect.Tracking(NoticeFormatter.notice(p.meta, view))
        fx += Effect.Persist
        fx += Effect.Publish
        if (ended != null) {
            fx += Effect.StopRinging(StopCause.TRIP_ENDED)
            fx += Effect.CancelFallback
            fx += Effect.CancelWake
            fx += Effect.ClearNotices
            fx += Effect.Finish(FinishedRecordBuilder.fromEvent(p.meta.tripId, ended))
        }
        return fx
    }

    private fun ringRequest(a: Alarm, p: PlanInput): RingRequest =
        RingRequest(
            tripId = p.meta.tripId,
            source = RingSource.ENGINE,
            reason = a.reason,
            snoozeAllowed = a.snoozeAllowed,
            distanceM = a.distanceM,
            etaS = a.etaS,
            batteryPct = a.batteryPct,
            destinationName = p.meta.destinationName,
            settings = p.meta.alarm,
            atWallMs = p.nowWallMs,
        )

    /** TripClock.toTrip with the Step's clock reading (pure). */
    private fun toTrip(wallMs: Long, p: PlanInput): Long = p.nowTripMs - ClockMath.up(maxOf(0L, p.nowWallMs - wallMs), p.speed)
}
