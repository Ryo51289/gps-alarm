import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T17.2 (docs/specs/T17.2.md): secondary button, launch action, sounds, native strings (AU01–AU13), plus the held "now"
/// ring of the review T17 round 3 risk (H1, H2).
@Suite("T172")
struct T172Tests {
    typealias U = RuntimeUnitTests

    // MARK: - Pure

    @Test("AU01 SecondaryActionPlanner: D1 table; switch off never gives snooze")
    func au01() {
        let on = RuntimeConstants.default
        var off = RuntimeConstants.default
        off.snoozeButtonEnabled = false
        func a(_ k: SystemAlarmKind, _ r: AlarmReason?, _ allowed: Bool, count: Int = 0, max: Int = 1,
               _ c: RuntimeConstants = .default) -> SecondaryAction? {
            SecondaryActionPlanner.action(kind: k, reason: r, snoozeAllowed: allowed, snoozeCount: count, maxSnoozes: max,
                                          snoozeMinutes: 1, constants: c)
        }
        #expect(a(.now, .distance, true) == .snooze(minutes: 1))
        #expect(a(.now, .overshoot, true) == .routeBack)
        #expect(a(.now, .overshoot, false) == .routeBack)
        #expect(a(.now, .distance, false) == nil)
        #expect(a(.now, .snoozeEnd, false) == nil)
        #expect(a(.fallback, nil, false, count: 0) == .snooze(minutes: 1))
        #expect(a(.fallback, nil, false, count: 1) == nil)
        #expect(a(.guardSlot, .overshoot, false) == .routeBack)
        #expect(a(.guardSlot, .timeout, true) == .snooze(minutes: 1))
        #expect(a(.guardSlot, .timeout, false) == nil)
        #expect(a(.guardSlot, nil, false, count: 0) == .snooze(minutes: 1))
        for k in [SystemAlarmKind.now, .fallback, .guardSlot] {
            for r in [AlarmReason.distance, .overshoot, .fallback, .snoozeEnd] as [AlarmReason?] + [nil] {
                for allowed in [true, false] {
                    #expect(a(k, r, allowed, count: 0, max: 3, off) != .snooze(minutes: 1))
                }
            }
        }
        #expect(a(.now, .overshoot, false, off) == .routeBack)
        #expect(on.snoozeButtonEnabled && on.akSelfStopMs == nil)
        #expect(SecondaryActionPlanner.snoozeMinutes(60) == 1 && SecondaryActionPlanner.snoozeMinutes(120) == 2)
        #expect(SecondaryActionPlanner.snoozeMinutes(30) == 1 && SecondaryActionPlanner.snoozeMinutes(600) == 10)
    }

    @Test("AU02 AlarmSoundCatalog: default/unknown/empty/nil → horn; system → no file")
    func au02() {
        let cases: [(String?, String, String?)] = [
            ("default", "horn", "alarm_horn.wav"), ("horn", "horn", "alarm_horn.wav"), ("bell", "bell", "alarm_bell.wav"),
            ("beep", "beep", "alarm_beep.wav"), ("system", "system", nil), ("", "horn", "alarm_horn.wav"),
            (nil, "horn", "alarm_horn.wav"), ("../x", "horn", "alarm_horn.wav"), ("Bell", "horn", "alarm_horn.wav"),
        ]
        for (id, resolved, file) in cases {
            #expect(AlarmSoundCatalog.resolve(id) == resolved, "\(id ?? "nil")")
            #expect(AlarmSoundCatalog.fileName(id ?? "") == file, "\(id ?? "nil")")
        }
        #expect(AlarmSoundCatalog.catalog == ["horn", "bell", "beep", "system"])
    }

