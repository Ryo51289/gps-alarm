import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Pigeon bridge to the native core (T14). Strong reference for the app's lifetime.
  private let coreBridge = CoreBridgeStub()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Maps key from Secrets.xcconfig via Info.plist (T23 D3). Without one, Dart never
    // creates a map (mapsConfig().apiKey == nil). Never log the key.
    if let key = MapsConfig.apiKey() {
      GMSServices.provideAPIKey(key)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    coreBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}
