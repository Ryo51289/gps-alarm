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

## 3. Pigeon API (chốt ở T14)

Nguồn chuẩn là `docs/specs/T14.md` §3 và `app/pigeons/core_api.dart`; mục này chỉ tóm tắt.

Pigeon 29.1.0 (ghim cứng). Code sinh commit vào repo: Dart `lib/core/bridge/core_api.g.dart`, Kotlin
`app.napstop.core.bridge` (`CoreApi.g.kt`), Swift `ios/Runner/Bridge/CoreApi.g.swift`; CI kiểm code sinh khớp input.
Mọi kiểu có hậu tố `Msg`. Dart dùng qua lớp mỏng `CoreBridge` (`lib/core/bridge/core_bridge.dart`), lỗi → `BridgeException`.

```dart
@HostApi() abstract class TripHostApi {            // mọi hàm @async (Kotlin suspend / Swift async)
  void startTrip(TripConfigMsg config, double destLat, double destLng, SimulationMsg? simulation);
      // Android: chỉ khi activity đang hiển thị (ADR-001 #2). Lỗi: invalid-config, trip-active, permission-missing,
      // not-foreground, start-failed, simulation-unavailable, internal (T14 §4)
  void stopTrip(String tripId);                    // UserAction STOP_TRIP; tripId lạ = no-op
  ActiveTripMsg? currentTrip();                    // config + TripStateMsg đọc từ snapshot (sống qua process chết, T10 §7)
  void setBatteryChoice(String tripId, BatteryChoiceMsg choice); // màn 7 → UserAction BATTERY_*
  void dismiss(String tripId); void snooze(String tripId);       // UserAction DISMISS / SNOOZE
  List<FinishedTripMsg> pendingFinishedTrips();    // hàng đợi chuyến đã kết thúc (lịch sử T28), lấy → ghi drift → ack
  void ackFinishedTrips(List<String> tripIds);
}
@HostApi() abstract class PermissionHostApi {
  PermissionStatusMsg status();                    // các mục §7 của nền tảng đang chạy; Android KHÔNG có vị trí nền (ADR-001)
  @async PermissionStatusMsg request(PermissionKindMsg kind);   // location | notifications | alarmKit
  bool openSettings(SettingsTargetMsg target);
  DeviceInfoMsg deviceInfo();                      // hãng máy → màn hướng dẫn pin
}
// PermissionStatusMsg: location (notDetermined | denied | whileInUse | always — `always` chỉ có trên iOS), precise,
//   locationServicesEnabled, notifications, fullScreenIntent (Android), exactAlarm (Android),
//   batteryOptimizationIgnored (Android), alarmKit (iOS 26+). Mục không áp dụng = notApplicable.
// SettingsTargetMsg: appDetails, locationServices, notifications, fullScreenIntent, exactAlarm, batteryOptimization.
@HostApi() abstract class AlarmHostApi { void previewSound(String soundId, double volume); void stopPreview(); }
@EventChannelApi() abstract class TripEventChannelApi { TripUpdateMsg tripUpdates(); }
// TripUpdateMsg là sealed: TripStateUpdateMsg(TripStateMsg = TripView T10 §2.4), PreAlertMsg, AlarmMsg, SnoozedMsg,
//   GpsLostMsg, GpsRecoveredMsg, LowBatteryRiskMsg, OvershootMsg, ArrivedMsg, TripEndedMsg(FinishedTripMsg).
// Mỗi Step: một TripStateUpdateMsg rồi các sự kiện theo thứ tự T10 §2.3; khi Dart bắt đầu nghe thì phát lại view mới nhất;
//   không người nghe thì không gửi (kết thúc chuyến vẫn còn trong pendingFinishedTrips).
```
- **Không lớp Pigeon nào chứa toạ độ** (T14 D5): Pigeon sinh `toString` in mọi trường. Toạ độ chỉ đi qua tham số
  `destLat`/`destLng` của `startTrip`; Dart tự lưu đích theo `tripId` (drift). Không log message Pigeon.
- `dismiss`/`snooze` nằm ở `TripHostApi` và nhận `tripId`: lệnh tới trễ của chuyến cũ là no-op (T14 D10).
- Mô phỏng đi qua `startTrip(…, simulation)`, cùng pipeline với chuyến thật (T14 D11). Trước T15/T18, Android chạy
  `StubTripBackend` với kịch bản `stub/normal`, `stub/gps_lost`, `stub/low_battery`, `stub/overshoot`, `stub/no_fix`.
