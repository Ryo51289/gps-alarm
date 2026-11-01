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

Định dạng fixture (schema v1, T02) và quy tắc đồng hồ ảo cho harness test: `fixtures/traces/README.md`.

**Nguyên tắc:** quyết định "báo hay chưa" nằm ở native để vẫn chạy khi Flutter engine đã bị huỷ.
Flutter chỉ cấu hình chuyến, hiển thị trạng thái, và lưu lịch sử khi được đánh thức.

## 2. Trip Engine (hợp đồng chung — nguồn chuẩn là `docs/specs/T10.md`, mục này chỉ tóm tắt)
- Reducer thuần: `reduce(state, input) → Step(state', events, view)` (T10 §1, §2.5). Không đồng hồ hệ thống, không IO;
  thời gian chỉ đến từ `input.atMs` (đồng hồ chuyến không lùi, T10 §2.6). Test bằng fixture trên JVM / `swift test`.
- Cấu hình: `TripConfig` (đích, chế độ, ngưỡng, nhắc nhẹ, `vehicleHint`) — T10 §2.1. Cài đặt báo (âm, rung, flash,
  cách tắt) **không** vào engine; `TripConfigMsg` (T14) mang thêm cho AlarmController.
- Input (T10 §2.2): `LocationFix` (lat, lng, accuracyM, speedMps?, fixAtMs), `Tick`, `BatterySample`,
  `LocationAvailability`, `FallbackScheduled`, `FallbackFired`, `AlarmSilenced` (báo đang kêu tự ngừng mà chưa ai bấm),
  `UserAction` (Dismiss / Snooze / StopTrip / lựa chọn màn 7).
- Output — sự kiện (T10 §2.3): `PreAlert`, `Alarm(reason, ringNow, snoozeAllowed)`, `Snoozed`, `GpsLost(cause)`,
  `GpsRecovered`, `LowBatteryRisk`, `Overshoot`, `Arrived`, `FallbackAlarmChanged(fallbackAtMs?, cause)`,
  `SamplingPolicyChanged(policy)`, `TripEnded(outcome, endReason, summary)`.
  - `reason` gồm cả hai lưới an toàn: `PASSED_CLOSEST` (đã qua điểm gần đích nhất) và `TIMEOUT` (hết thời lượng tối đa mà
    chưa báo — chuyến không bao giờ kết thúc lặng lẽ).
  - `ringNow = false`: báo đã kêu ở nơi khác (báo dự phòng của OS) → chỉ cập nhật UI/lịch sử, không phát âm, không đặt báo mới.
  - `outcome` ∈ `ON_TIME` / `SNOOZED` / `MISSED` / `CANCELLED` (dừng chuyến trước khi báo).
- Output — view: `TripView` (= `StateUpdate`) có trong **mọi** Step: khoảng cách, ETA và khoảng ETA, tiến độ, sai số khi mất GPS,
  pin, `samplingPolicy`, giờ báo dự phòng, `wakeAtMs`… (T10 §2.4). Sự kiện và view **không** chứa toạ độ.
- `SamplingPolicy` (tier `SPARSE`/`MEDIUM`/`DENSE`, interval, accuracy) do engine đề xuất theo giờ báo dự kiến; lớp Location áp dụng (§5).
- Báo dự phòng theo ETA: engine tính giờ, phát `FallbackAlarmChanged`; lớp nền tảng đặt báo của OS và phản hồi
  `FallbackScheduled` / `FallbackFired` (T10 §4.10).
- Snapshot/khôi phục: `EngineState` lưu được thành JSON (`snapshotVersion: 1`), lưu ở bộ nhớ riêng không sao lưu;
  process mở lại thì `restore(state, now, RestoreInfo)` (`RANG` / `DISMISSED` / `PENDING` / `MISSING` / `UNKNOWN`) để không kêu
  lần hai và ghi đúng kết quả khi người dùng đã bấm Tắt lúc process chết (T10 §7).
- Tham số: một bảng `EngineParams` (T10 §5), ghi đè qua **một** khoá Remote Config `trip_engine_params` (chuỗi JSON),
  cố định suốt chuyến.

