# NapStop — báo thức theo vị trí (MVP 1)

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
├── data/stations/             dữ liệu ga/bến thô + script build → app/assets/stations.json
└── spikes/                    app thí nghiệm của spike (vd `android-probe/`, Kotlin thuần) + `results/`; ngoài CI, bỏ được
```

## Quy ước code

- Dart: feature-first (`lib/features/<feature>/{data,domain,presentation}`), lint `very_good_analysis` 11
  (chốt ở T00), không `print` — dùng logger có mức độ.
- Dart 3.13: constructor viết `new(...)` / `const new(...)`, không lặp tên class
  (lint `unnecessary_type_name_in_constructor`); chỗ gọi vẫn là `NapStopApp(...)`. Constructor riêng: `new _(...)`.
  Factory **không** dùng `new`: không tên viết `factory (...)`, có tên viết `factory name(...)`
  (`factory new(...)` là lỗi biên dịch `factory_constructor_new_name`).
- Flutter ghim **3.47.8** (Dart ≥ 3.13.7, `pubspec.yaml` có `sdk: ^3.13.7`) — máy dev và CI dùng đúng bản này;
  nâng phiên bản phải qua task riêng, sửa cùng lúc `FLUTTER_VERSION`, `DART_VERSION`, `ANDROID_NDK_VERSION` trong `ci.yml`.
- Kotlin: coroutines + Flow, không blocking main thread, package `app.napstop.core.{location,trip,alarm}`.
- Swift: Swift Concurrency, module `Core/{Location,Trip,Alarm}`.
- Code, tên biến, comment: tiếng Anh. Chuỗi hiển thị: chỉ qua ARB, bản tiếng Việt là bản gốc.
- Mỗi hàm logic thuần (Trip Engine, format, search) phải có unit test.

## Lệnh thường dùng (sau T00)

```bash
cd app && flutter pub get
dart run pigeon --input pigeons/core_api.dart
flutter analyze && flutter test
flutter build apk --config-only                     # lần đầu sau khi clone: sinh gradlew + cấu hình Gradle
cd android && ./gradlew :app:testDevDebugUnitTest   # test Kotlin app, flavor dev
cd android && ./gradlew :core-trip:test :core-runtime:test  # Trip Engine (T12) + trip runtime Android (T15), JVM thuần
flutter build apk --debug                          # flavor mặc định dev; prod: --flavor prod
flutter test --dart-define=NAPSTOP_EXPECT_FLAVOR=dev  # giống CI; prod: --flavor prod --dart-define=...=prod

# Trace giả lập (chạy trong tools/tracegen; mặc định ghi vào ../../fixtures/traces)
cd tools/tracegen && dart pub get
dart run bin/tracegen.dart generate --profile train_hn_dh   # hoặc --all
dart run bin/tracegen.dart check && dart test               # fixture commit phải khớp generator
```

CI: `.github/workflows/ci.yml`, 3 job `dart`, `android`, `tracegen` (chi tiết: `app/README.md` mục CI).
Định dạng fixture dùng chung Dart/Kotlin/Swift: `fixtures/traces/README.md` (schema v1). Trace mới = thêm profile
trong `tools/tracegen/data/profiles/` rồi `generate`; **không sửa tay fixture**.

## Ràng buộc môi trường

- **Máy dev chính: Windows**, repo tại `D:\work\gps-alarm`. Claude Code chạy shell qua **Git Bash** →
  lệnh viết dạng bash, đường dẫn tương đối hoặc `/d/work/gps-alarm`; Gradle dùng `./gradlew` trong Git Bash
  (hoặc `gradlew.bat` trong PowerShell/cmd).
- **Làm được trên máy này:** Flutter/Dart, build + chạy Android (emulator hoặc máy thật qua USB),
  Kotlin JVM test, `tools/tracegen`, dataset ga/bến. Nhãn `[linux]` trong `docs/TASKS.md` = làm được ở đây.
- **Không làm được:** Xcode/iOS → task `[mac]` (S3, T13, T17, phần iOS của T40) chờ máy Mac hoặc CI macOS.
  Tạm thời làm **Android trước**; phương án iOS chốt ở Gate 1.
- **Yêu cầu Windows:** bật Developer Mode (Flutter cần symlink cho plugin); Flutter SDK ở `D:\src\flutter`
  và `PUB_CACHE=D:\src\pub-cache` — **cùng ổ với repo** (khác ổ thì Kotlin incremental build lỗi
  "different roots"); `JAVA_HOME` trỏ tới một JDK 17 bất kỳ (JBR của Android Studio hoặc MS OpenJDK 17 đều được,
  cần cho `./gradlew`); `git config --global core.longpaths true`; Android SDK + cmdline-tools (`ANDROID_HOME`
  đặt ở đâu cũng được), đã chạy `flutter doctor --android-licenses`; bật Windows Hypervisor Platform để chạy emulator.
  Chi tiết cài đặt: `docs/specs/T00.md` §2.
- **Máy hiện tại:** Flutter 3.47.8 ở `D:\src\flutter`, `ANDROID_HOME=D:\work\android-sdk`, JDK = MS OpenJDK 17.
  Máy còn một Flutter 3.41 cũ ở `D:\work\flutter` — không dùng được với project này (không resolve được lint).
  Nếu `flutter --version` không ra 3.47.8 thì thêm vào đầu lệnh:
  `export PATH="/d/src/flutter/bin:$PATH"; export PUB_CACHE=/d/src/pub-cache`.
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
