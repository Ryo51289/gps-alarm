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

  /// V11 (T14.1): limit of `TripConfigMsg.engineParamsJson` in UTF-16 code units, same as
  /// Dart `String.length` and the Android `TripConfigValidator`.
  static let maxEngineParamsJsonLength = 16_384

  /// Safety net until T17 ports the whole `TripConfigValidator`: only V11 here (T14.1).
  /// The message names the rule, never the value (T14 §4).
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
      priorityAllowsAlarms: nil
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
      try CoreBridgeStub.checkEngineParams(config)
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
/// `deviceStatus()` is real (battery only).
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
