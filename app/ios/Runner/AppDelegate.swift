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
  /// T23.5: address search channel (Apple Maps), created with the Flutter engine.
  private var addressSearch: AddressSearchChannel?

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
    #if NAPSTOP_DIAG
      // Spike T23.8-B0: re-creates the region probe (monitor, legacy delegate, service session, notification delegate) at
      // every launch, also a background launch for a region event. Does nothing until a probe region is set.
      DiagCommuteProbe.launch(launchOptions: launchOptions, host: host)
    #endif
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    traces.attach(engineBridge.pluginRegistry.registrar(forPlugin: FlutterAssetTraceStore.pluginKey))
    // T23.3 D1: the MapKit platform view of screens 2 and 4 (ADR-002).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: NapMapViewFactory.pluginKey) {
      registrar.register(NapMapViewFactory(messenger: registrar.messenger()), withId: MapWire.viewType)
    }
    // T23.5 D1: the address search channel (app level, not tied to a map view).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NapStopAddressSearch") {
      addressSearch = AddressSearchChannel.register(messenger: registrar.messenger())
    }
    let host = RuntimeHost.shared
      ?? RuntimeHost.bootstrap(options: AlarmIntents.options(), intentFactory: AlarmIntents.factory, traces: traces)
    coreBridge.register(messenger: engineBridge.applicationRegistrar.messenger(), runtime: host.runtime)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    RuntimeHost.shared?.willTerminate()
    super.applicationWillTerminate(application)
  }
}
