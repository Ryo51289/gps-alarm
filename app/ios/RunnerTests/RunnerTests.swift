import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
  }

}

// T14.1 tester additions (pure parts of the iOS stub). Not run yet: needs a Mac / CI macOS
// (`xcodebuild test -workspace ios/Runner.xcworkspace -scheme dev`); typechecked on WSL only.

final class DeviceStatusStubTests: XCTestCase {
  func testBatteryLevelRoundsToNearestPercent() {
    let cases: [(Float, Int64?)] = [
      (0.0, 0), (0.004, 0), (0.006, 1), (0.57, 57), (0.996, 100), (1.0, 100),
      (-1.0, nil),  // monitoring off or simulator
      (1.01, nil), (-0.01, nil), (.nan, nil), (.infinity, nil),
    ]
    for (level, pct) in cases {
      let status = CoreBridgeStub.deviceStatus(batteryLevel: level, batteryState: .unplugged)
      XCTAssertEqual(status.batteryPct, pct, "level \(level)")
    }
  }

  func testChargingFromBatteryState() {
    let cases: [(UIDevice.BatteryState, Bool?)] = [
      (.charging, true), (.full, true), (.unplugged, false), (.unknown, nil),
    ]
    for (state, charging) in cases {
      XCTAssertEqual(
        CoreBridgeStub.deviceStatus(batteryLevel: 0.5, batteryState: state).charging, charging)
    }
  }

  func testOnlyBatteryIsKnownOnIOS() {
    let status = CoreBridgeStub.deviceStatus(batteryLevel: 0.5, batteryState: .full)
    XCTAssertNil(status.alarmVolumePct)
    XCTAssertNil(status.alarmMuted)
    XCTAssertNil(status.priorityAllowsAlarms)
    XCTAssertEqual(status.interruptionFilter, .unknown)
    XCTAssertEqual(InterruptionFilterMsg.none.rawValue, 4)
    XCTAssertEqual(InterruptionFilterMsg.alarms.rawValue, 3)
  }

  private func config(_ json: String?) -> TripConfigMsg {
    TripConfigMsg(
      tripId: "t1", destinationName: "Ga Đông Hà", mode: .smart, distanceThresholdM: nil,
      timeThresholdMin: nil, preAlertEnabled: true, vehicleHint: .train,
      alarm: AlarmSettingsMsg(
        soundId: "default", volume: 0.8, rampUp: true, vibration: .medium, flash: false,
        preferHeadphones: false, dismissMethod: .swipe),
      engineParamsJson: json)
  }

  func testV11CountsUTF16CodeUnits() throws {
    let emoji = "\u{1F634}"
    for ok in [nil, "", String(repeating: "x", count: 16_384), String(repeating: emoji, count: 8_192)] {
      XCTAssertNoThrow(try CoreBridgeStub.checkEngineParams(config(ok)))
    }
    for tooLong in [
      String(repeating: "x", count: 16_385), String(repeating: emoji, count: 8_192) + "x",
    ] {
      XCTAssertThrowsError(try CoreBridgeStub.checkEngineParams(config(tooLong))) { error in
        let e = error as? PigeonError
        XCTAssertEqual(e?.code, "invalid-config")
        XCTAssertEqual(e?.message, "engineParamsJson: too long")
        XCTAssertNil(e?.details)
      }
    }
  }
}

// T17 IC03 (spec docs/specs/T17.md): MsgMapper copies BridgeDTO into Pigeon; StartOutcome → PigeonError.
// Runs on CI macOS (Simulator); typechecked on WSL only.

import Trip
import TripRuntime

final class T17MsgMapperTests: XCTestCase {
  func testStateCopiesEveryField() throws {
    let cfg = TripConfig(
      tripId: "t1", destLat: 16.8163, destLng: 107.1003, mode: .distance, distanceThresholdM: 1000,
      timeThresholdMin: nil, preAlertEnabled: false, vehicleHint: .coach)
    let view = try TripEngine.start(config: cfg, params: .defaults, nowMs: 1_000).view
    let dto = BridgeMapper.state(view: view, batteryChoice: .batteryAlarmAt5)
    let m = MsgMapper.state(dto)
    XCTAssertEqual(m.tripId, "t1")
    XCTAssertEqual(m.atMs, dto.atMs)
    XCTAssertEqual(m.phase, .acquiring)
    XCTAssertEqual(m.gps, .noFixYet)
    XCTAssertEqual(m.locationCause, .available)
    XCTAssertEqual(m.samplingTier, dto.samplingTier.map(MsgMapper.tier))
    XCTAssertEqual(m.fallbackStatus, MsgMapper.fallback(dto.fallbackStatus))
    XCTAssertEqual(m.fallbackAtMs, dto.fallbackAtMs)
    XCTAssertEqual(m.batteryChoice, .alarmAt5)
    XCTAssertEqual(m.vehicleGuess, MsgMapper.vehicle(dto.vehicleGuess))
    XCTAssertEqual(m.travelledM, dto.travelledM)
    XCTAssertEqual(MsgMapper.fallback(.notSet), .notSet)
    XCTAssertEqual(MsgMapper.reason(.smartSlowDistance), .smartSlowDistance)
  }

  func testUpdatesKeepClassAndOrder() {
    let rec = FinishedRecord(
      tripId: "t1", outcome: "ON_TIME", endReason: "DISMISSED", endedAtMs: 9, startedAtMs: 1, alarmAtMs: 5,
      alarmReason: "DISTANCE", dismissedAtMs: 9, snoozeCount: 0, travelledM: 10, vehicleGuess: "BUS")
    let fin = BridgeMapper.finished(rec)!
    let msgs = [
      TripUpdateDTO.alarm(
        tripId: "t1", atMs: 5, reason: .distance, ringNow: true, snoozeAllowed: true, distanceM: 900, etaS: nil,
        batteryPct: nil),
      .tripEnded(atMs: 9, trip: fin),
    ].map(MsgMapper.msg)
    XCTAssertTrue(msgs[0] is AlarmMsg)
    XCTAssertEqual((msgs[1] as? TripEndedMsg)?.trip.outcome, .onTime)
    XCTAssertEqual((msgs[1] as? TripEndedMsg)?.trip.endReason, .dismissed)
  }

  func testConfigRoundTrip() {
    let c = TripConfigMsg(
      tripId: "t1", destinationName: "Ga Huế", mode: .time, distanceThresholdM: nil, timeThresholdMin: 15,
      preAlertEnabled: true, vehicleHint: .train,
      alarm: AlarmSettingsMsg(
        soundId: "default", volume: 0.5, rampUp: false, vibration: .strong, flash: true, preferHeadphones: true,
        dismissMethod: .math),
      engineParamsJson: nil)
    XCTAssertEqual(MsgMapper.config(MsgMapper.meta(c)), c)
  }

  func testRejectedOutcomeIsPigeonError() {
    XCTAssertNil(RealTripBackend.error(.started))
    let e = RealTripBackend.error(.rejected(code: "permission-missing", message: nil, details: ["precise", "alarmChannel"]))
    XCTAssertEqual(e?.code, "permission-missing")
    XCTAssertEqual(e?.details as? [String], ["precise", "alarmChannel"])
  }

  func testUnexpectedErrorBecomesInternalWithTypeName() async {
    struct Boom: Error {}
    do {
      _ = try await CoreBridgeStub.guarded { () async throws -> Int in throw Boom() }
      XCTFail("no error")
    } catch let e as PigeonError {
      XCTAssertEqual(e.code, "internal")
      XCTAssertEqual(e.message, "Boom")
    } catch {
      XCTFail("\(error)")
    }
  }
}
