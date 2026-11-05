import Flutter
import Foundation
import TripRuntime

/// Bundled simulation traces (spec T18.1 D12, §6): `assets/sim/<id>.gpx` of the Flutter assets, looked up with the
/// plugin registrar [F-ASSET] (https://docs.flutter.dev/ui/assets/assets-and-images). The registrar is attached in
/// `didInitializeImplicitFlutterEngine`; before that every `open` is nil (`simulation-unavailable` "TraceNotFound"; a
/// Pigeon start always comes from an attached engine). Called off the main thread by the runtime (detached task); the
/// asset key is looked up on main (see `open`).
final class FlutterAssetTraceStore: TraceStore, @unchecked Sendable {
  static let pluginKey = "NapStopSimAssets"

  private let lock = NSLock()
  private var registrar: FlutterPluginRegistrar?

  func attach(_ registrar: FlutterPluginRegistrar?) {
    lock.lock()
    self.registrar = registrar
    lock.unlock()
  }

  func open(_ traceId: String) -> Data? {
    // The id is checked before it becomes part of an asset key: never a path (T18 D11).
    guard SimTraceIds.valid(traceId) else { return nil }
    lock.lock()
    let r = registrar
    lock.unlock()
    guard let r else { return nil }
    // The Flutter docs do not say the registrar may be used off the platform (main) thread, and the iOS embedding APIs
    // are documented for the platform thread (https://docs.flutter.dev/platform-integration/platform-channels, "Channels
    // and platform threading"): look the key up on main. `open` runs in a detached task of the runtime (never on main,
    // and main never waits for it), so the hop cannot deadlock; reading the file stays off main.
    let asset = "assets/sim/\(traceId).gpx"
    let key = Thread.isMainThread ? r.lookupKey(forAsset: asset) : DispatchQueue.main.sync { r.lookupKey(forAsset: asset) }
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else { return nil }
    return try? Data(contentsOf: URL(fileURLWithPath: path))
  }
}
