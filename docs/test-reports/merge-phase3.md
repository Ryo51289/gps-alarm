# Test report merge-phase3 (T26 + T27 + T28 trên `main`) — Lần 1

Kết luận: **FAIL**. Bộ integration trên `main` đang đỏ: T26 I03/I04 và T28 I01 hỏng sau khi gộp nhánh. Nguyên nhân nằm ở test, app vẫn chạy
đúng. Probe tạm thời (đã xoá) cho thấy app cho kết quả đúng ở cả ba ca. Không tìm thấy tình huống nào do T26–T28 gây ra khiến app không
đánh thức người dùng. Thấy một lỗi app mức minor (#3, T28). Các lỗi #5–#7 có từ trước phase 3 hoặc do môi trường.

Môi trường: Windows 11 Home (Git Bash), Flutter 3.47.8 (`D:\src\flutter`, `--no-pub`, `FLUTTER_ALREADY_LOCKED=true`), JDK MS OpenJDK 17.0.17.
Emulator AVD `napstop_api34` (Android 14 / API 34, `google_apis` x86_64, chạy headless từ lượt T27, máy để `en-US`, có Google Maps + Chrome).
Commit `8816590` (`main`, sạch). Ngày 2026-11-05. Không sửa code production, không commit. Log ở `app/build/merge3/*.log` (không commit).
Ảnh smoke lưu ở `docs/test-reports/merge-phase3/`.

Cách chạy integration: mỗi file chạy riêng, trước mỗi lượt đều gỡ app, cài APK dev thường, `pm grant` 3 quyền, `svc power stayon true`,
`wm dismiss-keyguard`. `flutter test` tự gỡ app sau mỗi file, nên mỗi file bắt đầu từ trạng thái sạch. Bỏ qua thư mục `manual/`.

## Lệnh đã chạy (đủ, không cờ quick)

| Lệnh (trong `app/`) | Kết quả |
|---|---|
| `flutter analyze --no-pub` | No issues found |
| `flutter test --no-pub --dart-define=NAPSTOP_EXPECT_FLAVOR=dev` | **`+2383 ~4` All tests passed** (1:20). Bỏ qua 4 ca: `manifest_t29` (không có build output của biến thể), TW24 (xem O3) và 2 ca có điều kiện |
| `cd android && ./gradlew :app:testDevDebugUnitTest :app:testProdDebugUnitTest` | BUILD SUCCESSFUL, test chạy thật (XML 15:36/15:37): **222/222 mỗi flavor**, 0 fail |
| `flutter test integration_test/<file> -d emulator-5554` × 13 file | Xem bảng "Integration" |
| `./gradlew :app:connectedDevDebugAndroidTest` | lượt 1: 10/11 (`ai01` đỏ, do màn khoá đang tắt: lỗi #7, môi trường). Bật màn khoá vuốt rồi chạy lượt 2: **11/11 PASS**. `ai03` xanh cả hai lượt |
| `:core-trip:test`, `:core-runtime:test` | Không chạy: T26–T28 không chạm hai module này (`git diff 8a82465 --stat`) |

## Kết quả

### Integration (`app/integration_test/*.dart`, emulator)

| File / ca | Task | Kết quả | Ghi chú |
|---|---|---|---|
| `t26_tracking_test.dart` I01 (tàu 600×), I02 (hầm 60×) | T26 | **PASS** | |
| `t26_tracking_test.dart` I03 (quá trạm 600×), I04 (dừng 60×) | T26 | **FAIL** (lỗi #1, do test) | Phần màn 4 đều qua: "Đã qua điểm đến" hiện, sheet dừng chạy đúng, có về Trang chủ. Chỉ hỏng ở `pendingFinishedTrips().singleWhere(...)`. Probe đọc `TripEndedMsg`: I03 `missed/dismissed`, I04 `cancelled/userStop` → **PASS** |
| `t27_alarm_flow_test.dart` IT1, IT2 | T27 | **PASS** (+2, 16:28) | Chờ bằng future thuần, không `pump` khi `AlarmActivity` phủ app |
| `t28_history_settings_test.dart` I01 | T28 | **FAIL** (lỗi #2, do test) | Lần đầu chạy trên emulator (T28 chưa chạy). Probe sửa 2 chỗ trong test → **PASS** (0:51): `AlarmMsg(DISTANCE)` trong cửa sổ, màn 11 có "Woke up on time" + "Simulated", không nút đặt lại, `pending` rỗng |
| `t28_history_settings_test.dart` I03 | T28 | PASS khi chạy riêng, máy để vi (`--plain-name I03`, app locale `vi-VN`). FAIL khi chạy cả file | Chạy sau I01 thì đỏ vì lỗi để lại từ I01 (#3, #4). Ở `en-US` đỏ vì test tìm chuỗi tiếng Việt (giao thức T28 §A yêu cầu máy để Tiếng Việt) |
| `t18_simulation_test.dart` SI01 (tàu 60×), SI03 | T18 | PASS | |
| `t18_simulation_test.dart` SI02 (buýt 600×) | T18 | **FAIL** (lỗi #6, có từ trước) | `Alarm(GPS_LOST)` thay vì `DISTANCE` |
| `bridge_smoke_test.dart` I01 (buýt 600×) | T14/T18 | **FAIL 5/6 lượt** (lỗi #6, có từ trước) | Base `8a82465` (trước T26–T28): **FAIL 3/3**, cùng lỗi |
| `bridge_scenarios_test.dart` | T14 | PASS (6:02) | |
| `bridge_t14_1_test.dart` | T14.1 | PASS | |
| `t15_location_service_test.dart` LI01–LI04 | T15 | PASS +4 | `adb emu geo fix 107.1003 16.8163`, `--dart-define=T15_LAT/LNG` |
| `permissions_t21_test.dart` I01–I03 | T21 | **PASS +3** | Có script host trả lời các dòng `T21> STEP/OPENED/STARTED`. I02: 6 trang đúng `topResumedActivity`. I03: `FIRED lateMs=7 screenOn=false exact=true` |
| `alarm_settings_start_test.dart` I01, I02 | T25 | FAIL (lỗi #5, có từ trước) | Lượt cài mới mở màn 0. Qua màn 0 trước khi chạy: I02 PASS, I01 vẫn FAIL vì chờ `find.text('Đang theo dõi')`, mà từ T26 màn 4 hiện "ĐANG THEO DÕI". Probe đổi finder → I01 PASS |
| `destination_flow_test.dart` TI02 | T23 | FAIL (lỗi #5, có từ trước) | Dừng ở màn 0 (`merge-phase3/ti02_fail.png`). Qua màn 0 trước → PASS (+1) |
| `telemetry_payload_test.dart` TC28 | T29 | PASS | `--flavor dev --dart-define=NAPSTOP_TELEMETRY=on` |
| `station_search_perf_test.dart` TI01 | T23 | PASS | Chạy debug trên emulator, không phải profile trên máy thật nên số đo không dùng được |

### Instrumentation (`connectedDevDebugAndroidTest`)

| Suite | Kết quả |
|---|---|
| `T27RouteBackTest` (AI-T27-1, AI-T27-1b, AI-T27-2) | 3/3 PASS (cả 2 lượt) |
| `AlarmUiTest` (T16 AI01–AI08) | lượt 1: 7/8 (`ai01_showsOverTheLockScreen`: "keyguard still locked", vì `locksettings get-disabled` = `true` do lượt T27 để lại); lượt 2, màn khoá vuốt: 8/8. `ai03_mathWrongThenRight` xanh cả 2 lượt, không cần chạy lại riêng |

### Smoke thủ công (adb + uiautomator; bật tạm dịch vụ a11y "Accessibility Menu" để đọc cây Flutter, đã tắt khi xong)

| # | Luồng | Kết quả | Bằng chứng |
|---|---|---|---|
| a | Mở app khi có chuyến giả lập đang chạy → màn 4 | **PASS** | Màn 12 → giữ logo 3,6 s → "Xe khách Mỹ Đình → Thái Bình" 60× → màn 3 Khoảng cách → Bắt đầu → màn 4. Home, mở lại từ launcher: màn 4 đúng chuyến ("Chuyến giả lập · tốc độ 60×", "Còn 76,5 km") (`smoke_a_screen4.png`). Thêm: Back về Trang chủ, `run-as … kill -9` process chính, mở lại: chuyến giả lập đã đóng, màn 11 có "Đã dừng · Giả lập". Đúng T18 D9 |
| b | Chuyến giả lập báo → `AlarmActivity` kêu → vuốt tắt → về đúng màn | **PASS** | App ở màn 4 → 18:02:27 `AlarmActivity` topResumed ("SẮP TỚI NƠI", "Còn khoảng 990 m…", `smoke_b_alarm.png`) → vuốt hết thanh → `MainActivity` Trang chủ, 0 ServiceRecord. Lượt lặp ở en (BRT01): ảnh chụp 1 s sau khi vuốt thấy SnackBar "Alarm off. Have a safe stop." (`smoke_b3_after.png`). Lượt vi đầu tiên chụp muộn (~6 s), SnackBar đã tắt. Tắt khi đang ở màn 12: app ở nguyên màn 12 |
| c | Quá trạm → "Xem đường quay lại" → màn 8 → Maps mở 1 lần | **PASS** | `ring_max_override 600` (như MT1 của T27, tránh O1). `coach_gb_phuly_overshoot` 60×, 1 km: báo 18:04:40, màn quá trạm 18:09:31 ("ĐÃ QUA ĐIỂM ĐẾN", "Đã qua 1 km", `smoke_c_overshoot.png`). Bấm nút → Maps `MapsActivity` topResumed, `START u0` của Maps/Chrome = **1** (đếm lại sau 6 s: vẫn 1). Back → màn 8 "Bến xe Trung tâm Phủ Lý", "Đã qua 1 km", 2 dòng ✓, ghi chú giả lập, "Chỉ đường quay lại", "Về trang chủ" (`smoke_c_screen8.png`). 1 ActivityRecord `MainActivity`, 0 ServiceRecord, không còn thông báo `napstop_tracking` |
| d | Lịch sử (màn 11) ghi đúng kết quả | **PASS** | "Bến xe Trung tâm Phủ Lý · Lỡ trạm · Giả lập", "Bến xe khách Trung tâm Thái Bình · Tỉnh đúng lúc · Giả lập", "… · Đã dừng · Giả lập" (chuyến bị kill). Thẻ tháng "0 chuyến" vì không tính chuyến giả lập (`smoke_d_history2.png`). "Chuyến gần đây" ở Trang chủ không có chuyến giả lập, đúng query `simulated = false` |
| e | Màn 12 đổi sang English → thông báo thường trực đổi theo | **PASS** | Chuyến đang chạy, app tiếng Việt: thông báo "Chuyến giả lập tới …", "Còn 84 km · khoảng 202 phút". Bấm English → trong ≤ 2 s đổi thành "Simulated trip to …", "49.2 km to go · about 52 min" (dấu chấm thập phân của en). Tên kênh: `napstop_tracking` = "Trip tracking". Màn báo thức tiếp theo ra tiếng Anh ("ALMOST THERE", "Stop alarm", "Snooze 1 min") |

## Tiêu chí chấp nhận (kiểm hồi quy sau gộp)

| Tiêu chí | Đạt? | Bằng chứng (test/log) |
|---|---|---|
| analyze sạch | Đạt | `flutter analyze` |
| `flutter test` (dev) xanh | Đạt | `+2383 ~4` |
| Gradle unit dev + prod xanh | Đạt | 222/222 × 2 |
| Integration T26 I01–I04, T28 I01/I03, T27 IT1/IT2 xanh | **Không đạt** | T27 2/2. T26 2/4 (I03/I04 đỏ do #1). T28 I01 đỏ (#2), I03 chỉ xanh khi chạy riêng ở vi (#3, #4) |
| Các integration khác không thoái lui do gộp | Đạt (không có thoái lui mới) | Mọi file đỏ đều đỏ vì lý do có từ trước. #6 đã đối chứng trên base `8a82465` (3/3 đỏ). #5 do màn 0 (T21) và finder cũ (T26) |
| Instrumentation AI-T27, AlarmUiTest/T16 | Đạt | 11/11 (lượt 2, màn khoá vuốt) |
| Smoke 5 luồng | Đạt | a–e ở trên |
| Không lỡ đánh thức | Đạt | Mọi chuyến giả lập 60× đều kêu (smoke ×4, IT ×6). Ở 600× có khi kêu `GPS_LOST` thay vì `DISTANCE` (#6): vẫn đánh thức, chỉ sớm hơn và sai lý do |

## Lỗi phát hiện

| # | Mức | Mô tả | Repro (lệnh/trace/bước) | Kỳ vọng vs Thực tế |
|---|---|---|---|---|
| 1 | major (test, **hỏng khi gộp T26 × T28**) | Từ T28, `HistorySync` của app tự đọc `pendingFinishedTrips` khi có `TripEndedMsg`, ghi vào drift rồi **ack**. T26 I03/I04 vẫn đọc hàng đợi native sau khi về Trang chủ, nhưng lúc đó hàng đợi đã rỗng | `flutter test integration_test/t26_tracking_test.dart -d emulator-5554` (đã cài APK + cấp quyền trước) → I03, I04 `Bad state: No element` ở dòng 157 / 183 (`pending.singleWhere`) | Kỳ vọng xanh. Thực tế đỏ, dù app đúng: probe nghe `TripEndedMsg` thấy `missed/dismissed` và `cancelled/userStop`. Đề xuất sửa test: lấy kết quả từ `TripEndedMsg` (đăng ký trên bridge của app, như T27), hoặc đọc dòng `trips` qua `tripsRepositoryProvider`. **Task gốc: T26 (test), do T28 đổi hợp đồng hàng đợi** |
| 2 | major (test, T28) | T28 I01 chưa từng chạy trên máy, có 2 lỗi. (a) `find.text('English')` không thấy vì mục Ngôn ngữ nằm dưới màn hình 12 (list lazy, chưa dựng), cần `scrollUntilVisible`. (b) Test nghe `CoreBridge().updates` bằng một instance riêng. App tạo `CoreBridge` thứ hai cũng đăng ký event channel `tripUpdates`. Phía native chỉ giữ một sink, nên stream của test không nhận gì (`no AlarmMsg within 0:02:00`). Lúc huỷ còn sinh `PlatformException(No active stream to cancel)` | `APP_LOCALE=vi-VN`, `flutter test integration_test/t28_history_settings_test.dart --plain-name I01` → `Bad state: No element` ở `_tap` dòng 83. Chỉ thêm scroll → `TimeoutException: no AlarmMsg within 0:02:00` (dòng 95) | Kỳ vọng xanh. Probe sửa (a) và (b) (nghe `container.read(coreBridgeProvider).updates` sau `_pumpApp`) → **PASS 0:51**, mọi assert của spec đạt. **Task gốc: T28** |
| 3 | minor (app, T28) | `historySyncProvider` truyền closure `ref.read(telemetryProvider)` và `ref.read(clockProvider)` (`history_sync.dart:148–149`). `_runOnce` gọi chúng sau `await` (dòng 110 `_nowMs()`, dòng 121 `_telemetry()`). Nếu provider bị huỷ khi một lượt sync còn chạy, sẽ ném `UnmountedRefException`. Lỗi nằm ngoài mọi `try` nên thành lỗi async không bắt, và lượt đó bỏ bước đánh dấu dòng mồ côi | Thấy ở 3 lượt IT: `t26probe` (I03), `t28`, `t28b` (I01): "UnmountedRefException … Provider<HistorySync> … thrown after the test had completed". Stack `history_sync.dart:149:22 ← _runOnce:110` và `148:26 ← _runOnce:121` | Kỳ vọng: huỷ container giữa lượt sync thì dừng êm. Thực tế: ném lỗi. Trên máy, chỉ xảy ra khi `ProviderContainer` bị huỷ (app đóng, engine Flutter bị gỡ) hoặc khi `coreBridgeProvider`/`tripsRepositoryProvider` dựng lại. Không ảnh hưởng báo thức. Đề xuất: đọc `now`/telemetry trước `await` đầu tiên, hoặc kiểm `ref.mounted` / `ref.onDispose` → cờ huỷ. **Task gốc: T28** |
| 4 | minor (test, T28) | T28 I03 tìm chuỗi tiếng Việt "Không rõ kết quả" mà không ép locale (T25/T26 có ép `vi`). Chạy sau I01 trong cùng file thì đỏ vì lỗi #3 và `PlatformException` do I01 để lại | Máy `en-US`: `flutter test … t28_history_settings_test.dart` → I03 `not found: "Không rõ kết quả"`. Đặt app locale `vi-VN`, chạy cả file → I03 đỏ ở giây thứ 6 (`PlatformException … tripUpdates`). Chạy riêng `--plain-name I03` → PASS | Đề xuất: ép `localesTestValue = vi` như T26, sửa #2(b) để không có stream thừa. **Task gốc: T28** |
| 5 | minor (test, có từ trước phase 3) | `alarm_settings_start_test.dart` (T25) và `destination_flow_test.dart` (T23) chạy `app.main()` rồi chờ Trang chủ, nhưng không qua màn 0 (`markOnboardingCompleted`). Lượt cài mới nào cũng đỏ ở bước đầu. Riêng T25 I01 còn chờ `find.text('Đang theo dõi')`, mà từ T26 màn 4 viết hoa thành "ĐANG THEO DÕI" (`NapSectionHeader.toUpperCase`), chuỗi thường chỉ còn ở khung loading | `flutter test integration_test/destination_flow_test.dart -d emulator-5554` → `Found 0 widgets with text "Tìm ga, bến xe, địa chỉ…"`, ảnh `merge-phase3/ti02_fail.png` (màn 0). T25: `HomeScreen` không thấy. Qua màn 0 bằng tay: TI02 PASS, T25 I02 PASS, I01 đỏ ở `'Đang theo dõi'`. Probe đổi sang `'ĐANG THEO DÕI'` → PASS | Đề xuất: thêm `markOnboardingCompleted` (như T26/T27), đổi finder T25 I01 sang `find.byType(TrackingScreen)`. **Task gốc: T21 (màn 0, lộ ra từ T21) + T26 (finder)**. Không do T26–T28 gây đỏ ở bước đầu |
| 6 | minor (giả lập 600×, có từ trước, không do gộp) | Chuyến buýt `bus_hn_brt01` ở **600×** hay kêu `Alarm(GPS_LOST)` thay vì `DISTANCE`: khoảng 1 740 s ảo (~2,9 s thật sau khi bắt đầu), ETA < `gpsLostAlarmEtaS`. `gpsLostMinS = 60` s ảo, ở 600× chỉ còn 100 ms thật. Bộ phát mẫu và engine chạy chung `actorDispatcher` một luồng (`RuntimeHost.kt:87`), nên chỉ cần trễ > 100 ms là engine thấy mất GPS. Người dùng vẫn được đánh thức (sớm hơn, sai lý do). Giao diện chỉ cho 1/10/60× | `flutter test integration_test/bridge_smoke_test.dart -d emulator-5554` → `Expected: distance, Actual: gpsLost`, **5/6 lượt** trên `main`, **3/3 lượt** trên worktree tạm ở `8a82465` (trước T26–T28, đã gỡ). Cũng gặp ở `t18_simulation_test.dart` SI02. T26 I01/I03 (600×) qua | Kỳ vọng (T18 SM19: dãy sự kiện giống nhau ở 1/60/600×): `DISTANCE`. Thực tế trên emulator: `GPS_LOST`. JVM SM19 vẫn xanh vì đồng hồ ảo tất định. Đề xuất: test IT dùng 60× cho các assert lý do báo, hoặc nới thời gian chờ GPS ở chế độ giả lập theo tốc độ phát. **Task gốc: T18** (không thuộc T26–T28). Có thể do emulator chạy liên tục nhiều giờ nên chậm hơn lúc T18 chạy |
| 7 | — (môi trường) | `AlarmUiTest.ai01_showsOverTheLockScreen` cần có màn khoá. Lượt T27 để lại `locksettings set-disabled true` | `./gradlew :app:connectedDevDebugAndroidTest` khi `locksettings get-disabled` = `true` → "keyguard still locked" (AlarmUiTest.kt:107) | `set-disabled false` → 11/11. Không phải lỗi code. Nên ghi điều kiện này vào giao thức T16 |

### Quan sát (không chặn)

| # | Mô tả |
|---|---|
| O1 | Màn 4 của chuyến giả lập hiện thời lượng theo giờ ảo ("~3 giờ 12 phút", "Dự kiến báo sau ~3 giờ 9 phút") dù chuyến chỉ kéo dài ~2 phút thật. Thông báo cũng vậy ("khoảng 188 phút"). Có vẻ đúng T18 D14 (đồng hồ ảo), nhưng khi demo dễ gây hiểu lầm. Sheet giả lập lại ghi giờ thật ("tới nơi sau khoảng 2 phút 2 giây") |
| O2 | O1 của T27 (chuông quá trạm chỉ còn vài giây khi quá trạm rơi vào cuối 5 phút) vẫn còn: smoke c quá trạm ở giây 291 sau lần kêu đầu, phải dùng `ring_max_override 600` mới bấm kịp |
| O3 | `destination_screen_test.dart:624` TW24 vẫn `skip: true` với lý do "T29 is not merged yet", nhưng T29 đã gộp. Skip cũ (nit) |
| O4 | Hai `CoreBridge` cùng lúc thì một bên mất stream `tripUpdates` (#2b). App chỉ có một instance qua provider, nhưng test hay probe nào tự `CoreBridge()` sau khi app chạy sẽ làm app mất cập nhật. Nên ghi vào doc của `CoreBridge` |

## Phần chưa chạy được & lý do

- **Máy thật Android**, TalkBack, iOS (`ios-compile.yml`): ngoài phạm vi lượt gộp này, chờ thiết bị / Mac (như T26–T28).
- **T28 §B (I02/M02) đủ các bước B3–B9**: chỉ kiểm phần cốt lõi ở smoke e (tiêu đề và nội dung thông báo, tên kênh `napstop_tracking`). Chưa kiểm
  đổi ngôn ngữ liên tục (B6), khởi động lạnh khi đang English (B7), "Theo ngôn ngữ máy" xoá file (B8), StrictMode (B9).
- **`station_search_perf_test`**: chỉ chạy debug trên emulator. Số đo hiệu năng cần chạy profile trên máy thật.
- **A3 của giao thức T28 ("xanh qua 2 lần chạy")**: chưa đạt vì #1, #2. Chạy lại sau khi sửa test.
- Không chạy `flutter test --flavor prod` (không được yêu cầu).

## Trạng thái emulator để lại

`napstop_api34` (`emulator-5554`) vẫn chạy headless. App `app.napstop.dev` bản dev debug thường (build từ `8816590`) đang cài, đã qua màn 0, có
4 dòng lịch sử giả lập. Ngôn ngữ app đã trả về "Use phone language". `ring_max_override` = 0. Không có chuyến hay FGS nào chạy. Dịch vụ a11y đã
tắt. `svc power stayon true`. Màn khoá đã trả về **tắt** (`locksettings set-disabled true`, như lượt T27 để lại; AI01 cần bật lại, xem #7).
Vị trí giả của emulator: `geo fix 107.1003 16.8163` (T15). Worktree tạm `D:\work\m3base` (base `8a82465`, dùng đối chứng #6) đã gỡ
(`git worktree remove`). Không kill tiến trình Python nào. Không còn file probe trong `integration_test/`, `git status` sạch (trừ báo cáo này và
thư mục ảnh).

Đề xuất trạng thái: mở task sửa test cho #1 (T26), #2/#4 (T28), #5 (T23/T25); #3 là lỗi app nhỏ của T28 (follow-up, có thể gộp vào T28.1);
#6 giao cho T18 (hoặc ghi chú giới hạn 600×). Sau khi sửa: chạy lại `t26_tracking_test.dart` và `t28_history_settings_test.dart` 2 lần.
