// Decides whether a region event starts a commute trip (docs/specs/T23.8.md §5.3, D6–D8, D18). Pure: no clock, no I/O.
// Day keys are consumed by the controller only after `runtime.start` returned `.started` (D7, `CommuteState.markingFired`).
import Foundation

public enum CommuteTriggerEvaluator {
    public static func evaluate(_ event: RegionEvent, route: CommuteRoute, state input: CommuteState, ctx: TriggerContext,
                                constants c: CommuteConstants = .default) -> (TriggerDecision, CommuteState) {
        // A state of another revision knows nothing about the current regions (D6, §5.10).
        var state = input.rebased(to: route.revision)
        guard let (rev, point) = CommuteRegionId.parse(event.identifier) else { return (.skip(.unknownIdentifier), state) }
        if rev != route.revision { return (.skip(.staleRevision), state) }
        if state.lastEventAtMs[point] == event.dateWallMs && state.lastState[point] == event.state {
            return (.skip(.duplicate), state)
        }
        // D18: an event older than the recorded one of this point changes nothing, unless the recorded date lies in the
        // future of the processing time (device clock set back): then the new event is taken as usual.
        if let last = state.lastEventAtMs[point], event.dateWallMs < last, last <= ctx.nowWallMs {
            return (.skip(.outOfOrder), state)
        }
        // D6 (review C1 #2): `unknown` keeps the last known state (and its date); only a new revision forgets it.
        if event.state == .unknown { return (.skip(.notEntry), state) }
        let prev = state.lastState[point] ?? .unknown
        state.lastState[point] = event.state
        state.lastEventAtMs[point] = event.dateWallMs
        if event.state != .inside { return (.skip(.notEntry), state) }
        if prev == .unknown { return (.skip(.firstDetermination), state) }
        if prev == .inside { return (.skip(.notEntry), state) }
        let (age, overflow) = ctx.nowWallMs.subtractingReportingOverflow(event.dateWallMs)
        if overflow || age > c.eventMaxStaleMs { return (.skip(.stale), state) }
        if !route.enabled { return (.skip(.routeDisabled), state) }
        let dir = point.direction
        let w = route.window(dir)
        if !w.enabled { return (.skip(.directionDisabled), state) }
        if !ctx.osSupported { return (.skip(.unsupportedOs), state) }
        if event.authorizationDenied || !ctx.access.always { return (.skip(.notAlways), state) }
        if !ctx.access.fullAccuracy { return (.skip(.notPrecise), state) }
        if !ctx.access.servicesEnabled { return (.skip(.servicesOff), state) }
        let local = LocalClock.local(event.dateWallMs, offsetS: ctx.utcOffsetS)
        if !w.includes(weekdayIndex: local.weekdayIndex) { return (.skip(.weekday), state) }
        if !w.includes(minuteOfDay: local.minuteOfDay) { return (.skip(.outsideWindow), state) }
        if state.firedKeys.contains(CommuteDayKey.make(dir, dateKey: local.dateKey)) {
            return (.skip(.alreadyFiredToday), state)
        }
        // Does not consume the day key (D7): the next entry after the trip ends may start.
        if ctx.tripActive { return (.skip(.tripActive), state) }
        return (.start(dir, dateKey: local.dateKey), state)
    }
}
