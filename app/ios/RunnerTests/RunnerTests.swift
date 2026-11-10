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
      let status = DeviceBridge.deviceStatus(batteryLevel: level, batteryState: .unplugged)
      XCTAssertEqual(status.batteryPct, pct, "level \(level)")
    }
  }

  func testChargingFromBatteryState() {
    let cases: [(UIDevice.BatteryState, Bool?)] = [
      (.charging, true), (.full, true), (.unplugged, false), (.unknown, nil),
    ]
    for (state, charging) in cases {
      XCTAssertEqual(
        DeviceBridge.deviceStatus(batteryLevel: 0.5, batteryState: state).charging, charging)
    }
  }

  func testOnlyBatteryIsKnownOnIOS() {
    let status = DeviceBridge.deviceStatus(batteryLevel: 0.5, batteryState: .full)
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

// T17.1 PC02–PC04 (docs/specs/T17.1.md): IOSPermissionHostApi on a fake probe, settings pages, backup exclusion.
// Run on CI macOS (Simulator); typechecked on WSL by hand only (see the T17.1 Implementation notes).

import NapStopIOS

/// `requestLocation` waits until the test releases it.
final class GatedProbe: PermissionProbing, @unchecked Sendable {
  private let lock = NSLock()
  private var waiting: CheckedContinuation<Void, Never>?

  func readings() async -> PermissionReadings {
    PermissionReadings(
      location: .whenInUse, accuracy: .full, servicesEnabled: true, notifications: .authorized,
      alarmKit: .unavailable)
  }

  func requestLocation(timeoutMs: Int64) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
      lock.lock()
      waiting = c
      lock.unlock()
    }
  }

  func requestNotifications() async {}
  func requestAlarmKit() async {}

  func lastKnown() async -> (fix: RawFix?, authorized: Bool, servicesEnabled: Bool) {
    (nil, true, true)
  }

  func distancesM(from fix: RawFix, to pairs: [Double]) -> [Double] { [] }

  func isWaiting() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return waiting != nil
  }

  func release() {
    lock.lock()
    let c = waiting
    waiting = nil
    lock.unlock()
    c?.resume()
  }
}

final class T171PermissionTests: XCTestCase {
  private let device = DeviceInfoMsg(
    platform: .ios, manufacturer: "Apple", brand: "Apple", model: "iPhone", osVersion: "26.0",
    androidSdkInt: nil, iosMajor: 26)

  func testPC02SecondRequestWhileOneRunsIsRefused() async throws {
    let probe = GatedProbe()
    let api = IOSPermissionHostApi(probe: probe, device: device, openURL: { _ in })
    let first = Task { try await api.request(kind: .location) }
    for _ in 0..<400 where !probe.isWaiting() {
      try await Task.sleep(nanoseconds: 5_000_000)
    }
    XCTAssertTrue(probe.isWaiting())
    do {
      _ = try await api.request(kind: .notifications)
      XCTFail("no error")
    } catch let e as PigeonError {
      XCTAssertEqual(e.code, "request-in-progress")
    }
    probe.release()
    let status = try await first.value
    XCTAssertEqual(status.location, .whileInUse)
    XCTAssertEqual(status.precise, .granted)
    XCTAssertEqual(status.alarmKit, .notApplicable)
    // Free again once the first one returned.
    let again = try await api.request(kind: .notifications)
    XCTAssertEqual(again.notifications, .granted)
  }

  func testPC03OpenSettingsTargets() throws {
    var opened: [String] = []
    let api = IOSPermissionHostApi(probe: GatedProbe(), device: device, openURL: { opened.append($0.absoluteString) })
    for target in SettingsTargetMsg.allCases {
      let expected = target == .appDetails || target == .notifications
      XCTAssertEqual(try api.openSettings(target: target), expected, "\(target)")
    }
    XCTAssertEqual(
      opened, [UIApplication.openSettingsURLString, UIApplication.openNotificationSettingsURLString])
  }

  func testPC04BackupExclusionMarksTheDirectory() throws {
    // The same call as AppDelegate (acceptance criterion 5: napstop_db and napstop_trip).
    let names = ["napstop_db", "napstop_trip"]
    let result = BackupExclusion.excludeAppSupportSubdirectories(names)
    XCTAssertEqual(result, ["napstop_db": true, "napstop_trip": true])
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    for name in names {
      let url = support.appendingPathComponent(name, isDirectory: true)
      var isDir: ObjCBool = false
      XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), name)
      XCTAssertTrue(isDir.boolValue, name)
      let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
      XCTAssertEqual(values.isExcludedFromBackup, true, name)
    }
  }
}