    @Test("AU03 LaunchActionSlot.valid: TTL by elapsed (same boot) or wall; trip id; pastM range")
    func au03() {
        let ttl: Int64 = 600_000
        func rec(trip: String = "t-1_A", past: Int? = 250, wall: Int64 = 1_000_000, el: Int64 = 50_000,
                 boot: String? = "B1") -> LaunchActionRec {
            LaunchActionRec(tripId: trip, pastM: past, atWallMs: wall, atElapsedMs: el, bootSessionId: boot)
        }
        func v(_ r: LaunchActionRec, wall: Int64 = 1_000_000, el: Int64, boot: String? = "B1") -> LaunchActionRec? {
            LaunchActionSlot.valid(r, nowWallMs: wall, nowElapsedMs: el, bootSessionId: boot, ttlMs: ttl)
        }
        #expect(v(rec(), el: 50_000 + 599_000)?.pastM == 250)                    // 9:59, same boot
        #expect(v(rec(), el: 50_000 + 601_000) == nil)                           // 10:01
        #expect(v(rec(), wall: 1_000_000 + 3_600_000, el: 50_000 + 1_000) != nil) // same boot: wall moved, elapsed counts
        #expect(v(rec(), wall: 1_000_000 + 300_000, el: 7, boot: "B2") != nil)   // other boot: wall 5 min
        #expect(v(rec(), wall: 1_000_000 + 601_000, el: 7, boot: "B2") == nil)
        #expect(v(rec(boot: nil), wall: 1_000_000 + 300_000, el: 7, boot: nil) != nil)  // unknown boot: wall
        #expect(v(rec(), wall: 999_000, el: 7, boot: "B2") == nil)               // wall in the future
        #expect(v(rec(trip: "a b"), el: 50_001) == nil)
        #expect(v(rec(trip: ""), el: 50_001) == nil)
        #expect(v(rec(trip: String(repeating: "x", count: 65)), el: 50_001) == nil)
        #expect(v(rec(trip: String(repeating: "x", count: 64)), el: 50_001) != nil)
        #expect(v(rec(past: -1), el: 50_001)?.pastM == nil)
        #expect(v(rec(past: 1_000_001), el: 50_001)?.pastM == nil)
        #expect(v(rec(past: 1_000_000), el: 50_001)?.pastM == 1_000_000)
        #expect(v(rec(past: 0), el: 50_001)?.pastM == 0)
        let other = LaunchActionRec(kind: "other", tripId: "t1", pastM: 1, atWallMs: 1_000_000, atElapsedMs: 50_000,
                                    bootSessionId: "B1")
        #expect(v(other, el: 50_001) == nil)
        #expect("\(rec())".contains("pastM set") && !"\(rec())".contains("250") && !"\(rec())".contains("t-1_A"))
    }

    final class Box: Locked, @unchecked Sendable {
        var value: LaunchActionRec?
        var inFlight = false
        var reads = 0
        var slept: Int64 = 0
    }

    @Test("AC02 (Linux part) LaunchActionWait: waits while a route-back intent runs; returns at once otherwise")
    func ac02Linux() async {
        let r = LaunchActionRec(tripId: "t1", pastM: 10, atWallMs: 1, atElapsedMs: 1, bootSessionId: nil)
        // In flight, written after 500 ms of polling.
        let b = Box()
        b.inFlight = true
        let got = await LaunchActionWait.consume(
            waitMs: 1_500, pollMs: 100, inFlight: { b.locked { b.inFlight } },
            read: { b.locked { b.reads += 1; let v = b.value; b.value = nil; return v } },
            sleep: { ms in b.locked { b.slept += ms; if b.slept >= 500 { b.value = r; b.inFlight = false } } })
        #expect(got == r)
        #expect(b.locked { b.slept } == 500)
        // Not in flight: one read, no wait.
        let c = Box()
        let none = await LaunchActionWait.consume(
            waitMs: 1_500, pollMs: 100, inFlight: { false },
            read: { c.locked { c.reads += 1 }; return nil },
            sleep: { ms in c.locked { c.slept += ms } })
        #expect(none == nil && c.locked { c.reads } == 1 && c.locked { c.slept } == 0)
        // In flight forever: gives up after 1 500 ms.
        let d = Box()
        let late = await LaunchActionWait.consume(
            waitMs: 1_500, pollMs: 100, inFlight: { true }, read: { nil },
            sleep: { ms in d.locked { d.slept += ms } })
        #expect(late == nil && d.locked { d.slept } == 1_500)
        // Written and flag cleared between two polls: the last read still finds it.
        let e = Box()
        e.inFlight = true
        let last = await LaunchActionWait.consume(
            waitMs: 1_500, pollMs: 100, inFlight: { e.locked { e.inFlight } },
            read: { e.locked { e.reads += 1; return e.reads == 3 ? r : nil } },
            sleep: { _ in e.locked { if e.reads == 2 { e.inFlight = false } } })
        #expect(last == r)
    }

    @Test("AU10 restore: snooze (t1) then dismiss (t2) → DISMISSED; snooze alone → RANG; dismiss wins on the same alarm")
    func au10() {
        func ev(_ a: RingEventRec.Action, _ id: String, _ t: Int64, trip: String = "t1") -> RingEventRec {
            RingEventRec(tripId: trip, alarmId: id, kind: .now, action: a, atWallMs: t)
        }
        #expect(RingEventPicker.effective([ev(.snooze, "A", 1), ev(.dismiss, "A", 2)], tripId: "t1")?.action == .dismiss)
        #expect(RingEventPicker.effective([ev(.dismiss, "A", 1), ev(.snooze, "A", 2)], tripId: "t1")?.action == .dismiss)
        #expect(RingEventPicker.effective([ev(.snooze, "A", 1), ev(.routeBack, "B", 2)], tripId: "t1")?.action == .routeBack)
        #expect(RingEventPicker.effective([ev(.dismiss, "A", 1), ev(.snooze, "B", 2)], tripId: "t1")?.action == .snooze)
        #expect(RingEventPicker.effective([ev(.dismiss, "A", 1, trip: "x")], tripId: "t1") == nil)
        // Through RestorePlanner on a real engine state.
        let w = World()
        let facts = EngineFacts.read(try! TripEngine.start(
            config: TestData.meta().config(destLat: TestData.destLat, destLng: TestData.destLng), params: .defaults,
            nowMs: 1_000).state)!
        func plan(_ events: [RingEventRec]) -> RestoreInfo {
            RestorePlanner.plan(facts, ledger: .empty, events: events, list: [], nowTripMs: 5_000, toTrip: { $0 })
        }
        #expect(plan([ev(.snooze, "A", 3_000), ev(.dismiss, "A", 4_000)]).status == .dismissed)
        #expect(plan([ev(.snooze, "A", 3_000)]) == RestoreInfo(status: .rang, firedAtMs: 3_000))
        #expect(plan([ev(.routeBack, "A", 3_000)]).status == .dismissed)
        _ = w
    }

