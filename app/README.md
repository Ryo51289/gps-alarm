# NapStop app

Flutter app của NapStop (báo thức theo vị trí). Tổng quan dự án, quy trình và quy ước code: xem
[`../CLAUDE.md`](../CLAUDE.md).

## Yêu cầu

- Flutter **3.47.8 stable** (Dart 3.13.7), đặt ở `D:\src\flutter`; `PUB_CACHE=D:\src\pub-cache` (cùng ổ với repo).
- Android SDK với platform **36** (`ANDROID_HOME`, đặt ở đâu cũng được), license đã chấp nhận.
- `JAVA_HOME` trỏ tới JDK 17 (JBR của Android Studio hoặc MS OpenJDK 17), cần cho `./gradlew`.
- Hướng dẫn cài đặt trên Windows: [`docs/specs/T00.md`](../docs/specs/T00.md) §2.

## Lệnh thường dùng (chạy trong `app/`)

```bash
flutter pub get
flutter analyze
flutter test
flutter run                              # flavor dev (mặc định)
flutter run --flavor prod
flutter build apk --debug                # -> build/app/outputs/flutter-apk/app-dev-debug.apk
flutter build apk --debug --flavor prod  # -> build/app/outputs/flutter-apk/app-prod-debug.apk

# Test Kotlin JVM. Sau khi clone mới, chạy --config-only trước để sinh gradlew và local.properties.
flutter build apk --config-only
cd android && ./gradlew :app:testDevDebugUnitTest
```

## CI

Workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) (GitHub Actions, `ubuntu-24.04`). Chạy khi mở hoặc
cập nhật PR, khi push `main`, và chạy tay ở tab Actions (`workflow_dispatch`). Bỏ qua commit chỉ đổi `docs/**`, `*.md`,
`.claude/**`. Bốn job chạy song song:

- Job `dart`: `flutter pub get --enforce-lockfile` · kiểm code Pigeon sinh ra khớp input (T14) ·
  `dart format --output=none --set-exit-if-changed lib test integration_test` ·
  `flutter analyze` · `flutter test` (dev) · `flutter test --flavor prod`.
- Job `android`: `flutter build apk --config-only` · `./gradlew :app:testDevDebugUnitTest :app:testProdDebugUnitTest` ·
  `flutter build apk --debug` · `flutter build apk --debug --flavor prod` · kiểm package id của 2 APK
  (`app.napstop.dev`, `app.napstop`) bằng `aapt2`.
- Job `tracegen` (thư mục `tools/tracegen`): `dart pub get --enforce-lockfile` ·
  `dart format --output=none --set-exit-if-changed .` · `dart analyze --fatal-infos` · `dart test` (gồm test golden:
  fixture commit từ Windows phải khớp từng byte khi sinh lại trên Linux) · `validate` 6 cặp fixture.
- Job `stationgen` (thư mục `tools/stationgen`, T24): `dart pub get --enforce-lockfile` ·
  `dart format --output=none --set-exit-if-changed .` · `dart analyze --fatal-infos` · `dart test` (gồm test golden:
  `app/assets/stations.json` và `data/stations/BUILD_REPORT.md` phải khớp từng byte khi build lại trên Linux) ·
  `dart run bin/stationgen.dart check` (ngưỡng A1–A5). Không bước nào gọi mạng; `fetch` chỉ chạy tay.

Kết quả từng job nằm ở phần **Summary** của run. Chạy test giống CI ở máy:

```bash
flutter test --dart-define=NAPSTOP_EXPECT_FLAVOR=dev
flutter test --flavor prod --dart-define=NAPSTOP_EXPECT_FLAVOR=prod
```

Không có define thì test `AppFlavor.current` bị skip. Phiên bản Flutter/Dart/NDK của CI nằm ở khối `env` trong workflow
(`FLUTTER_VERSION`, `DART_VERSION`, `ANDROID_NDK_VERSION`), phải trùng máy dev; nâng Flutter thì sửa cả 3 cùng lúc.

## Flavor

| Flavor | Android application id | Tên app | Ghi chú |
|---|---|---|---|
| `dev` (mặc định) | `app.napstop.dev` | NapStop Dev | `default-flavor: dev` trong `pubspec.yaml` |
| `prod` | `app.napstop` | NapStop | |

Dart đọc flavor qua `AppFlavor.current` (`lib/app/flavor.dart`, dựa trên `appFlavor`).
iOS flavor: chưa có (cần Mac). Phải tạo scheme `dev`/`prod` trước khi `flutter run` trên iOS.

## Design system, catalog, golden (T20)

Token, theme, component nằm ở `lib/core/design/` (import `package:napstop/core/design/design.dart`). Màu đọc qua
`context.napColors`, chữ qua `context.napText` / `context.napStyle(NapTypography.caption)`, khoảng cách `NapSpace`,
bo góc `NapRadii`, icon `NapIcons`. Không hard-code hex hay `Icons.*` trong feature. Spec: `docs/specs/T20.md`.

```bash
flutter run -t lib/main_catalog.dart                 # catalog: đổi light/dark/alarm, cỡ chữ, vi/en
flutter test --update-goldens --tags golden          # sinh lại 30 ảnh golden (test/core/design/goldens/)
flutter test --tags golden                           # chỉ chạy golden
```

- Catalog là công cụ dev, entrypoint riêng; `main.dart` không import nên mã catalog không vào APK.
- Golden vẽ chữ bằng font `FlutterTest` (ô vuông) và bóng đặc để giống nhau trên Windows và Linux; comparator
  (`test/helpers/nap_golden_comparator.dart`) cho lệch tối đa 0,1% pixel. Ảnh lỗi nằm ở `test/**/failures/`
  (không commit; CI upload kèm artifact `dart-test-results` khi fail). Chỉ cập nhật golden khi thay đổi giao diện là
  cố ý, và xem ảnh mới trước khi commit.
