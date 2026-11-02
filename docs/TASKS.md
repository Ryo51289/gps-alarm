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
| T10.1 | Sửa spec T10 theo rủi ro RK9: mất GPS ngay sau mẫu Doppler lúc hãm vào ga (lấy mẫu thưa) làm ước lượng tốc độ quá thấp → không báo trước khi tới (5/36 pha) | linux | T10, T11 | done | TR30 ở chế độ `policy` đạt ở cả 36 pha theo mô phỏng; T10 + test case cập nhật; không làm hỏng case khác |
| T10.2 | Thiết kế lại biên sớm của báo dự phòng theo ETA khi process chết (PO 01/11: nới biên, đo bằng harness `kill` quét mọi thời điểm) — hiện 88% báo muộn khi còn 1–2 h trên tàu HN–ĐH | linux | T10.1 | done | Tỉ lệ báo dự phòng rơi sau giờ tới giảm rõ rệt trên các trace dài, đánh đổi "báo sớm tối đa" được nêu bằng số; đường "now" vẫn thắng khi app sống |
| T10.4 | Sửa spec Trip Engine theo test report T12: GAP-1 (Tick đúng `wakeAtMs` không báo `GPS_LOST` vì điều kiện `<` nghiêm ngặt, engine kẹt TRACKING không còn `wakeAtMs`) và GAP-2 (bước 4 dùng chính sách lấy mẫu cũ); bất biến "Tick tại `wakeAtMs` phải báo hoặc hẹn giờ muộn hơn" | linux | T10.3 | spec | Spec + danh sách việc cho T12/T13; test U99+; nêu số đo bị ảnh hưởng (TR30, TR37, P05) |
| T11 | Bổ sung trace + expectations theo test case của T10 (coder mở rộng `tools/tracegen` theo T10 §8.2 + tester) | linux | T10 | done | Mọi test case T10 có trace/expect tương ứng; khoá fixture §8.2 và tuỳ chọn tracegen §8.3 (`dropSpeedAtStops`, `destinationOffsetM`, `truth.closest`, gap khi dừng ga); README §3.1, §4, §5; 9 profile mới `bus_hn_slow`, `coach_dn_langco_shortgap`, `coach_dn_langco_neardest`, `train_hn_dh_midgap`, `bus_hn_brt01_noisy_traps`, `train_hn_dh_stopgap`, `train_longstop`, `train_longstop_nospd`, `coach_gb_phuly_offroute`; case chuyển `final`; việc mang sang: T10 review R3-4, test report T10 #1, #5 |
| T11.1 | Tracegen theo T10.1: khoá `policyPhaseSweep`, TR30 chạy cả hai chế độ + quét 36 pha, điều kiện khả thi F1p; sửa bug `validate` thiếu kiểm anchor `overshoot` cần `truth.overshoot` (test report T11 #1) | linux | T10.2, T11 | done | Theo danh sách việc cho T11 trong T10.1/T10.2; chỉ các `*.expect.json` mà T10.1/T10.2 liệt kê + README đổi, mọi GPX giữ nguyên byte; không khẳng định các số "≈" ở T10 §8.3 (lệch 12–28 s so với GPX, test report T10.1-T10.2 nit 1); bỏ `skip` của test TG33 known validate gap; TR37 7 case (5 chặn + 2 chỉ thống kê), khoá `killSweep` có `earlyFrom`/`statsOnly`, sinh lại `train_longstop`, generator 1.2.0 |
| T11.2 | Tracegen theo T10.3: khoá `allowFallbackFirst` (V14–V16), TR38 trên `coach_gb_phuly_offroute`, profile mới `coach_gb_phuly_offroute_2k` (TR32, TR27), cửa sổ `coach_md_tb` theo Q10 = A; generator 1.3.0 | linux | T10.3, T11.1 | done | Theo `docs/specs/T11.2.md`; GPX cũ giữ nguyên từng byte; `check` + `dart test` xanh (TG52–TG59) |
| T12 | Trip Engine Kotlin (module pure JVM `:core-trip`) + test JVM chạy toàn bộ fixture | linux | T10, T10.2, T10.3, T11.1, T11.2 | done | U01–U98, TR01–TR38 (TR37: 5 kiểm + 2 chỉ thống kê), P01–P04, P06, P07 pass ở cả hai chế độ lấy mẫu; chốt T10 review R3-1 (trước T13) và test report T10 #2, #4; TR30 ở `policy` quét đủ 36 pha (tuỳ chọn dời lần giao fix SPARSE đầu 0…175 s) theo T10.1 (harness có mô phỏng báo hệ điều hành + khôi phục snapshot); logic không phụ thuộc Android API |
| T13 | Trip Engine Swift (Swift package thuần, `swift test` chạy được trên WSL) + test chạy cùng fixture | linux (WSL) + mac | T10, T10.2, T10.3, T11.1, T11.2, T12 (P05 manifest) | done | U01–U98, TR01–TR38, P01–P07 pass; P05 = khớp `fixtures/p05/manifest.json` của T12; được `done` khi chưa chạy macOS — bước đó chuyển sang lần chạy `ios-compile.yml` hoặc T17 |
| T14 | Pigeon API (`app/pigeons/core_api.dart`) + code sinh + stub 2 nền tảng | linux | T10, T19 | done | Build cả 2 nền tảng; Dart gọi được stub; có `setBatteryChoice`, `currentTrip()` đọc từ snapshot; iOS biên dịch qua workflow `ios-compile.yml` (macOS, chạy tay); code sinh commit + CI kiểm khớp; không lớp Pigeon nào chứa toạ độ |
| T14.1 | Bổ sung Pigeon (chỉ thêm, không phá): `TripConfigMsg.engineParamsJson` (luật V11 ≤ 16 384 ký tự), `PermissionHostApi.deviceStatus()` (pin + sạc, âm lượng báo thức, Không làm phiền; Android đọc thật, iOS chỉ pin) — hợp nhất đề xuất của T22 và T25; stub 2 nền tảng + test | linux | T14 | done | Theo T25 §7; code sinh commit + CI khớp; T22, T25, T29 dùng `deviceStatus()` |
| T15 | Android LocationService: foreground service, FLP, áp dụng SamplingPolicy, khôi phục sau khi app bị kill | linux | T12, T14, S1 | todo | Integration test với nguồn vị trí giả; notification cố định hiển thị trạng thái; snapshot ở `noBackupFilesDir`, Tick theo `wakeAtMs`, đặt báo dự phòng theo `FallbackAlarmChanged` (đặt mới trước, huỷ cũ sau; Tick không khởi động lại FGS bằng exact alarm), kiểm báo dự phòng trước khi kêu "now", gửi `AlarmSilenced`, notification khi chưa có GPS, khôi phục theo T10 §7.2; đo Tick c8 khi Doze (`dumpsys deviceidle force-idle`, mất GPS ≥ 60 phút; mọi Tick tới trước giờ dự phòng − 30 s, T10.2); **ghi snapshot lỗi (ví dụ bộ nhớ đầy) không bao giờ được chặn việc kêu/thông báo/full-screen**: kêu và commit trong bộ nhớ trước, ghi đĩa best-effort có thử lại (review T14 R2-1); bọc từng listener (R2-3); listener ném lỗi không được chặn listener khác hay làm fail API đã commit (test report T14 F1) |
| T16 | Android AlarmController: full-screen activity, âm thanh tăng dần, rung, flash, tai nghe, snooze, tắt (vuốt/lắc/phép tính) | linux | T14, S2 | todo | Test instrumentation/robolectric cho logic; biên bản test máy thật; âm báo chạy trong `AlarmRingService` ở process riêng `:ring` (T10 RK14); chỉ chặn "now" khi báo dự phòng đang kêu (T10 nghĩa vụ 3); bọc lỗi `AlarmHostApi` thật như T14 F3 |
| T17 | iOS LocationController + AlarmController (theo kết luận S3, yêu cầu K4) | mac | T13, T14, S3 | todo | Chạy trace giả lập trên iPhone, báo đúng mốc khi khoá máy; báo dự phòng theo ETA luôn tồn tại và kêu khi app bị vuốt tắt/tự thoát; không kêu lần hai sau khi đã Tắt (S3 lỗi #1); có lượt When In Use; chạy kênh TS S3-9…11; quyền denied và lỗi đặt báo hiện lên UI; khôi phục theo `RestoreInfo` có `DISMISSED` (StopIntent ghi `dismissedAtMs` trước), gửi `AlarmSilenced`, kiểm báo dự phòng trước khi kêu "now" (T10 §7.2), snapshot `isExcludedFromBackup`; thử AlarmKit đặt lại báo dự phòng ≥ 60 lần/giờ (T10.2) |
| T18 | Chế độ giả lập: `SimulatedLocationSource` phát GPX 1×/10×/60× qua cùng pipeline | linux (+mac) | T12, T15 | todo | Trace tàu HN→Đồng Hới 60× báo đúng mốc trên Android |
| T19 | Đồng bộ tài liệu theo ADR-001 (đã duyệt Gate 1): PRD §3 màn 0 ("Khi dùng ứng dụng" + "Chính xác"), ARCHITECTURE §6 rủi ro 4, `PermissionHostApi` ở ARCHITECTURE §3 bỏ "location always" trên Android | linux | Gate 1 | done | PRD/ARCHITECTURE không còn yêu cầu vị trí nền Android; khớp ADR-001 mục 2–6 và S5 |

## Phase 3 — Giao diện (theo wireframe)

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T20 | Design system Flutter: màu, font Be Vietnam Pro, component (nút, chip, segmented, toggle, card, bottom sheet), dark mode | linux | T00 | done | Trang catalog component; golden test |
| T21 | Màn 0 Cấp quyền + Màn 9 Hướng dẫn pin theo hãng (nhận diện hãng máy) | linux | T14, T19, T20 | todo | Mỗi quyền có trạng thái thật; mở đúng trang cài đặt; hiện thực `PermissionHostApi` Android thật (thay stub T14); bọc lỗi `PermissionHostApi` thật, không để `wrapError` gửi stack trace sang Dart (T14 F3); `DeviceStatusReader` thêm constructor inject được (sources, sdkInt, warn) để test JVM (T14.1 O2); native không trả `precise = notApplicable` trên Android (review T22: Trang chủ sẽ hiện "Vị trí: Gần đúng" và chặn bắt đầu chuyến); test report T22 O6: thẻ "Sẵn sàng" đang hiện xanh khi `deviceStatus()` lỗi, và DND Priority trên API 26–29 không cảnh báo được — T21 chốt cách đọc native và đề xuất designer sửa §8.3 T22 (lỗi đọc → mức `check`, không phải `ready`) |
| T22 | Màn 1 Trang chủ: điểm đã lưu, chuyến gần đây, thẻ "Sẵn sàng" | linux | T20, T24, T14.1 | done | Widget test; đặt lại chuyến 1 chạm; thẻ "Sẵn sàng" cảnh báo khi Không làm phiền ở mức "Tắt hoàn toàn" (`alarmMuted=true`, test report T14.1 O1) |
| T23 | Màn 2 Chọn điểm đến: tìm offline không dấu, Google Maps, Places fallback, ghim bản đồ | linux | T20, T24, T22, T14.1 | spec-ready | "dong hoi" → Ga Đồng Hới đứng đầu; ghim chỉnh được; luôn hiện lối vào Places (3 bến must-have chưa có trên OSM); việc mang sang từ T24: khớp bỏ khoảng trắng ("hanoi", "sapa"), "ben xe hue", điểm fuzzy âm (review T24 #10), dòng ghi công OSM; **xếp hạng "ben xe <thành phố>" phải ra bến xe khách chính trước ga tàu** (test report T24 O1: "ben xe nha trang", "ben xe vinh"); hook đo hiệu năng TC37 (integration_test) |
| T24 | Dataset ga/bến: script lấy từ OSM + làm sạch → `assets/stations.json` + module tìm kiếm | linux | T00 | done | ≥ 150 ga tàu + bến xe tỉnh; test tìm kiếm |
| T25 | Màn 3 Cài đặt báo + cảnh báo khoảng cách quá ngắn | linux | T20, T10, T14.1, T22 | spec-ready | Widget test cho 3 chế độ và cảnh báo (`shortDistanceWarning` theo T10 §4.7); cảnh báo trước khi bắt đầu nếu `alarmMuted=true` (Không làm phiền "Tắt hoàn toàn", T14.1 O1); tự gọi `currentTrip()` ngay trước `startTrip` (review T22 vòng 2: lúc `activeTripProvider` còn tải, màn 1 coi như chưa có chuyến) |
| T26 | Màn 4 Đang theo dõi + trạng thái màn 6 (mất GPS) + màn 7 (pin yếu) | linux | T15, T20 | todo | Hiển thị đúng theo TripState từ native; khôi phục khi mở lại app; ẩn `speedKmh` khi `isEstimated`; copy mới `alarmReasonFallback` (T10.2); subscriber mới khi mọi subscription đang pause nhận state cũ (T14 F2) |
| T27 | Màn 5 Báo thức (phía Flutter khi app mở) + Màn 8 Quá trạm | linux | T16, T20 | todo | Đồng bộ với native alarm; mở Google Maps chỉ đường quay lại |
| T28 | Màn 11 Lịch sử + Màn 12 Cài đặt chung + i18n vi/en + mở chế độ giả lập | linux | T20, T18 | todo | Lọc lịch sử; cài đặt lưu và áp dụng cho chuyến mới; sửa trước T20 N1/N2 (`NapListRow` intrinsic width khi đặt trong dialog, báo tràn) |
| T29 | Firebase: Crashlytics, Analytics (sự kiện, không vị trí), Remote Config tham số engine | linux | T00 | spec-ready | Kiểm tra payload không có toạ độ; tham số engine qua khoá `trip_engine_params` (T10 §5); chuyển `reportNonFatal()` (T22) sang Crashlytics bằng `recordFlutterError` (non-fatal, không phải `recordFlutterFatalError`), giữ quy tắc chỉ gửi kiểu lỗi, không gửi message (review T22 vòng 2 N1) |

## Phase 4 — Tích hợp & kiểm thử

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T30 | Integration test end-to-end bằng chế độ giả lập (6 trace) | linux (+mac) | T18, T21–T28 | todo | Tất cả trace pass trên Android; iOS chạy trên Mac |
| T31 | Giao thức + thực hiện field test: 3 chuyến thật (tàu, xe khách, buýt) | device | T30 | todo | Biên bản: mốc báo thực tế vs kỳ vọng, sự cố. iOS: lượt dài nếu S4 chưa chạy; S3-5, S3-15; máy iOS < 26 nếu mượn được; đo phần báo dự phòng muộn còn lại khi app chết (T10.2 RK16c, PO chấp nhận rủi ro) |
| T32 | Test pin 10 giờ trên 2+ máy | device | T30 | todo | ≤ 15% hoặc đề xuất chỉnh tham số |
| T33 | Bug bash + sửa lỗi (mỗi bug là một task con T33.x theo chuỗi chuẩn) | all | T31, T32 | todo | Không còn bug mức blocker/major |

## Phase 5 — Phát hành demo

| ID | Task | Env | Phụ thuộc | Trạng thái | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| T39 | Icon app (Android adaptive + iOS) + feature graphic Play + ảnh chụp store, theo design system T20 | linux | T20 | todo | Đủ kích thước theo yêu cầu Play/App Store; nguồn vector commit trong repo; PO duyệt |
| T40 | Build ký số + Play Internal Testing + TestFlight | linux + mac | T33, T39 | todo | Người thử cài được từ link; S3-3 kiểm lại trên bản TestFlight; Time Sensitive vượt Focus (tài khoản trả phí) |
| T41 | Kịch bản demo + video (giả lập 60× + clip đi xe thật) | device | T40 | todo | Video ≤ 3 phút, kịch bản trình bày |
