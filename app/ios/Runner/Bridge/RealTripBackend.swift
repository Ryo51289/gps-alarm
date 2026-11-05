import Flutter
import Foundation
import Trip
import TripRuntime

/// TripHostApi on the real iOS runtime (spec T17 §5.1, §5.11). Every call is wrapped like the T14 stub: unexpected
/// errors become `internal` + type name only.
final class RealTripBackend: TripHostApi {
  private let runtime: TripRuntime

  init(runtime: TripRuntime) {
    self.runtime = runtime
  }

  /// Wire result of `TripRuntime.start` (IC03).
  static func error(_ outcome: StartOutcome) -> PigeonError? {
    switch outcome {
    case .started: return nil
    case .rejected(let code, let message, let details): return PigeonError(code: code, message: message, details: details)
    }
  }

  func startTrip(config: TripConfigMsg, destLat: Double, destLng: Double, simulation: SimulationMsg?) async throws {
    let runtime = self.runtime
    try await CoreBridgeStub.guarded {
      let meta = MsgMapper.meta(config)
      let sim = simulation.map { SimulationInput(traceAsset: $0.traceAsset, speedFactor: $0.speedFactor) }
      if let rule = TripConfigValidator.validate(meta, destLat: destLat, destLng: destLng, simulation: sim) {
        throw PigeonError(code: "invalid-config", message: rule, details: nil)
      }
      // D18: simulation on iOS comes with T18.1.
      if simulation != nil { throw PigeonError(code: "simulation-unavailable", message: nil, details: nil) }
      if let e = Self.error(await runtime.start(meta: meta, destLat: destLat, destLng: destLng)) { throw e }
    }
  }

  func stopTrip(tripId: String) async throws {
    let runtime = self.runtime
    try await CoreBridgeStub.guarded { await runtime.userAction(tripId: tripId, .stopTrip) }
  }

  func currentTrip() async throws -> ActiveTripMsg? {
    let runtime = self.runtime
    return try await CoreBridgeStub.guarded {
      guard let cur = await runtime.current() else { return nil }
      let choice = await runtime.batteryChoice()
      return ActiveTripMsg(
        config: MsgMapper.config(cur.meta),
        state: MsgMapper.state(BridgeMapper.state(view: cur.view, batteryChoice: choice)), simulation: nil)
    }
  }

  func setBatteryChoice(tripId: String, choice: BatteryChoiceMsg) async throws {
    let runtime = self.runtime
    try await CoreBridgeStub.guarded {
      await runtime.userAction(tripId: tripId, BridgeMapper.batteryAction(MsgMapper.choiceDTO(choice)))
    }
  }

  func dismiss(tripId: String) async throws {
    let runtime = self.runtime
    try await CoreBridgeStub.guarded { await runtime.userAction(tripId: tripId, .dismiss) }
  }

  func snooze(tripId: String) async throws {
    let runtime = self.runtime
    try await CoreBridgeStub.guarded { await runtime.userAction(tripId: tripId, .snooze) }
  }

  func pendingFinishedTrips() async throws -> [FinishedTripMsg] {
    let runtime = self.runtime
    return try await CoreBridgeStub.guarded {
      await runtime.pendingFinished().compactMap { BridgeMapper.finished($0).map(MsgMapper.finished) }
    }
  }

  func ackFinishedTrips(tripIds: [String]) async throws {
    let runtime = self.runtime
    try await CoreBridgeStub.guarded { await runtime.ackFinished(tripIds) }
  }
}

/// Event channel tripUpdates on the runtime (§5.11): one listener per Dart subscription; attaching replays the latest
/// state with a Tick (T14 §2 rule 2). The runtime awaits the listener, so a Step reaches Dart before the next one.
final class TripUpdatesHandler: TripUpdatesStreamHandler, @unchecked Sendable {
  private let runtime: TripRuntime
  private var token: Int?
  private var generation = 0

  init(runtime: TripRuntime) {
    self.runtime = runtime
  }

  override func onListen(withArguments arguments: Any?, sink: PigeonEventSink<TripUpdateMsg>) {
    generation += 1
    let myGeneration = generation
    let old = token
    token = nil
    let runtime = self.runtime
    let box = SinkBox(sink)
    Task { @MainActor [weak self] in
      if let old { await runtime.removeListener(old) }
      let t = await runtime.addListener { tripId, view, choice, events in
        let updates = MsgMapper.updates(tripId: tripId, view: view, batteryChoice: choice, events: events)
        await MainActor.run { for u in updates { box.sink.success(u) } }
      }
      guard let self, self.generation == myGeneration else {
        await runtime.removeListener(t)
        return
      }
      self.token = t
    }
  }

  override func onCancel(withArguments arguments: Any?) {
    generation += 1
    let runtime = self.runtime
    if let t = token {
      token = nil
      Task { await runtime.removeListener(t) }
    }
  }
}

/// The Pigeon sink is only used on the main thread.
final class SinkBox: @unchecked Sendable {
  let sink: PigeonEventSink<TripUpdateMsg>
  init(_ sink: PigeonEventSink<TripUpdateMsg>) { self.sink = sink }
}
