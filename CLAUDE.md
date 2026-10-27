# Tới Rồi — báo thức theo vị trí (MVP 1)

App cho người đi xe khách / tàu đường dài: đặt điểm đến, ngủ, app đánh thức khi gần tới
(theo khoảng cách, theo thời gian, hoặc chế độ thông minh). MVP 1 **không có backend**.

## Đọc trước khi làm bất cứ task nào

| Tài liệu | Nội dung |
|---|---|
| `docs/product/PRD-MVP1.md` | Phạm vi, màn hình, quy tắc hành vi, yêu cầu phi chức năng |
| `docs/architecture/ARCHITECTURE.md` | Tech stack đã chốt, module, cấu trúc thư mục, data model |
| `docs/PLAN.md` | Lộ trình tới bản demo, các cổng duyệt (gate) |
| `docs/TASKS.md` | Bảng task: ID, phụ thuộc, trạng thái, tiêu chí hoàn thành |
| Wireframe | https://claude.ai/artifact/Wek6rKCuUwnvtUvKE8vxY6 (màn 0–9, 11, 12 thuộc MVP 1) |

## Tech stack (đã chốt — đổi phải có ADR trong `docs/architecture/adr/`)

- **UI:** Flutter (stable mới nhất), Dart 3, Riverpod, go_router, drift (SQLite), ARB i18n (vi, en)
- **Core native:** Android = Kotlin (Foreground Service `location`, Fused Location, full-screen intent,
  `USAGE_ALARM`); iOS = Swift (CLMonitor/region + continuous updates, AlarmKit iOS 26+, fallback
  Time Sensitive notification)
- **Cầu nối:** Pigeon (`app/pigeons/`)
- **Trip Engine:** viết native 2 bản (Kotlin + Swift), dùng chung fixture trong `fixtures/traces/`
- **Bản đồ:** Google Maps SDK; tìm kiếm ưu tiên dataset ga/bến offline, fallback Places Autocomplete
- **Phụ trợ:** Firebase Crashlytics, Analytics (KHÔNG có vị trí), Remote Config

## Quy trình agent (bắt buộc cho mọi task trong `docs/TASKS.md`)

```
solution-designer ─▶ coder ─▶ reviewer ─┬─ APPROVE ─▶ tester ─┬─ PASS ─▶ DONE
        ▲                ▲              │                      │
        │                └── CHANGES ───┘                      │
        │                └──────────── BUG (kèm repro) ─────────┘
        └── câu hỏi thiết kế / spec sai
```

1. **Orchestrator** (session Claude chính) chọn task `todo` có đủ phụ thuộc `done`, giao cho
   `solution-designer` → `docs/specs/<ID>.md`, trạng thái `spec-ready`.
   Nếu spec có mục "Câu hỏi mở" cần người quyết → dừng, hỏi người dùng.
2. `coder` hiện thực theo spec → trạng thái `in-review`, ghi "Implementation notes" cuối spec.
3. `reviewer` → `docs/reviews/<ID>.md`, kết luận `APPROVE` hoặc `CHANGES_REQUESTED`.
   Tối đa 3 vòng coder↔reviewer; quá 3 vòng → `blocked`, báo người dùng.
4. `tester` → viết/chạy test, `docs/test-reports/<ID>.md`, kết luận `PASS` hoặc `FAIL`.
   FAIL → quay lại coder (kèm repro) → reviewer xem phần thay đổi → tester chạy lại.
5. PASS → orchestrator commit cục bộ (`<ID>: <tóm tắt>`), cập nhật `docs/TASKS.md` = `done`.
   **Chỉ push khi người dùng yêu cầu.**
6. Hết mỗi Phase → dừng ở **Gate**, tóm tắt cho người dùng duyệt trước khi sang phase sau.

Trạng thái task: `todo` · `spec` · `spec-ready` · `coding` · `in-review` · `changes-requested`
· `testing` · `done` · `blocked`. Chỉ orchestrator sửa cột trạng thái trong `docs/TASKS.md`
(agent con ghi đề xuất trạng thái ở cuối báo cáo của mình).

## Cấu trúc repo