- `pendingFinishedTrips` + `ackFinishedTrips`: chuyến thường kết thúc khi Flutter không chạy, nên lịch sử đi qua hàng
  đợi bền hai pha thay vì chỉ qua stream (T14 D12).
- Phát lại view cho **mọi** subscriber: native chỉ thấy `onListen` của subscriber Dart đầu tiên (stream broadcast), nên
  `CoreBridge.updates` giữ `TripStateUpdateMsg` gần nhất và gửi ngay cho subscriber đến sau. Không phát lại sự kiện cũ,
  bỏ sau `TripEndedMsg` của chuyến đó, xoá khi không còn ai nghe.
- Android: backend sống theo process, có thể có 2 engine Flutter cùng lúc. Mỗi engine gắn listener riêng
  (`TripBackend.addListener` trả `ListenerHandle`) và chỉ gỡ đúng listener của mình. Lỗi trong vòng tick (ví dụ ghi
  snapshot khi đầy bộ nhớ) được bắt và ghi log tên lớp, không làm crash app.

> **Quy tắc cho backend thật (T15/T17, review T14 R2-1):** lỗi ghi snapshot không bao giờ được chặn việc kêu báo thức, thông báo
> hay full-screen. Engine kêu và commit trạng thái trong bộ nhớ trước; ghi đĩa là best-effort, có thử lại ở Step sau.

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
2. Android OEM (Xiaomi/Oppo/Vivo) diệt foreground service. Không có vị trí nền (ADR-001) nên không khởi động lại FGS `location` từ
   nền được (sticky restart: S1 đo trên máy thật); lưới an toàn là báo dự phòng theo ETA bằng exact alarm (T10 §4.10, T15) và âm báo
   trong service riêng không cần quyền vị trí (T16).
3. Pin trong 10 giờ.
4. Duyệt store: FGS `location` (khai use case Navigation / ride tracking), full-screen intent và quyền báo thức chính xác (khai là
   app báo thức), FGS phát âm báo. **Không** xin vị trí nền trên Android ([ADR-001](adr/001-android-foreground-only-location.md));
   iOS xin When In Use, Always tuỳ chọn. Phân tích và checklist nộp store: `docs/spikes/S5.md` (§4, §8, mục "Cập nhật sau Gate 1");
   danh sách quyền: §7.

Mọi thay đổi kiến trúc → ADR trong `adr/NNN-ten.md` (bối cảnh, quyết định, hệ quả).

## 7. Quyền theo nền tảng (MVP 1)

Nguồn chuẩn cho manifest (T15, T16), Info.plist (T17), màn 0 / thẻ "Sẵn sàng" (T21, T22) và khai báo store (T40). Căn cứ: ADR-001,
S2 §6 + Vòng 4, S5 §4–§8 + "Cập nhật sau Gate 1", S3 K3–K4, T10 §2.6/§4.10. Thêm hoặc bớt quyền phải có spec/ADR. Mức bắt buộc
khi bắt đầu chuyến: PRD §3.1.

### 7.1 Android — manifest đích

| Quyền / khai báo | Mục đích | Màn 0 | Đọc trạng thái | Mở cài đặt |
|---|---|---|---|---|
| `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` (xin cùng một lần) | FGS `location` theo dõi chuyến | "Khi dùng ứng dụng" + "Chính xác" | `checkSelfPermission`; chỉ COARSE = gần đúng; `LocationManager.isLocationEnabled()` | xin lại FINE + COARSE; `ACTION_APPLICATION_DETAILS_SETTINGS`; `ACTION_LOCATION_SOURCE_SETTINGS` |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_LOCATION`; `LocationService` `foregroundServiceType="location"` | theo dõi chuyến | — | — | — |
| `POST_NOTIFICATIONS` (runtime, API 33+) | thông báo thường trực, báo thức, "Chuyến đi bị gián đoạn" | Có: API 33+ xin quyền; mọi API kiểm, bị tắt thì cảnh báo | `areNotificationsEnabled()` (mọi API) | `ACTION_APP_NOTIFICATION_SETTINGS` |
| `USE_FULL_SCREEN_INTENT` | màn báo thức trên màn khoá | API 34+ khi chưa cấp | `canUseFullScreenIntent()` | `ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT` |
| `USE_EXACT_ALARM` (API 33+) + `SCHEDULE_EXACT_ALARM` `maxSdkVersion="32"` | báo dự phòng theo ETA, `wakeAtMs` (T10 §2.6, §4.10); điều kiện dùng FGS `systemExempted` | chỉ khi `canScheduleExactAlarms() == false` | `canScheduleExactAlarms()` (API 31+) | `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` |
| `FOREGROUND_SERVICE_SYSTEM_EXEMPTED` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK`; `AlarmRingService` `foregroundServiceType="systemExempted\|mediaPlayback"`, `android:process=":ring"` | phát âm báo không cần quyền vị trí, khởi động được từ exact alarm (ADR-001 Hệ quả, S2 V4-1, T10 RK14); thứ tự kiểu do T16 chốt | — | — | — |
| `RECEIVE_BOOT_COMPLETED` | sau reboot: thông báo "Chuyến đi bị gián đoạn", đặt lại báo dự phòng (T10 §7.2 `MISSING`) | — | — | — |
| `VIBRATE`, `WAKE_LOCK` | rung, giữ CPU khi kêu | — | — | — |
| `INTERNET`, `ACCESS_NETWORK_STATE` | bản đồ, Places, Firebase | — | — | — |
| Tối ưu pin: **không khai quyền** | giảm rủi ro OEM diệt FGS | hướng dẫn + màn 9 | `PowerManager.isIgnoringBatteryOptimizations()` | `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` |

