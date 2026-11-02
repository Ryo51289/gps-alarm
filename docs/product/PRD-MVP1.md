# PRD — NapStop MVP 1 (báo thức theo vị trí, không backend)

## 0. Tên & thương hiệu (chốt 2026-10-28)
| Hạng mục | Giá trị |
|---|---|
| Tên app | **NapStop** (bản dev: "NapStop Dev"); tên thương hiệu, không dịch |
| Tagline | "Ngủ không lỡ trạm" (vi) · "Nap. We'll wake you at your stop." (en, nháp) |
| Tên miền | `napstop.app` |
| App id Android / Bundle id iOS | `app.napstop` (dev: `app.napstop.dev`) — **không đổi được sau khi phát hành** |
| Package Kotlin / Dart | `app.napstop.core.*` / `package:napstop/` |

Wireframe đã đổi sang "NapStop" (tên làm việc trước đây: "Tới Rồi").

## 1. Vấn đề & mục tiêu
Người đi xe khách/tàu đường dài hay ngủ quên và lỡ trạm. MVP 1 chứng minh: **app đánh thức đúng lúc,
kể cả khi máy khoá, im lặng, chạy suốt 10 giờ, mà tốn ít pin.**

Chỉ số thành công của bản demo/beta:
- ≥ 95% chuyến thử nghiệm báo đúng mốc (sai lệch ≤ 1 phút với chế độ thời gian, ≤ 300 m với chế độ khoảng cách).
- 0 lần "không báo" trong bộ test thiết bị (Xiaomi, Oppo, Vivo, Samsung, iPhone).
- Pin tiêu hao ≤ 15% cho chuyến 10 giờ (màn hình tắt).

