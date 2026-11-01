import Flutter
import UIKit

/// Minimal iOS side of the core bridge (spec T14 §7): in-memory state, no timers, no disk.
/// Lets Dart call the Pigeon APIs on iOS until T17 brings the real engine, permissions
/// and the snapshot. No coordinates are kept (`destLat`/`destLng` are dropped).
///
/// Threading: synchronous Pigeon calls and stream callbacks arrive on the main thread.
/// Async calls hop to the main actor before touching `State`, so state and the event
/// sink are only used on the main thread.
final class CoreBridgeStub {
  /// Shared by the API stubs. Only accessed on the main thread (see above).
  final class State: @unchecked Sendable {
    var active: ActiveTripMsg?
    var startedAtMs: Int64 = 0
    var finished: [FinishedTripMsg] = []
    var sink: PigeonEventSink<TripUpdateMsg>?

    func send(_ update: TripUpdateMsg) {
      sink?.success(update)
    }
  }

  private let state = State()
  private var tripApi: TripHostApiStub?
  private var permissionApi: PermissionHostApiStub?
  private let alarmApi = AlarmHostApiStub()
  private var updatesHandler: TripUpdatesHandler?
  private var eventChannel: TripUpdatesEventChannel?

  @MainActor
  func register(messenger: FlutterBinaryMessenger) {
    let trip = TripHostApiStub(state: state)
    let permission = PermissionHostApiStub(device: CoreBridgeStub.readDeviceInfo())
    let updates = TripUpdatesHandler(state: state)
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

final class TripHostApiStub: TripHostApi {
  private let state: CoreBridgeStub.State

  init(state: CoreBridgeStub.State) {
    self.state = state
  }

  func startTrip(
    config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?
  ) async throws {
    let state = self.state
    try await CoreBridgeStub.guarded {
      try await MainActor.run {
        if state.active != nil {
          throw PigeonError(code: "trip-active", message: nil, details: nil)
        }
        let now = CoreBridgeStub.nowMs()
        let view = TripStateMsg(
          tripId: config.tripId,
          atMs: now,
          phase: .acquiring,
          gps: .noFixYet,
          locationCause: .available,
          isEstimated: false,
          fallbackStatus: .notSet,
          batteryRisk: false,
          preAlertFired: false,
          alarmRinging: false,
          snoozeCount: 0,
          vehicleGuess: config.vehicleHint,
          travelledM: 0
        )
        state.active = ActiveTripMsg(config: config, state: view, simulation: simulation)
        state.startedAtMs = now
        state.send(TripStateUpdateMsg(state: view))
      }
    }
  }

  func stopTrip(tripId: String) async throws {
    let state = self.state
    try await CoreBridgeStub.guarded {
      await MainActor.run {
        guard let active = state.active, active.config.tripId == tripId else { return }
        let now = CoreBridgeStub.nowMs()
        var view = active.state
        view.atMs = now
        view.phase = .ended
        view.outcome = .cancelled
        view.samplingTier = nil
        let record = FinishedTripMsg(
          tripId: tripId,
          outcome: .cancelled,
          endReason: .userStop,
          endedAtMs: now,
          startedAtMs: state.startedAtMs,
          alarmAtMs: nil,
          alarmReason: nil,
          dismissedAtMs: nil,
          snoozeCount: 0,
          travelledM: 0,
          vehicleGuess: active.config.vehicleHint
        )
        state.finished.append(record)
        state.active = nil
        state.send(TripStateUpdateMsg(state: view))
        state.send(TripEndedMsg(atMs: now, trip: record))
      }
    }
  }

  func currentTrip() async throws -> ActiveTripMsg? {
    let state = self.state
    return try await CoreBridgeStub.guarded {
      await MainActor.run { state.active }
    }
  }

  /// No-op in the iOS stub (no engine).
  func setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) async throws {}

  /// No-op in the iOS stub (never alarms).
  func dismiss(tripId: String) async throws {}

  /// No-op in the iOS stub (never alarms).
  func snooze(tripId: String) async throws {}

  func pendingFinishedTrips() async throws -> [FinishedTripMsg] {
    let state = self.state
    return try await CoreBridgeStub.guarded {
      await MainActor.run { state.finished.sorted { $0.endedAtMs < $1.endedAtMs } }
    }
  }

  func ackFinishedTrips(tripIds: [String]) async throws {
    let state = self.state
    try await CoreBridgeStub.guarded {
      await MainActor.run {
        let acked = Set(tripIds)
        state.finished.removeAll { acked.contains($0.tripId) }
      }
    }
  }
}

/// Fixed answers until T17 (ARCHITECTURE §7). Android-only items are notApplicable.
final class PermissionHostApiStub: PermissionHostApi {
  private let device: DeviceInfoMsg

  init(device: DeviceInfoMsg) {
    self.device = device
  }

  func status() throws -> PermissionStatusMsg {
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
    try status()
  }

  func openSettings(target: SettingsTargetMsg) throws -> Bool {
    false
  }

  func deviceInfo() throws -> DeviceInfoMsg {
    device
  }
}

/// Sound preview stub (T17 plays it).
final class AlarmHostApiStub: AlarmHostApi {
  func previewSound(soundId: String, volume: Double) throws {}

  func stopPreview() throws {}
}

/// Event channel tripUpdates: keeps the sink while Dart listens and replays the
/// latest state on listen (spec T14 §2 rule 2).
final class TripUpdatesHandler: TripUpdatesStreamHandler {
  private let state: CoreBridgeStub.State

  init(state: CoreBridgeStub.State) {
    self.state = state
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<TripUpdateMsg>) {
    state.sink = sink
    if let active = state.active {
      sink.success(TripStateUpdateMsg(state: active.state))
    }
  }

  override func onCancel(withArguments arguments: Any?) {
    state.sink = nil
  }
}
