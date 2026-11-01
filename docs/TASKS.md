# Bảng task — MVP 1

Chuỗi mặc định cho mỗi task: `solution-designer → coder → reviewer → tester`.
Task loại **spike** dùng chuỗi rút gọn: `solution-designer` (kế hoạch thí nghiệm) → `coder` (app thí nghiệm)
→ người chạy trên máy thật → `solution-designer` (kết luận Go/No-go trong `docs/spikes/<ID>.md`).

Môi trường: `[linux]` container/máy Linux · `[mac]` cần macOS + Xcode · `[device]` cần máy thật + người.

## Phase 0 — Khởi động

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T00 | Toolchain + khung repo: cài Flutter & Android SDK, `flutter create` trong `app/` (app id `app.napstop`), lint, cấu trúc thư mục, flavor `dev`/`prod` | linux | — | done | `flutter analyze` sạch, `flutter build apk --debug` thành công |
| T01 | CI GitHub Actions: analyze, test Dart, test Kotlin JVM, build APK debug | linux | T00 | done | Workflow xanh trên PR mẫu |
| T02 | `tools/tracegen` (Dart CLI) + 6 trace đầu: tàu HN→Đồng Hới, xe khách Mỹ Đình→Thái Bình, buýt nội thành, hầm Hải Vân (mất GPS 6 phút), quá trạm, GPS nhiễu | linux | T00 | done | GPX hợp lệ + `*.expect.json` (mốc báo kỳ vọng) cho mỗi trace |

## Phase 1 — Spikes rủi ro (Gate: Go / No-go)

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| S1 | Android: foreground service location sống 10 giờ trên Xiaomi/Oppo/Vivo/Samsung (có/không tắt tối ưu pin) | linux + device | T00 | testing | Bảng kết quả từng máy, log thời gian sống, khuyến nghị |
| S2 | Android: báo thức kêu khi khoá máy + im lặng + DND, kích hoạt từ service (full-screen intent, `USAGE_ALARM`) | linux + device | T00 | testing | Video/biên bản 4 máy; quyền & policy Play cần khai |
| S3 | iOS: kích hoạt báo thức từ nền khi chạm mốc vị trí — AlarmKit (iOS 26) và fallback (Time Sensitive, Critical Alerts) | linux + device | — | done | Biên bản: kêu được không, âm lượng, khi im lặng/Focus; quyết định phương án |
| S4 | Đo pin 10 giờ với chiến lược lấy mẫu thưa→dày (Android + iOS) | device | S1, S3 | todo | % pin / 10 giờ mỗi máy; đề xuất tham số. iOS: thay S3-12 (When In Use, Im lặng + Ngủ, rút sạc): pha dày không trống > 60 s, đặt lại báo dự phòng từ nền không lỗi |
| S5 | Chính sách store: khai báo vị trí nền (Play), full-screen intent, App Store "Always" location; soạn mô tả + kịch bản video | linux | — | spec | Checklist nộp store + bản nháp mô tả |

