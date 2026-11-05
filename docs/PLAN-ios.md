# Lộ trình iOS — từ hiện trạng tới bản demo TestFlight

Ngày: **2026-11-05**. Người viết: solution-designer. Bối cảnh: PO đổi ưu tiên (05/11/2026), làm **iOS trước**, Android để sau.
Tài liệu này là kế hoạch; spec chi tiết của task đầu tiên ở `docs/specs/T17.md`. Không sửa `docs/TASKS.md` (đề xuất dòng task ở §9).

Nguồn đã đọc: `CLAUDE.md`, PRD-MVP1 §3.1, §4, §5; ARCHITECTURE §1, §3, §5, §7.2; `docs/TASKS.md`; `docs/spikes/S3.md` (Kết luận K1–K6);
`docs/test-reports/S3.md` (lỗi #1–#9); T10 §2.6, §4.10 (nghĩa vụ 1–8), §7, §9; T13; T14 (Implementation notes, typecheck WSL); T15 (thân
spec + "sau hiện thực" + "sau test" G1–G3, B1–B3); T16 (D1–D21); T18 §13; T21 §9; T27 D1–D15; `app/pigeons/core_api.dart`;
`app/ios/**`; `.github/workflows/ios-compile.yml`, `ios-build.yml`.

## 1. Ràng buộc và công cụ

| Có | Dùng để | Không làm được |
|---|---|---|
| WSL Ubuntu, Swift 6.4.1 (`app/ios/Core/scripts/test-wsl.sh`) | `swift test` mọi target **thuần** của package NapStopCore (Trip Engine, runtime iOS thuần, fixture `fixtures/traces`) | Không có CoreLocation, AlarmKit, UIKit |
| xtool + Darwin SDK iPhoneOS/iPhoneSimulator 27.1 (WSL) | `swiftc -typecheck`/`-emit-module` cho mã Apple (CoreLocation, AlarmKit, UserNotifications, AppIntents) và Runner + `Flutter.xcframework` (`flutter precache --ios`); ký lại IPA + `xtool install` | Không chạy được app; không đọc `project.pbxproj`; không trích metadata App Intents |
| GitHub Actions `macos-latest` | `swift test` trên macOS, `flutter build ios` (simulator, device không ký), XCTest + `flutter test integration_test` trên iOS Simulator, đóng gói IPA | Không có máy thật; AlarmKit trên Simulator chưa có tài liệu xác nhận (§6.4) |
| iPhone 16 Plus, iOS 27.0 của PO (Apple ID miễn phí, xtool) | Biên bản trên máy thật (khoá máy, Im lặng, Tập trung, vuốt tắt app) | Chỉ khi PO cắm máy; hồ sơ ký hết hạn sau 7 ngày; bundle id có tiền tố `XTL-<TeamID>.`; không có Time Sensitive, không TestFlight |
| — | — | Không có Mac, không có `gh` CLI. `workflow_dispatch` chỉ chạy được từ giao diện web → đề xuất kích hoạt bằng push nhánh (§6.5) |

## 2. Hiện trạng iOS

- **Có:** NapStopCore (`app/ios/Core`, module `Trip`, chỉ thư viện chuẩn Swift) bit-parity với Kotlin: T13–T13.5 xong, P05 303/303 trên WSL.
  Chưa chạy `swift test` trên macOS (TASKS T13.x "chờ gộp ios-compile").
- **Có:** Pigeon Swift `Runner/Bridge/CoreApi.g.swift`; `CoreBridgeStub.swift` (trip trong bộ nhớ, không engine, quyền cố định,
  `deviceStatus()` chỉ pin, `mapsConfig()` thật, `setAppLocale` ghi `UserDefaults` khoá `napstop.appLocale`).
- **Có:** S3 kết luận **A — AlarmKit + fallback, có điều kiện**: AlarmKit đặt từ callback vị trí nền khi máy khoá kêu được khi Im lặng +
  Không làm phiền + Ngủ (trễ 5,0–5,9 s, gồm `AK_LEAD_S` 5 s); báo đặt trước vẫn kêu khi app treo/tự thoát/bị vuốt tắt. Chưa kiểm: When In
  Use (C2), lượt 10 giờ (C1), kênh Time Sensitive (C3), đặt lại báo từ nền nhiều lần.
- **Chưa có:** NapStopCore **chưa được liên kết vào Runner** (`project.pbxproj` chỉ có gói `FlutterGeneratedPluginSwiftPackage`).
  Info.plist chưa có khoá vị trí/AlarmKit/`UIBackgroundModes`. Chưa có flavor iOS (workflow xoá `default-flavor` khi build).
- **CI:** `ios-compile.yml` chỉ `workflow_dispatch`; chưa chạy lần nào được ghi trong tài liệu (T14 B02, T21, T27 đều "chờ").

## 3. Phân tích khoảng trống

### 3.1 Hợp đồng Pigeon (`app/pigeons/core_api.dart`)

