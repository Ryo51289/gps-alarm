import Flutter
import Foundation
import NapStopIOS

/// The application channel `app.napstop/address_search` (docs/specs/T23.5.md §3, §5.3, D1): request → reply, not tied
/// to a view. `StandardMessageCodec`, no Pigeon (T14 D5: the messages carry coordinates). Invalid messages are
/// answered `failed`, never an error; unknown methods give `FlutterMethodNotImplemented`. The `diagFake` command exists
/// only with NAPSTOP_DIAG (the compilation condition of the Runner does not reach the local package, so it lives here:
/// T23.3 RK2).
/// PRIVACY: never logs a payload, a typed text or a coordinate.
final class AddressSearchChannel {
  private let channel: FlutterMethodChannel
  private let service: AddressSearchService

  private init(channel: FlutterMethodChannel, service: AddressSearchService) {
    self.channel = channel
    self.service = service
  }

  /// The caller (AppDelegate) keeps the returned object for the app's lifetime.
  static func register(messenger: FlutterBinaryMessenger) -> AddressSearchChannel {
    let channel = FlutterMethodChannel(name: AddressSearchWire.channel, binaryMessenger: messenger)
    let service = MainActor.assumeIsolated { AddressSearchService() }
    channel.setMethodCallHandler { call, result in
      // Flutter delivers platform channel calls on the main thread.
      MainActor.assumeIsolated { AddressSearchChannel.handle(service, call, result) }
    }
    return AddressSearchChannel(channel: channel, service: service)
  }

  @MainActor
  private static func handle(_ service: AddressSearchService, _ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "complete":
      guard let request = AddressSearchWire.completeRequest(call.arguments) else {
        result(AddressSearchWire.status("failed"))
        return
      }
      service.complete(request) { result($0) }
    case "resolve":
      guard let request = AddressSearchWire.resolveRequest(call.arguments) else {
        result(AddressSearchWire.status("failed"))
        return
      }
      service.resolve(request) { result($0) }
    case "cancel":
      service.cancel()
      result(nil)
    default:
      #if NAPSTOP_DIAG
        if call.method == "diagFake" {
          service.setFake(AddressSearchWire.fakeItems(call.arguments))
          result(nil)
          return
        }
      #endif
      result(FlutterMethodNotImplemented)
    }
  }
}
