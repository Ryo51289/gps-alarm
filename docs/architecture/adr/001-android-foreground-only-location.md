# ADR-001 — Android: chỉ dùng vị trí "Khi dùng ứng dụng" + foreground service, không xin vị trí nền (MVP 1)

Trạng thái: **Đã duyệt** (product owner, Gate 1, 2026-11-01). Đề xuất từ spike S5 (2026-10-29); xem lại khi có kết quả S1 trên máy thật.

## Bối cảnh

- PRD §3 màn 0 ghi xin vị trí "Luôn cho phép". Trên Android, mức này = `ACCESS_BACKGROUND_LOCATION`, kéo theo
  khai báo "Location permissions" trên Play Console (video, prominent disclosure, review) [P1].
- Play chỉ duyệt vị trí nền khi đem lại "significant benefit" (an toàn thân thể, sức khoẻ…); "convenience" là lợi
  ích nhỏ, và Play xét "liệu trải nghiệm có làm được mà không cần vị trí nền" [P1]. Báo thức tránh lỡ trạm có
  nguy cơ bị xếp là tiện lợi.
- Android coi app đang chạy foreground service (FGS) là dùng "foreground location" [A1]. Play chấp nhận FGS dùng
  quyền "while in use" nếu khởi động từ hành động người dùng trong app và dừng ngay khi xong mục đích [P2].
- Từ Android 14, FGS loại `location` không tạo được khi app ở nền nếu thiếu `ACCESS_BACKGROUND_LOCATION`
  (`SecurityException`) [A2][A3]; ngoại lệ gồm "The service starts by interacting with a notification".
- ARCH §5 trên Android dùng Fused Location trong FGS, không dùng Geofencing API.

## Quyết định

1. Android MVP 1 **không** khai/không xin `ACCESS_BACKGROUND_LOCATION`. Quyền vị trí: `ACCESS_FINE_LOCATION` +
   `ACCESS_COARSE_LOCATION` (người dùng chọn "Khi dùng ứng dụng" + "Chính xác").
2. FGS `foregroundServiceType="location"` (+ `FOREGROUND_SERVICE_LOCATION`) chỉ được khởi động khi có activity đang
   hiển thị (nút "Bắt đầu theo dõi"), hoặc khi người dùng chạm notification của app.
3. FGS dừng ngay khi chuyến kết thúc (báo thức đã tắt, tới nơi, xử lý xong quá trạm, người dùng bấm Dừng — có nút
   Dừng trong notification) và có trần thời lượng (T10/T15 chốt giá trị, Remote Config).
4. Sau reboot / khi không thể khởi động lại FGS từ nền: nhận `BOOT_COMPLETED` (quyền thường), nếu còn chuyến dang dở
   → notification ưu tiên cao "Chuyến đi bị gián đoạn — chạm để tiếp tục theo dõi".
5. Play Console: khai FGS `location` với use case **Navigation / ride tracking**; không khai Location permissions
   (vị trí nền).
6. iOS **không** bị ảnh hưởng bởi ADR này (xem S5 F9: When In Use là mức tối thiểu, Always là nâng cấp tuỳ chọn).

## Phương án đã loại

| Phương án | Lý do loại |
|---|---|
| Xin `ACCESS_BACKGROUND_LOCATION` bắt buộc (như PRD hiện tại) | Rủi ro bị Play từ chối trung bình–cao; thêm 1 bước Cài đặt cho người dùng (Android 11+ phải vào Settings); không cần cho luồng chính |
| Geofencing API (cần vị trí nền) thay cho FGS | Cần vị trí nền; không cho ETA/chế độ thời gian/mất GPS/pin/quá trạm liên tục (PRD §4); Play đã bỏ geofencing khỏi use case FGS được duyệt [P4] |
| Vị trí nền dạng tuỳ chọn ngay từ MVP 1 | Vẫn phải qua khai báo + review vị trí nền; chỉ đáng làm nếu S1 chứng minh cần (xem "Điều kiện xem lại") |

## Hệ quả

- (+) Không cần khai báo/video vị trí nền; ít bước cấp quyền hơn; phù hợp nguyên tắc "minimum scope" của Play.
- (−) Không tự phục hồi theo dõi từ nền sau reboot, và có thể không phục hồi sau khi OEM giết tiến trình
  (`START_STICKY` — **chưa rõ**, S1 đo). Người đang ngủ sẽ không thấy notification "chạm để tiếp tục".
  Emulator Android 14 (2026-10-29): sticky restart **vẫn có** vị trí khi chỉ có "Khi dùng ứng dụng"; khởi động lại bằng exact alarm
  (watchdog, ranh giới pha, dự phòng báo thức) thì **`SecurityException`** — exact alarm không nằm trong danh sách miễn trừ
  while-in-use [A2]. Cần xác nhận trên máy thật (S1 R2).
- (−) **Đường báo thức không được phụ thuộc việc khởi động lại FGS `location` từ nền** (S1/S2 smoke test emulator, lỗi #1: báo thức
  dự phòng không kêu khi không có vị trí nền). Hệ quả cho T16: âm báo + thông báo toàn màn hình phải chạy được từ một service riêng
  không cần quyền vị trí, khởi động từ exact alarm (FGS `systemExempted` cho app giữ quyền exact alarm, hoặc `mediaPlayback`) [A3];
  cho T15: luôn giữ một exact alarm dự phòng cho báo thức để còn kêu khi FGS `location` đã chết; cho S5: khai thêm kiểu FGS
  này trên Play Console. Kiểm trên máy thật bằng S2-11 (`docs/spikes/S2.md` mục "Vòng 4").
- Thay đổi tài liệu khi được duyệt: PRD §3 màn 0 (Android: "Khi dùng ứng dụng" + "Chính xác"); ARCHITECTURE §6 rủi ro 4
  trỏ tới S5 + ADR này; spec T15/T21 theo danh sách quyền ở S5 §8.1.
- Không có thay đổi phá vỡ cho task đã `done` (T00–T02 chưa khai quyền nào).

## Điều kiện xem lại

Nếu S1 cho thấy trên ≥ 1 máy mục tiêu FGS bị giết giữa chuyến và **chỉ** phục hồi được khi có
`ACCESS_BACKGROUND_LOCATION` → ADR mới: thêm vị trí nền dạng tuỳ chọn "Tự phục hồi khi hệ thống tắt app", nộp khai
báo Location permissions với kịch bản video dự phòng (`docs/spikes/S5-store-drafts.md` §5.3).

## Tham khảo (kiểm tra 2026-10-29)

- [P1] https://support.google.com/googleplay/android-developer/answer/9799150
- [P2] https://support.google.com/googleplay/android-developer/answer/16558241
- [P4] https://support.google.com/googleplay/android-developer/answer/16926792
- [A1] https://developer.android.com/develop/sensors-and-location/location/permissions
- [A2] https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- [A3] https://developer.android.com/develop/background-work/services/fgs/service-types
- Phân tích đầy đủ: `docs/spikes/S5.md` §4 F1–F3
