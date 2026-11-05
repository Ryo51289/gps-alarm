import Flutter
import TripRuntime
import UIKit

/// iOS side of the core bridge: registers the Pigeon APIs. Trips go to the real runtime (`RealTripBackend`, T17);
/// permissions and the alarm extras are still stubs until T17.1 / T17.2. No coordinates are kept here.
///
/// Threading: synchronous Pigeon calls and stream callbacks arrive on the main thread.
final class CoreBridgeStub {
  private var tripApi: RealTripBackend?
  private var permissionApi: PermissionHostApiStub?
  private let alarmApi = AlarmHostApiStub()
  private var updatesHandler: TripUpdatesHandler?
  private var eventChannel: TripUpdatesEventChannel?

  @MainActor
  func register(messenger: FlutterBinaryMessenger, runtime: TripRuntime) {
    let trip = RealTripBackend(runtime: runtime)
    let permission = PermissionHostApiStub(device: CoreBridgeStub.readDeviceInfo())
    let updates = TripUpdatesHandler(runtime: runtime)
    tripApi = trip
    permissionApi = permission
    updatesHandler = updates
    TripHostApiSetup.setUp(binaryMessenger: messenger, api: trip)
    PermissionHostApiSetup.setUp(binaryMessenger: messenger, api: permission)
    AlarmHostApiSetup.setUp(binaryMessenger: messenger, api: alarmApi)
    eventChannel = TripUpdatesStreamHandler.register(with: messenger, streamHandler: updates)
  }

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

  /// V11 (T14.1): limit of `TripConfigMsg.engineParamsJson` in UTF-16 code units. The full V1–V11 check is
  /// `TripConfigValidator` (TripRuntime, T17); this wrapper keeps the T14.1 test entry point.
  static let maxEngineParamsJsonLength = TripConfigValidator.maxEngineParamsJsonLength

  static func checkEngineParams(_ config: TripConfigMsg) throws {
    if let json = config.engineParamsJson, json.utf16.count > maxEngineParamsJsonLength {
      throw PigeonError(code: "invalid-config", message: "engineParamsJson: too long", details: nil)
    }
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

  static func nowMs() -> Int64 {
    Int64((Date().timeIntervalSince1970 * 1000).rounded())
  }

  /// Maps unexpected errors to `internal` with the type name only (spec T14 §4):
  /// Pigeon's own wrapError would send the error description.
  static func guarded<T>(_ body: () async throws -> T) async throws -> T {
    do {
      return try await body()
    } catch let error as PigeonError {
      throw error
    } catch {
      throw PigeonError(code: "internal", message: String(describing: type(of: error)), details: nil)
    }
  }
}

/// Fixed answers until T17 (ARCHITECTURE §7). Android-only items are notApplicable.
/// `deviceStatus()` is real (battery only). T21: `status()` is async (Pigeon @async); T17
/// implements the mapping of docs/specs/T21.md §9 (`precise` is never notApplicable).
final class PermissionHostApiStub: PermissionHostApi {
  private let device: DeviceInfoMsg

  init(device: DeviceInfoMsg) {
    self.device = device
  }

  func status() async throws -> PermissionStatusMsg {
    fixedStatus()
  }

  private func fixedStatus() -> PermissionStatusMsg {
    PermissionStatusMsg(
      location: .whileInUse,
      precise: .granted,
      locationServicesEnabled: true,
      notifications: .granted,
      fullScreenIntent: .notApplicable,
      exactAlarm: .notApplicable,
      batteryOptimizationIgnored: .notApplicable,
      alarmKit: (device.iosMajor ?? 0) >= 26 ? .granted : .notApplicable
    )
  }

  func request(kind: PermissionKindMsg) async throws -> PermissionStatusMsg {
    fixedStatus()
  }

  func openSettings(target: SettingsTargetMsg) throws -> Bool {
    false
  }

  func deviceInfo() throws -> DeviceInfoMsg {
    device
  }

  /// Battery only (T14.1). Synchronous Pigeon calls arrive on the main thread, where
  /// UIDevice may be used.
  func deviceStatus() throws -> DeviceStatusMsg {
    MainActor.assumeIsolated { CoreBridgeStub.readDeviceStatus() }
  }

  /// T23: key from Info.plist `GMSApiKey` (Secrets.xcconfig) and the bundle id for the
  /// `X-Ios-Bundle-Identifier` header. Never log the result.
  func mapsConfig() throws -> MapsConfigMsg {
    MapsConfigMsg(
      apiKey: MapsConfig.apiKey(),
      androidPackage: nil,
      androidCertSha1: nil,
      iosBundleId: Bundle.main.bundleIdentifier
    )
  }

  /// T23: no distances on iOS until T17 (CLLocationManager().location). T17 must round each
  /// value like Android `LastKnownMath.roundForDisplay` (10 m under 1 km, 100 m above) and
  /// never log them: several distances to public stations locate the user.
  func distancesFromLastKnownM(latLngPairs: [Double], maxAgeMs: Int64) async throws -> [Double]? {
    nil
  }

  /// T21: the screen 9 background check is Android only (iOS has no battery optimization).
  func startBackgroundCheck(delayMs: Int64) async throws -> BackgroundCheckMsg {
    throw PigeonError(code: "internal", message: "unsupported", details: nil)
  }

  func backgroundCheck() async throws -> BackgroundCheckMsg? {
    nil
  }

  func cancelBackgroundCheck() async throws {}
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

/// Sound preview stub (T17 plays it).
final class AlarmHostApiStub: AlarmHostApi {
  func previewSound(soundId: String, volume: Double) throws {}

  func stopPreview() throws {}

  /// T27: no launch actions on iOS (T17).
  func consumeLaunchAction() async throws -> LaunchActionMsg? {
    nil
  }

  /// T27: no native alarm screen on iOS yet (T17).
  func showAlarmScreen(tripId: String) async throws -> Bool {
    false
  }

  /// UserDefaults key read by T17 for AlarmKit / notification strings (T28 §6.3).
  static let appLocaleKey = "napstop.appLocale"

  /// T28: 'vi' | 'en' is stored; nil or any other value removes the key (= device language).
  func setAppLocale(languageTag: String?) throws {
    let tag = languageTag?.trimmingCharacters(in: .whitespaces)
    if tag == "vi" || tag == "en" {
      UserDefaults.standard.set(tag, forKey: Self.appLocaleKey)
    } else {
      UserDefaults.standard.removeObject(forKey: Self.appLocaleKey)
    }
  }
}