// T17.2 AC02–AC03 (docs/specs/T17.2.md): IOSAlarmHostApi. Runs on CI macOS (Simulator); typechecked on WSL only.

import AVFoundation

/// Records preview calls instead of playing.
final class RecordingPreview: SoundPreviewing {
  var played: [(file: String, maxMs: Int64)] = []
  var stops = 0
  private(set) var isPlaying = false
  func play(file: String, maxMs: Int64) {
    played.append((file, maxMs))
    isPlaying = true
  }
  func stop() {
    stops += 1
    isPlaying = false
  }
}

/// launch_action.json stand-in: written later from another queue, taken once.
final class LaunchBox: @unchecked Sendable {
  private let lock = NSLock()
  private var value: LaunchActionRec?
  private var running = false
  func set(_ r: LaunchActionRec?) { lock.lock(); value = r; lock.unlock() }
  func take() -> LaunchActionRec? { lock.lock(); defer { lock.unlock() }; let v = value; value = nil; return v }
  var inFlight: Bool {
    get { lock.lock(); defer { lock.unlock() }; return running }
    set { lock.lock(); running = newValue; lock.unlock() }
  }
}

final class T172AlarmHostApiTests: XCTestCase {
  private let rec = LaunchActionRec(tripId: "t1", pastM: 1_340, atWallMs: 1, atElapsedMs: 1, bootSessionId: nil)

  private func api(_ box: LaunchBox, preview: SoundPreviewing = RecordingPreview(), alerting: Bool = false,
                   constants: RuntimeConstants = .default) -> IOSAlarmHostApi {
    IOSAlarmHostApi(
      launchActions: { box.take() }, routeBackInFlight: { box.inFlight }, alarmAlerting: { alerting },
      preview: preview, constants: constants)
  }

  func testAC02WaitsForRouteBackInFlight() async throws {
    let box = LaunchBox()
    box.inFlight = true
    let rec = self.rec
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
      box.set(rec)
      box.inFlight = false
    }
    let started = Date()
    let msg = try await api(box).consumeLaunchAction()
    XCTAssertEqual(msg?.kind, .overshootRoute)
    XCTAssertEqual(msg?.tripId, "t1")
    XCTAssertEqual(msg?.pastM, 1_340)
    XCTAssertLessThanOrEqual(Date().timeIntervalSince(started), 1.5 + 0.3)
  }

  func testAC02NotInFlightAnswersAtOnce() async throws {
    let box = LaunchBox()
    let started = Date()
    let msg = try await api(box).consumeLaunchAction()
    XCTAssertNil(msg)
    XCTAssertLessThan(Date().timeIntervalSince(started), 0.2)
    box.set(rec)
    let first = try await api(box).consumeLaunchAction()
    XCTAssertEqual(first?.tripId, "t1")
    let second = try await api(box).consumeLaunchAction()
    XCTAssertNil(second, "taken once")
  }

  func testAC03SystemSoundCreatesNoPlayerAndAlertingBlocksPreview() throws {
    let rec = RecordingPreview()
    try api(LaunchBox(), preview: rec).previewSound(soundId: "system", volume: 0.3)
    XCTAssertTrue(rec.played.isEmpty)
    try api(LaunchBox(), preview: rec, alerting: true).previewSound(soundId: "bell", volume: 0.3)
    XCTAssertTrue(rec.played.isEmpty, "never over a ringing alarm (T16 AE11)")
    try api(LaunchBox(), preview: rec).previewSound(soundId: "default", volume: 0.0)
    XCTAssertEqual(rec.played.map(\.file), ["alarm_horn.wav"])
    XCTAssertEqual(rec.played.first?.maxMs, 10_000)
  }

  func testAC03BellPlaysAtFullVolumeAndStopsByItself() throws {
    let preview = AVSoundPreview()
    var c = RuntimeConstants.default
    c.previewMaxMs = 400
    try api(LaunchBox(), preview: preview, constants: c).previewSound(soundId: "bell", volume: 0.3)
    let player = try XCTUnwrap(preview.player, "alarm_bell.wav in the app bundle")
    XCTAssertEqual(player.volume, 1.0, "volume ignored (Q4 = A)")
    XCTAssertTrue(player.isPlaying)
    XCTAssertGreaterThanOrEqual(player.duration, 28.0)
    let stopped = expectation(description: "auto stop")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      XCTAssertNil(preview.player)
      stopped.fulfill()
    }
    wait(for: [stopped], timeout: 3)
    XCTAssertEqual(IOSAlarmHostApi.msg(rec).pastM, 1_340)
  }

  func testPreviewStopsWhenAnAlarmStartsRinging() throws {
    // Review T17.2 nit #5: polled once a second while the preview plays.
    let rec = RecordingPreview()
    var ringing = false
    let a = IOSAlarmHostApi(
      launchActions: { nil }, routeBackInFlight: { false }, alarmAlerting: { ringing }, preview: rec)
    try a.previewSound(soundId: "beep", volume: 1)
    XCTAssertTrue(rec.isPlaying)
    ringing = true
    let done = expectation(description: "stopped by the watch")
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
      XCTAssertFalse(rec.isPlaying)
      XCTAssertEqual(rec.stops, 1)
      done.fulfill()
    }
    wait(for: [done], timeout: 3)
  }

  func testShowAlarmScreenIsFalseAndLocaleKeyKept() async throws {
    let a = api(LaunchBox())
    let shown = try await a.showAlarmScreen(tripId: "t1")
    XCTAssertFalse(shown)
    try a.setAppLocale(languageTag: "en")
    XCTAssertEqual(UserDefaults.standard.string(forKey: RuntimeHost.appLocaleKey), "en")
    try a.setAppLocale(languageTag: "fr")
    XCTAssertNil(UserDefaults.standard.string(forKey: RuntimeHost.appLocaleKey))
  }
}

