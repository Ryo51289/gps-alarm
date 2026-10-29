import Foundation
import XCTest
@testable import ProbeCore

final class TriggerLogicTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_793_284_000)

    // U4
    func testShouldFire() {
        let deadline = t0
        XCTAssertFalse(TriggerLogic.shouldFire(now: deadline.addingTimeInterval(-0.001), deadline: deadline, alreadyFired: false))
        XCTAssertTrue(TriggerLogic.shouldFire(now: deadline, deadline: deadline, alreadyFired: false))
        XCTAssertTrue(TriggerLogic.shouldFire(now: deadline.addingTimeInterval(5), deadline: deadline, alreadyFired: false))
        for offset in [-0.001, 0, 5] {
            XCTAssertFalse(
                TriggerLogic.shouldFire(now: deadline.addingTimeInterval(offset), deadline: deadline, alreadyFired: true)
            )
        }
    }

    // U5
    func testIsRescheduleDue() {
        let now = t0.addingTimeInterval(300)
        XCTAssertTrue(TriggerLogic.isRescheduleDue(last: nil, now: now))
        XCTAssertTrue(TriggerLogic.isRescheduleDue(last: t0, now: now))
        XCTAssertFalse(TriggerLogic.isRescheduleDue(last: t0.addingTimeInterval(1), now: now))
        XCTAssertFalse(TriggerLogic.isRescheduleDue(last: t0.addingTimeInterval(299), now: now))
        XCTAssertTrue(TriggerLogic.isRescheduleDue(last: t0, now: t0.addingTimeInterval(301)))
    }

    /// Review #2: the 5-minute delay makes the re-arm due exactly at the deadline; it must not run then.
    func testShouldRescheduleIsQuietNearAndAfterDeadline() {
        let deadline = t0.addingTimeInterval(300)
        XCTAssertFalse(TriggerLogic.shouldReschedule(last: t0, now: deadline, deadline: deadline, fired: false))
        XCTAssertFalse(TriggerLogic.shouldReschedule(last: t0, now: deadline.addingTimeInterval(0.4), deadline: deadline, fired: false))
        XCTAssertFalse(TriggerLogic.shouldReschedule(last: nil, now: deadline.addingTimeInterval(-30), deadline: deadline, fired: false))
        XCTAssertTrue(TriggerLogic.shouldReschedule(last: nil, now: deadline.addingTimeInterval(-30.5), deadline: deadline, fired: false))
        XCTAssertFalse(TriggerLogic.shouldReschedule(last: nil, now: deadline.addingTimeInterval(-60), deadline: deadline, fired: true))
        let longDeadline = t0.addingTimeInterval(36_000)
        XCTAssertTrue(TriggerLogic.shouldReschedule(last: t0, now: t0.addingTimeInterval(300), deadline: longDeadline, fired: false))
        XCTAssertFalse(TriggerLogic.shouldReschedule(last: t0, now: t0.addingTimeInterval(299), deadline: longDeadline, fired: false))
    }

    // U6
    func testPhaseWithoutSparsePart() {
        XCTAssertEqual(TriggerLogic.phase(now: t0, runStart: t0, durationS: 600, densePhaseS: 1200), .dense)
    }

    func testPhaseBoundaryOfLongRun() {
        let duration: TimeInterval = 10 * 3600
        let dense: TimeInterval = 20 * 60
        let boundary = t0.addingTimeInterval(duration - dense)
        XCTAssertEqual(TriggerLogic.phase(now: t0, runStart: t0, durationS: duration, densePhaseS: dense), .sparse)
        XCTAssertEqual(
            TriggerLogic.phase(now: boundary.addingTimeInterval(-1), runStart: t0, durationS: duration, densePhaseS: dense),
            .sparse
        )
        XCTAssertEqual(TriggerLogic.phase(now: boundary, runStart: t0, durationS: duration, densePhaseS: dense), .dense)
    }

    func testPrearmDateAndTimeout() {
        XCTAssertEqual(TriggerLogic.prearmDate(deadline: t0), t0.addingTimeInterval(60))
        XCTAssertFalse(TriggerLogic.isTimedOut(now: t0.addingTimeInterval(599), deadline: t0))
        XCTAssertTrue(TriggerLogic.isTimedOut(now: t0.addingTimeInterval(600), deadline: t0))
    }
}

final class WavToneTests: XCTestCase {
    private func u16(_ d: [UInt8], _ at: Int) -> Int { Int(d[at]) | Int(d[at + 1]) << 8 }

    private func u32(_ d: [UInt8], _ at: Int) -> Int {
        Int(d[at]) | Int(d[at + 1]) << 8 | Int(d[at + 2]) << 16 | Int(d[at + 3]) << 24
    }

    private func ascii(_ d: [UInt8], _ at: Int) -> String { String(decoding: d[at..<(at + 4)], as: UTF8.self) }

    private func sample(_ d: [UInt8], _ index: Int) -> Int16 {
        Int16(bitPattern: UInt16(u16(d, 44 + index * 2)))
    }

    // U3
    func testDefaultToneLayout() {
        let d = [UInt8](WavTone.make())
        XCTAssertEqual(d.count, 44 + 2_557_800)
        XCTAssertEqual(ascii(d, 0), "RIFF")
        XCTAssertEqual(u32(d, 4), 36 + 2_557_800)
        XCTAssertEqual(ascii(d, 8), "WAVE")
        XCTAssertEqual(ascii(d, 12), "fmt ")
        XCTAssertEqual(u32(d, 16), 16)
        XCTAssertEqual(u16(d, 20), 1)          // PCM
        XCTAssertEqual(u16(d, 22), 1)          // mono
        XCTAssertEqual(u32(d, 24), 44_100)
        XCTAssertEqual(u32(d, 28), 88_200)
        XCTAssertEqual(u16(d, 32), 2)
        XCTAssertEqual(u16(d, 34), 16)
        XCTAssertEqual(ascii(d, 36), "data")
        XCTAssertEqual(u32(d, 40), 2_557_800)

        XCTAssertEqual(sample(d, 0), 0)        // fade in
        // Second 2 (index 1): first half has sound, second half is silent.
        var peak = 0
        for i in 44_100..<(44_100 + 22_050) { peak = max(peak, abs(Int(sample(d, i)))) }
        XCTAssertGreaterThan(peak, 20_000)
        for i in (44_100 + 22_050)..<88_200 where sample(d, i) != 0 {
            return XCTFail("sample \(i) should be silent")
        }
    }

    func testShortTone() {
        let d = [UInt8](WavTone.make(seconds: 1, sampleRate: 8000, freq: 440, amplitude: 0.5))
        XCTAssertEqual(d.count, 44 + 16_000)
        var peak = 0
        for i in 0..<4000 { peak = max(peak, abs(Int(sample(d, i)))) }
        XCTAssertLessThanOrEqual(peak, 16_384)
        XCTAssertGreaterThan(peak, 15_000)
    }
}