```
gps-alarm/
├── CLAUDE.md
├── .claude/agents/            solution-designer, coder, reviewer, tester
├── docs/
│   ├── product/PRD-MVP1.md
│   ├── architecture/ARCHITECTURE.md, adr/
│   ├── PLAN.md, TASKS.md
│   ├── specs/<ID>.md  reviews/<ID>.md  test-reports/<ID>.md
│   ├── spikes/<ID>.md test-protocols/
├── app/                       Flutter app (lib/, android/, ios/, test/, integration_test/, pigeons/)
├── fixtures/traces/           GPX + expectations.json dùng chung cho Dart/Kotlin/Swift
├── tools/tracegen/            Dart CLI sinh trace giả lập (tàu, xe khách, buýt, hầm, quá trạm)
└── data/stations/             dữ liệu ga/bến thô + script build → app/assets/stations.json
```

## Quy ước code

- Dart: feature-first (`lib/features/<feature>/{data,domain,presentation}`), `very_good_analysis`
  hoặc `flutter_lints` (chốt ở T00), không `print` — dùng logger có mức độ.
- Kotlin: coroutines + Flow, không blocking main thread, package `vn.toiroi.core.{location,trip,alarm}`.
- Swift: Swift Concurrency, module `Core/{Location,Trip,Alarm}`.
- Code, tên biến, comment: tiếng Anh. Chuỗi hiển thị: chỉ qua ARB, bản tiếng Việt là bản gốc.
- Mỗi hàm logic thuần (Trip Engine, format, search) phải có unit test.

## Lệnh thường dùng (sau T00)

```bash
cd app && flutter pub get
dart run pigeon --input pigeons/core_api.dart
flutter analyze && flutter test
cd android && ./gradlew :app:testDebugUnitTest      # test Kotlin (Trip Engine)
flutter build apk --debug
dart run ../tools/tracegen --profile train_hn_dh --out ../fixtures/traces/
```

## Ràng buộc môi trường

- **Máy dev chính: Windows**, repo tại `D:\work\gps-alarm`. Claude Code chạy shell qua **Git Bash** →
  lệnh viết dạng bash, đường dẫn tương đối hoặc `/d/work/gps-alarm`; Gradle dùng `./gradlew` trong Git Bash
  (hoặc `gradlew.bat` trong PowerShell/cmd).
- **Làm được trên máy này:** Flutter/Dart, build + chạy Android (emulator hoặc máy thật qua USB),
  Kotlin JVM test, `tools/tracegen`, dataset ga/bến. Nhãn `[linux]` trong `docs/TASKS.md` = làm được ở đây.
- **Không làm được:** Xcode/iOS → task `[mac]` (S3, T13, T17, phần iOS của T40) chờ máy Mac hoặc CI macOS.
  Tạm thời làm **Android trước**; phương án iOS chốt ở Gate 1.
- **Yêu cầu Windows:** bật Developer Mode (Flutter cần symlink cho plugin); Flutter SDK ở đường dẫn không có
  dấu cách (vd `C:\src\flutter`); `git config --global core.longpaths true`; Android Studio + Android SDK +
  cmdline-tools, đã chạy `flutter doctor --android-licenses`; bật Windows Hypervisor Platform để chạy emulator.
- **Line ending:** repo dùng LF (`.gitattributes`, thêm ở T00); file `.bat`/`.cmd` dùng CRLF.
- Task `[device]`: điện thoại Android cắm USB, bật USB debugging; iPhone khi có Mac.
- Remote: GitHub `Ryo51289/gps-alarm`, nhánh `main`. **Chỉ push khi người dùng yêu cầu.**

## Quy tắc bắt buộc

- **Quyền riêng tư:** vị trí không rời khỏi máy trong MVP 1. Không log toạ độ ở mức release,
  không gửi vị trí vào Analytics/Crashlytics.
- **Độ tin cậy trên hết:** mọi thay đổi chạm tới Location/Trip/Alarm phải có test trace tương ứng.
- **Không bịa API:** API nền tảng (AlarmKit, Android 14+/15+ policies…) phải kiểm chứng với tài liệu
  chính thức và ghi link trong spec.
- **Copy tiếng Việt:** ngắn, rõ, có dấu đầy đủ; nút ≥ 44 px; tương phản ≥ 4.5:1.
