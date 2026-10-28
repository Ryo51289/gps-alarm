# NapStop app

Flutter app của NapStop (báo thức theo vị trí). Tổng quan dự án, quy trình và quy ước code: xem
[`../CLAUDE.md`](../CLAUDE.md).

## Yêu cầu

- Flutter **3.47.x stable** (Dart 3.13), đặt ở `D:\src\flutter`; `PUB_CACHE=D:\src\pub-cache` (cùng ổ với repo).
- Android SDK với platform **36** (`ANDROID_HOME`), license đã chấp nhận.
- `JAVA_HOME` trỏ tới JDK 17+ (JBR của Android Studio), cần cho `./gradlew`.
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

## Flavor

| Flavor | Android application id | Tên app | Ghi chú |
|---|---|---|---|
| `dev` (mặc định) | `app.napstop.dev` | NapStop Dev | `default-flavor: dev` trong `pubspec.yaml` |
| `prod` | `app.napstop` | NapStop | |

Dart đọc flavor qua `AppFlavor.current` (`lib/app/flavor.dart`, dựa trên `appFlavor`).
iOS flavor: chưa có (cần Mac). Phải tạo scheme `dev`/`prod` trước khi `flutter run` trên iOS.

## Cấu trúc `lib/`

```
lib/
├── main.dart          entrypoint duy nhất
├── app/               NapStopApp, AppFlavor
├── core/              dùng chung: platform bridge (Pigeon), logging, utils
└── features/<feature>/{data,domain,presentation}
```

Feature-first theo `docs/architecture/ARCHITECTURE.md` §1. Định nghĩa Pigeon nằm trong `pigeons/`.
