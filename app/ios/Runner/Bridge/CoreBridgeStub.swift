import Flutter
import NapStopIOS
import TripRuntime
import UIKit

/// iOS side of the core bridge: registers the Pigeon APIs. Trips go to the real runtime (`RealTripBackend`, T17),
/// permissions to `IOSPermissionHostApi` (T17.1), the alarm extras to `IOSAlarmHostApi` (T17.2). No coordinates are kept
/// here.
///
/// Threading: synchronous Pigeon calls and stream callbacks arrive on the main thread.
final class CoreBridgeStub {
  private var tripApi: RealTripBackend?
  private var permissionApi: IOSPermissionHostApi?
  private var alarmApi: IOSAlarmHostApi?
  private var updatesHandler: TripUpdatesHandler?
  private var eventChannel: TripUpdatesEventChannel?

  @MainActor
  func register(messenger: FlutterBinaryMessenger, runtime: TripRuntime) {
    let trip = RealTripBackend(runtime: runtime)
    let permission = IOSPermissionHostApi(probe: PermissionProbe(), device: DeviceBridge.readDeviceInfo())
    let updates = TripUpdatesHandler(runtime: runtime)
    let alarmApi = IOSAlarmHostApi(
      launchActions: { await runtime.consumeLaunchAction() },
      routeBackInFlight: { RuntimeHost.routeBackInFlight.active },
      alarmAlerting: { RuntimeHost.shared?.anyAlarmAlerting() ?? false })
    tripApi = trip
    permissionApi = permission
    self.alarmApi = alarmApi
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
