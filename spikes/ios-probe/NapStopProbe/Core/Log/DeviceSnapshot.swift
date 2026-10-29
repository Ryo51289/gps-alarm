import AlarmKit
import AVFoundation
import CoreLocation
import Foundation
import UIKit
import UserNotifications

/// Device and permission state shown in the UI and logged as `perm_snapshot` (S3 §6.5, §6.6).
struct DeviceInfo: Equatable {
    var model = "?"
    var ios = "?"
    var bundleId = "?"
    var batteryPercent: Double?
    var batteryState = "?"
    var lowPower = false
    var bgRefresh = "?"
    var locAuth = "?"
    var locAccuracy = "?"
    var notifAuth = "?"
    var timeSensitive = "?"
    var notifSound = "?"
    var notifLock = "?"
    var alarmKitAuth = "?"
    var mediaVolume: Double?

    var batteryText: String {
        guard let batteryPercent else { return "?" }
        return "\(Int(batteryPercent))% (\(batteryState))"
    }
}

/// Names of system enums as log values. Nonisolated: also used from delegate callbacks.
enum StatusNames {
    static func location(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedAlways: return "always"
        case .authorizedWhenInUse: return "whenInUse"
        @unknown default: return "unknown"
        }
    }

    static func accuracy(_ a: CLAccuracyAuthorization) -> String {
        switch a {
        case .fullAccuracy: return "full"
        case .reducedAccuracy: return "reduced"
        @unknown default: return "unknown"
        }
    }

    static func notification(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown"
        }
    }

    static func setting(_ s: UNNotificationSetting) -> String {
        switch s {
        case .notSupported: return "notSupported"
        case .disabled: return "disabled"
        case .enabled: return "enabled"
        @unknown default: return "unknown"
        }
    }

    /// Explicit switch: String(describing:) of a system Swift enum is not guaranteed to be the case name.
    static func alarmKit(_ s: AlarmManager.AuthorizationState) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    static func alarmState(_ s: Alarm.State) -> String {
        switch s {
        case .scheduled: return "scheduled"
        case .countdown: return "countdown"
        case .paused: return "paused"
        case .alerting: return "alerting"
        @unknown default: return "unknown"
        }
    }
}

@MainActor
enum DeviceSnapshot {
    /// Hardware model id, e.g. "iPhone17,4".
    static func model() -> String {
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        let machine = withUnsafePointer(to: &info.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
        return machine.isEmpty ? UIDevice.current.model : machine
    }

    static func appState() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    static func batteryPercent() -> Double? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : (Double(level) * 100).rounded()
    }

    static func batteryState() -> String {
        switch UIDevice.current.batteryState {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }

    static func collect(location: CLLocationManager) async -> DeviceInfo {
        var d = DeviceInfo()
        d.model = model()
        d.ios = UIDevice.current.systemVersion
        d.bundleId = Bundle.main.bundleIdentifier ?? "?"
        d.batteryPercent = batteryPercent()
        d.batteryState = batteryState()
        d.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: d.bgRefresh = "available"
        case .denied: d.bgRefresh = "denied"
        case .restricted: d.bgRefresh = "restricted"
        @unknown default: d.bgRefresh = "unknown"
        }
        d.locAuth = StatusNames.location(location.authorizationStatus)
        d.locAccuracy = StatusNames.accuracy(location.accuracyAuthorization)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        d.notifAuth = StatusNames.notification(settings.authorizationStatus)
        d.timeSensitive = StatusNames.setting(settings.timeSensitiveSetting)
        d.notifSound = StatusNames.setting(settings.soundSetting)
        d.notifLock = StatusNames.setting(settings.lockScreenSetting)
        d.alarmKitAuth = StatusNames.alarmKit(AlarmManager.shared.authorizationState)
        d.mediaVolume = Double(AVAudioSession.sharedInstance().outputVolume)
        return d
    }

    /// `perm_snapshot` fields (S3 §6.6).
    static func permFields(_ d: DeviceInfo) -> [String: JSONScalar] {
        [
            "locAuth": .str(d.locAuth),
            "locAccuracy": .str(d.locAccuracy),
            "notifAuth": .str(d.notifAuth),
            "timeSensitive": .str(d.timeSensitive),
            "notifSound": .str(d.notifSound),
            "notifLock": .str(d.notifLock),
            "alarmKitAuth": .str(d.alarmKitAuth),
            "lowPower": .flag(d.lowPower),
            "bgRefresh": .str(d.bgRefresh),
            "batt": .num(d.batteryPercent),
            "battState": .str(d.batteryState),
            "mediaVol": .num(d.mediaVolume),
        ]
    }
}