**Không khai:** `ACCESS_BACKGROUND_LOCATION` (ADR-001), `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `SYSTEM_ALERT_WINDOW`,
`ACCESS_NOTIFICATION_POLICY`, FGS `specialUse` / `shortService` / `dataSync`. Kiểm **manifest đã merge**: plugin có thể tự thêm
`ACCESS_BACKGROUND_LOCATION`, khi đó phải gỡ bằng `tools:node="remove"` (S5 §8.1).

Quyền báo thức chính xác: phương án A của PO (T19 Q1, 2026-11-01) — `USE_EXACT_ALARM` khai trên Play là app báo thức. Play từ chối ở
bản internal → chuyển sang `SCHEDULE_EXACT_ALARM` cho mọi API (người dùng tự cấp trên màn 0), không đổi cách đọc trạng thái.

Ràng buộc FGS `location` (ADR-001 #2–#4): chỉ `startForegroundService` khi activity đang hiển thị (nút "Bắt đầu theo dõi") hoặc từ
lúc người dùng chạm notification của app; không khởi động bằng exact alarm hay `BOOT_COMPLETED` (Android 14+: `SecurityException`;
Android 11–13: service chạy nhưng không có vị trí; T10 §2.6).
Dừng ngay khi chuyến kết thúc; trần thời lượng theo T10 §4.13. Lưu ý: `mediaPlayback` không được khởi động từ `BOOT_COMPLETED` khi
target 35+, nên báo ngay sau reboot dùng `systemExempted` (T16).

### 7.2 iOS — Info.plist / capability

| Khoá / capability | Mục đích | Màn 0 | Đọc trạng thái | Mở cài đặt |
|---|---|---|---|---|
| `NSLocationWhenInUseUsageDescription`, `UIBackgroundModes=[location]`; `allowsBackgroundLocationUpdates = true`, bắt đầu cập nhật khi app đang mở; iOS 17+: thêm `CLBackgroundActivitySession` | theo dõi chuyến; mức tối thiểu | "Khi dùng ứng dụng" + "Chính xác" | `authorizationStatus`, `accuracyAuthorization`, `locationServicesEnabled()` | `openSettingsURLString` |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | chỉ khi T17 dùng vùng `CLMonitor` quanh đích (§5); thay S3 K4 #17 "hai chuỗi quyền vị trí": không dùng Always thì không khai | không | — | — |
| `NSAlarmKitUsageDescription` (iOS 26+) | báo thức vượt Im lặng/Tập trung | Có | `AlarmManager.authorizationState` | `openSettingsURLString` |
| Thông báo (`UNUserNotificationCenter`), capability Time Sensitive | trạng thái, nhắc nhẹ, kênh báo iOS < 26 | Có | `notificationSettings()` | `openNotificationSettingsURLString` |

Không bật `audio` background mode. Critical Alerts chỉ dùng nếu Apple duyệt entitlement; demo không phụ thuộc (S5 F10).

### 7.3 Quy tắc bắt đầu chuyến

`startTrip` chỉ chạy khi có vị trí ("Khi dùng ứng dụng" hoặc cao hơn) + chính xác + định vị bật + ít nhất một kênh báo thức
(Android: luôn có; iOS: AlarmKit hoặc thông báo). Còn lại là cảnh báo (PRD §3.1). Hàm kiểm tra viết bằng Dart thuần (T21).
