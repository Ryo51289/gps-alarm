import Foundation
import Testing
@testable import Trip
@testable import TripRuntime

/// T18.1 SIU01–SIU09 (docs/specs/T18.1.md): trip clock with a speed factor (parity Kotlin SM01–SM03, SM08), snapshot and
/// ledger keys, GPX reader (parity SM06 + the test GPX reader), SimDriver (SM07, D3).
@Suite("SimPure")
struct SimPureTests {
    // MARK: Clock

    @Test("SIU01 speed 1.0 gives the T17 results to the millisecond (IU01–IU03 numbers), futureWallToTrip = now + d")
    func siu01() {
        let t = VirtualTime(wallBase: 1_000_000, elapsedBase: 50_000)
        var c = TripClock(anchor: .now(t))
        #expect(c.speed == 1.0)
        t.v = 30_000
        t.shiftWall(-10_000)
        #expect(c.now(t) == 1_030_000)
        t.setElapsed(70_000)
        #expect(c.now(t) == 1_030_000)
        let t3 = VirtualTime(wallBase: 2_000_000)
        var c3 = TripClock(anchor: ClockAnchor(wallMs: 1_000_000, elapsedMs: t3.elapsedMs(), bootSessionId: "A"))
        #expect(c3.toWall(1_060_000, t3) == 2_060_000)
        #expect(c3.toWall(990_000, t3) == 2_000_000)
        #expect(c3.toTrip(wall: 1_995_000, t3) == 995_000)
        #expect(c3.toTrip(wall: 2_500_000, t3) == 1_000_000)
        #expect(c3.futureWallToTrip(t3.wallMs() + 5_000, t3) == c3.now(t3) + 5_000)
        #expect(c3.futureWallToTrip(t3.wallMs() - 5_000, t3) == c3.now(t3))
        #expect(c3.realDelayMs(1_060_000, t3) == 60_000)
        #expect(c3.realDelayMs(900_000, t3) == 0)
        #expect(ClockAnchor.now(t3).speed == 1.0)
        #expect(TripClock.anchorValid(ClockAnchor(wallMs: 1, elapsedMs: t3.elapsedMs(), bootSessionId: "A", speed: 60),
                                      t3, driftMaxMs: Int64.max / 4))
    }

    @Test("SIU02 speed 60 converts both ways (= Kotlin SM02)")
    func siu02() {
        let t = VirtualTime(wallBase: 1_000_000, elapsedBase: 50_000)
        var c = TripClock(anchor: ClockAnchor(wallMs: 1_000_000, elapsedMs: 50_000, bootSessionId: "A", speed: 60))
        t.v = 1_000
        let now = c.now(t)
        #expect(now == 1_060_000)
        #expect(c.toWall(now + 60_000, t) == t.wallMs() + 1_000)
        #expect(c.toTrip(wall: t.wallMs() - 1_000, t) == now - 60_000)
        #expect(c.realDelayMs(now + 59_999, t) == 1_000)  // ceil
        #expect(c.futureWallToTrip(t.wallMs() + 5_000, t) == now + 300_000)
    }

    @Test("SIU03 rebase(1.0) is continuous and never goes back (= Kotlin SM03); bad speeds refused; D8 rebase at the event time")
    func siu03() {
        let t = VirtualTime(wallBase: 1_000_000, elapsedBase: 50_000)
        var c = TripClock(anchor: ClockAnchor(wallMs: 1_000_000, elapsedMs: 50_000, bootSessionId: "A", speed: 60))
        t.v = 2_000
        let n = c.now(t)
        #expect(n == 1_120_000)
        c.rebase(1.0, t)
        #expect(c.speed == 1.0)
        #expect(c.now(t) == n)
        t.v += 1_000
        #expect(c.now(t) == n + 1_000)
        #expect(c.anchor.bootSessionId == "A")
        // Round 2 (review nit): a bad speed is refused like Kotlin SM03 (which throws); the clock is unchanged.
        let before = c.anchor
        let refused = [c.rebase(0, t), c.rebase(.nan, t), c.rebase(-1, t), c.rebase(.infinity, t), c.rebase(0, t, atTripMs: n)]
        #expect(refused == [false, false, false, false, false])
        #expect(c.anchor == before)
        // D8 round 2: restart at 1× from the event time of the Step (the catch-up ran behind the clock).
        var late = TripClock(anchor: ClockAnchor(wallMs: 1_000_000, elapsedMs: t.elapsedMs(), bootSessionId: "A", speed: 600))
        t.v += 2_000  // timer 2 s late: the clock is 1 200 trip s ahead of the event
        #expect(late.now(t) == 2_200_000)
        let okLate = late.rebase(1.0, t, atTripMs: 1_000_000 + 60_000)
        #expect(okLate)
        #expect(late.now(t) == 1_060_000)
        #expect(late.speed == 1.0)
        t.v += 1_000
        #expect(late.now(t) == 1_061_000)
        let okHigh = late.rebase(1.0, t, atTripMs: 9_999_999_999)  // above now: clamped to now
        #expect(okHigh)
        #expect(late.now(t) == 1_061_000)
    }

    @Test("SIU08 after rebase(1.0) at trip 300 s the sample at 600 s is 300 000 real ms away (= SM08)")
    func siu08() {
        let t = VirtualTime(wallBase: 1_000_000)
        var c = TripClock(anchor: ClockAnchor(wallMs: 1_000_000, elapsedMs: t.elapsedMs(), bootSessionId: "A", speed: 60))
        let start = c.now(t)
        var d = SimDriver(trace: SimTrace(id: "x", samples: [sample(0), sample(600)]), startTripMs: start)
        #expect(d.pop(upTo: c.now(t), intervalMs: 5_000) == .sample(sample(0), atTripMs: start))
        t.v = 5_000  // trip 300 s
        #expect(c.now(t) == start + 300_000)
        #expect(c.realDelayMs(d.nextDueTripMs(intervalMs: 5_000)!, t) == 5_000)
        c.rebase(1.0, t)
        #expect(c.realDelayMs(d.nextDueTripMs(intervalMs: 5_000)!, t) == 300_000)
    }

    // MARK: Codec

    /// The T17 snapshot shape (synthesized coding): a real trip must still encode to exactly these bytes.
    private struct T17Anchor: Codable { var wallMs: Int64; var elapsedMs: Int64; var bootSessionId: String? }
    private struct T17Meta: Codable {
        var tripId: String; var destinationName: String; var mode: String; var distanceThresholdM: Int?
        var timeThresholdMin: Int?; var preAlertEnabled: Bool; var vehicleHint: String; var alarm: RingSettings
        var engineParamsJson: String?
    }
    private struct T17Trip: Codable {
        var runtimeVersion: Int; var meta: T17Meta; var anchor: T17Anchor; var engineSnapshot: String; var savedAtWallMs: Int64
    }

    @Test("SIU04 snapshot: a real trip keeps the T17 bytes; a simulated one round-trips; bad speed is an error")
    func siu04() throws {
        let meta = TestData.meta()
        let real = StoredTrip(meta: meta, anchor: ClockAnchor(wallMs: 1_700_000_000_000, elapsedMs: 1_000_000, bootSessionId: "A"),
                              engineSnapshot: "{}", savedAtWallMs: 1_700_000_000_500)
        let bytes = StoredTripCodec.encode(real)
        let legacy = T17Trip(runtimeVersion: 1,
                             meta: T17Meta(tripId: "t1", destinationName: meta.destinationName, mode: "distance",
                                           distanceThresholdM: 1000, timeThresholdMin: nil, preAlertEnabled: false,
                                           vehicleHint: "train", alarm: meta.alarm, engineParamsJson: nil),
                             anchor: T17Anchor(wallMs: 1_700_000_000_000, elapsedMs: 1_000_000, bootSessionId: "A"),
                             engineSnapshot: "{}", savedAtWallMs: 1_700_000_000_500)
        #expect(bytes == (try LedgerCodec.encode(legacy)))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("speed") && !text.contains("simulation"))
        #expect(try StoredTripCodec.decode(bytes) == real)

        let simMeta = meta.with(simulation: SimSpec(traceId: "train_hn_dh", speedFactor: 60))
        let sim = StoredTrip(meta: simMeta, anchor: ClockAnchor(wallMs: 1, elapsedMs: 2, bootSessionId: nil, speed: 60),
                             engineSnapshot: "{}", savedAtWallMs: 3)
        let simBytes = StoredTripCodec.encode(sim)
        #expect(try StoredTripCodec.decode(simBytes) == sim)
        let simText = String(decoding: simBytes, as: UTF8.self)
        #expect(simText.contains("\"speed\":60") && simText.contains("\"traceId\":\"train_hn_dh\""))
        for bad in ["0", "-1", "\"NaN\"", "1e999"] {
            let broken = simText.replacingOccurrences(of: "\"speed\":60", with: "\"speed\":\(bad)")
            #expect(throws: StoredTripError.corrupt) { try StoredTripCodec.decode(Data(broken.utf8)) }
        }
        let badFactor = simText.replacingOccurrences(of: "\"speedFactor\":60", with: "\"speedFactor\":0")
        #expect(throws: StoredTripError.corrupt) { try StoredTripCodec.decode(Data(badFactor.utf8)) }
        #expect(!simMeta.description.contains(meta.destinationName))
        #expect(simMeta.description.contains("simulated=true"))
        #expect(meta.description.contains("simulated=false"))
    }

    @Test("SIU05 ledger: activeSimulated round-trips, false writes no key, a T17 ledger still decodes")
    func siu05() throws {
        var l = AlarmLedger.empty
        l.activeTripId = "t1"
        l.activeSimulated = true
        let d = try LedgerCodec.encode(l)
        #expect(String(decoding: d, as: UTF8.self).contains("\"activeSimulated\":true"))
        #expect(try LedgerCodec.decode(AlarmLedger.self, d) == l)
        l.activeSimulated = false
        let d2 = try LedgerCodec.encode(l)
        #expect(!String(decoding: d2, as: UTF8.self).contains("activeSimulated"))
        #expect(try LedgerCodec.decode(AlarmLedger.self, d2) == l)
        let t17 = #"{"activeTripId":"t1","endedTripIds":["a"],"interruptedAlerted":true,"ledgerVersion":1,"nextGeneration":4}"#
        let old = try LedgerCodec.decode(AlarmLedger.self, Data(t17.utf8))
        #expect(old.activeTripId == "t1" && old.nextGeneration == 4 && old.interruptedAlerted && !old.activeSimulated)
        #expect(try LedgerCodec.encode(old) == Data(t17.utf8))
    }

    // MARK: GPX

    static let gpxIds: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: RTPaths.tracesDir)) ?? []
        return names.filter { $0.hasSuffix(".gpx") }.map { String($0.dropLast(4)) }
            .filter { FileManager.default.fileExists(atPath: "\(RTPaths.tracesDir)/\($0).expect.json") }.sorted()
    }()

    @Test("SIU06 every fixture GPX: count, duration, gaps (= SM06) and bit-equal to the test GPX reader", arguments: gpxIds)
    func siu06(_ id: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.tracesDir)/\(id).gpx"))
        let samples = try TraceGpx.parse(data)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.tracesDir)/\(id).expect.json")))
            as? [String: Any] ?? [:]
        let trace = json["trace"] as? [String: Any] ?? [:]
        #expect(samples.count == (trace["sampleCount"] as? NSNumber)?.intValue, "\(id) sampleCount")
        #expect(samples.first?.t == 0)
        #expect(samples.last?.t == (trace["durationS"] as? NSNumber)?.intValue, "\(id) durationS")
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0.t < $1.t })
        let gaps = (json["truth"] as? [String: Any])?["gpsGaps"] as? [[String: Any]] ?? []
        for g in gaps {
            let from = (g["fromT"] as? NSNumber)?.intValue ?? 0, to = (g["toT"] as? NSNumber)?.intValue ?? 0
            #expect(!samples.contains { $0.t >= from && $0.t < to }, "\(id): sample in gap")
        }
        let (_, ref) = try RuntimeFixtures.readGpx(String(decoding: data, as: UTF8.self))
        #expect(ref.count == samples.count)
        for (a, b) in zip(ref, samples) {
            #expect(a.t == b.t)
            #expect(a.lat.bitPattern == b.lat.bitPattern && a.lng.bitPattern == b.lng.bitPattern, "\(id) t=\(a.t) position")
            #expect(a.accuracyM.bitPattern == b.accM.bitPattern, "\(id) t=\(a.t) acc")
            #expect(a.speedMps?.bitPattern == b.spdMps?.bitPattern, "\(id) t=\(a.t) spd")
        }
    }

    @Test("SIU06 train_longstop_nospd has samples without speed")
    func siu06NoSpeed() throws {
        let s = try TraceGpx.parse(Data(contentsOf: URL(fileURLWithPath: "\(RTPaths.tracesDir)/train_longstop_nospd.gpx")))
        #expect(s.contains { $0.spdMps == nil } && s.contains { $0.spdMps != nil })
    }

    static let head = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1" xmlns:napstop="https://napstop.app/xmlns/trace/1">
          <metadata><time>2026-03-14T02:00:00Z</time></metadata>
          <trk><trkseg>

        """
    static let tail = "  </trkseg></trk>\n</gpx>\n"

    static func pt(lat: String = "16.0549823", time: String = "2026-03-14T02:00:00Z", acc: String? = "8.1", spd: String? = "0.17")
        -> String {
        "<trkpt lat=\"\(lat)\" lon=\"108.1733614\"><time>\(time)</time><extensions>"
            + (acc.map { "<napstop:acc>\($0)</napstop:acc>" } ?? "") + (spd.map { "<napstop:spd>\($0)</napstop:spd>" } ?? "")
            + "</extensions></trkpt>\n"
    }

    static func rule(_ xml: String) -> String? {
        do {
            _ = try TraceGpx.parse(Data(xml.utf8))
            return nil
        } catch {
            return error.rule
        }
    }

    @Test("SIU06 broken GPX: TraceFormatError naming the rule only (same rules as Kotlin)")
    func siu06Errors() throws {
        let h = Self.head, t = Self.tail
        let ok = try TraceGpx.parse(Data((h + Self.pt() + Self.pt(time: "2026-03-14T02:00:05Z", spd: nil) + "</trkseg><trkseg>"
            + Self.pt(time: "2026-03-14T02:01:00Z") + t).utf8))
        #expect(ok.map(\.t) == [0, 5, 60])
        #expect(ok[1].spdMps == nil)
        #expect(ok[0].accM == 8.1 && ok[0].spdMps == 0.17)
        let full = h + Self.pt() + Self.pt(time: "2026-03-14T02:00:05Z") + t
        let cases: [(String, String)] = [
            (String(full.prefix(full.count / 2 + 40)), "xml malformed"),
            (h + Self.pt(acc: nil) + t, "acc missing"),
            (h + Self.pt(acc: "0") + t, "acc invalid"),
            (h + Self.pt(acc: "NaN") + t, "acc invalid"),
            (h + Self.pt(spd: "-1") + t, "spd invalid"),
            (h + Self.pt() + Self.pt() + t, "time not increasing"),
            (h + Self.pt() + Self.pt(time: "2026-03-14T01:59:00Z") + t, "time not increasing"),
            (h + Self.pt(time: "yesterday") + t, "time invalid"),
            (h + Self.pt(lat: "91.5") + t, "lat out of range"),
            (h + t, "no trkpt"),
        ]
        for (xml, expected) in cases {
            let r = Self.rule(xml)
            #expect(r == expected, "expected \(expected)")
            #expect(!(r ?? "").contains { $0.isNumber }, "no value in \(r ?? "")")
        }
        let frac = try TraceGpx.parse(Data((h + Self.pt() + Self.pt(time: "2026-03-14T02:00:05.000Z") + t).utf8))
        #expect(frac.map(\.t) == [0, 5])
        #expect(frac.map(\.tMs) == [0, 5_000])
        // Round 2 (review nit): milliseconds are kept; two samples in the same second stay strictly increasing.
        let ms = try TraceGpx.parse(Data((h + Self.pt() + Self.pt(time: "2026-03-14T02:00:00.500Z")
            + Self.pt(time: "2026-03-14T02:00:01.250Z") + t).utf8))
        #expect(ms.map(\.tMs) == [0, 500, 1_250])
        #expect(ms.map(\.t) == [0, 0, 1])
        var d = SimDriver(trace: SimTrace(id: "ms", samples: ms), startTripMs: 10_000)
        var at: [Int64] = []
        while let e = d.pop(upTo: .max, intervalMs: 500) { at.append(e.atTripMs) }
        #expect(at == [10_000, 10_500, 11_250])
        #expect(!TraceSample(t: 1, lat: 16.0549823, lng: 108.1733614, accM: 8, spdMps: nil).description.contains("16.05"))
    }

    @Test("SIU06 trace ids: never a path")
    func traceIds() {
        for ok in ["train_hn_dh", "a", "a1_b2", String(repeating: "a", count: 64)] { #expect(SimTraceIds.valid(ok), "\(ok)") }
        for bad in ["stub/normal", "../x", "UPPER", "", "_a", "a_", "a__b", "a-b", "a.gpx", String(repeating: "a", count: 65)] {
            #expect(!SimTraceIds.valid(bad), "\(bad)")
        }
    }

    // MARK: SimDriver

    static func sample(_ t: Int) -> TraceSample { TraceSample(t: t, lat: 16, lng: 107, accM: 8, spdMps: 1) }
    func sample(_ t: Int) -> TraceSample { Self.sample(t) }

    static func times(_ d: inout SimDriver, upTo: Int64, _ interval: Int64?, start: Int64) -> [Int] {
        var out: [Int] = []
        while let e = d.pop(upTo: start + upTo * 1000, intervalMs: interval) {
            if case let .sample(s, at) = e {
                #expect(at == start + Int64(s.t) * 1000)
                out.append(s.t)
            }
        }
        return out
    }

    @Test("SIU07 policy sampling: 30 s, then 5 s, no request, 5 s again: no late delivery (= SM07)")
    func siu07() {
        let start: Int64 = 1_000_000
        var d = SimDriver(trace: SimTrace(id: "x", samples: (0...10).map { sample($0 * 5) }), startTripMs: start)
        #expect(d.nextDueTripMs(intervalMs: 30_000) == start)
        var got = Self.times(&d, upTo: 31, 30_000, start: start)
        #expect(got == [0, 30])
        #expect(d.nextDueTripMs(intervalMs: 5_000) == start + 35_000)
        got += Self.times(&d, upTo: 41, 5_000, start: start)
        #expect(got == [0, 30, 35, 40])
        #expect(d.nextDueTripMs(intervalMs: nil) == nil)
        got += Self.times(&d, upTo: 49, nil, start: start)
        got += Self.times(&d, upTo: 50, 5_000, start: start)
        #expect(got == [0, 30, 35, 40, 50])
        got += Self.times(&d, upTo: 100, 5_000, start: start)
        #expect(got == [0, 30, 35, 40, 50])
        #expect(d.traceEnded)
        #expect(d.nextDueTripMs(intervalMs: 5_000) == nil)
    }

    @Test("SIU09 same trip time: fallback → engine wake → sample (D3); a past wake comes out at the cursor")
    func siu09() {
        let start: Int64 = 0
        var d = SimDriver(trace: SimTrace(id: "x", samples: [sample(0), sample(10)]), startTripMs: start)
        d.engineWakeTripMs = 10_000
        d.fallbackDueTripMs = 10_000
        #expect(d.pop(upTo: 9_999, intervalMs: 5_000) == .sample(sample(0), atTripMs: 0))
        #expect(d.pop(upTo: 9_999, intervalMs: 5_000) == nil)
        #expect(d.nextDueTripMs(intervalMs: 5_000) == 10_000)
        #expect(d.pop(upTo: 10_000, intervalMs: 5_000) == .fallbackDue(atTripMs: 10_000))
        #expect(d.pop(upTo: 10_000, intervalMs: 5_000) == .engineWake(atTripMs: 10_000))
        #expect(d.pop(upTo: 10_000, intervalMs: 5_000) == .sample(sample(10), atTripMs: 10_000))
        d.engineWakeTripMs = 3_000  // set in the past by the Step of the last sample
        #expect(d.pop(upTo: 10_000, intervalMs: 5_000) == .engineWake(atTripMs: 10_000))
        #expect(d.pop(upTo: .max, intervalMs: 5_000) == nil)
    }
}