## 3. Pigeon API (phác thảo — chốt ở T14)
```dart
@HostApi() abstract class TripHostApi {
  void startTrip(TripConfigMsg config);      // bắt đầu foreground service / location updates
  void stopTrip();
  TripStateMsg? currentTrip();               // khôi phục UI sau khi app bị kill (đọc view từ snapshot, T10 §7)
  void setBatteryChoice(BatteryChoiceMsg choice); // màn 7 → UserAction (T10 §2.2, §4.9)
  void startSimulation(String traceAsset, double speedFactor);
}
@HostApi() abstract class PermissionHostApi {
  PermissionStatusMsg status();              // location always, notifications, full-screen, battery opt
  void openSettings(SettingsTargetMsg target);
  DeviceInfoMsg deviceInfo();                // hãng máy → màn hướng dẫn pin
}
@HostApi() abstract class AlarmHostApi {
  void previewSound(String soundId, double volume);
  void dismiss(String method); void snooze();  // → UserAction DISMISS / SNOOZE
}
@FlutterApi() abstract class TripFlutterApi {
  void onState(TripStateMsg state);          // TripStateMsg = TripView (T10 §2.4)
  void onEvent(TripEventMsg event);          // sự kiện T10 §2.3, dạng dẹt: type + trường nullable
}
```

## 4. Dữ liệu cục bộ (drift)
- `trips(id, destinationName, lat, lng, mode, threshold, startedAt, alarmAt, dismissedAt, result, distanceKm, vehicleGuess)`;
  `result` ∈ `on_time` / `snoozed` / `missed` / `cancelled`, lấy từ `TripEnded` (`outcome` + `summary`, T10 §2.3; T28)
- `saved_places(id, label, name, lat, lng, kind)`
- Cài đặt: `shared_preferences` (âm báo, âm lượng, rung, flash, tai nghe, đơn vị, giờ, giao diện, ngôn ngữ, mặc định chuyến).
- `assets/stations.json`: `{id, name, nameAscii, kind: train|coach|bus, province, lat, lng}` build từ `data/stations/`.

## 5. Chiến lược lấy mẫu vị trí (định hướng)
Mốc tính theo **thời gian tới giờ báo dự kiến** (không phải giờ tới nơi), có trễ chống đổi qua lại. Giá trị mặc định nằm ở
T10 §5 (chỉnh qua Remote Config), quy tắc chọn tier ở T10 §4.12. Lớp nền tảng chỉ ánh xạ `SamplingPolicy` sang API của mình.

| Tới giờ báo dự kiến | Tier (mặc định T10 §5) | Android (FLP) | iOS (**T17 chốt**) |
|---|---|---|---|
| > 60 phút | `SPARSE`: 180 s, BALANCED | BALANCED | T17 chốt; định hướng: continuous, độ chính xác thấp |
| 15–60 phút | `MEDIUM`: 30 s, HIGH | HIGH_ACCURACY | T17 chốt; định hướng: continuous, accuracy hundredMeters |
| < 15 phút | `DENSE`: 5 s, HIGH | HIGH_ACCURACY | T17 chốt; định hướng: continuous, accuracy best |

- Đang lấy fix đầu, đang báo / báo lại / đã quá trạm → `DENSE`. Chưa đủ dữ liệu tốc độ → ít nhất `MEDIUM`.
- Màn 7 "Tiết kiệm tối đa" → nhân đôi chu kỳ `SPARSE`/`MEDIUM`, `DENSE` giữ nguyên.
- iOS: mức quyền tối thiểu là When In Use + background location updates (S3 K4 #16, S5 F9; S3 chưa chốt C2), nên cột iOS mặc định
  dùng continuous updates. Region monitoring / significant change chỉ khởi chạy lại app đã chết khi có quyền **Always**
  ([Apple: Choosing the Location Services Authorization to Request](https://developer.apple.com/documentation/bundleresources/choosing-the-location-services-authorization-to-request));
  chỉ dùng nếu T17 xin được Always, và phải kiểm S3-13 trước.

## 6. Rủi ro kỹ thuật (xử lý ở Phase 1 — spikes)
1. iOS: phát báo thức to khi app đang chạy nền vì vị trí (AlarmKit/fallback).
2. Android OEM (Xiaomi/Oppo/Vivo) diệt foreground service.
3. Pin trong 10 giờ.
4. Duyệt store: quyền vị trí nền, full-screen intent.

Mọi thay đổi kiến trúc → ADR trong `adr/NNN-ten.md` (bối cảnh, quyết định, hệ quả).
