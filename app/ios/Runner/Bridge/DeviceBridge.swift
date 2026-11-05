import Flutter
import UIKit

/// Device facts of `PermissionHostApi` (T14.1, T23), moved from the T14 stub unchanged (spec T17.1 §3).
enum DeviceBridge {
  /// Real device data (UIDevice is main-actor isolated).
  @MainActor
  static func readDeviceInfo() -> DeviceInfoMsg {
    let device = UIDevice.current
    return DeviceInfoMsg(
      platform: .ios,
      manufacturer: "Apple",
      brand: "Apple",
      model: device.model,
      osVersion: device.systemVersion,
      androidSdkInt: nil,
      iosMajor: Int64(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    )
  }

  /// Live battery (T14.1, T22 §8.1). Turns battery monitoring on first: without it
  /// `batteryLevel` is -1.0 and `batteryState` is `.unknown` [I-BAT].
  @MainActor
  static func readDeviceStatus() -> DeviceStatusMsg {
    let device = UIDevice.current
    if !device.isBatteryMonitoringEnabled {
      device.isBatteryMonitoringEnabled = true
    }
    return deviceStatus(batteryLevel: device.batteryLevel, batteryState: device.batteryState)
  }

  /// iOS has no public API for the alarm volume, the Silent switch or Focus state, so only
  /// the battery is filled in; AlarmKit manages its own volume.
  static func deviceStatus(batteryLevel: Float, batteryState: UIDevice.BatteryState) -> DeviceStatusMsg {
    let pct: Int64? =
      (0...1).contains(batteryLevel) ? Int64((batteryLevel * 100).rounded()) : nil
    let charging: Bool?
    switch batteryState {
    case .charging, .full:
      charging = true
    case .unplugged:
      charging = false
    case .unknown:
      charging = nil
    @unknown default:
      charging = nil
    }
    return DeviceStatusMsg(
      batteryPct: pct,
      charging: charging,
      alarmVolumePct: nil,
      alarmMuted: nil,
      interruptionFilter: .unknown,
      priorityAllowsAlarms: nil,
      headphonesConnected: nil
    )
  }

  /// T23: key from Info.plist `GMSApiKey` (Secrets.xcconfig) and the bundle id for the
  /// `X-Ios-Bundle-Identifier` header. Never log the result.
  static func mapsConfig() -> MapsConfigMsg {
    MapsConfigMsg(
      apiKey: MapsConfig.apiKey(),
      androidPackage: nil,
      androidCertSha1: nil,
      iosBundleId: Bundle.main.bundleIdentifier
    )
  }
}

/// Maps/Places key of this build (T23 D3, D4).
enum MapsConfig {
  /// `GMSApiKey` of Info.plist, nil when empty or when the build variable was not set
  /// (an unexpanded `$(MAPS_API_KEY)`).
  static func apiKey(bundle: Bundle = .main) -> String? {
    guard let raw = bundle.object(forInfoDictionaryKey: "GMSApiKey") as? String else {
      return nil
    }
    let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if key.isEmpty || key.hasPrefix("$(") {
      return nil
    }
    return key
  }
}
