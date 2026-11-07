import Flutter
import Foundation
import TripRuntime
import UIKit

/// `PermissionHostApi` on iOS (spec T17.1 §3; contract T21 §9). Raw reads and prompts come from a `PermissionProbing`
/// (`NapStopIOS.PermissionProbe` in the app, a fake in RunnerTests); the mapping is `PermissionMapper` (TripRuntime).
/// PRIVACY: never logs a position, a distance or the station coordinates; errors carry the type name only.
final class IOSPermissionHostApi: PermissionHostApi {
  private let probe: PermissionProbing
  private let device: DeviceInfoMsg
  private let gate = PermissionRequestGate()
  private let openURL: (URL) -> Void
  private let nowWallMs: @Sendable () -> Int64
  private let promptTimeoutMs: Int64

  /// `openURL` runs on the main thread (synchronous Pigeon calls arrive there).
  init(
    probe: PermissionProbing,
    device: DeviceInfoMsg,
    openURL: @escaping (URL) -> Void = IOSPermissionHostApi.openWithApplication,
    nowWallMs: @escaping @Sendable () -> Int64 = { CoreBridgeStub.nowMs() },
    promptTimeoutMs: Int64 = PermissionConstants.promptTimeoutMs
  ) {
    self.probe = probe
    self.device = device
    self.openURL = openURL
    self.nowWallMs = nowWallMs
    self.promptTimeoutMs = promptTimeoutMs
  }

  static func openWithApplication(_ url: URL) {
    MainActor.assumeIsolated { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
  }

  func status() async throws -> PermissionStatusMsg {
    let probe = self.probe
    return try await CoreBridgeStub.guarded { Self.msg(PermissionMapper.status(await probe.readings())) }
  }

  /// D5: a second request while one runs fails with `request-in-progress`.
  func request(kind: PermissionKindMsg) async throws -> PermissionStatusMsg {
    guard gate.tryEnter() else {
      throw PigeonError(code: "request-in-progress", message: nil, details: nil)
    }
    defer { gate.leave() }
    let probe = self.probe
    let timeout = promptTimeoutMs
    return try await CoreBridgeStub.guarded {
      switch kind {
      case .location: await probe.requestLocation(timeoutMs: timeout)
      case .notifications: await probe.requestNotifications()
      case .alarmKit: await probe.requestAlarmKit()
      }
      return Self.msg(PermissionMapper.status(await probe.readings()))
    }
  }

  /// D6: the settings URL of the target, nil when iOS has no public page for it.
  static func settingsURLString(_ target: SettingsTargetMsg) -> String? {
    switch target {
    case .appDetails: return UIApplication.openSettingsURLString
    case .notifications: return UIApplication.openNotificationSettingsURLString
    case .locationServices, .fullScreenIntent, .exactAlarm, .batteryOptimization: return nil
    }
  }

  func openSettings(target: SettingsTargetMsg) throws -> Bool {
    guard let s = Self.settingsURLString(target), let url = URL(string: s) else { return false }
    openURL(url)
    return true
  }

  func deviceInfo() throws -> DeviceInfoMsg {
    device
  }

  /// Battery only (T14.1). Synchronous Pigeon calls arrive on the main thread, where
  /// UIDevice may be used.
  func deviceStatus() throws -> DeviceStatusMsg {
    MainActor.assumeIsolated { DeviceBridge.readDeviceStatus() }
  }

  /// T23 on iOS (D7): rounded like Android `LastKnownMath.roundForDisplay`; any failure answers nil.
  func distancesFromLastKnownM(latLngPairs: [Double], maxAgeMs: Int64) async throws -> [Double]? {
    let probe = self.probe
    let now = nowWallMs
    return await LastKnownMath.distances(latLngPairs, maxAgeMs: maxAgeMs, probe: probe, nowWallMs: now)
  }

  /// T21: the screen 9 background check is Android only (iOS has no battery optimization).
  func startBackgroundCheck(delayMs: Int64) async throws -> BackgroundCheckMsg {
    throw PigeonError(code: "internal", message: "unsupported", details: nil)
  }

  func backgroundCheck() async throws -> BackgroundCheckMsg? {
    nil
  }

  func cancelBackgroundCheck() async throws {}

  // MARK: DTO → Pigeon

  static func msg(_ d: PermissionStatusDTO) -> PermissionStatusMsg {
    PermissionStatusMsg(
      location: location(d.location),
      precise: state(d.precise),
      locationServicesEnabled: d.locationServicesEnabled,
      notifications: state(d.notifications),
      fullScreenIntent: state(d.fullScreenIntent),
      exactAlarm: state(d.exactAlarm),
      batteryOptimizationIgnored: state(d.batteryOptimizationIgnored),
      alarmKit: state(d.alarmKit)
    )
  }

  static func location(_ l: LocationAccessDTO) -> LocationAccessMsg {
    switch l {
    case .notDetermined: return .notDetermined
    case .denied: return .denied
    case .whileInUse: return .whileInUse
    case .always: return .always
    }
  }

  static func state(_ s: PermissionStateDTO) -> PermissionStateMsg {
    switch s {
    case .notDetermined: return .notDetermined
    case .denied: return .denied
    case .granted: return .granted
    case .notApplicable: return .notApplicable
    }
  }
}