    @Test("AU11 NativeCopy: secondary labels vi/en = ARB; the table holds both keys (IU34 checks them)")
    func au11() throws {
        #expect(NativeCopy.secondaryLabel(.snooze(minutes: 1), locale: "vi") == "Báo lại sau 1 phút")
        #expect(NativeCopy.secondaryLabel(.snooze(minutes: 1), locale: "en") == "Snooze 1 min")
        #expect(NativeCopy.secondaryLabel(.routeBack, locale: "vi") == "Xem đường quay lại")
        #expect(NativeCopy.secondaryLabel(.routeBack, locale: "en") == "Route back")
        #expect(NativeCopy.table["alarmSnoozeMinutes"] != nil && NativeCopy.table["alarmRouteBack"] != nil)
        let d = try Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.l10nDir)/app_en.arb"))
        let en = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        #expect((en["alarmSnoozeMinutes"] as? String)?.replacingOccurrences(of: "{minutes}", with: "1")
            == NativeCopy.secondaryLabel(.snooze(minutes: 1), locale: "en"))
    }

    // MARK: - Sounds (AU13)

    struct Wav {
        let channels: Int
        let rate: Int
        let byteRate: Int
        let bits: Int
        let format: Int
        let data: Data
        var seconds: Double { Double(data.count) / Double(byteRate) }

        static func read(_ path: String) throws -> Wav {
            let d = try Data(contentsOf: URL(fileURLWithPath: path))
            let b = [UInt8](d)
            func u(_ o: Int, _ n: Int) -> Int { (0..<n).reduce(0) { $0 | Int(b[o + $1]) << (8 * $1) } }
            func tag(_ o: Int) -> String { String(decoding: b[o..<(o + 4)], as: UTF8.self) }
            guard b.count >= 44, tag(0) == "RIFF", tag(8) == "WAVE", tag(12) == "fmt ", u(16, 4) == 16, tag(36) == "data",
                  u(4, 4) == b.count - 8, u(40, 4) == b.count - 44 else { throw CocoaError(.fileReadCorruptFile) }
            return Wav(channels: u(22, 2), rate: u(24, 4), byteRate: u(28, 4), bits: u(34, 2), format: u(20, 2),
                       data: d.subdata(in: 44..<b.count))
        }
    }

    /// 2x linear interpolation of 16-bit mono PCM, wrapping last → first (same rule as make-alarm-sounds.sh):
    /// out[2i] = s[i], out[2i+1] = (s[i] + s[(i+1) mod n]) / 2 truncated toward zero.
    static func upsample2(_ d: Data) -> Data {
        let b = [UInt8](d)
        let n = b.count / 2
        let s = (0..<n).map { Int(Int16(bitPattern: UInt16(b[2 * $0]) | UInt16(b[2 * $0 + 1]) << 8)) }
        var out = [UInt8]()
        out.reserveCapacity(4 * n)
        func put(_ v: Int) {
            let u = UInt16(bitPattern: Int16(v))
            out.append(UInt8(u & 0xFF))
            out.append(UInt8(u >> 8))
        }
        for i in 0..<n {
            put(s[i])
            put((s[i] + s[(i + 1) % n]) / 2)
        }
        return Data(out)
    }

    @Test("AU13 Runner/Sounds: 3 PCM 44.1 kHz files of 28.0–29.5 s = whole loops of the upsampled Android sources; script rebuilds")
    func au13() throws {
        let ios = RTPaths.repoRoot + "/app/ios"
        let raw = RTPaths.repoRoot + "/app/android/app/src/main/res/raw"
        for f in AlarmSoundCatalog.files {
            let w = try Wav.read("\(ios)/Runner/Sounds/\(f)")
            // Review T17.2 #1: the format of the S3 probe tone that rang through AlarmKit (WavTone.make: 44 100 Hz,
            // 16-bit, mono).
            #expect(w.format == 1 && w.bits == 16 && w.channels == 1 && w.rate == 44_100 && w.byteRate == 88_200,
                    "\(f) PCM 16-bit mono 44.1 kHz")
            #expect(w.seconds >= 28.0 && w.seconds <= 29.5, "\(f): \(w.seconds) s")
            let src = try Wav.read("\(raw)/\(f)")
            let loop = src.rate == 44_100 ? src.data : Self.upsample2(src.data)
            #expect(src.rate == 44_100 || src.rate == 22_050, "\(f): source rate \(src.rate)")
            let n = w.data.count / loop.count
            #expect(n * loop.count == w.data.count, "\(f): whole loops")
            #expect(w.data == Data((0..<n).flatMap { _ in loop }), "\(f): seamless repeat of the upsampled source")
            #expect(n == 29_500 * w.byteRate / (1_000 * loop.count), "\(f): largest loop count ≤ 29.5 s")
        }
        // The generator (bash + coreutils) gives the same bytes; skipped when bash is not there.
        let bash = ["/bin/bash", "/usr/bin/bash"].first { FileManager.default.isExecutableFile(atPath: $0) }
        if let bash {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bash)
            p.arguments = ["\(ios)/scripts/make-alarm-sounds.sh", "--check"]
            p.standardOutput = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0, "make-alarm-sounds.sh --check")
        }
    }

    // MARK: - Runtime (fakes)

    static func secondaryOf(_ w: World, kind: SystemAlarmKind) -> [SecondaryAction?] {
        w.alarms.scheduledRequests().filter { $0.kind == kind }.map(\.secondary)
    }

    @Test("Requests: now/fallback/guard carry the D1 button and the sound file of the settings")
    func requests() async {
        let w = World()
        #expect(await U.started(w) == .started)
        let fb = w.alarms.scheduledRequests().first { $0.kind == .fallback }
        #expect(fb?.secondary == .snooze(minutes: 1) && fb?.soundFile == "alarm_horn.wav")
        await U.ringing(w)
        let now = U.nowAlarms(w).first
        #expect(now?.secondary == .snooze(minutes: 1) && now?.soundFile == "alarm_horn.wav")
        let guardReq = w.alarms.scheduledRequests().first { $0.kind == .guardSlot }
        #expect(guardReq?.secondary == .snooze(minutes: 1))
        // `system` → AlertSound.default; switch off → no snooze button.
        var c = RuntimeConstants.default
        c.snoozeButtonEnabled = false
        let w2 = World(constants: c)
        let meta = TripMeta(tripId: "t1", destinationName: "X", mode: .distance, distanceThresholdM: 1000, timeThresholdMin: nil,
                            preAlertEnabled: false, vehicleHint: .train,
                            alarm: RingSettings(soundId: "system", volume: 0.3, rampUp: false, vibration: "off", flash: false,
                                                preferHeadphones: false, dismissMethod: "swipe"), engineParamsJson: nil)
        #expect(await U.started(w2, meta: meta) == .started)
        await U.ringing(w2)
        #expect(w2.alarms.scheduledRequests().allSatisfy { $0.soundFile == nil && $0.secondary == nil })
    }

    /// Runs the T17.2 §3.2 intent order with fakes: (1) ring event, (2) stop, (3) runtime.
    static func intent(_ w: World, _ rec: RingEventRec, order: OpLog? = nil) async {
        await StopIntentFlow.perform(
            rec, write: { r in order?.add("write"); try w.store.appendRingEvent(r) },
            stopSystemAlarm: { order?.add("stop"); w.alarms.setState(rec.alarmId, nil) },
            handOver: { r in
                order?.add("handOver")
                switch r.action {
                case .snooze: await w.runtime.onSnoozeIntent(r)
                case .routeBack: await w.runtime.onRouteBackIntent(r)
                case .dismiss: await w.runtime.onStopIntent(r)
                }
            })
        await w.settle()
    }

    static func snoozedEvents(_ w: World) -> [TripEvent.Snoozed] {
        w.seen.events.compactMap { if case let .snoozed(s) = $0 { return s }; return nil }
    }

    @Test("AU04 snooze intent, app alive: write → stop → SNOOZE; slot at until + 30 s without button; SNOOZE_END without button")
    func au04() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        let now = U.nowAlarms(w).first!
        #expect(now.secondary == .snooze(minutes: 1))
        let order = OpLog()
        let tap = w.time.wallMs()
        await Self.intent(w, RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze, atWallMs: tap), order: order)
        #expect(order.ops == ["write", "stop", "handOver"])
        let s = Self.snoozedEvents(w)
        #expect(s.count == 1)
        #expect(s.first?.atMs == tap, "snooze at the tap time (same clock in the fakes)")
        let v = w.seen.entries.last!.view
        #expect(v.phase == .snoozed)
        let until = v.snoozeUntilMs!
        let slot = w.alarms.scheduledRequests().last { $0.kind == .fallback }
        #expect(slot?.fireAtWallMs == until + 30_000)
        #expect(slot?.secondary == nil, "maxSnoozes 1: no snooze left")
        #expect(w.store.readRingEvents().isEmpty)
        #expect(!w.alarms.all.contains { $0.state == .alerting })
        await w.advance(to: until - w.startWall + 1_000)
        #expect(w.seen.events.contains { if case let .alarm(a) = $0 { return a.reason == .snoozeEnd }; return false })
        let end = U.nowAlarms(w).last!
        #expect(U.nowAlarms(w).count == 2 && end.secondary == nil)
    }

    @Test("AU05 snooze on a ringing fallback slot the runtime has not seen: FallbackFired first, then Snoozed")
    func au05() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.drive(w, km: 30, max: 6) { false }
        let slot = w.store.currentLedger.current!
        #expect(slot.kind == .fallback)
        #expect(Self.secondaryOf(w, kind: .fallback).last == .snooze(minutes: 1))
        w.suspended = true  // no alarmUpdates while the slot starts ringing
        await w.advance(to: slot.targetAtWallMs - w.startWall + 2_000)
        #expect(w.alarms.all.first { $0.id == slot.alarmId }?.state == .alerting)
        w.suspended = false
        await Self.intent(w, RingEventRec(tripId: "t1", alarmId: slot.alarmId, kind: .fallback, action: .snooze,
                                          atWallMs: w.time.wallMs()))
        let evs = w.seen.events
        let fired = evs.firstIndex { if case let .alarm(a) = $0 { return a.reason == .fallback }; return false }
        let snoozed = evs.firstIndex { if case .snoozed = $0 { return true }; return false }
        #expect(fired != nil && snoozed != nil && fired! < snoozed!)
        #expect(w.journal.all.contains { $0.ev == "fb_fired" && $0.fields["src"] == "interpreter" })
        #expect(w.seen.entries.last?.view.phase == .snoozed)
        #expect(w.store.currentLedger.lastFired?.alarmId == slot.alarmId)
    }

    @Test("AU06 snooze intent the engine refuses (no snooze left): no Snoozed, AlarmSilenced, nothing rings at once")
    func au06() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        await w.runtime.userAction(tripId: "t1", .snooze)
        await w.settle()
        let until = w.seen.entries.last!.view.snoozeUntilMs!
        await w.advance(to: until - w.startWall + 7_000)  // SNOOZE_END now alarm alerting
        let end = U.nowAlarms(w).last!
        #expect(w.alarms.all.first { $0.id == end.id }?.state == .alerting)
        #expect(end.secondary == nil, "D1: the button is not offered when the engine refuses")
        let snoozes0 = Self.snoozedEvents(w).count
        let nows0 = U.nowAlarms(w).count
        await Self.intent(w, RingEventRec(tripId: "t1", alarmId: end.id, kind: .now, action: .snooze, atWallMs: w.time.wallMs()))
        #expect(Self.snoozedEvents(w).count == snoozes0)
        let v = w.seen.entries.last!.view
        #expect(v.phase == .alarming && !v.alarmRinging)
        #expect(w.journal.all.contains { $0.ev == "snooze_intent" && $0.fields["refused"] == "true" })
        await w.advance(by: 30_000)
        #expect(U.nowAlarms(w).count == nows0, "D6: no ring at once")
    }

    @Test("AU07 process died after the snooze intent wrote its event: background relaunch → RANG → SNOOZE; slot until + 30 s")
    func au07() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        let now = U.nowAlarms(w).first!
        let nows0 = U.nowAlarms(w).count
        w.kill()
        let tap = w.time.wallMs()
        try? w.store.appendRingEvent(RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze, atWallMs: tap))
        w.alarms.setState(now.id, nil)  // the intent stopped it, then the process died
        await w.advance(by: 1_000)
        w.relaunch(.background)
        _ = await w.runtime.addListenerWithoutRestoreWait { _, view, choice, events in
            w.seen.add(.init(view: view, choice: choice, events: events))
        }
        await w.runtime.ensureLoaded()
        await w.advance(by: 2_100)  // D13 settle
        let s = Self.snoozedEvents(w)
        #expect(s.count == 1)
        // The engine clock never goes back: the restore Step runs at the restore time, so the snooze counts from there
        // (≤ RESTORE_SETTLE_MS + the relaunch after the tap here; the intent's own launch restores at once).
        if let at = s.last?.atMs { #expect(at >= tap && at <= tap + 1_000 + w.constants.restoreSettleMs + 200) }
        let v = w.seen.entries.last!.view
        #expect(v.phase == .snoozed)
        #expect(w.alarms.all.contains { $0.kind == .fallback && $0.fireAtWallMs == v.snoozeUntilMs! + 30_000 })
        #expect(U.nowAlarms(w).count == nows0, "no ring at once")
        #expect(w.store.readRingEvents().isEmpty, "applied once")
        // A second process death: the snooze is not applied again.
        w.newProcess()
        w.app.state = .background
        await w.runtime.ensureLoaded()
        await w.advance(by: 2_100)
        #expect(U.nowAlarms(w).count == nows0)
    }

    @Test("AU07b the snooze intent launches the process in the background (restore pending): snoozed once, at once, no ring")
    func au07b() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        let now = U.nowAlarms(w).first!
        let nows0 = U.nowAlarms(w).count
        w.kill()
        await w.advance(by: 20_000)
        w.relaunch(.background)
        _ = await w.runtime.addListenerWithoutRestoreWait { _, view, choice, events in
            w.seen.add(.init(view: view, choice: choice, events: events))
        }
        await w.runtime.ensureLoaded()
        await w.advance(by: 300)
        let tap = w.time.wallMs()
        await Self.intent(w, RingEventRec(tripId: "t1", alarmId: now.id, kind: .now, action: .snooze, atWallMs: tap))
        let s = Self.snoozedEvents(w)
        #expect(s.count == 1 && s.last?.atMs == tap)
        #expect(w.seen.entries.last?.view.phase == .snoozed)
        #expect(Self.order(w, "snooze_intent", "restore"), "the restore waited for the intent (D13)")
        await w.advance(by: 30_000)
        #expect(U.nowAlarms(w).count == nows0)
        #expect(w.store.readRingEvents().isEmpty)
    }

    static func order(_ w: World, _ a: String, _ b: String) -> Bool { U.order(w, a, b) }

    /// ALARMING → first ring silenced → driving on north until Alarm(OVERSHOOT, ringNow); returns that "now" request.
    static func overshootRinging(_ w: World) async -> SystemAlarmRequest? {
        #expect(await U.started(w) == .started)
        await U.ringing(w)
        await w.advance(by: 6_000)
        let first = U.nowAlarms(w).first!
        w.alarms.setState(first.id, nil)  // rang out without a StopIntent
        await w.settle()
        await w.advance(by: 3_500)  // goneCheck → AlarmSilenced
        var km = 0.5
        for _ in 0..<120 {
            if w.seen.events.contains(where: { if case let .alarm(a) = $0 { return a.reason == .overshoot }; return false }) {
                break
            }
            km -= 0.075
            await w.advance(by: 5_000)
            await w.emit(TestData.fix(kmSouth: km, wall: w.time.wallMs()))
        }
        await w.advance(by: 6_000)
        return U.nowAlarms(w).last { $0.id != first.id }
    }

    @Test("AU08 route back on the OVERSHOOT alarm: launch action written before DISMISS; consume once")
    func au08() async {
        let w = World()
        let over = await Self.overshootRinging(w)
        #expect(over?.secondary == .routeBack)
        let pastM = w.seen.entries.last?.view.overshootPastM
        #expect(pastM != nil && w.seen.entries.last?.view.phase == .overshot)
        guard let over else { return }
        await Self.intent(w, RingEventRec(tripId: "t1", alarmId: over.id, kind: .now, action: .routeBack,
                                          atWallMs: w.time.wallMs()))
        let ops = w.log.ops
        let la = ops.firstIndex(of: "writeLaunchAction")
        let fin = ops.firstIndex(of: "writeFinished")
        #expect(la != nil && fin != nil && la! < fin!, "launch action before the trip ends")
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        let a = await w.runtime.consumeLaunchAction()
        #expect(a?.kind == LaunchActionRec.overshootRoute && a?.tripId == "t1" && a?.pastM == pastM)
        #expect(await w.runtime.consumeLaunchAction() == nil)
        #expect(!w.journal.all.contains { $0.fields.values.contains { $0 == "\(pastM ?? -1)" } }, "pastM never logged")
    }

    @Test("AU08b launch action expires after 10 min; route back of an unknown trip writes tripId only, cancels, markEnded")
    func au08b() async {
        let w = World()
        #expect(await U.started(w) == .started)
        await Self.intent(w, RingEventRec(tripId: "ghost", alarmId: "zzz", kind: .now, action: .routeBack,
                                          atWallMs: w.time.wallMs()))
        #expect(w.alarms.cancels.contains("zzz"))
        #expect(await w.runtime.current()?.meta.tripId == "t1")
        // Review T17.2 #3: route back ends that trip like Stop (spec §3.3 said cancel only).
        #expect(w.store.currentLedger.endedTripIds.contains("ghost"))
        w.time.v += 601_000
        #expect(await w.runtime.consumeLaunchAction() == nil, "expired")
        await Self.intent(w, RingEventRec(tripId: "ghost", alarmId: "zzz", kind: .now, action: .routeBack,
                                          atWallMs: w.time.wallMs()))
        w.time.v += 599_000
        let a = await w.runtime.consumeLaunchAction()
        #expect(a?.tripId == "ghost" && a?.pastM == nil)
        // Snooze of an unknown trip: cancel only.
        await Self.intent(w, RingEventRec(tripId: "ghost2", alarmId: "yyy", kind: .now, action: .snooze,
                                          atWallMs: w.time.wallMs()))
        #expect(w.alarms.cancels.contains("yyy") && !w.store.currentLedger.endedTripIds.contains("ghost2"))
        #expect(await w.runtime.current()?.meta.tripId == "t1")
    }

    @Test("Review #3: route back of a lost trip (F2) — its other slots are stopped/cancelled, nothing of it rings later")
    func routeBackLostTripEndsIt() async throws {
        let w = World()
        #expect(await U.started(w) == .started)
        // Leftovers of a trip whose snapshot was lost: a slot ringing now (the button the user taps) and a later one.
        let wall = w.time.wallMs()
        for (id, at) in [("L1", wall), ("L2", wall + 600_000)] {
            try await w.alarms.schedule(SystemAlarmRequest(id: id, tripId: "lost", kind: .fallback, generation: 1,
                                                           fireAtWallMs: at, title: "x", channel: .alarmKit))
        }
        w.alarms.setState("L1", .alerting)
        await w.settle()
        #expect(w.alarms.all.contains { $0.id == "L2" && $0.state == .scheduled })
        await Self.intent(w, RingEventRec(tripId: "lost", alarmId: "L1", kind: .fallback, action: .routeBack,
                                          atWallMs: w.time.wallMs()))
        #expect(await w.runtime.consumeLaunchAction()?.tripId == "lost")
        await w.runtime.onSystemAlarms(w.alarms.all)  // next alarmUpdates
        await w.settle()
        #expect(w.store.currentLedger.endedTripIds.contains("lost"))
        #expect(w.alarms.cancels.contains("L2"), "the later slot of that trip is cancelled")
        await w.advance(by: 700_000)
        #expect(!w.alarms.transitionList.contains { $0.tripId == "lost" && $0.id == "L2" }, "L2 never rings")
        #expect(await w.runtime.current()?.meta.tripId == "t1", "the active trip is untouched")
    }

    @Test("AU09 process died after the route-back intent wrote its event: DISMISSED → TripEnded; launch action written")
    func au09() async {
        let w = World()
        let over = await Self.overshootRinging(w)
        guard let over else { Issue.record("no overshoot alarm"); return }
        let pastM = w.seen.entries.last?.view.overshootPastM
        w.kill()
        try? w.store.appendRingEvent(RingEventRec(tripId: "t1", alarmId: over.id, kind: .now, action: .routeBack,
                                                  atWallMs: w.time.wallMs()))
        w.alarms.setState(over.id, nil)
        await w.advance(by: 500)
        w.relaunch(.background)
        await w.runtime.ensureLoaded()
        await w.advance(by: 2_100)
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        let a = await w.runtime.consumeLaunchAction()
        #expect(a?.tripId == "t1" && a?.pastM == pastM)
    }

    @Test("AU12 overshoot while the first ring is live, ring stops → one OVERSHOOT ring with route back (P1, T10.8 / T17.2.2)")
    func au12() async throws {
        let trace = try RuntimeFixtures.read("coach_gb_phuly_overshoot")
        // TR44: DISTANCE 1 000, nobody answers the first ring, the system stops it after osRingMaxS (AM05 gives the real D).
        let c = try #require(trace.cases.first { $0.id == "distance_1000_overshoot_ringing" })
        let ringMaxS = try #require(c.osRingMaxS)
        let w = World(startWall: trace.startMs)
        w.alarms.silenceAfterMs = Int64(ringMaxS) * 1000
        await w.listen()
        #expect(await w.runtime.start(meta: RuntimeFixtures.meta(trace, c), destLat: trace.destLat, destLng: trace.destLng)
            == .started)
        let run = TraceRun(world: w, trace: trace)
        await run.run(endT: trace.durationS)
        let over = w.alarms.scheduledRequests().filter { $0.kind == .now && $0.secondary == .routeBack }
        #expect(over.count == 1)
        let name = RuntimeFixtures.meta(trace, c).destinationName
        #expect(over.first?.title == NativeCopy.alarmTitle(.overshoot, destinationName: name, locale: "vi"))
        // At the first AlarmSilenced Step after the trip went OVERSHOT: the previous Step overshot with the first ring live.
        let entries = w.seen.entries
        func isOvershootAlarm(_ e: TripEvent) -> Bool { if case let .alarm(a) = e { return a.reason == .overshoot }; return false }
        let i = try #require(entries.firstIndex { $0.events.contains(where: isOvershootAlarm) })
        #expect(i > 0 && entries[i - 1].view.phase == .overshot && entries[i - 1].view.alarmRinging)
        #expect(entries[i].events.count == 1)
        let iOver = try #require(entries.firstIndex { $0.events.contains { $0.fixtureName == "overshoot" } })
        #expect(iOver < i && entries[iOver].events.allSatisfy { if case .alarm = $0 { return false }; return true })
        #expect(entries[iOver..<i].allSatisfy { $0.view.alarmRinging }, "no other AlarmSilenced in between")
        let first = try #require(w.seen.firstAlarm())
        let dt = entries[i].view.atMs - first.atMs
        #expect(dt >= Int64(ringMaxS) * 1000 && dt <= Int64(ringMaxS + 10) * 1000, "ring₁ + osRingMaxS + grace: \(dt) ms")
        #expect(w.alarms.doubleRings == 0)
        #expect(w.seen.events.filter(isOvershootAlarm).count == 1)
    }

    // MARK: - Held "now" ring (review T17 round 3 risk)

    /// Far trip; the app is suspended while the fallback slot rings and the user stops it on the lock screen (iOS 26.1
    /// removes it before perform). Back from suspension, fixes near the destination make the engine ring. Returns the slot
    /// and the virtual-time window [lo, hi] in which the held decision was made (the first Step after the suspension is
    /// the overdue Tick: GPS_LOST after 30 min without fixes, a ringNow Step like the queued fixes of spec R4).
    static func heldRing(_ w: World) async -> (slot: AlarmSlotRec, lo: Int64, hi: Int64)? {
        #expect(await U.started(w) == .started)
        await U.drive(w, km: 30, max: 6) { false }
        let slot = w.store.currentLedger.current!
        w.suspended = true
        await w.advance(to: slot.targetAtWallMs - w.startWall + 2_000)
        w.alarms.setState(slot.alarmId, nil)  // Stop on the lock screen; the StopIntent is late
        w.suspended = false
        func held() -> Bool { w.journal.all.contains { $0.ev == "ring_held" } }
        for _ in 0..<40 {
            let lo = w.time.v
            await w.advance(by: 1_000)
            if held() { return (slot, lo, w.time.v) }
            await w.emit(TestData.fix(kmSouth: 0.4, wall: w.time.wallMs()))
            if held() { return (slot, lo, w.time.v) }
        }
        Issue.record("no held ring")
        return nil
    }

    @Test("H1 StopIntent 2 s after the ring decision of queued fixes: no \"now\" alarm at all, trip DISMISSED, one ring")
    func h1() async {
        let w = World()
        guard let (slot, lo, _) = await Self.heldRing(w) else { return }
        #expect(U.nowAlarms(w).isEmpty, "held, not scheduled")
        #expect(w.seen.firstAlarm()?.ringNow == true)
        await w.advance(to: lo + 2_000)
        #expect(U.nowAlarms(w).isEmpty)
        await U.stopIntent(w, slot)
        await w.advance(by: 60_000)
        #expect(U.nowAlarms(w).isEmpty, "no second ring after Stop")
        #expect(w.store.finished["t1"]?.endReason == "DISMISSED")
        #expect(w.alarms.transitionList.filter { $0.tripId == "t1" }.count == 1)
    }

    @Test("H2 no StopIntent: the held ring is scheduled STOP_INTENT_GRACE_MS after the decision, once; Flutter snooze drops it")
    func h2() async {
        let w = World()
        guard let (_, lo, hi) = await Self.heldRing(w) else { return }
        await w.advance(to: lo + w.constants.stopIntentGraceMs - 200)
        #expect(U.nowAlarms(w).isEmpty)
        await w.advance(to: hi + w.constants.stopIntentGraceMs + 1_500)
        #expect(U.nowAlarms(w).count == 1)
        #expect(w.journal.all.filter { $0.ev == "ring_held" }.count >= 1)
        await w.advance(by: 30_000)
        #expect(U.nowAlarms(w).count == 1)
        #expect(w.alarms.doubleRings == 0)
        // Snoozed from Flutter while held: nothing rings when the grace ends.
        let w2 = World()
        guard let (_, _, d2) = await Self.heldRing(w2) else { return }
        await w2.runtime.userAction(tripId: "t1", .snooze)
        await w2.settle()
        await w2.advance(to: d2 + w2.constants.stopIntentGraceMs + 1_500)
        #expect(U.nowAlarms(w2).isEmpty)
        #expect(w2.seen.entries.last?.view.phase == .snoozed)
    }

    @Test("Hold pure rule: past-due slot gone from the list and never seen ringing; not when listed, seen, or not due")
    func holdPure() {
        func slot(_ id: String, _ at: Int64) -> AlarmSlotRec {
            AlarmSlotRec(alarmId: id, kind: .fallback, generation: 1, targetAtMs: at, targetAtWallMs: at, setAtWallMs: 0,
                         channel: .alarmKit)
        }
        var l = AlarmLedger.empty
        l.current = slot("S", 1_000)
        #expect(RingHold.slot(l, list: [], nowWallMs: 1_000)?.alarmId == "S")
        #expect(RingHold.slot(l, list: [], nowWallMs: 999) == nil)
        let listed = SystemAlarmInfo(id: "S", tripId: "t1", kind: .fallback, generation: 1, state: .scheduled,
                                     fireAtWallMs: 1_000, channel: .alarmKit)
        #expect(RingHold.slot(l, list: [listed], nowWallMs: 5_000) == nil)
        l.lastFired = FiredRec(alarmId: "S", kind: .fallback, generation: 1, firedAtMs: 1_000, firedAtWallMs: 1_000)
        #expect(RingHold.slot(l, list: [], nowWallMs: 5_000) == nil)
        l.lastFired = nil
        l.current = nil
        l.stale = slot("T", 2_000)
        #expect(RingHold.slot(l, list: [], nowWallMs: 5_000)?.alarmId == "T")
    }
}
