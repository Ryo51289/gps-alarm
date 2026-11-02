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
