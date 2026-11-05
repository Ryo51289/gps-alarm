// Native strings of the iOS runtime (docs/specs/T17.md §8, D19). Vietnamese is the source; IU34 compares with the ARB.
import Foundation
import Trip

public enum NativeCopy {
    /// ARB key → (vi, en). Placeholders use the ARB names ({destination}, {minutes}, {distance}).
    public static let table: [String: (vi: String, en: String)] = [
        "notifAlarmTitle": ("Sắp tới {destination}", "Almost at {destination}"),
        "alarmReasonOvershoot": ("Có thể bạn đã đi quá {destination}", "You may have passed {destination}"),
        "alarmKitTitleCheck": ("Kiểm tra đã tới {destination} chưa", "Check if you've reached {destination}"),
        "alarmKitTitleFallback": ("Có thể sắp tới {destination}", "You may be near {destination}"),
        "alarmKitStop": ("Tắt", "Stop"),
        "alarmKitRingFailed": ("Chưa đặt được báo thức. Mở NapStop ngay.", "Couldn't set the alarm. Open NapStop now."),
        "notifDestinationUnknown": ("nơi đến", "your stop"),
        "gpsNotAcquired": ("Chưa có GPS — báo thức chưa hoạt động", "No GPS yet — alarm isn't active"),
        "gpsPermissionRevoked": ("Mất quyền vị trí — mở Cài đặt để bật lại", "Location permission off — open Settings"),
        "gpsServicesOff": ("Định vị đang tắt — bật lại để báo đúng lúc", "Location is off — turn it on"),
        "fallbackScheduleFailed": ("Chưa đặt được báo thức dự phòng. Mở Cài đặt để cấp quyền.",
                                   "Couldn't set the backup alarm. Open Settings to allow it."),
        "preAlertBody": ("Sắp tới {destination} — còn khoảng {minutes} phút", "Almost at {destination} — about {minutes} min"),
        "preAlertBodyDistance": ("Sắp tới {destination} — còn khoảng {distance}", "Almost at {destination} — about {distance}"),
        "notifInterruptedTitle": ("Chuyến đi bị gián đoạn", "Trip tracking interrupted"),
        "notifInterruptedBody": ("Chạm để tiếp tục theo dõi", "Tap to keep tracking"),
    ]

    /// Keys added by T17 (§8); the others already exist in app_vi.arb / app_en.arb.
    public static let newKeys: Set<String> = ["alarmKitTitleCheck", "alarmKitTitleFallback", "alarmKitStop", "alarmKitRingFailed"]

    /// "vi" | "en": `napstop.appLocale` (T28) when set to one of them, else the device language, else vi.
    public static func localeTag(stored: String?, preferredLanguages: [String]) -> String {
        if stored == "vi" || stored == "en" { return stored! }
        for l in preferredLanguages {
            if l.hasPrefix("vi") { return "vi" }
            if l.hasPrefix("en") { return "en" }
        }
        return "vi"
    }

    public static func string(_ key: String, _ locale: String, _ args: [String: String] = [:]) -> String {
        guard let pair = table[key] else { return key }
        var s = locale == "en" ? pair.en : pair.vi
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    static func destination(_ name: String?, _ locale: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? string("notifDestinationUnknown", locale) : trimmed
    }

    /// Title of a "now" or guard alarm for `reason` (§8 table).
    public static func alarmTitle(_ reason: AlarmReason, destinationName: String?, locale: String) -> String {
        let key: String
        switch reason {
        case .overshoot: key = "alarmReasonOvershoot"
        case .timeout, .fallbackMissed: key = "alarmKitTitleCheck"
        case .gpsLost, .fallback: key = "alarmKitTitleFallback"
        default: key = "notifAlarmTitle"
        }
        return string(key, locale, ["destination": destination(destinationName, locale)])
    }

    /// Title of a fallback slot (it rings only when the app could not ring itself).
    public static func fallbackTitle(destinationName: String?, locale: String) -> String {
        string("alarmKitTitleFallback", locale, ["destination": destination(destinationName, locale)])
    }

    /// (title, body) of a trip notice (§5.10).
    public static func notice(_ n: TripNotice, destinationName: String?, locale: String) -> (title: String, body: String) {
        let dest = destination(destinationName, locale)
        switch n {
        case .noGpsYet: return (dest, string("gpsNotAcquired", locale))
        case .permissionRevoked: return (dest, string("gpsPermissionRevoked", locale))
        case .servicesOff: return (dest, string("gpsServicesOff", locale))
        case .fallbackFailed: return (dest, string("fallbackScheduleFailed", locale))
        case .interrupted: return (string("notifInterruptedTitle", locale), string("notifInterruptedBody", locale))
        case .ringFailed: return (dest, string("alarmKitRingFailed", locale))
        case let .preAlert(distanceM, etaS, byDistance):
            if byDistance || etaS == nil {
                return (dest, string("preAlertBodyDistance", locale,
                                     ["destination": dest, "distance": NoticeFormatter.distance(Double(distanceM), locale)]))
            }
            return (dest, string("preAlertBody", locale,
                                 ["destination": dest, "minutes": String(NoticeFormatter.minutes(etaS ?? 0))]))
        }
    }
}

/// Distance / minutes text, same rounding as T15 §5.10 / T23 (Dart formatDistanceShort). Pure.
public enum NoticeFormatter {
    /// 10 m steps below 1 km, 100 m steps from 1 km (half up).
    public static func roundedDistanceM(_ m: Double) -> Int {
        let r10 = Int((m / 10.0 + 0.5).rounded(.down)) * 10
        return r10 < 1000 ? r10 : Int((m / 100.0 + 0.5).rounded(.down)) * 100
    }

    /// "850 m"; "1,2 km" (vi) / "1.2 km" (en); "1 km" without a trailing zero.
    public static func distance(_ m: Double, _ locale: String) -> String {
        let shown = roundedDistanceM(m)
        if shown < 1000 { return "\(shown) m" }
        let tenths = shown / 100
        let whole = tenths / 10, frac = tenths % 10
        let sep = locale == "en" ? "." : ","
        let group = locale == "en" ? "," : "."
        var w = String(whole)
        if whole >= 1000 {
            var parts: [String] = []
            var x = whole
            while x >= 1000 { parts.insert(String(format: "%03d", x % 1000), at: 0); x /= 1000 }
            parts.insert(String(x), at: 0)
            w = parts.joined(separator: group)
        }
        return (frac == 0 ? w : "\(w)\(sep)\(frac)") + " km"
    }

    /// ceil(etaS / 60), at least 1.
    public static func minutes(_ etaS: Int) -> Int { max(1, (etaS + 59) / 60) }
}
