import Flutter
import GoogleMaps
import NapStopIOS
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Pigeon bridge to the native core (T14, T17). Strong reference for the app's lifetime.
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
    // T17: the trip runtime exists before Flutter, also when iOS launches the app in the background (StopIntent).
    RuntimeHost.bootstrap(options: AlarmIntents.options(), stopIntentFactory: AlarmIntents.factory)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let host = RuntimeHost.shared ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), stopIntentFactory: AlarmIntents.factory)
    coreBridge.register(messenger: engineBridge.applicationRegistrar.messenger(), runtime: host.runtime)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    RuntimeHost.shared?.willTerminate()
    super.applicationWillTerminate(application)
  }
}
