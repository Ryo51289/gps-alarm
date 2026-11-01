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

- Job `dart`: `flutter pub get --enforce-lockfile` · `dart format --output=none --set-exit-if-changed lib test` ·
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
