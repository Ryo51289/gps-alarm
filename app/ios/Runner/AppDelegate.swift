import Flutter
import NapStopIOS
import TripRuntime
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Pigeon bridge to the native core (T14, T17). Strong reference for the app's lifetime.
  private let coreBridge = CoreBridgeStub()
  /// T18.1 D12: bundled simulation traces; the registrar is attached once the Flutter engine exists.
  private let traces = FlutterAssetTraceStore()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // T17.1 D10: keep the database (destination coordinates, screen 0 flags) and the runtime files out of backups. At
    // every launch, before Flutter opens the database; a failure never blocks the launch.
    let excluded = BackupExclusion.excludeAppSupportSubdirectories(["napstop_db", "napstop_trip"])
    #if NAPSTOP_DIAG && targetEnvironment(simulator)
      // T01.2 CI: `SIMCTL_CHILD_NAPSTOP_DIAG_FAKE_ALARMS=1` in the environment of `flutter test` reaches the app through
      // `simctl launch`; `simctl spawn defaults write` would only write the simulator's domain, not the app container.
      // Stored so that AlarmIntents.options() and later launches by App Intents see the same switch.
      if ProcessInfo.processInfo.environment["NAPSTOP_DIAG_FAKE_ALARMS"] == "1" {
        UserDefaults.standard.set(true, forKey: "napstop.diag.fakeAlarms")
      }
    #endif
    // T17: the trip runtime exists before Flutter, also when iOS launches the app in the background (StopIntent).
    let host = RuntimeHost.bootstrap(options: AlarmIntents.options(), intentFactory: AlarmIntents.factory, traces: traces)
    host.journal.record("backup_exclusion", excluded.mapValues { $0 ? "ok" : "failed" })
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    traces.attach(engineBridge.pluginRegistry.registrar(forPlugin: FlutterAssetTraceStore.pluginKey))
    let host = RuntimeHost.shared
      ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), intentFactory: AlarmIntents.factory, traces: traces)
    coreBridge.register(messenger: engineBridge.applicationRegistrar.messenger(), runtime: host.runtime)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    RuntimeHost.shared?.willTerminate()
    super.applicationWillTerminate(application)
  }
}