## Phase 2 — Core engine

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T10 | **Spec Trip Engine**: máy trạng thái, EMA tốc độ, 3 chế độ, nhắc nhẹ, mất GPS, pin, quá trạm, SamplingPolicy, giờ báo dự phòng theo ETA (dùng chung T15/T17), bảng test case | linux | T02, Gate 1 | done | Spec duyệt; mỗi quy tắc PRD §4 có ≥ 1 test case; ARCHITECTURE §2/§3/§5 và PRD §4 đồng bộ với spec (Q1, Q2, Q4) |
| T10.1 | Sửa spec T10 theo rủi ro RK9: mất GPS ngay sau mẫu Doppler lúc hãm vào ga (lấy mẫu thưa) làm ước lượng tốc độ quá thấp → không báo trước khi tới (5/36 pha) | linux | T10, T11 | in-review | TR30 ở chế độ `policy` đạt ở cả 36 pha theo mô phỏng; T10 + test case cập nhật; không làm hỏng case khác |
| T11 | Bổ sung trace + expectations theo test case của T10 (coder mở rộng `tools/tracegen` theo T10 §8.2 + tester) | linux | T10 | done | Mọi test case T10 có trace/expect tương ứng; khoá fixture §8.2 và tuỳ chọn tracegen §8.3 (`dropSpeedAtStops`, `destinationOffsetM`, `truth.closest`, gap khi dừng ga); README §3.1, §4, §5; 9 profile mới `bus_hn_slow`, `coach_dn_langco_shortgap`, `coach_dn_langco_neardest`, `train_hn_dh_midgap`, `bus_hn_brt01_noisy_traps`, `train_hn_dh_stopgap`, `train_longstop`, `train_longstop_nospd`, `coach_gb_phuly_offroute`; case chuyển `final`; việc mang sang: T10 review R3-4, test report T10 #1, #5 |
| T11.1 | Tracegen theo T10.1: khoá `policyPhaseSweep`, TR30 chạy cả hai chế độ + quét 36 pha, điều kiện khả thi F1p; sửa bug `validate` thiếu kiểm anchor `overshoot` cần `truth.overshoot` (test report T11 #1) | linux | T10.1, T11 | todo | Theo danh sách việc cho T11 trong T10.1; chỉ `train_hn_dh_stopgap.expect.json` + README đổi, GPX giữ nguyên byte; bỏ `skip` của test TG33 known validate gap |
| T12 | Trip Engine Kotlin + test JVM chạy toàn bộ fixture | linux | T10, T10.1, T11.1 | todo | U01–U89, TR01–TR35, P01–P04, P06, P07 pass ở cả hai chế độ lấy mẫu; chốt T10 review R3-1 (trước T13) và test report T10 #2, #4; TR30 ở `policy` quét đủ 36 pha (tuỳ chọn dời lần giao fix SPARSE đầu 0…175 s) theo T10.1 (harness có mô phỏng báo hệ điều hành + khôi phục snapshot); logic không phụ thuộc Android API |
| T13 | Trip Engine Swift (Swift package thuần, `swift test` chạy được trên WSL) + test chạy cùng fixture | linux (WSL) + mac | T10, T10.1, T11.1 | todo | U01–U89, TR01–TR35, P01–P07 pass; P05 = trùng chính xác bản Kotlin |
| T14 | Pigeon API (`app/pigeons/core_api.dart`) + code sinh + stub 2 nền tảng | linux | T10, T19 | spec-ready | Build cả 2 nền tảng; Dart gọi được stub; có `setBatteryChoice`, `currentTrip()` đọc từ snapshot; iOS biên dịch qua workflow `ios-compile.yml` (macOS, chạy tay); code sinh commit + CI kiểm khớp; không lớp Pigeon nào chứa toạ độ |
| T15 | Android LocationService: foreground service, FLP, áp dụng SamplingPolicy, khôi phục sau khi app bị kill | linux | T12, T14, S1 | todo | Integration test với nguồn vị trí giả; notification cố định hiển thị trạng thái; snapshot ở `noBackupFilesDir`, Tick theo `wakeAtMs`, đặt báo dự phòng theo `FallbackAlarmChanged` (đặt mới trước, huỷ cũ sau; Tick không khởi động lại FGS bằng exact alarm), kiểm báo dự phòng trước khi kêu "now", gửi `AlarmSilenced`, notification khi chưa có GPS, khôi phục theo T10 §7.2 |
| T16 | Android AlarmController: full-screen activity, âm thanh tăng dần, rung, flash, tai nghe, snooze, tắt (vuốt/lắc/phép tính) | linux | T14, S2 | todo | Test instrumentation/robolectric cho logic; biên bản test máy thật; âm báo chạy trong `AlarmRingService` ở process riêng `:ring` (T10 RK14); chỉ chặn "now" khi báo dự phòng đang kêu (T10 nghĩa vụ 3) |
| T17 | iOS LocationController + AlarmController (theo kết luận S3, yêu cầu K4) | mac | T13, T14, S3 | todo | Chạy trace giả lập trên iPhone, báo đúng mốc khi khoá máy; báo dự phòng theo ETA luôn tồn tại và kêu khi app bị vuốt tắt/tự thoát; không kêu lần hai sau khi đã Tắt (S3 lỗi #1); có lượt When In Use; chạy kênh TS S3-9…11; quyền denied và lỗi đặt báo hiện lên UI; khôi phục theo `RestoreInfo` có `DISMISSED` (StopIntent ghi `dismissedAtMs` trước), gửi `AlarmSilenced`, kiểm báo dự phòng trước khi kêu "now" (T10 §7.2), snapshot `isExcludedFromBackup` |
| T18 | Chế độ giả lập: `SimulatedLocationSource` phát GPX 1×/10×/60× qua cùng pipeline | linux (+mac) | T12, T15 | todo | Trace tàu HN→Đồng Hới 60× báo đúng mốc trên Android |
| T19 | Đồng bộ tài liệu theo ADR-001 (đã duyệt Gate 1): PRD §3 màn 0 ("Khi dùng ứng dụng" + "Chính xác"), ARCHITECTURE §6 rủi ro 4, `PermissionHostApi` ở ARCHITECTURE §3 bỏ "location always" trên Android | linux | Gate 1 | done | PRD/ARCHITECTURE không còn yêu cầu vị trí nền Android; khớp ADR-001 mục 2–6 và S5 |

## Phase 3 — Giao diện (theo wireframe)

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T20 | Design system Flutter: màu, font Be Vietnam Pro, component (nút, chip, segmented, toggle, card, bottom sheet), dark mode | linux | T00 | changes-requested | Trang catalog component; golden test |
| T21 | Màn 0 Cấp quyền + Màn 9 Hướng dẫn pin theo hãng (nhận diện hãng máy) | linux | T14, T19, T20 | todo | Mỗi quyền có trạng thái thật; mở đúng trang cài đặt; hiện thực `PermissionHostApi` Android thật (thay stub T14) |
| T22 | Màn 1 Trang chủ: điểm đã lưu, chuyến gần đây, thẻ "Sẵn sàng" | linux | T20, T24 | todo | Widget test; đặt lại chuyến 1 chạm |
| T23 | Màn 2 Chọn điểm đến: tìm offline không dấu, Google Maps, Places fallback, ghim bản đồ | linux | T20, T24 | todo | "dong hoi" → Ga Đồng Hới đứng đầu; ghim chỉnh được; luôn hiện lối vào Places (3 bến must-have chưa có trên OSM); việc mang sang từ T24: khớp bỏ khoảng trắng ("hanoi", "sapa"), "ben xe hue", điểm fuzzy âm (review T24 #10), dòng ghi công OSM; **xếp hạng "ben xe <thành phố>" phải ra bến xe khách chính trước ga tàu** (test report T24 O1: "ben xe nha trang", "ben xe vinh"); hook đo hiệu năng TC37 (integration_test) |
| T24 | Dataset ga/bến: script lấy từ OSM + làm sạch → `assets/stations.json` + module tìm kiếm | linux | T00 | done | ≥ 150 ga tàu + bến xe tỉnh; test tìm kiếm |
| T25 | Màn 3 Cài đặt báo + cảnh báo khoảng cách quá ngắn | linux | T20, T10 | todo | Widget test cho 3 chế độ và cảnh báo (`shortDistanceWarning` theo T10 §4.7) |
| T26 | Màn 4 Đang theo dõi + trạng thái màn 6 (mất GPS) + màn 7 (pin yếu) | linux | T15, T20 | todo | Hiển thị đúng theo TripState từ native; khôi phục khi mở lại app |
| T27 | Màn 5 Báo thức (phía Flutter khi app mở) + Màn 8 Quá trạm | linux | T16, T20 | todo | Đồng bộ với native alarm; mở Google Maps chỉ đường quay lại |
| T28 | Màn 11 Lịch sử + Màn 12 Cài đặt chung + i18n vi/en + mở chế độ giả lập | linux | T20, T18 | todo | Lọc lịch sử; cài đặt lưu và áp dụng cho chuyến mới |
| T29 | Firebase: Crashlytics, Analytics (sự kiện, không vị trí), Remote Config tham số engine | linux | T00 | spec-ready | Kiểm tra payload không có toạ độ; tham số engine qua khoá `trip_engine_params` (T10 §5) |

## Phase 4 — Tích hợp & kiểm thử

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T30 | Integration test end-to-end bằng chế độ giả lập (6 trace) | linux (+mac) | T18, T21–T28 | todo | Tất cả trace pass trên Android; iOS chạy trên Mac |
| T31 | Giao thức + thực hiện field test: 3 chuyến thật (tàu, xe khách, buýt) | device | T30 | todo | Biên bản: mốc báo thực tế vs kỳ vọng, sự cố. iOS: lượt dài nếu S4 chưa chạy; S3-5, S3-15; máy iOS < 26 nếu mượn được |
| T32 | Test pin 10 giờ trên 2+ máy | device | T30 | todo | ≤ 15% hoặc đề xuất chỉnh tham số |
| T33 | Bug bash + sửa lỗi (mỗi bug là một task con T33.x theo chuỗi chuẩn) | all | T31, T32 | todo | Không còn bug mức blocker/major |

## Phase 5 — Phát hành demo

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T39 | Icon app (Android adaptive + iOS) + feature graphic Play + ảnh chụp store, theo design system T20 | linux | T20 | todo | Đủ kích thước theo yêu cầu Play/App Store; nguồn vector commit trong repo; PO duyệt |
| T40 | Build ký số + Play Internal Testing + TestFlight | linux + mac | T33, T39 | todo | Người thử cài được từ link; S3-3 kiểm lại trên bản TestFlight; Time Sensitive vượt Focus (tài khoản trả phí) |
| T41 | Kịch bản demo + video (giả lập 60× + clip đi xe thật) | device | T40 | todo | Video ≤ 3 phút, kịch bản trình bày |
