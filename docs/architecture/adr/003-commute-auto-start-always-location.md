# ADR-003 — Tuyến đi làm: tự bật theo dõi khi tới điểm cố định, cần vị trí "Luôn cho phép" (iOS trước)

Trạng thái: **iOS: Đã duyệt về hướng** (PO 13/11/2026: tự bật hoàn toàn khi tới A/B, chấp nhận xin "Luôn cho phép", làm trước
T23.6 B1). Chi tiết kỹ thuật chờ spike B0 của T23.8 (Go/No-go). **Android: Đề xuất, chưa duyệt** — quyết ở T23.8.A khi quay lại Android.
Spec: `docs/specs/T23.8.md`. Spike: `docs/spikes/T23.8.md`.

## Bối cảnh

- PO yêu cầu 13/11/2026 "tuyến đi làm": người dùng khai một tuyến cố định A→B. Tới A trong khung giờ sáng (vd 07:00–08:00) thì app
  tự theo dõi tới B; tới B trong khung giờ chiều (vd 17:30–19:30) thì tự theo dõi về A. Báo thức khi gần tới như chuyến thường.
- Hiện tại, chuyến chỉ bắt đầu khi người dùng bấm "Bắt đầu theo dõi" lúc app đang mở (PRD §4 "Theo dõi chuyến"; T17 D8, D10;
  ADR-001 #2). iOS chỉ dùng "Khi dùng ứng dụng" (When In Use). Android không xin vị trí nền (ADR-001).
- Muốn tự bật khi app không chạy, hệ thống phải đánh thức app khi người dùng vào vùng A/B. Trên iOS chỉ quyền **Always** làm được
  điều này: "If your app isn't running, the system launches your app and delivers the event" [I2]. Apple nêu đúng ca này là lý do
  hợp lệ để xin Always: "if your app triggers automatic actions when the user enters a location … your app may require Always
  authorization" [I2].
- Region monitoring/`CLMonitor`: tối đa 20 điều kiện mỗi app; app không chạy thì hệ thống thử khởi chạy lại; phải tạo lại monitor
  cùng tên khi khởi chạy [I6]. Sự kiện cần ra khỏi ranh giới ~200 m và giữ ≥ 20 s; trung bình 3–5 phút; cần mạng; Wi-Fi tắt thì kém
  chính xác; Background App Refresh tắt thì không đánh thức [I7][I8].
- Tài liệu Apple **không** nói rõ app được đánh thức ở nền (do vùng) có bắt đầu được cập nhật vị trí liên tục và chạy tiếp hàng giờ hay
  không. `allowsBackgroundLocationUpdates` chỉ bảo đảm khi "you start location updates while the app is in the foreground" [I9];
  `CLServiceSession` phải tạo "while your app is in the foreground" và tạo lại "immediately upon launch in the background" [I3]. Diễn
  đàn có báo cáo `CLMonitor` bỏ sót sự kiện ở nền trên iOS 18/26, API vùng cũ (`startMonitoring(for:)`) ổn định hơn, nhưng API cũ bị
  đánh dấu deprecated từ iOS 27.3 [F1][I10]. → Cần spike trên iPhone trước khi làm phần lõi.
- Android: geofence là ngoại lệ được khởi động FGS từ nền (Android 12+), nhưng FGS cần quyền "while-in-use" (vị trí) khởi động từ nền
  chỉ có vị trí khi app có `ACCESS_BACKGROUND_LOCATION` [A2]; Geofencing API cũng bắt buộc quyền này từ API 29 [A4]. Play chỉ duyệt
  vị trí nền khi là chức năng cốt lõi và có lợi ích đáng kể; "convenience" là lợi ích nhỏ [P1].

## Quyết định

1. **iOS — quyền.** Màn 0 không đổi (When In Use + Chính xác vẫn là mức tối thiểu cho mọi chuyến). Chỉ khi người dùng bật "Tuyến đi
   làm" mới hiện màn giải thích rồi gọi `requestAlwaysAuthorization()` (một lần duy nhất [I4]). Từ chối → tính năng tắt, có nút
   "Mở Cài đặt". Thêm `NSLocationAlwaysAndWhenInUseUsageDescription` (vi/en) [I5].
2. **iOS — đánh thức.** Theo dõi **hai vùng tròn** A và B (bán kính 200 m) bằng region monitoring khi tuyến đang bật. Không có cập nhật
   vị trí liên tục nào ngoài chuyến. API cụ thể (`CLMonitor` hay `CLLocationManager.startMonitoring(for:)`) chốt theo B0; cả hai nằm
   sau một cổng `RegionMonitorPort`.
3. **iOS — tự bật chuyến từ nền.** Ngoại lệ có giới hạn cho T17 D8/D10: runtime được bắt đầu chuyến khi app không `active` **chỉ** khi
   (a) nguồn là sự kiện vào vùng của tuyến đi làm, (b) quyền đang là Always + Chính xác, (c) qua bộ quyết định thuần (khung giờ, ngày,
   một lần mỗi chiều mỗi ngày, không có chuyến đang chạy). Khôi phục chuyến sau khi process chết vẫn theo D10 (không tự bật lại vị trí).
4. **Minh bạch.** Chuyến tự bật luôn có thông báo "Đã tự bật theo dõi tới …" kèm nút "Dừng", và `showsBackgroundLocationIndicator =
   true` (thanh/viên xanh) [I11]. Live Activity không bắt đầu được từ nền khi không có push [AK-FG] → bắt đầu ở lần mở app kế tiếp (đã
   có trong T23.6 §5.5 `pendingStart`).
5. **Quyền riêng tư không đổi.** Toạ độ A/B chỉ nằm trên máy (drift `napstop_db/` và `napstop_trip/commute/`, đều loại khỏi sao lưu),
   không log, không vào Analytics/Crashlytics. Không thêm sự kiện Analytics trong T23.8.
6. **Android — đề xuất, chưa duyệt.** Bản Android (T23.8.A) cần `ACCESS_BACKGROUND_LOCATION` **tuỳ chọn**, chỉ xin khi bật tính năng,
   `GeofencingClient`, khai báo Location permissions trên Play (video, prominent disclosure). Đây là thay đổi ADR-001 #1 cho riêng
   tính năng này; ADR-001 vẫn đúng cho mọi chuyến thường. PO quyết khi quay lại Android (Câu hỏi mở Q8 của spec).

## Phương án đã loại

| Phương án | Lý do loại |
|---|---|
| Chỉ nhắc bằng thông báo khi tới A ("chạm để bắt đầu"), giữ When In Use | PO chọn tự bật hoàn toàn (13/11). Giữ làm phương án dự phòng nếu B0 No-go |
| `UNLocationNotificationTrigger` (chạy với When In Use [I2]) | Hệ thống tự hiện thông báo khi vào vùng, app không chạy để lọc khung giờ/ngày → báo cả ngoài giờ; vẫn cần người dùng chạm |
| Bật "theo dõi chuyến" (GPS liên tục) suốt khung giờ chờ người dùng tới A | Tốn pin vô ích, không cần thiết vì vùng do hệ thống canh; vẫn cần bắt đầu từ nền khi khung giờ mở |
| Báo thức chỉ bằng vùng quanh B (không GPS liên tục) | Trễ trung bình 3–5 phút [I10] = muộn 1–2 km ở tốc độ xe buýt; mất ETA, chế độ thời gian, quá trạm, mất GPS (PRD §4). Chỉ giữ làm ý tưởng dự phòng B0 No-go |
| Xin Always ngay ở màn 0 cho mọi người | Trái nguyên tắc "request only When In Use whenever possible" [I2], PRD §3.1; người không dùng tuyến đi làm không cần |
| Android: khởi động FGS `location` từ geofence **không** có vị trí nền | Geofencing API bắt buộc `ACCESS_BACKGROUND_LOCATION` (API 29+) [A4]; FGS khởi động từ nền không có vị trí nếu thiếu quyền này [A2] |

## Hệ quả

- (+) Tính năng mới không ảnh hưởng người dùng không bật nó: quyền, pin, luồng chuyến thường giữ nguyên.
- (+) Pin khi chờ: chỉ region monitoring do hệ thống quản lý; không có phiên vị trí liên tục ngoài chuyến.
- (−) Độ trễ vào vùng 3–5 phút, có thể sót khi Wi-Fi tắt, không mạng, Background App Refresh tắt hoặc Chế độ nguồn điện thấp
  (Low Power tự tắt Background App Refresh [I12]) → hiện cảnh báo trên màn cấu hình; người dùng vẫn bắt đầu tay được.
- (−) Rủi ro App Review: phải giải thích Always (5.1.1, 5.1.5) và chứng minh trong ghi chú review; nháp ở spec §11.
- (−) **Thay đổi phá vỡ:** T17 D8 ("bắt đầu chỉ khi app `active`") và D10 có ngoại lệ ở mục 3; PRD §4 "Theo dõi chuyến" gạch đầu
  tiên; PRD §3.1 (iOS: Always có tính năng dùng tới); ARCHITECTURE §3 (Pigeon `CommuteHostApi`, `PermissionKindMsg.locationAlways`),
  §4 (drift v2), §5 (ghi chú region), §7.2 (khoá Always). Không đổi engine (`Trip`), không đổi snapshot engine.
- (−) Android (khi làm): khai báo vị trí nền trên Play, rủi ro bị xếp "convenience" — có thể phải bỏ tính năng trên Android.

## Tham khảo (kiểm tra 13/11/2026)

- [I2] Choosing the Location Services Authorization to Request: https://developer.apple.com/documentation/bundleresources/choosing-the-location-services-authorization-to-request
- [I3] Handling location updates in the background: https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- [I4] `requestAlwaysAuthorization()`: https://developer.apple.com/documentation/corelocation/cllocationmanager/requestalwaysauthorization()
- [I5] `NSLocationAlwaysAndWhenInUseUsageDescription`: https://developer.apple.com/documentation/bundleresources/information-property-list/nslocationalwaysandwheninuseusagedescription
- [I6] Monitoring the user's proximity to geographic regions: https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions
- [I7] Location and Maps Programming Guide — Region Monitoring (lưu trữ): https://developer.apple.com/library/archive/documentation/UserExperience/Conceptual/LocationAwarenessPG/RegionMonitoring/RegionMonitoring.html
- [I8] (như I7) Background App Refresh và đánh thức theo vùng
- [I9] `allowsBackgroundLocationUpdates`: https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates
- [I10] `startMonitoring(for:)` (20 vùng, 3–5 phút, deprecated iOS 27.3): https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)
- [I11] `showsBackgroundLocationIndicator`: https://developer.apple.com/documentation/corelocation/cllocationmanager/showsbackgroundlocationindicator
- [I12] `backgroundRefreshStatus`: https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus
- [AK-FG] Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- [F1] Diễn đàn Apple (không chính thức): https://developer.apple.com/forums/thread/806783 , https://developer.apple.com/forums/thread/768373
- [A2] Restrictions on starting a foreground service from the background: https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- [A4] Create and monitor geofences: https://developer.android.com/develop/sensors-and-location/location/geofencing
- [P1] Play — Requesting access to location in the background: https://support.google.com/googleplay/android-developer/answer/9799150