// T17.3 NC02 (coder): the UNNotificationRequest of each planned request of the notification channel. Runs on CI macOS
// (Simulator); not typechecked on WSL (RunnerTests needs XCTest).
import UserNotifications

final class T173NotificationRequestTests: XCTestCase {
  private func requests(kind: SystemAlarmKind, fireIn: Int64, sound: String?) -> [UNNotificationRequest] {
    let now: Int64 = 1_700_000_000_000
    let r = SystemAlarmRequest(
      id: "X", tripId: "t1", kind: kind, generation: 1, fireAtWallMs: now + fireIn, title: "Sắp tới Ga A",
      channel: .notification, soundFile: sound)
    return NotificationAlarmPlan.requests(r, nowWallMs: now).map { NotificationSystemAlarms.makeRequest($0) }
  }

  private func intervals(_ reqs: [UNNotificationRequest]) -> [Double?] {
    reqs.map { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval }
  }

  func testFallbackSlotIsThreeTimeSensitiveRequestsThirtySecondsApart() {
    let reqs = requests(kind: .fallback, fireIn: 600_000, sound: "alarm_horn.wav")
    XCTAssertEqual(reqs.map { $0.identifier }, ["X#0", "X#1", "X#2"])
    XCTAssertEqual(intervals(reqs), [600, 630, 660])
    for q in reqs {
      XCTAssertEqual(q.content.interruptionLevel, .timeSensitive)
      XCTAssertEqual(q.content.title, "Sắp tới Ga A")
      XCTAssertNotNil(q.content.sound)
      XCTAssertEqual((q.trigger as? UNTimeIntervalNotificationTrigger)?.repeats, false)
      XCTAssertEqual(q.content.userInfo["tripId"] as? String, "t1")
      XCTAssertNil(q.content.userInfo["lat"])
    }
  }

  func testNowAlarmFirstRequestHasNoTrigger() {
    let reqs = requests(kind: .now, fireIn: 5_000, sound: nil)
    XCTAssertNil(reqs[0].trigger)
    XCTAssertEqual(intervals(reqs), [nil, 35, 65])
    XCTAssertTrue(reqs.allSatisfy { $0.content.interruptionLevel == .timeSensitive })
  }
}

// T23.5 AS-X01: the numeric MKError codes the Linux-testable AddressSearchWire relies on (docs/specs/T23.5.md §3).
import MapKit

final class AddressSearchErrorCodeTests: XCTestCase {
  func testMapKitErrorCodesMatchTheWireConstants() {
    XCTAssertEqual(MKError.Code.loadingThrottled.rawValue, AddressSearchWire.mkLoadingThrottled)
    XCTAssertEqual(MKError.Code.placemarkNotFound.rawValue, AddressSearchWire.mkPlacemarkNotFound)
    XCTAssertEqual(MKError.errorDomain, AddressSearchWire.mkErrorDomain)
  }
}
