# Kiến trúc MVP 1

## 1. Tổng quan

```
┌───────────────────────── Flutter (Dart) ─────────────────────────┐
│ features/: onboarding, home, destination, alarm_settings,        │
│ tracking, alarm, history, settings, battery_guide, simulation    │
│ data: drift (SQLite) · stations.json · shared_preferences        │
└───────────────────────────── Pigeon ─────────────────────────────┘
┌────────── Android (Kotlin) ──────────┐ ┌──────────── iOS (Swift) ────────────┐
│ LocationService (Foreground, FLP)    │ │ LocationController (CLMonitor +     │
│ TripEngine (thuần Kotlin, test JVM)  │ │   continuous updates)               │
│ AlarmController (full-screen intent, │ │ TripEngine (thuần Swift, XCTest)    │
│   MediaPlayer USAGE_ALARM, vibrate)  │ │ AlarmController (AlarmKit/fallback) │
│ SimulatedLocationSource (GPX replay) │ │ SimulatedLocationSource             │
└──────────────────────────────────────┘ └─────────────────────────────────────┘
                   ▲ cùng bộ fixture: fixtures/traces/*.gpx + *.expect.json ▲
```

**Nguyên tắc:** quyết định "báo hay chưa" nằm ở native để vẫn chạy khi Flutter engine đã bị huỷ.
Flutter chỉ cấu hình chuyến, hiển thị trạng thái, và lưu lịch sử khi được đánh thức.

## 2. Trip Engine (hợp đồng chung — chi tiết trong spec T10)
- Input: `TripConfig` (đích, chế độ, ngưỡng, nhắc nhẹ, cài đặt báo) + chuỗi `LocationSample`
  (lat, lng, accuracy, speed?, timestamp) + `BatterySample`.
- Output (sự kiện): `PreAlert`, `Alarm(reason)`, `GpsLost`, `GpsRecovered`, `LowBatteryRisk`,
  `Overshoot`, `Arrived`, `StateUpdate(distance, etaRange, progress, samplingPolicy)`.
- Thuần (pure): không phụ thuộc Android/iOS API → test được bằng fixture trên JVM/XCTest.
- `SamplingPolicy` do engine đề xuất (interval, accuracy) theo ETA còn lại; Location layer áp dụng.

## 3. Pigeon API (phác thảo — chốt ở T14)
```dart
@HostApi() abstract class TripHostApi {
  void startTrip(TripConfigMsg config);      // bắt đầu foreground service / location updates
  void stopTrip();
  TripStateMsg? currentTrip();               // khôi phục UI sau khi app bị kill
  void startSimulation(String traceAsset, double speedFactor);
}
@HostApi() abstract class PermissionHostApi {
  PermissionStatusMsg status();              // location always, notifications, full-screen, battery opt
  void openSettings(SettingsTargetMsg target);
  DeviceInfoMsg deviceInfo();                // hãng máy → màn hướng dẫn pin
}
@HostApi() abstract class AlarmHostApi {
  void previewSound(String soundId, double volume);
  void dismiss(String method); void snooze();
}
@FlutterApi() abstract class TripFlutterApi {
  void onState(TripStateMsg state);
  void onEvent(TripEventMsg event);          // PreAlert, Alarm, GpsLost, Overshoot, Arrived...
}
```

## 4. Dữ liệu cục bộ (drift)
- `trips(id, destinationName, lat, lng, mode, threshold, startedAt, alarmAt, dismissedAt, result, distanceKm, vehicleGuess)`
- `saved_places(id, label, name, lat, lng, kind)`
- Cài đặt: `shared_preferences` (âm báo, âm lượng, rung, flash, tai nghe, đơn vị, giờ, giao diện, ngôn ngữ, mặc định chuyến).
- `assets/stations.json`: `{id, name, nameAscii, kind: train|coach|bus, province, lat, lng}` build từ `data/stations/`.

## 5. Chiến lược lấy mẫu vị trí (định hướng)
| ETA còn lại | Android (FLP) | iOS |
|---|---|---|
| > 60 phút | BALANCED, 3–5 phút | region monitoring + significant change |
| 15–60 phút | BALANCED → HIGH, 30–60 giây | continuous, accuracy hundredMeters |
| < 15 phút | HIGH_ACCURACY, 5–10 giây | continuous, accuracy best |

## 6. Rủi ro kỹ thuật (xử lý ở Phase 1 — spikes)
1. iOS: phát báo thức to khi app đang chạy nền vì vị trí (AlarmKit/fallback).
2. Android OEM (Xiaomi/Oppo/Vivo) diệt foreground service.
3. Pin trong 10 giờ.
4. Duyệt store: quyền vị trí nền, full-screen intent.

Mọi thay đổi kiến trúc → ADR trong `adr/NNN-ten.md` (bối cảnh, quyết định, hệ quả).