## 2. Phạm vi
**Trong MVP 1:** màn 0–9, 11, 12 trong wireframe (https://claude.ai/artifact/Wek6rKCuUwnvtUvKE8vxY6)
+ **chế độ giả lập chuyến đi** cho demo.
**Ngoài MVP 1 (V2):** chia sẻ cho người nhà, trang web người nhà, Zalo/SMS, gọi dậy từ xa (màn 10, 13–19),
tài khoản, thanh toán, bản đồ offline.

## 3. Màn hình
| # | Màn | Ghi chú MVP 1 |
|---|---|---|
| 0 | Cấp quyền | Vị trí "Khi dùng ứng dụng" + "Chính xác" (Android **không** xin vị trí nền — ADR-001); thông báo; Android: báo thức toàn màn hình, báo thức chính xác (chỉ khi máy chưa cấp), hướng dẫn tắt tối ưu pin theo hãng; iOS 26+: báo thức (AlarmKit). Chi tiết và mức bắt buộc: §3.1 |
| 1 | Trang chủ | Ô tìm kiếm, điểm đã lưu (Nhà/Quê/Công ty), chuyến gần đây, thẻ "Sẵn sàng" (quyền + pin + âm lượng) |
| 2 | Chọn điểm đến | Dataset ga/bến offline (tìm không dấu) → fallback Places; bản đồ ghim, vòng tròn vùng báo |
| 3 | Cài đặt báo | 3 chế độ, nhắc nhẹ, kiểu báo, cách tắt, cảnh báo khoảng cách quá ngắn |
| 4 | Đang theo dõi | Khoảng cách/ETA chữ lớn, thanh tiến độ + mốc báo, trạng thái GPS/pin/tai nghe, dừng theo dõi |
| 5 | Báo thức | Toàn màn hình, nền tối, vuốt hết thanh để tắt, báo lại tối đa 1 lần |
| 6 | Mất GPS | Trạng thái "Đang ước tính" + sai số |
| 7 | Pin yếu | Bottom sheet: tiết kiệm tối đa (lấy vị trí thưa hơn) / báo sớm khi 5% / báo sớm hơn (khi 15%) |
| 8 | Đã đi quá trạm | Khoảng cách đã quá, mở Google Maps chỉ đường quay lại |
| 9 | Hướng dẫn tắt tối ưu pin | Theo hãng: Xiaomi, Samsung, Oppo, Vivo; 3 bước + chạy thử 30 giây |
| 11 | Lịch sử | Kết quả mỗi chuyến: tỉnh đúng lúc / báo lại / lỡ trạm / đã dừng; "Đặt lại" 1 chạm |
| 12 | Cài đặt chung | Âm báo, âm lượng, tăng dần, rung, flash, ưu tiên tai nghe, mặc định chuyến, đơn vị, giờ, giao diện, ngôn ngữ |

### 3.1 Màn 0 — quyền theo nền tảng

_Cập nhật 2026-11-01 theo T19 (ADR-001 đã duyệt ở Gate 1): Android chỉ xin vị trí "Khi dùng ứng dụng"; danh sách quyền kỹ thuật ở
ARCHITECTURE §7._

| Mục | Android | iOS | Khi thiếu |
|---|---|---|---|
| Vị trí "Khi dùng ứng dụng" | Có | Có | Không bắt đầu chuyến được |
| Vị trí "Chính xác" | Có | Có | Không bắt đầu chuyến được (vị trí gần đúng sai số vài km, không báo đúng mốc) |
| Định vị của máy đang bật | Có | Có | Không bắt đầu chuyến được |
| Thông báo | Có (Android 13+: xin quyền; bản cũ hơn: chỉ kiểm, vì người dùng vẫn tắt được trong Cài đặt) | Có | Android: vẫn bắt đầu được, cảnh báo đỏ. iOS: bắt buộc nếu không có AlarmKit (iOS < 26 hoặc bị từ chối) |
| Báo thức toàn màn hình | Có (Android 14+, khi chưa cấp) | — | Vẫn kêu, chỉ hiện thông báo nổi thay cho màn hình báo thức; cảnh báo đỏ |
| Báo thức chính xác ("Báo thức và lời nhắc") | Chỉ khi máy chưa cấp | — | Không đặt được báo thức dự phòng; cảnh báo đỏ |
| Báo thức (AlarmKit) | — | Có (iOS 26+) | Báo thức không kêu khi máy đang Im lặng; cảnh báo đỏ |
| Tối ưu pin theo hãng (màn 9) | Hướng dẫn | — | Không chặn; nhắc ở thẻ "Sẵn sàng" |

- **Android không xin vị trí nền ("Luôn cho phép")** và không xin miễn tối ưu pin trực tiếp (chỉ mở trang Cài đặt + hướng dẫn theo
  hãng) — chính sách Google Play, S5.
- **iOS:** "Khi dùng ứng dụng" là mức tối thiểu và app phải chạy đúng với mức này. "Luôn cho phép" không có trên màn 0; chỉ đề nghị
  sau, và chỉ khi có tính năng dùng tới (T17).
- Mỗi quyền có màn giải thích ngắn trước hộp thoại hệ thống. Bị từ chối thì hiện nút "Mở Cài đặt".
- Bắt đầu chuyến cần: vị trí "Khi dùng ứng dụng" + "Chính xác" + định vị bật + ít nhất một cách báo thức kêu được
  (Android: luôn có; iOS: AlarmKit hoặc Thông báo).

## 4. Quy tắc hành vi (giá trị mặc định — designer chốt chi tiết trong spec T10, có thể chỉnh qua Remote Config)

_Cập nhật 2026-11-01 theo T10 (PO duyệt Q1–Q4): khoảng cách chim bay × 1.0, hệ số tuyến chỉ cho ETA; nghĩa các lựa
chọn ở màn 7; bắt đầu trong vùng báo thì báo ngay; thêm kết quả `cancelled`._

_Cập nhật 2026-11-01 theo T10 vòng 2 (PO duyệt review #9, #18): thêm quy tắc "đã qua điểm gần đích nhất" cho đích nằm xa
tuyến; quá trạm khi báo đã tự ngừng kêu thì kêu lại._

**Chế độ báo**
- Khoảng cách: 200 m – 10 km, chip 500 m / 1 km / 2 km / 5 km, mặc định 1 km. Khoảng cách tính theo
  đường chim bay (× 1.0) nên không báo muộn hơn mốc dọc tuyến (trừ độ trễ lọc nhiễu ≤ 1 mẫu). Áp dụng cho cả ngưỡng khoảng cách,
  vùng nhắc nhẹ và mốc 1 km của chế độ thông minh.
- Thời gian: chip 5 / 10 / 15 / 20 / 30 phút, mặc định 15. ETA = khoảng cách còn lại × hệ số tuyến / tốc độ
  trung bình động (EMA), bỏ qua lúc đứng yên ngắn (dừng ga). Hệ số tuyến chỉ dùng cho ETA: khởi đầu 1.2, học
  dần trong chuyến.
- Thông minh (mặc định cho người dùng mới): mục tiêu ~10 phút tỉnh ngủ; không bao giờ muộn hơn mốc 1 km;
  xe chậm (< 15 km/h) thì dùng khoảng cách.
- ETA không biết trước đoạn đường chậm hoặc lần dừng phía trước, nên nhắc nhẹ và báo thông minh có thể đến sớm hơn mốc
  (ví dụ còn 13 phút thay vì 10 phút). _(PO duyệt 02/11/2026, Q10 = A — T10.3.)_
- Cảnh báo ở màn 3 khi chế độ khoảng cách cho < 4 phút ở tốc độ dự kiến của phương tiện.
- Bắt đầu chuyến khi đã ở trong vùng báo → báo ngay.

**Nhắc nhẹ trước** (mặc định bật): rung nhẹ khi còn 30 phút (chế độ thời gian/thông minh) hoặc 5× ngưỡng
khoảng cách (tối thiểu 3 km).

**Báo thức**
- Kêu cả khi máy im lặng / Không làm phiền (Android: `USAGE_ALARM`; iOS 26+: AlarmKit; iOS cũ: Time
  Sensitive + âm thanh tuỳ chỉnh, xin Critical Alerts).
- Âm lượng tăng dần 30 giây (tuỳ chọn), rung (Nhẹ/Vừa/Mạnh), flash (tuỳ chọn), ưu tiên tai nghe (rút tai
  nghe → chuyển rung).
- Tắt bằng: vuốt hết thanh (mặc định) / lắc máy / giải phép tính. Báo lại tối đa 1 lần, sau 1 phút.

**Tình huống bất thường**
- Mất GPS: ước tính vị trí theo tốc độ cuối; hiển thị sai số. Nếu ETA ước tính < 20 phút khi đang mất
  tín hiệu → báo luôn.
- Pin: dự báo pin còn đủ tới nơi không; không đủ → hiện màn 7. Pin ≤ 5% mà chưa tới → báo sớm, ghi rõ lý do.
  Màn 7: "Tiết kiệm tối đa" = nhân đôi chu kỳ lấy vị trí khi còn xa (lúc gần tới giữ nguyên); "Báo sớm khi 5%" =
  giữ quy tắc trên; "Báo sớm hơn" = báo khi pin ≤ 15%.
- Quá trạm: đã vào gần đích (< max(ngưỡng, 1 km)) rồi khoảng cách tăng liên tục > 1 km với tốc độ > 10 km/h,
  mà báo thức chưa được tắt → màn 8. Nếu báo đã tự ngừng kêu mà chưa ai tắt thì kêu lại.
- Đã qua điểm gần đích nhất (đích nằm xa tuyến đường): chưa báo mà xe đã tiến lại gần đích (gần hơn lúc bắt đầu ≥ 500 m),
  qua điểm gần đích nhất (cách đích < 3 km, hoặc xa hơn khi ngưỡng lớn) và đang xa dần (thêm ≥ 500 m, tốc độ > 10 km/h)
  → báo luôn.

**Theo dõi chuyến** _(cập nhật 2026-11-01 theo T19 / ADR-001)_
- Theo dõi chỉ bắt đầu khi người dùng bấm "Bắt đầu theo dõi" lúc app đang mở (Android không cho tự bắt đầu từ nền). Thông báo
  thường trực hiện trạng thái chuyến và có nút Dừng.
- Theo dõi dừng ngay khi chuyến kết thúc: đã tắt báo thức (kể cả ở màn quá trạm), người dùng bấm Dừng, hoặc báo thức
  không được tắt trong 1 giờ sau lần kêu gần nhất.
- Chuyến kéo dài quá trần thời lượng (gấp đôi ETA tại vị trí hợp lệ đầu tiên, từ 4 đến 48 giờ) mà chưa báo thì app
  **báo thức** "Chuyến đi lâu hơn dự kiến", không dừng lặng lẽ (T10 §4.13).
- Android không có quyền vị trí nền, nên **không tự theo dõi lại** được sau khi máy khởi động lại (và có thể cả khi hệ thống tắt app;
  S1 đo trên máy thật). Khi đó app đặt lại báo thức dự phòng theo giờ báo dự kiến (tính từ ETA cuối cùng; giờ đó đã qua thì báo
  ngay) và hiện thông báo "Chuyến đi bị gián đoạn — chạm để tiếp tục theo dõi". Người đang ngủ sẽ không thấy thông báo này.
  Lúc đó chỉ còn báo dự phòng đánh thức họ, theo ETA cuối cùng nên có thể lệch.
- iOS: app bị tắt giữa chuyến thì iOS không mở lại để theo dõi tiếp; báo thức dự phòng đặt sẵn vẫn kêu (S3; trên iOS < 26 hoặc khi
  AlarmKit bị từ chối, báo dự phòng là thông báo Time Sensitive, không kêu khi Im lặng — xem §3.1).

**Lịch sử:** lưu điểm đến, phương tiện (tự đoán theo tốc độ), chế độ báo, thời điểm báo/tắt, kết quả
(`on_time` / `snoozed` / `missed` / `cancelled` — dừng chuyến trước khi báo, hiển thị "Đã dừng"), quãng đường.

**Chế độ giả lập (demo):** mở bằng nhấn giữ logo 3 giây ở Cài đặt chung → chọn trace (tàu Hà Nội–Đồng Hới,
xe khách Mỹ Đình–Thái Bình, buýt nội thành, có hầm, quá trạm) và tốc độ phát (1×, 10×, 60×). Trace đi qua
cùng đường ống Location → Trip Engine → Alarm như dữ liệu thật.

## 5. Yêu cầu phi chức năng
- Pin ≤ 15% / 10 giờ; cold start ≤ 2 giây; app không crash trong 10 giờ chạy nền.
- Chạy offline hoàn toàn khi đã chọn điểm đến (trừ bản đồ nền và tìm địa chỉ).
- Android 8.0+ (API 26), target SDK mới nhất; iOS 16+ (AlarmKit khi iOS 26+).
- Tiếp cận: nút ≥ 44 px, tương phản ≥ 4.5:1, nhãn cho icon, hỗ trợ cỡ chữ hệ thống.
- Quyền riêng tư: vị trí không rời khỏi máy; analytics chỉ ghi sự kiện, không toạ độ.

## 6. Ngoài phạm vi kỹ thuật MVP 1
Backend, tài khoản, đồng bộ, API tìm đường, bản đồ offline, Live Activity (stretch goal nếu kịp).
