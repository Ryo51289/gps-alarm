import Foundation
import Testing
@testable import TripRuntime

/// Spike T23.8-B0 (docs/spikes/T23.8.md §2): pure part of the region wake probe (transitions, fix gaps, report).
@Suite("T23.8 B0 commute probe")
struct CommuteProbeTests {
    static func event(_ api: ProbeApi = .clmonitor, _ point: ProbePoint = .a, state: ProbeRegionState = .inside,
                      transition: ProbeTransition = .entry, eventMs: Int64? = 1_000_000, receivedMs: Int64 = 1_008_000,
                      app: String = "background", procAgeS: Int = 3, bg: Bool = true, first: Bool = true) -> ProbeEventRecord {
        ProbeEventRecord(api: api, point: point, state: state, transition: transition, eventWallMs: eventMs,
                         receivedWallMs: receivedMs, appState: app, procAgeS: procAgeS, launchedInBackground: bg,
                         firstOfProcess: first)
    }

    @Test("transition: only outside → inside is an entry; the first known state never is (H8, spec D6)")
    func transitions() {
        #expect(CommuteProbe.transition(prev: .unknown, new: .inside) == .first)
        #expect(CommuteProbe.transition(prev: .unknown, new: .outside) == .first)
        #expect(CommuteProbe.transition(prev: .outside, new: .inside) == .entry)
        #expect(CommuteProbe.transition(prev: .inside, new: .outside) == .exit)
        #expect(CommuteProbe.transition(prev: .inside, new: .inside) == .same)
        #expect(CommuteProbe.transition(prev: .outside, new: .outside) == .same)
        #expect(CommuteProbe.transition(prev: .inside, new: .unknown) == .same)
        #expect(CommuteProbe.transition(prev: .unknown, new: .unknown) == .same)
    }

    @Test("accuracy buckets and 10 m rounding")
    func buckets() {
        #expect(CommuteProbe.accuracyBucket(-1) == "bad")
        #expect(CommuteProbe.accuracyBucket(.nan) == "bad")
        #expect(CommuteProbe.accuracyBucket(4.9) == "<10")
        #expect(CommuteProbe.accuracyBucket(10) == "<20")
        #expect(CommuteProbe.accuracyBucket(65) == "<100")
        #expect(CommuteProbe.accuracyBucket(499.9) == "<500")
        #expect(CommuteProbe.accuracyBucket(500) == ">=500")
        #expect(CommuteProbe.roundTo10(144) == 140)
        #expect(CommuteProbe.roundTo10(145) == 150)
        #expect(CommuteProbe.roundTo10(-3) == 0)
    }

    @Test("fix stats: gaps on receipt time, > 60 s counted, out-of-order receipt never negative")
    func fixStats() {
        var s = ProbeFixStats()
        #expect(s.add(wallMs: 10_000) == nil)
        #expect(s.add(wallMs: 11_000) == nil)
        #expect(s.add(wallMs: 71_000) == nil)  // exactly 60 s: not a big gap
        #expect(s.add(wallMs: 141_001) == 70_001)
        #expect(s.add(wallMs: 140_000) == nil)  // earlier than last: gap 0, last unchanged
        #expect(s.count == 5)
        #expect(s.firstWallMs == 10_000)
        #expect(s.lastWallMs == 141_001)
        #expect(s.maxGapMs == 70_001)
        #expect(s.bigGaps == 1)
    }

    @Test("median is the lower median; nil when empty")
    func median() {
        #expect(CommuteProbe.median([]) == nil)
        #expect(CommuteProbe.median([5]) == 5)
        #expect(CommuteProbe.median([9, 1, 4, 7]) == 4)
        #expect(CommuteProbe.median([3, 1, 2]) == 2)
    }

    @Test("local stamp: offset, day change, leap day 2028")
    func stamp() {
        // 2026-11-13T00:30:00Z
        let t: Int64 = 1_762_993_800_000 + 365 * 86_400_000
        #expect(CommuteProbe.localStamp(t, utcOffsetS: 7 * 3600) == "13/11 07:30")
        #expect(CommuteProbe.localStamp(t, utcOffsetS: -3600) == "12/11 23:30")
        // 2028-02-29T23:59:00Z
        #expect(CommuteProbe.localStamp(1_835_481_540_000, utcOffsetS: 0) == "29/02 23:59")
        #expect(CommuteProbe.localStamp(1_835_481_540_000, utcOffsetS: 60) == "01/03 00:00")
        #expect(CommuteProbe.localStamp(0, utcOffsetS: 0) == "01/01 00:00")
    }

    @Test("relaunched = background launch, first event of the process, within 120 s")
    func relaunched() {
        #expect(Self.event().relaunched)
        #expect(!Self.event(bg: false).relaunched)
        #expect(!Self.event(first: false).relaunched)
        #expect(!Self.event(procAgeS: 121).relaunched)
        #expect(Self.event().ageS == 8)
        #expect(Self.event(eventMs: nil).ageS == nil)
        #expect(Self.event(eventMs: 2_000_000).ageS == 0)
    }

