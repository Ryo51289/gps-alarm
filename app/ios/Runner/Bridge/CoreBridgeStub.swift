import Flutter
import NapStopIOS
import TripRuntime
import UIKit

/// iOS side of the core bridge: registers the Pigeon APIs. Trips go to the real runtime (`RealTripBackend`, T17),
/// permissions to `IOSPermissionHostApi` (T17.1); the alarm extras are still stubs until T17.2. No coordinates are kept here.
///
/// Threading: synchronous Pigeon calls and stream callbacks arrive on the main thread.
final class CoreBridgeStub {
  private var tripApi: RealTripBackend?
  private var permissionApi: IOSPermissionHostApi?
  private let alarmApi = AlarmHostApiStub()
  private var updatesHandler: TripUpdatesHandler?
  private var eventChannel: TripUpdatesEventChannel?

  @MainActor
  func register(messenger: FlutterBinaryMessenger, runtime: TripRuntime) {
    let trip = RealTripBackend(runtime: runtime)
    let permission = IOSPermissionHostApi(probe: PermissionProbe(), device: DeviceBridge.readDeviceInfo())
    let updates = TripUpdatesHandler(runtime: runtime)
    tripApi = trip
    permissionApi = permission
    updatesHandler = updates
    TripHostApiSetup.setUp(binaryMessenger: messenger, api: trip)
    PermissionHostApiSetup.setUp(binaryMessenger: messenger, api: permission)
    AlarmHostApiSetup.setUp(binaryMessenger: messenger, api: alarmApi)
    eventChannel = TripUpdatesStreamHandler.register(with: messenger, streamHandler: updates)
  }

  /// V11 (T14.1): limit of `TripConfigMsg.engineParamsJson` in UTF-16 code units. The full V1–V11 check is
  /// `TripConfigValidator` (TripRuntime, T17); this wrapper keeps the T14.1 test entry point.
  static let maxEngineParamsJsonLength = TripConfigValidator.maxEngineParamsJsonLength

  static func checkEngineParams(_ config: TripConfigMsg) throws {
    if let json = config.engineParamsJson, json.utf16.count > maxEngineParamsJsonLength {
      throw PigeonError(code: "invalid-config", message: "engineParamsJson: too long", details: nil)
    }
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