| Hợp đồng | Android (task) | iOS hiện tại | iOS cần làm | Task iOS |
|---|---|---|---|---|
| `TripHostApi.startTrip` | T15 `TripRuntime.start` (cổng `startGate`, kiểm quyền, FGS, `TripStateUpdateMsg` trước khi trả lời, `trip-active` cho lời gọi thứ hai), T18 nhánh giả lập | Stub trong bộ nhớ | Runtime thật: kiểm app đang `active` (`not-foreground`), quyền vị trí/chính xác/định vị/kênh báo (`permission-missing` + `details`), bắt đầu `CLLocationManager` khi app đang mở, đặt báo dự phòng AlarmKit theo `FallbackAlarmChanged` đầu tiên. `simulation != nil` → `simulation-unavailable` tới T18.1 | **T17** (giả lập: T18.1) |
| `stopTrip`, `dismiss`, `snooze`, `setBatteryChoice` | T15 `userAction` | No-op | `UserAction` vào engine; `Snoozed`/`TripEnded` → dừng/huỷ alarm AlarmKit của chuyến | **T17** |
| `currentTrip()` | T15 đọc từ snapshot | Bộ nhớ | Đọc runtime đã nạp snapshot (sống qua process chết) | **T17** |
| `pendingFinishedTrips` / `ackFinishedTrips` | T15 `finished/<id>.properties` | Bộ nhớ | `Application Support/napstop_trip/finished/<id>.json`, loại khỏi sao lưu; ghi khi `TripEnded`, kể cả khi `TripEnded` sinh lúc khôi phục do StopIntent | **T17** |
| Stream `tripUpdates` (`TripStateUpdateMsg` + sự kiện, phát lại view cho subscriber mới) | T14/T15 `ListenerHub` + Tick phát lại | Phát lại view của stub | `RuntimeListener` → `MsgMapper` → `PigeonEventSink` trên main; phát lại bằng Tick khi `onListen` | **T17** |
| Khôi phục (`RestoreInfo` RANG/DISMISSED/PENDING/MISSING) | T15 §5.8 + G3, B1–B3 | — | `RestorePlanner` iOS: đối chiếu `AlarmManager.shared.alarms` + sổ báo + sự kiện StopIntent (K4 #8–#10, S3 #1) | **T17** |
| Báo "now" + báo dự phòng (nghĩa vụ 1–8 T10 §4.10) | T15 (sổ 2 khe, khe canh chuông G1) + T16 (`AlarmRingService` `:ring`) | — | AlarmKit `.fixed(now + 5 s)` cho "now"; báo dự phòng = alarm AlarmKit 2 khe (đặt mới trước, huỷ cũ sau); huỷ dự phòng chỉ khi thấy "now" `alerting` (K4 #3); không bao giờ huỷ alarm đang `alerting` (K4 #4) | **T17** |
| `AlarmHostApi.previewSound` / `stopPreview` | T16 (`USAGE_ALARM`) | No-op | `AVAudioPlayer` trong app (app đang mở); danh mục âm `default/horn/bell/beep/system` → file âm trong bundle cho AlarmKit `.named(...)` | **T17.2** |
| `consumeLaunchAction()` (`overshootRoute`) | T16 `LaunchActions` + T27 | `nil` | Nút phụ của alarm quá trạm "Xem đường quay lại" (AlarmKit `secondaryButtonBehavior = .custom`, mở app) ghi launch action; TTL 10 phút | **T17.2** |
| `showAlarmScreen(tripId)` | T16 mở `AlarmActivity` | `false` | Giữ `false` (iOS không có màn báo thức tự dựng; màn khoá dùng UI AlarmKit). Màn 5 Flutter (T27 D1, D2) là UI khi app đang mở. T17.2 xác nhận trên máy | T17.2 (chỉ xác nhận) |
| `setAppLocale` | T28 (cả process `:ring`) | Ghi `UserDefaults` | Chuỗi native (tiêu đề alarm, thông báo) đọc khoá này; T17 dùng ngay khi dựng tiêu đề alarm | **T17** (đọc), T17.2 (đủ mọi chuỗi) |
| `PermissionHostApi.status/request/openSettings` | T21 | Cố định | Ánh xạ T21 §9 (đã chốt): `authorizationStatus`, `accuracyAuthorization`, `locationServicesEnabled()` (không gọi trên main), `notificationSettings()`, `AlarmManager.authorizationState`; `request` chỉ When In Use | **T17.1** |
| `deviceInfo()` | T14 | Thật | Giữ | — |
| `deviceStatus()` | T14.1/T21 | Chỉ pin | Giữ (iOS không có API công khai cho âm lượng báo thức, nút Im lặng, Tập trung) | — |
| `mapsConfig()` | T23 | Thật (`GMSApiKey`, bundle id) | Giữ; khoá do PO cấp (Q5) | T23.1 |
| `distancesFromLastKnownM` | T23 (làm tròn 10 m / 100 m) | `nil` | `CLLocationManager().location` (không xin fix mới, không hỏi quyền), làm tròn như Android, không log | **T17.1** |
| `*BackgroundCheck` (màn 9) | T21 | `internal("unsupported")` / `nil` | Giữ (màn 9 iOS chỉ hiện "iPhone không cần bước này", T21 D17) | — |

### 3.2 Ngoài Pigeon: Flutter, cấu hình, dịch vụ

| Mục | Hiện trạng | Việc cho iOS | Task |
|---|---|---|---|
| Màn 0 quyền (T21) / thẻ "Sẵn sàng" (T22) | Dart đã có nhánh iOS (U08, U09, W12, W21: dòng Vị trí, Thông báo, Báo thức AlarmKit; `alarmChannel` chặn khi thiếu cả hai) | Chỉ cần native thật (T17.1). Kiểm trên Simulator + máy | T17.1 |
| Info.plist | Thiếu | T17: `NSLocationWhenInUseUsageDescription`, `NSAlarmKitUsageDescription`, `UIBackgroundModes=[location]` (**không** `audio`), `NSSupportsLiveActivities` (giữ như probe S3); chẩn đoán `UIFileSharingEnabled` tới T40. T17.1: `InfoPlist.strings` vi/en, `PrivacyInfo.xcprivacy`. **Không** khai `NSLocationAlwaysAndWhenInUseUsageDescription` (ARCH §7.2) | T17, T17.1 |
| Sao lưu iCloud | Android loại `napstop_db/`, `napstop_onboarding`, `napstop_permissions` khỏi sao lưu (`data_extraction_rules.xml`). iOS: `Application Support` **có** trong sao lưu; `shared_preferences` = `NSUserDefaults` (cũng sao lưu) | T17: snapshot runtime `isExcludedFromBackup`. T17.1: đặt `isExcludedFromBackup` cho `Application Support/napstop_db/` (chứa toạ độ đích, **lỗ hổng riêng tư hiện có**) và quyết cờ màn 0 (TASKS T17: "quyết loại khỏi iCloud backup như Android") | T17, T17.1 |
| Màn 5 / màn 8 | Android: `AlarmActivity` native ở `:ring` (T16 D8). Flutter có màn 5 dự phòng (T27 D1: chỉ khi app `resumed`, chuông kêu ≥ 4 s, `showAlarmScreen` = false) và màn 8 sau launch action | iOS: **UI AlarmKit của hệ thống** là bản tương đương `AlarmActivity` (toàn màn trên màn khoá, S3-1…4). Khi app đang mở, màn 5 Flutter hiện (vì `showAlarmScreen` = false), vuốt để tắt → `dismiss` → native `stop` alarm. Cách tắt lắc/phép tính, tăng dần, rung theo mức, flash, ưu tiên tai nghe **không** áp được lên UI AlarmKit (Q2). Màn 8 qua nút phụ AlarmKit (T17.2) | T17 (luồng tắt), T17.2, T28.3 |
| Mở Maps chỉ đường (T27 D8) | Maps URLs `https://www.google.com/maps/dir/?api=1&destination=…` + `url_launcher` `externalApplication`, không `canLaunchUrl` | Dùng nguyên trên iOS: có app Google Maps thì mở app, không thì trình duyệt [G-URLS]. Không cần `LSApplicationQueriesSchemes` (không gọi `canLaunchUrl`). Chỉ kiểm trên Simulator/máy | T28.3 (kiểm) |
| Google Maps iOS (T23) | `AppDelegate` gọi `GMSServices.provideAPIKey` từ `GMSApiKey` (`Secrets.xcconfig`, gitignore) | PO cấp khoá iOS; khoá giới hạn theo bundle id phải gồm cả bundle id có tiền tố xtool (`XTL-<TeamID>.app.napstop`); CI cần secret để IPA thử có bản đồ (Q5). Places dùng header `X-Ios-Bundle-Identifier` = bundle id thật lúc chạy | T23.1 |
| Firebase iOS (T29) | Bước B chờ file cấu hình của PO; `telemetry_bootstrap` không có cấu hình thì no-op | Đăng ký app iOS trong dự án Firebase, `firebase_options` có mục iOS; Crashlytics cần bước tải dSYM (build phase) | T29.2 |
| Flavor dev/prod | Android có; iOS không có scheme `dev` (workflow xoá `default-flavor`), `AppFlavor` = dev, bundle id `app.napstop` | Giữ một cấu hình tới T40 (Q6); T40.1 thêm scheme/flavor | T40.1 |
| Chế độ giả lập (T18) | Android xong; T18 §13 liệt kê việc iOS | `SimulatedLocationSource` + `TripClock` có hệ số tốc độ trong NapStopCore; giữ phiên CoreLocation nền thật để app không bị treo | T18.1 |
| Live Activity / thông báo thường trực | Android có thông báo FGS | iOS: chỉ báo xanh của hệ thống khi dùng vị trí nền (When In Use). Live Activity ngoài MVP (PRD §6) (Q9) | — |
| Biểu tượng app iOS, ảnh store | Template Flutter | T39 | T39 |
| Ký số, TestFlight, Time Sensitive, App Review | — | Cần tài khoản Apple Developer **trả phí** | T40.1, T40 |

## 4. Kiến trúc iOS đề xuất (chi tiết ở T17)

```
app/ios/Core (Swift package NapStopCore, iOS 16 / macOS 13)
├── Trip            (có sẵn, T13) chỉ thư viện chuẩn — bit-parity Kotlin
├── TripRuntime     (MỚI, T17) Foundation, KHÔNG dùng framework Apple-only → swift test trên WSL
│                    TripRuntime (actor, hàng đợi lệnh tuần tự), TripClock, FixMapper, FixThrottle, LocationRequestMapper,
│                    EffectPlanner, AlarmLedger + FallbackSlots, AlarmUpdateInterpreter, RingFacts, RestorePlanner,
│                    LedgerReconciler, StoredTrip codec, FinishedRecord, TripConfigValidator, BridgeDTO, NativeCopy, ports
└── NapStopIOS      (MỚI, T17) #if os(iOS): CoreLocationSession, AlarmKitSystemAlarms, NotificationSystemAlarms,
                     FileRuntimeStore, IOSDeviceEnv, IOSTripNotifier, DispatchWakeTimer, RuntimeHost
                     → typecheck/emit-module bằng SDK xtool trên WSL; build thật trên CI macOS
app/ios/Runner      AppDelegate (sửa), Bridge/RealTripBackend + MsgMapper (MỚI), Native/AlarmIntents (StopIntent; MỚI),
                    Native/DiagIntents (chỉ bản chẩn đoán), Info.plist, project.pbxproj (tham chiếu gói local `Core`)
```

Nguyên tắc (giống `:core-runtime` của Android): mọi quyết định (đặt/huỷ/khôi phục báo, chuyển chế độ, lọc fix) là hàm thuần trong
`TripRuntime`; `NapStopIOS` chỉ gọi API Apple. App Intents (StopIntent) ở target Runner vì metadata App Intents cần nằm trong app —
cách đã chạy được ở probe S3; intent chỉ ghi sự kiện rồi gọi vào `RuntimeHost`.

## 5. Danh sách task iOS

Nhãn môi trường mới (đề xuất thêm vào chú giải TASKS): `wsl` = WSL Swift/xtool trên máy dev; `ci-mac` = GitHub Actions macOS;
`device` = iPhone của PO cắm máy; `paid` = cần tài khoản Apple Developer trả phí.

| ID | Task | Env | Phụ thuộc | Tiêu chí hoàn thành |
|---|---|---|---|---|
| **T01.2** | CI iOS chạy được không cần `gh`: `ios-compile.yml` thêm trigger `push` nhánh `ci/ios-**` (chọn job theo tiền tố nhánh), job `ios-sim-test` (XCTest RunnerTests + `flutter test integration_test` trên Simulator), job `publish-results` ghi tóm tắt kết quả vào nhánh `ci-results/<nhánh>`; device IPA có tuỳ chọn chẩn đoán (`Diag.xcconfig`); script `app/ios/scripts/typecheck-wsl.sh` (xtool SDK) commit vào repo | wsl + ci-mac | T14 | Một lần push `ci/ios-all-*` chạy xanh 4 job; orchestrator đọc được kết quả bằng `git fetch` nhánh `ci-results/…`; chạy lần đầu cũng là lần "chờ gộp" `swift-macos` của T13–T13.5 (so u127/u128-loop/t135 như TASKS ghi); `actionlint` sạch; script typecheck có đối chứng âm |
| **T17** | iOS trip runtime + location + báo AlarmKit cơ bản (spec `docs/specs/T17.md`) | wsl + ci-mac + device | T13.5, T14.1, S3, T01.2 (phần CI) | Theo T17 "Tiêu chí chấp nhận": `swift test` xanh (IU, ITR) trên WSL và macOS; P05 không đổi; typecheck WSL 0 lỗi; build Simulator + IPA xanh; IC03–IC04 xanh trên Simulator; biên bản IM01–IM08 trên iPhone |
| **T17.1** | iOS `PermissionHostApi` thật theo T21 §9 + `distancesFromLastKnownM` (làm tròn như Android, không log) + `InfoPlist.strings` vi/en + `PrivacyInfo.xcprivacy` + loại `napstop_db/` (và quyết cờ màn 0) khỏi sao lưu iCloud | wsl + ci-mac + device | T17 (cùng file `AppDelegate`/Info.plist; làm sau khi T17 vào `main`, hoặc song song nếu coder giữ tách file) | Test thuần ánh xạ quyền trên WSL; RunnerTests kiểm Info.plist/privacy manifest; màn 0 trên Simulator hiện đúng 3 dòng; trên máy: từ chối Thông báo/AlarmKit → hiện "Mở Cài đặt" (S3 #3, K4 #13–#14) |
| **T17.2** | Trải nghiệm báo AlarmKit: nút phụ "Báo lại" (Q3), nút "Xem đường quay lại" cho alarm quá trạm + `consumeLaunchAction` iOS, `showAlarmScreen` iOS = `false` (xác nhận), danh mục âm → file `.caf` cho AlarmKit + `previewSound`/`stopPreview` (`AVAudioPlayer`), mọi chuỗi native theo `setAppLocale`, quá trạm khi chuông đầu còn kêu (theo quyết định PO ở T16.2), đo thời lượng kêu tối đa của AlarmKit và phát hiện `AlarmSilenced` (K4 #20) | wsl + ci-mac + device | T17, T17.1, T16.2 (quyết định PO) | Test thuần cho launch action TTL, chọn nút phụ theo `snoozeAllowed`/lý do; IM trên máy: báo lại từ màn khoá kêu lại sau 60 s; "Xem đường quay lại" mở màn 8 + Maps; số đo thời lượng kêu tối đa |
| **T17.3** | Kênh báo bằng thông báo khi không có AlarmKit (iOS 16–25 hoặc AlarmKit bị từ chối): thông báo `.timeSensitive` + âm < 30 s, lặp 3 lần cách 30 s, đặt sẵn cho báo dự phòng; chạy S3-9…11 trên iOS 27 (từ chối AlarmKit để buộc kênh này) | wsl + ci-mac + device (+ paid cho phần vượt Tập trung) | T17 | Test thuần lịch lặp; biên bản S3-9…11 (kỳ vọng: không kêu khi Im lặng, H4); phần "Time Sensitive vượt Tập trung" chuyển sang T40 |
| **T18.1** | Giả lập trên iOS (spec T18 §13): `TripClock` có hệ số tốc độ, `SimulatedLocationSource` + parser GPX trong NapStopCore, hẹn giờ giả lập trong process, đọc asset Flutter, giữ phiên CoreLocation nền thật khi giả lập | wsl + ci-mac + device | T17, T18 | SM02/SM03/SM06 bản Swift trùng số với Kotlin trên WSL; `train_hn_dh` 60× báo đúng mốc trên Simulator (CI) và trên iPhone khoá màn hình |
| **T28.3** | Hoàn thiện Flutter cho iOS: màn 3/12 ẩn hoặc ghi chú các tuỳ chọn không áp dụng trên iOS (Q2); copy iOS cho thẻ "Sẵn sàng"; màn 5 Flutter khi app mở lúc AlarmKit kêu; màn 8 + Maps URL trên iOS; golden/integration trên Simulator | linux + ci-mac | T17.2 | Widget test theo `platform == ios`; integration trên Simulator xanh |
| **T23.1** | Bản đồ/Places iOS: nạp khoá từ GitHub secret vào `Secrets.xcconfig` ở job IPA; hướng dẫn giới hạn khoá theo bundle id (gồm tiền tố xtool); kiểm màn 2 trên máy | ci-mac + device | T01.2; khoá của PO (Q5) | IPA thử có bản đồ; Places trả kết quả trên máy; không log khoá |
| **T29.2** | Firebase iOS: app iOS trong dự án Firebase, `firebase_options` mục iOS, bước tải dSYM Crashlytics, kiểm payload không toạ độ trên iOS | linux + ci-mac + device | T29 bước B (cấu hình của PO) | Sự kiện thấy trong DebugView từ iPhone; crash thử lên Crashlytics; quét payload |
| **T30 (iOS)** | Phần iOS của T30: 6 trace giả lập end-to-end trên iOS Simulator trong CI | ci-mac | T18.1, T28.3 | 6 trace pass trên Simulator |
| **S4 / T31 / T32 (iOS)** | Lượt dài When In Use 10 giờ (C1, C2), pin, field test | device | T17.2, T18.1 | Như TASKS (S4 có sẵn tiêu chí iOS) |
| **T40.1** | Chuẩn bị phát hành iOS: flavor/scheme `dev`/`prod`, bundle id `app.napstop(.dev)`, ký bằng tài khoản trả phí, capability Time Sensitive, bỏ khoá chẩn đoán (`UIFileSharingEnabled`), ghi chú App Review (AlarmKit cho báo theo vị trí, S3 R8) | ci-mac + paid | T33, T39 | Build ký số trên CI; checklist App Store |
| **T40 (iOS)** | TestFlight | ci-mac + paid | T40.1 | Người thử cài được; S3-3 kiểm lại trên bản TestFlight; Time Sensitive vượt Tập trung |

### 5.1 Thứ tự và đường găng

```
T01.2 ─┬─▶ T17 ─▶ T17.1 ─▶ [máy: IM01–IM08] ─▶ T17.2 ─┬─▶ T28.3 ─▶ T30(iOS) ─▶ [máy: S4/T31] ─▶ T33 ─▶ T40.1 ─▶ T40
       │          └──▶ T17.3 (song song, máy riêng)    └─▶ T18.1 ┘
       └─▶ T23.1 (khi có khoá) ; T29.2 (khi có cấu hình Firebase)
```

**Đêm nay (không có máy):** T01.2 (YAML + script), T17 (mã + test WSL + typecheck), T17.1 (mã + test WSL). Orchestrator push nhánh
`ci/ios-all-<id>` để CI kiểm; **không** push `main`. Phiên máy đầu tiên (khi PO cắm máy): IM01–IM08 của T17 + kiểm nhanh màn 0 (T17.1).

## 6. Chiến lược kiểm chứng khi không có Mac

### 6.1 Năm lớp kiểm

| Lớp | Công cụ | Kiểm được gì | Chạy khi |
|---|---|---|---|
| L1 thuần | `swift test` WSL (`test-wsl.sh`) | Mọi logic quyết định: runtime, khôi phục, sổ báo, diễn giải `alarmUpdates`, lọc fix, codec, chuỗi native vs ARB, trace `fixtures/traces` qua runtime | Mỗi vòng coder/reviewer/tester |
| L2 kiểu | `app/ios/scripts/typecheck-wsl.sh` (xtool SDK 27.1) | Mã `NapStopIOS` + Runner biên dịch được với SDK thật (CoreLocation, AlarmKit, AppIntents, Pigeon, Flutter.xcframework), cho `arm64-apple-ios16.0` và `-simulator`; bắt lỗi `@available` | Mỗi vòng coder/reviewer |
| L3 CI build | `ios-compile.yml` qua push `ci/ios-*` | `project.pbxproj` đọc được, gói local liên kết đúng, metadata App Intents trích được, IPA đóng gói; `swift test` macOS (libm Apple) | Trước khi báo `in-review`, sau vòng sửa lớn |
| L4 Simulator | CI: XCTest `RunnerTests` + `flutter test integration_test` | Cầu nối Pigeon thật ↔ runtime thật ↔ `CLLocationManager` (vị trí giả bằng `xcrun simctl location`), Info.plist; báo thức dùng **cổng giả** trong bản chẩn đoán (§6.4) | Tester |
| L5 máy thật | Giao thức IM của từng task, cài bằng xtool | AlarmKit thật (khoá máy, Im lặng, Tập trung), When In Use ở nền, vuốt tắt app, StopIntent mở lại app | Khi PO cắm máy |

### 6.2 Tách tối đa vào NapStopCore

Như `:core-runtime` của Android (T15 D1): target `TripRuntime` chứa snapshot/sổ báo/sổ sự kiện chuông (codec), máy trạng thái runtime
(`TrackingMode`), `EffectPlanner`, `RestorePlanner`, `LedgerReconciler`, `AlarmUpdateInterpreter` (diễn giải `alarmUpdates` thành
`FallbackFired`/`AlarmSilenced`/lệnh huỷ — chính là các yêu cầu K4 #3, #4, #6, #8–#11), `FixThrottle` (giữ nhịp fix theo `SamplingPolicy`
từ luồng CoreLocation liên tục), chính sách báo dự phòng đã có sẵn trong engine (T10 §4.10). Test dùng chung `fixtures/traces` và cùng
`expect.json` với Kotlin; thêm một bảng `fixtures/runtime/first-alarms.json` do test Kotlin sinh để so trực tiếp lý do + giờ báo đầu
(T17 ITR30p). Cổng (`SystemAlarms`, `LocationSession`, `RuntimeStore`, `DeviceEnv`, `TripNotifier`, `WakeTimer`, `AppStatePort`) có
bản giả trong test.

### 6.3 Typecheck tại chỗ (L2)

Script mới `app/ios/scripts/typecheck-wsl.sh` (T01.2) làm đúng cách T14 đã làm tay (T14 Implementation notes): `swiftc -emit-module`
lần lượt `Trip` → `TripRuntime` → `NapStopIOS` với `-sdk <iPhoneOS.sdk của xtool> -target arm64-apple-ios16.0`, rồi `-typecheck` các file
Swift của Runner với `-I <modules> -F <slice Flutter.xcframework> -import-objc-header Runner-Bridging-Header.h`; lặp cho
`arm64-apple-ios16.0-simulator`. Có `--self-test` thêm một file sai cố ý và phải báo lỗi. Đường dẫn SDK/xcframework qua biến môi trường
(`NAPSTOP_DARWIN_SDK`, `NAPSTOP_FLUTTER_XCFRAMEWORK`). Không thay được L3: `project.pbxproj`, App Intents metadata, liên kết framework.

### 6.4 Simulator trên GitHub Actions

- Runner `macos-latest` (macOS 26 arm64, S3 [G3]) có Xcode và iOS Simulator; job dùng `xcrun simctl list devices available -j` chọn
  iPhone mới nhất, `xcrun simctl boot`, rồi `flutter test integration_test/<file> -d <udid>`.
- **Vị trí giả:** `xcrun simctl location <udid> set <lat>,<lng>` (một điểm) hoặc `start` (nhiều điểm, có `--speed`); cờ của lệnh lấy từ
  `xcrun simctl help location` in vào log job (tài liệu chính thức của `simctl` không có trên web; các trang bên thứ ba [SIMCTL] chỉ để
  tham khảo). XCTest còn có `XCUIDevice.shared.location` (iOS 16.4+) [XCUI-LOC] cho test UI native nếu cần.
- **Quyền:** `xcrun simctl privacy <udid> grant location <bundle id>` trước khi chạy (cờ kiểm bằng `xcrun simctl help privacy` trên runner;
  hộp thoại hệ thống không bấm được từ `integration_test`). Thông báo và AlarmKit không cấp được bằng `simctl` → test Simulator không
  đụng tới hộp thoại đó.
- **AlarmKit trên Simulator: chưa có tài liệu Apple.** Nguồn bên thứ ba cho thấy chỉ "hỗ trợ hạn chế", lỗi trễ báo chỉ tái hiện trên máy
  thật [AK-SIM]. Vì vậy: bản chẩn đoán chạy trên Simulator dùng `FakeSystemAlarms` (ghi lại lệnh đặt/huỷ, giả lập `alerting` đúng giờ)
  khi `UserDefaults` có `napstop.diag.fakeAlarms = true` (đặt bằng `xcrun simctl spawn <udid> defaults write <bundle id>
  napstop.diag.fakeAlarms -bool YES`). Một bước "ghi lại, không chặn" thử `AlarmManager.shared.schedule` thật trên Simulator và in kết quả
  vào tóm tắt (T17 IC05).
- Simulator không chạy được build profile/release của Flutter (chỉ debug [FL-MODES]) → test Simulator luôn là bản Debug.

### 6.5 Kích hoạt CI không cần `gh` (đề xuất cho T01.2)

`workflow_dispatch` chỉ gọi được từ web hoặc API có token. Đề xuất thêm trigger `push` cho nhánh `ci/ios-**` vào `ios-compile.yml`
(workflow ở nhánh được push được dùng, không cần nằm trên `main` [G1]). `ci.yml` chỉ nghe `main` + `pull_request` nên không chạy thêm.

```yaml
on:
  workflow_dispatch: { inputs: { target: … } }           # giữ như cũ
  push:
    branches: ['ci/ios-**']
# Chọn job theo tiền tố nhánh (mỗi job một biểu thức if):
#   ci/ios-swift-*  → swift-macos
#   ci/ios-sim-*    → ios-simulator (build) + ios-sim-test
#   ci/ios-ipa-*    → ios-device (IPA, có Diag.xcconfig)
#   ci/ios-all-*    → tất cả
# Ví dụ: if: inputs.target == 'swift' || startsWith(github.ref_name, 'ci/ios-swift-') || startsWith(github.ref_name, 'ci/ios-all-')
publish-results:                                          # ubuntu-latest, needs: [mọi job], if: always()
  permissions: { contents: write }                        # chỉ job này
  # tải artifact tóm tắt của các job (summary.md, đuôi log test, kết quả typecheck/XCTest),
  # tạo commit mồ côi, push --force tới refs/heads/ci-results/<github.ref_name>. Không đưa IPA vào git.
```

Orchestrator: `git push origin HEAD:refs/heads/ci/ios-all-<id>` → chờ → `git fetch origin ci-results/ci/ios-all-<id>` →
`git show FETCH_HEAD:summary.md`. IPA vẫn là artifact (`napstop-ios-unsigned`), PO tải bằng trình duyệt khi cài máy. Xoá nhánh `ci/ios-*`
cũ bằng `git push origin --delete`. **Chi phí:** nếu repo là private, phút macOS tính hệ số cao [G2]; mỗi lần `ci/ios-all-*` ≈ 45–60 phút
runner → dùng tiền tố hẹp (`swift`, `sim`) khi có thể (Q4).

Bản chẩn đoán cho máy thật: job IPA tạo `app/ios/Flutter/Diag.xcconfig` (gitignore, `#include?` từ `Release.xcconfig` như
`Secrets.xcconfig`) với `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) NAPSTOP_DIAG` khi nhánh là `ci/ios-ipa-*`; Debug luôn có
`NAPSTOP_DIAG`. Bản TestFlight (T40) không có tệp này.

### 6.6 Kiểm chứng theo task

| Task | L1 WSL | L2 typecheck | L3 CI build | L4 Simulator | L5 máy |
|---|---|---|---|---|---|
| T01.2 | — | script + đối chứng âm | 4 job xanh | sim boot + 1 test khói | — |
| T17 | IU01–IU45, ITR30–ITR33 | NapStopIOS + Runner | build sim + IPA; `swift test` macOS | IC03 (XCTest), IC04 (integration), IC05 (ghi lại) | IM01–IM08 |
| T17.1 | ánh xạ quyền, làm tròn khoảng cách | có | có | màn 0 + `status()` | từ chối/cấp quyền, Cài đặt |
| T17.2 | launch action, chọn nút phụ | có (AppIntents) | có | màn 5/8 Flutter với cổng giả | báo lại, quá trạm, thời lượng kêu |
| T17.3 | lịch lặp thông báo | có | có | — | S3-9…11 |
| T18.1 | SM02/SM03/SM06 Swift | có | có | 6 trace trên Simulator | `train_hn_dh` 60× khoá máy |
| T28.3 | widget test Dart | — | — | integration | màn 0–12 trên iPhone |

## 7. Rủi ro

| # | Rủi ro | Phương án |
|---|---|---|
| RI1 | When In Use không giữ app chạy nền đủ lâu (C1, C2 của S3 còn mở) | Báo dự phòng theo ETA luôn tồn tại (K4 #5, đã PASS S3-6/7/8). Đo ở IM07 (ngắn) và S4 (10 giờ). Không đạt → đề nghị Always + CLMonitor quanh đích (S5 F9), cần S3-13 trước |
| RI2 | AlarmKit đặt/huỷ dày làm báo trễ hoặc không kêu khi máy khoá (diễn đàn Apple, iOS 26.x, không có trả lời của Apple) [AK-FAN] | Giảm áp lực: chỉ đặt lại khi engine phát `FallbackAlarmChanged` (đã giới hạn ≤ 56 lần/giờ, T10 §10); đo ở IM06 (≥ 60 lần/giờ, T10.2). Không đạt → khoá Remote Config riêng iOS nới `fallbackMinIntervalS`/`fallbackMinShiftS` (task T29.x) |
| RI3 | Sửa tay `project.pbxproj` sai → không build | Chép đúng mẫu mục `FlutterGeneratedPluginSwiftPackage` có sẵn; mã Apple nằm trong gói (thư mục tự gom file) nên Runner chỉ thêm 4 file; L3 bắt lỗi |
| RI4 | AlarmKit bị liên kết mạnh khi deployment target 16 → app không mở được trên iOS < 26 | CI kiểm `otool -l Runner` có `LC_LOAD_WEAK_DYLIB` cho AlarmKit; thiếu → thêm `-weak_framework AlarmKit` vào `OTHER_LDFLAGS` (T17 IC02) |
| RI5 | Hành vi bản ký development khác bản phân phối (S3 R7) | T40 kiểm lại S3-3 trên TestFlight |
| RI6 | App Review từ chối AlarmKit cho báo theo vị trí (S3 R8) | Ghi chú review ở T40.1; phương án C của S3 (thông báo) nếu bị từ chối — PO duyệt |
| RI7 | Phút macOS cạn (repo private) | Tiền tố nhánh hẹp; chạy `all` tối đa vài lần/ngày; ưu tiên L1/L2 tại chỗ |
| RI8 | Hồ sơ ký miễn phí hết hạn 7 ngày, 10 App ID/7 ngày | Giữ một bundle id; không thêm extension (không widget, không countdown) cho tới T40 |
| RI9 | Simulator không đại diện AlarmKit | Chỉ dùng Simulator cho đường ống; mọi kết luận về tiếng kêu lấy từ L5 |
| RI10 | `batteryLevel` của iOS có bậc thô | Quy tắc pin 5 %/15 % vẫn đúng ở bậc 5 %; S4 ghi lại |

## 8. Câu hỏi mở cho PO (mỗi câu có phương án đề xuất; orchestrator được chọn phương án đề xuất trong đêm nay, trừ chỗ ghi "không tự chọn")

| # | Câu hỏi | Phương án | Đề xuất |
|---|---|---|---|
| Q1 | Phiên bản iOS tối thiểu cho MVP | **A.** Giữ iOS 16 như PRD §5; mã AlarmKit gate `#available(iOS 26, *)`; iOS 16–25 có kênh thông báo (T17.3) nhưng chỉ kiểm được trên iOS 27 (không có máy cũ). **B.** Nâng lên iOS 26: bỏ được nhánh iOS cũ, ít rủi ro liên kết | **A** (không đổi PRD; B làm được sau bằng một dòng cấu hình) |
| Q2 | Tuỳ chọn báo không áp dụng được lên UI AlarmKit: cách tắt lắc/phép tính, tăng dần 30 s, rung Nhẹ/Vừa/Mạnh, flash, ưu tiên tai nghe | **A.** Trên iOS bỏ qua các tuỳ chọn này; màn 3/12 ẩn hoặc ghi "Chỉ có trên Android" (T28.3); màn 5 Flutter (app đang mở) giữ vuốt để tắt (T27 D2). **B.** Tự dựng UI báo trong app (chỉ khi app mở, không có trên màn khoá) | **A** |
| Q3 | Báo lại từ màn khoá | **A.** Nút phụ AlarmKit `.custom` chạy intent trong app: đặt alarm mới sau 60 s (cần kiểm trên máy ở T17.2). **B.** `.countdown` (nút "Lặp lại" của hệ thống) — cần widget extension (thêm App ID, rủi ro RI8). **C.** Không báo lại trên màn khoá; mở app để báo lại | **A**, rơi về **C** nếu A không chạy trên máy |
| Q4 | Kích hoạt CI và đọc kết quả khi không có `gh` | **A.** Push nhánh `ci/ios-*`; workflow tự ghi tóm tắt vào nhánh `ci-results/*`; IPA PO tải bằng trình duyệt. **B.** Orchestrator lấy token của Git Credential Manager để gọi GitHub REST API (chạy `workflow_dispatch`, tải artifact) | **A**. **B: không tự chọn** — dùng thông tin xác thực của PO cho việc ngoài `git push`, cần PO đồng ý rõ |
| Q5 | Khoá Google Maps/Places cho iOS | **A.** PO tạo khoá iOS, giới hạn bundle id `app.napstop` **và** `XTL-<TeamID>.app.napstop` (bản cài bằng xtool), thêm secret repo `IOS_MAPS_API_KEY` để job IPA chèn vào `Secrets.xcconfig`. **B.** Build thử không có bản đồ (màn 2 chỉ tìm offline + Places tắt) | **A**; trong lúc chờ: **B** |
| Q6 | Flavor iOS trước T40 | **A.** Một cấu hình (bundle `app.napstop`, `AppFlavor` = dev như hiện tại) tới T40.1. **B.** Làm scheme dev/prod ngay | **A** |
| Q7 | Thời điểm đăng ký Apple Developer Program (trả phí) | **A.** Đăng ký trước T33 để T17.3 (Time Sensitive) và T40 không chờ (duyệt có thể mất 1–2 ngày). **B.** Đợi tới T40 | **A** (chỉ là khuyến nghị lịch; orchestrator không làm gì) |
| Q8 | Live Activity / trạng thái chuyến trên màn khoá iOS | **A.** Không làm trong MVP (chỉ báo xanh vị trí của hệ thống). **B.** Làm Live Activity (stretch PRD §6, cần widget extension) | **A** |
| Q9 | Repo public hay private (ảnh hưởng chi phí macOS, RI7) | Orchestrator tự kiểm: `curl -s -o /dev/null -w '%{http_code}' https://api.github.com/repos/Ryo51289/gps-alarm` (200 = public, 404 = private) | Kiểm trước lần push CI đầu; private thì giới hạn `ci/ios-all-*` ≤ 3 lần/ngày |

### 8.1 Quyết định (05/11/2026)

**orchestrator chọn thay PO ngày 05/11 theo phép PO cho; PO xem lại khi dậy**

| # | Quyết định |
|---|---|
| Q1 | **A** — giữ iOS 16 (PRD §5); AlarmKit gate `#available(iOS 26, *)`; iOS 16–25 chưa kiểm trên máy |
| Q2 | **A** — iOS bỏ qua lắc/phép tính, tăng dần, mức rung, flash, ưu tiên tai nghe; màn 3/12 ẩn hoặc ghi chú (T28.3) |
| Q3 | **A** — nút phụ AlarmKit `.custom` (T17.2); nếu không chạy trên máy thì **C** (mở app để báo lại) |
| Q4 | **A** — push nhánh `ci/ios-*`, kết quả ở nhánh `ci-results/*`; B (token GCM) không dùng |
| Q5 | **Chờ PO** (khoá Maps iOS + secret `IOS_MAPS_API_KEY`); trong lúc chờ build không có bản đồ |
| Q6 | **A** — một cấu hình iOS tới T40.1 |
| Q7 | **Chờ PO** (thời điểm đăng ký Apple Developer Program) |
| Q8 | **A** — không Live Activity trong MVP |
| Q9 | Repo **private** (API trả 404 khi không đăng nhập). Phút macOS tính theo giá riêng, đắt gấp ~10 lần Linux; ngân sách và ước lượng ở `docs/specs/T01.2.md` §6 |

## 9. Đề xuất cập nhật `docs/TASKS.md` (orchestrator sửa)

1. Chú giải môi trường: thêm `wsl` (WSL Swift 6.4.1 + xtool SDK), `ci-mac` (GitHub Actions macOS), `paid` (tài khoản Apple trả phí).
2. Phase 0 thêm **T01.2** (bảng §5).
3. Hàng **T17**: Env `wsl + ci-mac + device`; phụ thuộc `T13.5, T14.1, S3, T01.2`; tiêu chí: "theo `docs/specs/T17.md` (runtime + location +
   báo AlarmKit cơ bản); phần còn lại của tiêu chí cũ chuyển sang T17.1 (`distancesFromLastKnownM`, cờ màn 0 iCloud, quyền denied lên UI
   ở màn 0), T17.2 (thời lượng kêu tối đa, báo lại, quá trạm), T17.3 (kênh TS S3-9…11)".
4. Thêm hàng **T17.1, T17.2, T17.3** (bảng §5).
5. Hàng **T18.1**: Env `wsl + ci-mac + device`; phụ thuộc `T18, T17`.
6. Phase 3 thêm **T28.3**, **T23.1**, **T29.2**; Phase 5 thêm **T40.1**.
7. Hàng **T13.3/T13.4/T13.5** ("chờ gộp ios-compile swift"): ghi "chạy ở lần đầu của T01.2".
8. Hàng **T30**, **S4**, **T31**, **T32**, **T40**: phần iOS theo bảng §5 (không đổi tiêu chí Android).
9. Hàng **T16.2** thêm: "quyết định của PO áp dụng cho cả iOS (T17.2): AlarmKit không đổi được nội dung alarm đang kêu".

## 10. Tài liệu tham khảo (kiểm 2026-11-05)

Apple
- [I3] Handling location updates in the background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- [CL-BG] `allowsBackgroundLocationUpdates`: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- [CL-BAS] `CLBackgroundActivitySession` (iOS 17+): https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3
- [I6] AlarmKit: https://developer.apple.com/documentation/alarmkit
- [I7] Scheduling an alarm with AlarmKit: https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit
- [AK-MGR] `AlarmManager`: https://developer.apple.com/documentation/alarmkit/alarmmanager
- [AK-CFG] `AlarmManager.AlarmConfiguration`: https://developer.apple.com/documentation/alarmkit/alarmmanager/alarmconfiguration
- [AK-ALERT] `AlarmPresentation.Alert` + `SecondaryButtonBehavior` (`countdown`, `custom`): https://developer.apple.com/documentation/alarmkit/alarmpresentation/alert-swift.struct
- [XCUI-LOC] `XCUIDevice.location`: https://developer.apple.com/documentation/xcuiautomation/xcuidevice/location
- [PRIV] Describing use of required reason API: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- [I10] WWDC21 Time Sensitive notifications: https://developer.apple.com/videos/play/wwdc2021/10091/
- [AK-FAN] Diễn đàn Apple "AlarmKit dense fan-out scheduling…" (không có trả lời của Apple): https://developer.apple.com/forums/thread/825427

Flutter, Google, GitHub
- [FL-MODES] Flutter build modes (Simulator chỉ chạy debug): https://docs.flutter.dev/testing/build-modes
- [G-URLS] Google Maps URLs: https://developers.google.com/maps/documentation/urls/get-started
- [G1] GitHub Actions workflow syntax (lọc `branches` cho `push`): https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- [G2] GitHub Actions billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions

Bên thứ ba (chỉ tham khảo, không làm căn cứ)
- [SIMCTL] `simctl location start` (fig.io): https://fig.io/manual/simctl/location/start
- [AK-SIM] flutter_alarmkit (ghi chú Simulator hỗ trợ hạn chế): https://pub.dev/documentation/flutter_alarmkit/latest