- Font Be Vietnam Pro (4 weight) bundle trong `assets/fonts/BeVietnamPro/` (nguồn + SHA-256 ở README trong đó).

## Cầu nối native (Pigeon, T14)

Định nghĩa API: [`pigeons/core_api.dart`](pigeons/core_api.dart) (spec `docs/specs/T14.md` §3). Pigeon ghim **29.1.0**
(`dev_dependencies`, không `^`). Code sinh được **commit**:

| Nền tảng | File sinh | Viết tay |
|---|---|---|
| Dart | `lib/core/bridge/core_api.g.dart` | `core_bridge.dart` (`CoreBridge`, `StubTraces`), `bridge_exception.dart` |
| Android | `android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt` | `BridgeRegistrar`, `TripHostApiImpl`, `TripConfigValidator`, `stub/` |
| iOS | `ios/Runner/Bridge/CoreApi.g.swift` | `CoreBridgeStub.swift` (trạng thái trong bộ nhớ, chờ T17) |

```bash
# Sau khi sửa pigeons/core_api.dart (chạy trong app/), commit cả 3 file sinh trong CÙNG commit:
dart run pigeon --input pigeons/core_api.dart
dart format lib/core/bridge/core_api.g.dart
```

- CI (job `dart`, bước "Check Pigeon output is up to date") sinh lại rồi `git diff --exit-code`: quên sinh lại thì fail.
- **Quyền riêng tư:** không lớp Pigeon nào được chứa toạ độ (Pigeon sinh `toString` in mọi trường); toạ độ chỉ đi qua
  tham số `destLat`/`destLng` của `startTrip`. Không log message Pigeon (có `destinationName`). Test
  `test/core/bridge/bridge_source_scan_test.dart` chặn.
- Dart dùng `CoreBridge` (một stream `updates` dùng chung; ai nghe sau cũng nhận ngay `TripStateUpdateMsg` gần nhất,
  không nhận lại sự kiện cũ; lỗi native → `BridgeException` với `BridgeErrorCode`).
- Android trước T15 chạy **stub có kịch bản** (`StubTripBackend`, snapshot ở `noBackupFilesDir/napstop_stub`, nên
  `currentTrip()` vẫn đọc được sau khi process chết). Chọn kịch bản qua `SimulationMsg.traceAsset`:

  | `traceAsset` (`StubTraces.*`) | Diễn biến (thời gian ảo, chia cho `speedFactor` ra thời gian thật) |
  |---|---|
  | `stub/normal` | có fix sau 5 s, nhắc nhẹ, báo chính (SMART ≈ 738 s → 12,3 s thật ở 60×) |
  | `stub/gps_lost` | mất GPS từ 60 s tới 240 s |
  | `stub/low_battery` | pin 30 % giảm dần, cảnh báo pin ở 30 s (màn 7) |
  | `stub/overshoot` | chạy quá đích, `OvershootMsg` khi đã qua ≥ 1 km |
  | `stub/no_fix` | không bao giờ có fix: `GpsLostMsg(neverAcquired)` ở 120 s, báo `timeout` ở 4 giờ |

  `startTrip` không có `simulation` = `stub/normal` ở 1× (báo sau ~12 phút; `currentTrip().simulation` = null). Stub chỉ
  tick khi Dart đang nghe `updates`.
  Quyền: `PermissionHostApi` trả cố định (thật ở T21), `deviceInfo()` đọc thật; `AlarmHostApi` không phát âm (T16).
- Test: Dart `flutter test test/core/bridge`; Kotlin `cd android && ./gradlew :app:testDevDebugUnitTest`; tích hợp I01
  trên emulator/máy Android (API 26+):

  ```bash
  flutter devices
  flutter test integration_test/bridge_smoke_test.dart -d <device-id>
  ```

- iOS chỉ được kiểm bằng biên dịch: workflow chạy tay
  [`.github/workflows/ios-compile.yml`](../.github/workflows/ios-compile.yml) (`flutter build ios --simulator --debug
  --no-codesign` trên macOS). Chạy khi đổi code Swift.

## Chuỗi hiển thị (ARB, gen-l10n)

- Bản gốc tiếng Việt `lib/l10n/app_vi.arb`, bản dịch `lib/l10n/app_en.arb`. Mỗi khoá cần `@khoá.description` (tiếng
  Anh) và có mặt ở cả hai file (test `test/app/l10n_arb_test.dart`). Tiền tố theo feature (`home…`), dùng chung `common…`.
- `flutter pub get` tự sinh `lib/l10n/gen/` (không commit); sinh tay: `flutter gen-l10n`.
  Dùng: `AppLocalizations.of(context).commonBack`.
- Ngôn ngữ máy khác vi/en → tiếng Việt (`kAppSupportedLocales`, vi đứng đầu).

## Cấu trúc `lib/`

```
lib/
├── main.dart          entrypoint của app
├── main_catalog.dart  entrypoint catalog design system (chỉ dev)
├── app/               NapStopApp, AppFlavor, kAppSupportedLocales
├── core/              dùng chung: platform bridge (Pigeon), logging, utils
│   └── design/        design system: tokens, theme, component Nap*, catalog/
├── l10n/              app_vi.arb (gốc), app_en.arb; gen/ do gen-l10n sinh
└── features/<feature>/{data,domain,presentation}
```

Feature-first theo `docs/architecture/ARCHITECTURE.md` §1. Định nghĩa Pigeon nằm trong `pigeons/`.