    @Test("session passes with ≥ 60 min of fixes and no gap > 60 s")
    func sessionPass() {
        var r = ProbeWakeRecord(id: "w1", event: Self.event(receivedMs: 0), notStarted: nil, serviceSession: false)
        for m in stride(from: Int64(1_000), through: 3_600_000, by: 30_000) { r.stats.add(wallMs: m) }
        #expect(r.coveredMs < 3_600_000)
        #expect(!r.sessionPassed)
        r.stats.add(wallMs: 3_600_000)
        #expect(r.sessionPassed)
        r.stats.add(wallMs: 3_700_000)  // 100 s gap
        #expect(!r.sessionPassed)
        let skipped = ProbeWakeRecord(id: "w2", event: Self.event(), notStarted: "running", serviceSession: false)
        #expect(!skipped.started && !skipped.sessionPassed && skipped.coveredMs == 0)
    }

    @Test("trim keeps the newest events and wakes, clears a dropped active wake")
    func trim() {
        var f = CommuteProbeFile()
        for i in 0..<(CommuteProbe.maxEvents + 5) { f.events.append(Self.event(receivedMs: Int64(i))) }
        for i in 0..<(CommuteProbe.maxWakes + 2) {
            f.wakes.append(ProbeWakeRecord(id: "w\(i)", event: Self.event(), notStarted: nil, serviceSession: false))
        }
        f.activeWakeId = "w0"
        f.trim()
        #expect(f.events.count == CommuteProbe.maxEvents)
        #expect(f.events.first?.receivedWallMs == 5)
        #expect(f.wakes.count == CommuteProbe.maxWakes)
        #expect(f.wakes.first?.id == "w2")
        #expect(f.activeWakeId == nil)
        #expect(CommuteProbeFile.stateKey(.legacy, .b) == "legacy.B")
    }

    @Test("file round-trips through JSON")
    func codable() throws {
        var f = CommuteProbeFile()
        f.config = CommuteProbeConfig(apiMode: .both, serviceSession: true, holdMin: 70, alarmMin: 10, radiusM: 200,
                                      points: [.a, .b])
        f.states["clmonitor.A"] = .inside
        f.events = [Self.event()]
        var w = ProbeWakeRecord(id: "w", event: Self.event(), notStarted: nil, serviceSession: true)
        w.stats.add(wallMs: 5)
        w.firstFixDistM = 120
        w.alarm = "ok"
        f.wakes = [w]
        f.activeWakeId = "w"
        let back = try JSONDecoder().decode(CommuteProbeFile.self, from: JSONEncoder().encode(f))
        #expect(back == f)
    }

    @Test("report: per-API counts, delays, sessions, recent lines")
    func report() {
        var f = CommuteProbeFile()
        f.config = CommuteProbeConfig(apiMode: .clmonitor, serviceSession: false, holdMin: 70, alarmMin: 10, radiusM: 200,
                                      points: [.a])
        f.events = [Self.event(state: .outside, transition: .first, app: "active", bg: false)]
        var ok = ProbeWakeRecord(id: "w1", event: Self.event(eventMs: 0, receivedMs: 10_000), notStarted: nil,
                                 serviceSession: false)
        for m in stride(from: Int64(20_000), through: 3_700_000, by: 1_000) { ok.stats.add(wallMs: m) }
        ok.endedWallMs = 4_200_000
        ok.endReason = "hold"
        ok.alarm = "ok"
        ok.firstFixDistM = 80
        var running = ProbeWakeRecord(id: "w2", event: Self.event(eventMs: 0, receivedMs: 30_000, app: "background",
                                                                   procAgeS: 900, first: false),
                                      notStarted: nil, serviceSession: false)
        running.stats.add(wallMs: 40_000)
        let skipped = ProbeWakeRecord(id: "w3", event: Self.event(.clmonitor, .a, eventMs: 0, receivedMs: 50_000,
                                                                   app: "active", bg: false, first: false),
                                      notStarted: "running", serviceSession: false)
        f.wakes = [ok, running, skipped]
        f.activeWakeId = "w2"
        let live = ProbeLiveStatus(authorization: "Luôn", fullAccuracy: true, backgroundRefresh: "bật", lowPower: false,
                                   sessionRunning: true, monitored: ["CLMonitor A"])
        let text = CommuteProbe.report(f, live: live, utcOffsetS: 0)
        #expect(text.contains("Cấu hình: clmonitor, phiên Always: tắt, giữ 70 phút, báo sau 10 phút, bán kính 200 m, vùng: A"))
        #expect(text.contains("Quyền: Luôn · Làm mới nền: bật · Nguồn điện thấp: tắt"))
        #expect(text.contains("Hệ thống đang canh: CLMonitor A"))
        #expect(text.contains("CLMonitor: vào vùng 3 (khởi chạy lại 1, app đang mở 1, app còn chạy nền 1); trễ giao sự kiện trung vị 30 s, tối đa 50 s"))
        #expect(text.contains("Phiên: 2 bắt đầu, 1/1 đạt"))
        #expect(text.contains("Legacy: chưa có lần vào vùng"))
        #expect(text.contains("Lần xác định đầu: CLMonitor A ngoài"))
        #expect(text.contains("01/01 00:00 CLMonitor A khởi chạy lại, trễ 10 s, phiên 61 phút, 3681 fix, trống tối đa 1 s, fix đầu cách tâm 80 m, báo: ok, kết thúc: hold"))
        #expect(text.contains("app còn chạy nền, trễ 30 s, phiên 0 phút, 1 fix, trống tối đa 0 s, kết thúc: đang chạy"))
        #expect(text.contains("app đang mở, trễ 50 s, không bật: running"))
        let empty = CommuteProbe.report(CommuteProbeFile(), live: live, utcOffsetS: 0)
        #expect(empty.contains("Cấu hình: chưa đặt vùng"))
    }
}
