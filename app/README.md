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

# Trip Engine (T12, module :core-trip, Kotlin JVM thuần) + harness fixture fixtures/traces (295 lượt, P05).
./gradlew :core-trip:test                                     # báo cáo: build/core-trip/napstop/summary.md
./gradlew :core-trip:test --tests '*FallbackPlannerTest*'     # một lớp
# Ghi lại fixtures/p05/manifest.json + samples: CHỈ khi cố ý đổi hành vi engine (designer duyệt), ghi lý do vào commit.
./gradlew :core-trip:test --tests '*P05ManifestTest*' -Pnapstop.updateP05=true --rerun
# Xuất mọi transcript P05 (+ .diag.jsonl) ra build/core-trip/napstop/transcripts/ để T13 (Swift) so.
./gradlew :core-trip:test --tests '*TraceSuiteTest*' -Pnapstop.dumpTranscripts=true --rerun

# Trip runtime Android (T15, module :core-runtime, Kotlin JVM thuần): actor, hiệu ứng, khôi phục, trace qua runtime.
./gradlew :core-runtime:test                                  # thống kê L31/L32: build/core-runtime/napstop/
```

## CI

Workflow [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) (GitHub Actions, `ubuntu-24.04`). Chạy khi mở hoặc
cập nhật PR, khi push `main`, và chạy tay ở tab Actions (`workflow_dispatch`). Bỏ qua commit chỉ đổi `docs/**`, `*.md`,
`.claude/**`. Năm job chạy song song:

- Job `dart`: `flutter pub get --enforce-lockfile` · kiểm code Pigeon sinh ra khớp input (T14) · kiểm code drift sinh ra (T22) ·
  `dart format --output=none --set-exit-if-changed lib test integration_test` ·
  `flutter analyze` · `flutter test` (dev) · `flutter test --flavor prod`.
- Job `android`: `flutter build apk --config-only` · `./gradlew :core-trip:test` (Trip Engine T12; tóm tắt TR30/TR36/TR37
  và killSweep vào Summary, artifact `trip-engine-reports`) · `./gradlew :app:testDevDebugUnitTest :app:testProdDebugUnitTest` ·
  `flutter build apk --debug` · `flutter build apk --debug --flavor prod` · kiểm package id của 2 APK
  (`app.napstop.dev`, `app.napstop`) bằng `aapt2`.
- Job `swift` (container `swift:6.4.1-noble`, thư mục `ios/Core`): `swift build` + `swift test` bản release của Trip Engine
  Swift (T13), P05 phải khớp `fixtures/p05/manifest.json`; artifact `swift-report`.
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
| Dart | `lib/core/bridge/core_api.g.dart` | `core_bridge.dart` (`CoreBridge`), `bridge_exception.dart` |
| Android | `android/app/src/main/kotlin/app/napstop/core/bridge/CoreApi.g.kt` | `BridgeRegistrar`, `BridgeGuard`, `TripHostApiImpl`, `TripConfigValidator`, `permission/` (`PermissionHostApi` thật, T21) |
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
- Android: mọi chuyến chạy trên trip runtime của T15 (mục dưới). Từ T18 (mục "Chế độ giả lập"), `simulation` =
  (`traceAsset` = id trace trong `assets/sim/catalog.json`, `SimTraces.*`; `speedFactor` 1..600) chạy **giả lập trên
  runtime thật**; `stub/…`, đường dẫn, id không có → `simulation-unavailable`. Stub T14 (`StubTripBackend`…) chỉ còn
  là test double trong `android/app/src/test`.
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

## Trip runtime Android (T15)

Spec: `docs/specs/T15.md`. Engine (`:core-trip`) chạy trong `TripRuntime` (module `:core-runtime`, JVM thuần, actor một
coroutine), singleton theo process; `:app` chỉ nối cổng với Android:

| Thành phần (`android/app/src/main/kotlin/app/napstop/core/`) | Việc |
|---|---|
| `location/LocationService` | FGS `location` (vỏ: thông báo thường trực + giữ quyền nhận vị trí khi dùng app); chỉ khởi động khi app đang hiển thị (ADR-001) |
| `location/FusedLocationSource` | Fused Location theo `SamplingPolicy` của engine (`FlpMapper`) |
| `trip/host/AndroidAlarmScheduler` | `wakeAtMs` = `setExactAndAllowWhileIdle(ELAPSED_REALTIME_WAKEUP)`; báo dự phòng = `setAlarmClock`, 2 khe A/B (đặt mới trước, huỷ cũ sau) |
| `trip/host/Receivers.kt` | `WakeAlarmReceiver`, `FallbackAlarmReceiver`, `BootReceiver` (`BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`), `RingEventReceiver`, `TripActionReceiver` |
| `trip/host/TripNotifications` | kênh `napstop_tracking` (thường trực, nút "Dừng theo dõi"), `napstop_trip_alerts` (chưa có GPS, gián đoạn…) |
| `alarm/AlarmController` | `AlarmPort` thật (T16, mục dưới) |
| `bridge/RealTripBackend`, `ListenerHub`, `MsgMapper` | Pigeon ↔ runtime (Pigeon không đổi) |

Lưu trữ: `noBackupFilesDir/napstop_trip/` (`active_trip.properties`, `fallback_ledger.properties`,
`ring_config.properties`, `finished/`) — luôn bị loại khỏi Auto Backup và chuyển máy. Chuỗi thông báo ở
`res/values{,-en}/strings.xml`, cùng nội dung khoá ARB (test `NativeStringsParityTest`).

```bash
cd android && ./gradlew :core-runtime:test        # L01–L43 (JVM), trace qua runtime, quét process chết, mô hình Doze
flutter test integration_test/t15_location_service_test.dart -d <device-id>   # LI01–LI03 (xem đầu file: pm grant, geo fix)
```

**Lệnh debug (chỉ bản debug, qua adb; receiver được bảo vệ bằng quyền `DUMP` nên chỉ `adb shell` gửi được):**

```bash
R="-n app.napstop.dev/app.napstop.core.trip.host.DebugCommandReceiver -a app.napstop.action.DEBUG"
adb shell am broadcast $R --es cmd dump                                  # trạng thái runtime ra logcat (tag NapStopDebug)
adb push ../fixtures/traces/coach_md_tb.gpx ../fixtures/traces/coach_md_tb.expect.json   /sdcard/Android/data/app.napstop.dev/files/replay/
adb shell am broadcast $R --es cmd replay --es file coach_md_tb.gpx --es expect coach_md_tb.expect.json   --ef speedScale 1.0 --es mode distance --ei threshold 1000        # app phải đang mở trên màn hình
adb shell am broadcast $R --es cmd force_tier --es value sparse          # sparse|medium|dense|off (LM1)
adb shell am broadcast $R --es cmd gps_drop --es value on                # on|off
adb shell am broadcast $R --es cmd snapshot_fail --es value on           # on|off (LM7)
adb shell am broadcast $R --es cmd ring_fail --es value on               # on|off: ringNow ném (LM7, khe canh chuông)
adb shell am broadcast $R --es cmd slow_read --es value 2500             # ms, giữ qua reboot; 0 = tắt (LM6, F1)
adb shell am broadcast $R --es cmd listener_throw --es value on          # on|off
adb shell am broadcast $R --es cmd fb_test --ei leadS 10 --ei cancelDelayS 0   # LM4, khi không có chuyến
adb shell am broadcast $R --es cmd journal_clear
# Journal đo (không toạ độ): kéo về rồi phân tích
adb exec-out run-as app.napstop.dev cat no_backup/napstop_trip/journal.ndjson > journal.ndjson
cd android && ./gradlew :core-runtime:analyzeJournal -Pjournal=$PWD/../journal.ndjson
```

Giao thức đo trên máy (LM1–LM8): `docs/test-protocols/T15.md`.

## Báo thức Android (T16)

Spec: `docs/specs/T16.md`. Âm, rung, flash và màn báo thức chạy ở **process `:ring`** (`AlarmRingService` FGS
`systemExempted`/`mediaPlayback`, `AlarmActivity` trên màn khoá, `RingCommandReceiver`), tách khỏi Flutter và FGS
`location`: process chính chết vẫn kêu (T10 RK14). Process chính chỉ có `AlarmController` (= `AlarmControllerCore` thuần trong
`:core-runtime` + transport Android + watchdog) và hai thông báo phụ (dự phòng `napstop_alarm_backup`, nhắc nhẹ `napstop_prealert`).
Sổ chuông `noBackupFilesDir/napstop_ring/<tripId>.properties` (khoá `FileLock` chéo process) là nguồn sự thật "đang kêu".
Âm báo: `res/raw/alarm_{horn,bell,beep}.wav`, sinh bằng `python3 ../tools/alarm_sounds/generate.py` (CC0, `docs/third_party/alarm_sounds.md`).

```bash
cd android && ./gradlew :core-runtime:test --tests "app.napstop.core.alarm.*" --tests "*T16*"   # A01–A43, AT1, AT3 (JVM)
cd android && ./gradlew :app:testDevDebugUnitTest                         # AA1–AA5
cd android && ./gradlew :app:connectedDevDebugAndroidTest                 # AI01–AI07 (UI Automator, cần emulator/máy)
```

**Điều kiện máy cho instrumentation (T28.2 #7):** `AlarmUiTest.ai01_showsOverTheLockScreen` cần máy **có màn khoá** (kiểu vuốt
là đủ). Lượt nào đã tắt màn khoá (`locksettings set-disabled true`, vd lượt T27) thì AI01 đỏ "keyguard still locked". Trước khi chạy:

```bash
adb shell locksettings set-disabled false   # bật lại màn khoá vuốt; kiểm: adb shell locksettings get-disabled → false
```

**Lệnh debug (cùng receiver ở trên, chuyến giả `debug-ring` nếu không ghi `--es tripId`):**

```bash
adb shell am broadcast $R --es cmd ring_test --es dismiss swipe --ef volume 0.5 --ez ramp true --es vibration medium --ez snooze true
adb shell am broadcast $R --es cmd ring_test --es source fallback --es dismiss math      # shake|math|swipe; --ez headphones true; --ez flash true
adb shell am broadcast $R --es cmd ring_overshoot --ei pastM 1200
adb shell am broadcast $R --es cmd ring_facts                             # RingFacts ra logcat
adb shell am broadcast $R --es cmd ring_stop
adb shell am broadcast $R --es cmd ring_max_override --ei seconds 30      # 0 = bỏ; áp cho phiên chuông / lần mở app sau
adb shell am broadcast $R --es cmd prealert_test --ez byDistance true
adb shell am broadcast $R --es cmd preview_test --es sound bell --ef volume 0.5 ; adb shell am broadcast $R --es cmd preview_stop
adb exec-out run-as app.napstop.dev cat no_backup/napstop_ring/journal_ring.ndjson     # journal của :ring
adb shell pidof app.napstop.dev:ring                                      # pid process chuông
```

## Màn 5 dự phòng + màn 8 sau khi tắt (T27)

Spec: `docs/specs/T27.md`. Màn báo thức lúc kêu vẫn là `AlarmActivity` native (T16 D8). Flutter có `AlarmUiCoordinator`
(`lib/features/alarm`, gắn ở `MaterialApp.router(builder:)`): đọc launch action `overshootRoute` qua
`AlarmHostApi.consumeLaunchAction` (frame đầu + mỗi lần `resumed`; khe `LaunchActions` sống 10 phút) → `go('/overshoot?trip=…
&past=…&open=1')`; chỉ khi app `resumed` mà chuông kêu ≥ 4 s và `showAlarmScreen` không phủ được thì mới `push('/alarm?trip=…')`
(màn dự phòng, luôn có thanh vuốt). Màn 8 mở Google Maps bằng Maps URL (`url_launcher`), toạ độ đích đọc từ drift.

```bash
flutter test test/features/alarm                                           # U01–U10, W01–W23
cd android && ./gradlew :app:testDevDebugUnitTest --tests "*LaunchActions*" --tests "*AlarmHostApiImpl*"   # K01–K05
# Giả "Xem đường quay lại" (app dev, chuyến <id> có trong lịch sử thì có nút chỉ đường; > 48 h thì không tự mở Maps).
# Bắt buộc napstop.atWallMs (giờ của máy, ≤ 10 phút trước); intent hệ thống trả lại khi dựng lại activity
# (process chết, mở từ Recents) bị bỏ qua:
adb shell am start -n app.napstop.dev/app.napstop.MainActivity --es napstop.launch overshootRoute --es napstop.tripId <id> --ei napstop.pastM 900 --el napstop.atWallMs "$(adb shell date +%s)000"
```

## Chế độ giả lập (T18)

- Trace đóng gói: `assets/sim/<id>.gpx` (bản sao từng byte của `fixtures/traces`, 6 trace gốc T02) + `catalog.json`,
  sinh bằng `cd ../tools/tracegen && dart run bin/tracegen.dart bundle-sim` (danh sách ở `data/sim_bundle.json`);
  `tracegen check` (CI job `tracegen`) bắt lệch. Đổi fixture trong danh sách → chạy lại `bundle-sim`, commit cả hai.
- Dart: `SimTraces` (id), `SimTraceCatalog` (`lib/features/simulation`). Native (`:core-runtime`): đồng hồ chuyến có hệ
  số tốc độ (`TripClock.rebase`), `SimulatedLocationSource` (SAX `TraceGpx`), hẹn giờ trong process
  (`SimAlarmScheduler` qua `RoutingAlarmScheduler`): **không đặt báo của OS**; về 1× từ lần báo đầu; không pin thật.
  Bắt đầu như chuyến thật (cần quyền vị trí, app hiển thị, FGS `location`); process chết → lần nạp sau kết thúc chuyến
  (STOP_TRIP, có trong `pendingFinishedTrips`), không kêu.
- Wakelock `napstop:sim` (trần 110 phút) giữ CPU khi tắt màn hình. Doze bỏ qua wakelock: demo dài nên cắm sạc hoặc để
  màn hình sáng (T18 R1).
- Tích hợp (emulator API 34+, đã `adb shell pm grant app.napstop.dev android.permission.ACCESS_FINE_LOCATION`,
  `adb shell svc power stayon true`): `flutter test integration_test/t18_simulation_test.dart -d <id>` (SI01 tàu
  HN → Đồng Hới 60× ≈ 9,5 phút).

## Khung app (T22)

- Router `lib/app/router/` (go_router 17, **không** 18: bản 18 chuyển sang `material_ui`). Path là hợp đồng, task sau
  không đổi path; chi tiết `docs/specs/T22.md` §3.1.

  | Màn | Path | Navigator |
  |---|---|---|
  | 1 Trang chủ / 11 Lịch sử / 12 Cài đặt | `/home`, `/trips`, `/settings` | shell 3 tab (`StatefulShellRoute`) |
  | 0, 9 | `/onboarding`, `/battery-guide` | root |
  | 2 | `/destination` (`?mode=pick`: trả `TripDestination` khi pop) | root |
  | 3 | `/alarm-settings` (`extra: TripDraft` bắt buộc, thiếu thì về `/home`) | root |
  | 4, 5, 8 | `/tracking`, `/alarm`, `/overshoot` | root |

  Điều hướng qua extension `AppNavigation` (`context.openAlarmSettings(draft)`, `pickDestination()`…). Màn chưa làm dùng
  `PlaceholderScreen`; task làm màn đó thay builder của route.
- Lần chạy đầu (T21): `main()` đọc cờ `onboarding.completedVersion` (`startupLocation`, tối đa 500 ms; chậm hơn thì coi như
  chưa xong) rồi đặt `initialLocation` = `/onboarding` hoặc `/home` qua `startupLocationProvider`. Màn 9 đọc hướng dẫn theo
  hãng từ `assets/battery_guides.json` (cấu trúc + khoá ARB `bg*`; thêm/sửa hãng chỉ sửa JSON + ARB, `docs/specs/T21.md` §6.3).
- Riverpod 3, provider viết tay; `ProviderScope(retry: (_, _) => null)` trong `main.dart` (tắt tự thử lại).
  Provider lõi: `coreBridgeProvider`, `appDatabaseProvider`, `tripsRepositoryProvider`, `savedPlacesRepositoryProvider`,
  `activeTripProvider`, `deviceInfoProvider`, `clockProvider`, `appRouterProvider`, `destinationPickerProvider`.
- Kiểu dùng chung `lib/core/trip/domain/` (`TripDestination`, `TripDraft`, `TripAlarmChoice`, `TripRecord`, `SavedPlace`);
  `checkStart` ở `lib/features/onboarding/domain/start_check.dart` (T19 §1.3).
- Test: `test/helpers/fake_core_bridge.dart` (`FakeCoreBridge` + builder `androidPermissions()`, `deviceStatusMsg()`,
  `activeTrip()`…), `test/helpers/app_harness.dart` (`pumpAppHarness(tester, {overrides, initialLocation, theme,
  textScale, locale, size, fontFamily, seed, batteryGuides…})`: cả app với fake bridge, DB bộ nhớ, giờ cố định 19:30,
  hướng dẫn pin parse sẵn),
  `test/helpers/trip_fixtures.dart` (đích, bản ghi mẫu, `seedData`).

## drift (cơ sở dữ liệu, T22)

```bash
dart run build_runner build      # sinh lib/core/db/app_database.g.dart (COMMIT)
dart run drift_dev make-migrations   # sau khi đổi schema: ảnh chụp drift_schemas/ + steps + test migration
```

- Sau khi sửa `lib/core/db/`, chạy `build_runner` và commit file sinh ra; kiểm `git diff -- lib/core/db drift_schemas`
  sạch. Job `dart` của CI chạy lại `build_runner` và báo lỗi nếu code sinh bị lệch (bước "Check drift output is up to date").
- Schema v1: bảng `trips`, `saved_places` (`lib/core/db/tables.dart`). Thời gian là epoch ms UTC (`INTEGER`). Enum lưu
  bằng chuỗi wire cố định (`converters.dart`): chỉ thêm, không bao giờ đổi.
- Đổi schema: sửa bảng, tăng `schemaVersion`, chạy `make-migrations`, viết `onUpgrade: stepByStep(...)`, commit ảnh chụp
  + steps + test. Không viết migration tay.
- File DB: `<getApplicationSupportDirectory()>/napstop_db/napstop.sqlite` (Android: `files/napstop_db/`). Thư mục này bị
  loại khỏi Auto Backup và chuyển máy (`res/xml/data_extraction_rules.xml`, `res/xml/backup_rules.xml`): lịch sử chứa
  toạ độ, vị trí không rời máy. iOS: T17 đặt `isExcludedFromBackup`.
- Chỉ `lib/core/db` và `lib/core/trip/data` dùng lớp hàng sinh ra (`TripRow`, `SavedPlaceRow`): `toString()` của chúng in
  toạ độ. Không log.
- SQLite do `package:sqlite3` đóng gói qua build hook: lần build/test đầu tải binary từ GitHub release (cần mạng, có kiểm
  sha256), sau đó dùng cache trong `.dart_tool/`.

## Bản đồ & Places (T23)

API key Google Maps Platform **không bao giờ vào git** (`.gitignore` có `secrets.properties`, `Secrets.xcconfig`).
Không có key thì app vẫn build và chạy: màn 2 hiện ô thay bản đồ, chế độ "Địa chỉ" báo "Bản này chưa bật tìm địa chỉ."
CI không cần secret.

- **Android:** chép `android/secrets.properties.example` thành `android/secrets.properties`, điền
  `MAPS_API_KEY_DEV` (flavor dev, `app.napstop.dev`) và `MAPS_API_KEY_PROD` (flavor prod, `app.napstop`). Hoặc đặt biến
  môi trường `NAPSTOP_MAPS_API_KEY_DEV` / `NAPSTOP_MAPS_API_KEY_PROD`. Thiếu cả hai → `DEFAULT_API_KEY` (native coi là
  không có key). Key hạn chế theo package + SHA-1: thêm SHA-1 debug keystore của máy mình vào key
  (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`).
- **iOS:** chép `ios/Flutter/Secrets.xcconfig.example` thành `ios/Flutter/Secrets.xcconfig`, điền `MAPS_API_KEY = …`
  (key iOS, bundle `app.napstop`). `Info.plist` → `GMSApiKey`; `AppDelegate` gọi `GMSServices.provideAPIKey`.
- Một key mỗi nền tảng cho cả Maps SDK lẫn Places API (New); Dart đọc key và định danh app qua
  `PermissionHostApi.mapsConfig()`. Places chỉ gọi khi người dùng chọn "Địa chỉ" (REST, `http`); test dùng `MockClient`,
  không bao giờ gọi Google thật.

```bash
# Hook đo hiệu năng tìm kiếm (TC37 của T24 = TI01 của T23), máy thật, bản profile:
flutter drive --profile --driver=test_driver/integration_test.dart   --target=integration_test/station_search_perf_test.dart -d <serial>
# Kết quả: build/integration_response_data.json (loadMs, p50Ms, p95Ms, maxMs)

# Luồng màn 1 → 2 → 3 (TI02), emulator hoặc máy, không cần key:
flutter test integration_test/destination_flow_test.dart -d <device-id>
```

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
├── app/               NapStopApp, AppFlavor, kAppSupportedLocales, clockProvider
│   └── router/        go_router: route, shell 3 tab, màn giữ chỗ (T22)
├── core/              dùng chung: platform bridge (Pigeon), logging, utils
│   ├── db/            drift: bảng, converter, AppDatabase (T22)
│   ├── trip/          kiểu chuyến dùng chung, repository, activeTripProvider (T22)
│   └── design/        design system: tokens, theme, component Nap*, catalog/
├── l10n/              app_vi.arb (gốc), app_en.arb; gen/ do gen-l10n sinh
└── features/<feature>/{data,domain,presentation}
```

Feature-first theo `docs/architecture/ARCHITECTURE.md` §1. Định nghĩa Pigeon nằm trong `pigeons/`.
