import Foundation
import Testing
@testable import Trip

/// Tester T13.6 (T10.8, PO P1, C32): Kotlin `unit/TesterT125Test.kt` X2–X4 on the Swift engine (X1 lives in `T108Tests`).
/// Same base trip as `T108Tests` (U34 build: DISTANCE 1000, fixes 60 s apart at 40 km/h, overshoot at t = 420 while the DISTANCE
/// alarm still rings). Same inputs and the same expectations as Kotlin, assertion for assertion.
/// - X2: the expiry is measured from the latest ring (a FallbackFired in OVERSHOT moves lastRingAtMs): AlarmSilenced at
///   ring1 + alarmMaxActiveS still rings when a fallback rang later; at fallback + alarmMaxActiveS it ends without a ring.
/// - X3: a late AlarmSilenced (input atMs later than silencedAtMs; app dead 30 min) rings at the Step time, not at silencedAtMs.
/// - X4: location services turned off in OVERSHOT before the chime stops does not block the ring; SNOOZE on the OVERSHOOT ring is
///   ignored and the next AlarmSilenced is silent; DISMISS ends MISSED / DISMISSED.
@Suite("TesterT136Tests")
struct TesterT136Tests {
    typealias T = T108Tests

    static func ended(_ s: Step) -> [TripEvent.TripEnded] { s.events.compactMap(\.asEnded) }

    @Test("T125 X2 the expiry counts from the latest ring - a fallback ring in OVERSHOT moves it")
    func x2ExpiryFromLatestRing() throws {
        var e = T.overshotWhileRinging()
        let ring1 = try #require(e.state.alarm.lastRingAtMs)
        let fbAt = T.ms(1_000)
        e.feed(.fallbackFired(atMs: fbAt, firedAtMs: fbAt))
        #expect(e.state.alarm.lastRingAtMs == fbAt)
        // At ring1 + alarmMaxActiveS (not expired from the fallback ring): step 3 does not end, the rule rings.
        let s = e.feed(T.silencedIn(ring1 + T.maxActiveMs))
        #expect(Self.ended(s).isEmpty, "\(s.events)")
        #expect(s.events.alarms.map(\.reason) == [.overshoot], "\(s.events)")
        // Second scenario: the chime stops exactly at fallback + alarmMaxActiveS → TripEnded, no ring.
        var e2 = T.overshotWhileRinging()
        e2.feed(.fallbackFired(atMs: fbAt, firedAtMs: fbAt))
        let g = e2.feed(T.silencedIn(fbAt + T.maxActiveMs))
        #expect(g.events.alarms.isEmpty, "\(g.events)")
        #expect(Self.ended(g).map(\.endReason) == [.alarmUnanswered])
        #expect(T.overshootAlarms(e2).isEmpty)
    }

    @Test("T125 X3 a late AlarmSilenced rings at the Step time, alarmMaxActiveS counts from it")
    func x3LateSilenced() {
        var e = T.overshotWhileRinging()
        let stepAt = T.ms(425 + 30 * 60)
        let s = e.feed(.alarmSilenced(atMs: stepAt, silencedAtMs: T.ms(425)))
        let a = s.events.alarms
        #expect(a.map(\.reason) == [.overshoot])
        #expect(a.map(\.atMs) == [stepAt], "Alarm.atMs = now of the Step, not silencedAtMs")
        #expect(s.state.alarm.lastRingAtMs == stepAt)
        #expect(Self.ended(e.tickMs(stepAt + T.maxActiveMs - 1)).isEmpty)
        #expect(Self.ended(e.tickMs(stepAt + T.maxActiveMs)).map(\.endReason) == [.alarmUnanswered])
    }

    @Test("T125 X4 location services off before the chime stops still rings, SNOOZE on the OVERSHOOT ring is ignored, DISMISS ends MISSED")
    func x4ServicesOffSnoozeDismiss() {
        var e = T.overshotWhileRinging()
        e.feed(.locationAvailability(atMs: T.ms(422), cause: .servicesOff))
        let s = e.feed(T.silencedIn(T.ms(425)))
        #expect(s.events.alarms.map(\.reason) == [.overshoot], "\(s.events)")
        let z = e.feed(.userAction(atMs: T.ms(430), action: .snooze))
        #expect(z.events.isEmpty, "SNOOZE in OVERSHOT ignored: \(z.events)")
        #expect(z.view.phase == .overshot)
        #expect(z.state.alarm.ringing)
        #expect(e.feed(T.silencedIn(T.ms(1_025))).events.isEmpty)
        let d = e.feed(.userAction(atMs: T.ms(1_030), action: .dismiss))
        let end = Self.ended(d)
        #expect(end.map(\.endReason) == [.dismissed])
        #expect(end.map(\.outcome) == [.missed])
        #expect(T.overshootAlarms(e).count == 1)
    }
}
