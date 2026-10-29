import Foundation
import UIKit
import UserNotifications

/// Process lifecycle (S3 §6.4): proc_start, resume of an active run, will_terminate, memory warnings,
/// protected data (lock with passcode), low power and battery changes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let store = RunStore.shared
        let events = EventLog.shared
        let prevCleanExit = store.consumeCleanExit()
        let active = store.loadConfig()
        events.currentRunId = active?.runId ?? ""
        UIDevice.current.isBatteryMonitoringEnabled = true
        let appState = DeviceSnapshot.appState()
        let launchKeys = (launchOptions?.keys.map { Self.shortName($0.rawValue) } ?? []).sorted().joined(separator: ",")
        events.log("proc_start", [
            "launchKeys": .str(launchKeys), "appState": .str(appState), "bundleId": .str(Bundle.main.bundleIdentifier),
            "ios": .str(UIDevice.current.systemVersion), "model": .str(DeviceSnapshot.model()),
            "activeRun": .str(active?.runId ?? ""), "prevCleanExit": .flag(prevCleanExit),
            "protectedData": .flag(application.isProtectedDataAvailable),
        ])

        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        NotificationChannel.shared.registerCategories()
        DispatchQueue.global(qos: .utility).async { ToneFile.ensure() }
        AlarmKitChannel.shared.startObserving()
        observeDevice()
        RunController.shared.resumeAfterLaunch(appState: appState)
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        EventLog.shared.log("will_terminate")
        RunStore.shared.markCleanExit(true)
        EventLog.shared.flushSync()
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        EventLog.shared.log("mem_warning")
    }

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        EventLog.shared.log("protected_data", ["available": false])
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        EventLog.shared.log("protected_data", ["available": true])
        EventLog.shared.retryPending()
    }

    private func observeDevice() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            EventLog.shared.log("lowpower", ["on": .flag(ProcessInfo.processInfo.isLowPowerModeEnabled)])
        })
        observers.append(center.addObserver(
            forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                EventLog.shared.log("battery", [
                    "lvl": .num(DeviceSnapshot.batteryPercent()), "state": .str(DeviceSnapshot.batteryState()),
                ])
            }
        })
        observers.append(center.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                EventLog.shared.log("battery", [
                    "lvl": .num(DeviceSnapshot.batteryPercent()), "state": .str(DeviceSnapshot.batteryState()),
                ])
            }
        })
    }

    /// "UIApplicationLaunchOptionsLocationKey" → "location".
    private static func shortName(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("UIApplicationLaunchOptions") { s.removeFirst("UIApplicationLaunchOptions".count) }
        if s.hasSuffix("Key") { s.removeLast(3) }
        guard let first = s.first else { return raw }
        return first.lowercased() + s.dropFirst()
    }
}

/// UNUserNotificationCenter delegate, nonisolated on purpose (the protocol is not main-actor isolated).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// App in the foreground: show the alarm notification anyway, and log it as delivered.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        NotificationChannel.shared.logDelivered([notification])
        completionHandler([.banner, .list, .sound])
    }

    /// "Tắt" action → alarm_stop via=notif_action and end the run; other taps are only logged.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let info = request.content.userInfo
        let runId = info["runId"] as? String ?? ""
        let kind = info["kind"] as? String ?? "?"
        let action = response.actionIdentifier
        NotificationChannel.shared.logDelivered([response.notification])
        if action == NotificationChannel.stopAction {
            EventLog.shared.log(to: runId, "alarm_stop", ["via": "notif_action", "id": .str(request.identifier), "kind": .str(kind)])
            Task { @MainActor in
                RunController.shared.alarmStopped(via: "notif_action", runId: runId, kind: kind)
                completionHandler()
            }
        } else {
            EventLog.shared.log(to: runId, "notif_tap", ["action": .str(action), "id": .str(request.identifier), "kind": .str(kind)])
            completionHandler()
        }
    }
}
