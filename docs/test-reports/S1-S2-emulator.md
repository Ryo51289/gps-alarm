# Test report S1-S2 (emulator smoke test của app thí nghiệm) — Lần 1

Kết luận: **FAIL** — mọi mục tiêu được giao (M00, S2-1, M-WD, R2-1/R2-2) chạy được và cho đúng verdict. Nhưng tìm thấy 3 lỗi
của probe (#2, #3, #4) làm **sai số liệu thu trên máy thật** trong một số trình tự thao tác, và 1 phát hiện lớn về đường báo thức
(#1). Đề xuất sửa #2, #3 và chốt #4 (spec) trước khi giao người dùng. Phần cần máy thật xem mục cuối.

Môi trường:
- Windows 11 Home 10.0.26200, Git Bash. Android SDK `D:\work\android-sdk`, emulator WHPX, headless (`-no-window -no-audio -no-snapshot`).
- AVD riêng **`napstop_api34`** (tạo bằng `cmdline-tools/latest/bin/avdmanager.bat`, `system-images;android-34;google_apis;x86_64`,
  device `pixel_6`, port 5580 → serial `emulator-5580`). Android 14 (SDK 34), bản `UE1A.230829.050`, GMS OK. Không dùng/không sửa
  `amomi_api34`.
- APK: `spikes/android-probe/app/build/outputs/apk/debug/app-debug.apk` (commit f188301, 3 440 971 byte, không build lại; `find app/src -newer`
  rỗng → APK khớp mã nguồn).
- Vị trí: luồng giả `adb emu geo fix` mỗi 3 s quanh toạ độ tổng hợp (10.000°, 10.000°), không phải địa điểm thật.
- Khoá màn hình: AVD mặc định tắt khoá màn hình; đã bật lại khoá dạng vuốt (`locksettings set-disabled false`) để `isKeyguardLocked = true`.
- Không có loa: xác minh "kêu" bằng `dumpsys audio` (player `USAGE_ALARM` `state:started`, audio focus `GAIN_TRANSIENT`),
  `dumpsys vibrator_manager` (`Usage=ALARM`, `status: running`), `dumpsys power` (`mWakefulness`), `dumpsys window`
  (`isKeyguardShowing`, `mCurrentFocus`), `dumpsys notification`, log SystemUI (`dumpsys activity service com.android.systemui`).

## Kết quả

21 lượt, log ở `spikes/results/emulator/runs/` (đã grep: không có khoá `lat/lng/lon/latitude/longitude/alt`, không có giá trị
toạ độ đã bơm). Unit test probe: `./gradlew --init-script <scratchpad>/central-mirror.init.gradle :app:testDebugUnitTest --rerun-tasks`
→ BUILD SUCCESSFUL, **70/70** (RunAnalyzerTest 52, FlatJsonTest 8, RunConfigTest 6, AndroidNamesTest 3, AlarmToneTest 1).

| Test case | Tầng | Kết quả | Ghi chú (runId, bằng chứng) |
|---|---|---|---|
| Cài đặt + cấp quyền bằng luồng trong app (S1 Phần 1–2) | thủ công (emulator, uiautomator) | PASS | `install -r` → `Success`. Trong app: "Cấp quyền" → Precise + While using; "Mở cài đặt" → Allow all the time; "Cấp quyền" thông báo → Allow. Màn chính: Vị trí chính xác / Thông báo / Báo thức toàn màn hình / Báo thức chính xác = **Đã cấp**, Tối ưu pin = Đang tối ưu, Hạn chế nền = Không. `dumpsys package` khớp |
| **M00** (S1 A, 0,2 giờ, pha dày 6 phút, `battery unplug`, màn khoá tắt) | thủ công | **PASS** | `20261029-112124-S1-A`. `phase_alarm_scheduled exact=true` → `phase_alarm lateMs=61 alive=true action=switch` → `phase_switch via=alarm lateMs=101` → `loc_req HIGH 10 000 ms` ngay sau (cùng ms). Báo thức kích hoạt bằng `fix`, lệch +8,2 s; AlarmActivity trên keyguard; player `USAGE_ALARM` started; rung `Usage=ALARM` running. Tóm tắt: "Chuyển pha: ranh giới +0:06:00 · thật +0:06:00 (trễ 0 s, via alarm)", dày 36 fix (khoảng trống lớn nhất 10 s), **PASS** |
| **S2-1** khoá, chuông bình thường, không DND, 2 ph | thủ công | **PASS** | `…113612-S2-1`: lệch +4 s, nguồn fix, `alarm_ui_shown viaFsi=true keyguardLocked=true`, màn bật (`Awake`), `isKeyguardShowing=true` + focus `AlarmActivity`, tắt bằng nút "Tắt báo thức" sau 21 s |
| S2-2 im lặng | thủ công | PASS | `…114158-S2-2`: ringer `SILENT` (đặt qua bảng âm lượng SystemUI), `STREAM_ALARM Muted: false`; player ALARM started, rung chạy, FSI hiện. PASS |
| S2-3 im lặng + DND mặc định (`cmd notification set_dnd priority`, `allow(alarms=true)`) | thủ công | PASS | `…115019-S2-3`: `ZEN_MODE_IMPORTANT_INTERRUPTIONS`, kêu + rung + FSI trên màn khoá. PASS |
| S2-4 như S2-3 + tắt FSI (`appops set … USE_FULL_SCREEN_INTENT deny`) | thủ công | PASS (đúng kỳ vọng) | `…115341-S2-4`: app hiện "Thiếu quyền: Báo thức toàn màn hình"; `perm_snapshot fsi=false`. Âm + rung chạy, **màn không bật** (`mWakefulness=Asleep`, emulator không có AOD), thông báo không còn `fullscreenIntent`. Đánh thức màn hình: thông báo "Báo thức thử (S2)" ở đầu màn khoá (thu gọn); phải mở rộng mới thấy nút "Tắt"; nút "Tắt" chạy được không cần mở khoá (khoá vuốt). Tóm tắt PASS ("hiện được: có (FSI: không) · màn báo thức: không hiện"). Đã bật lại FSI |
| S2-5 như S2-3 + Doze ép (`battery unplug` + `deviceidle force-idle` → "Now forced in to deep idle mode") | thủ công | PASS | `…115748-S2-5`: `idle on=true` lúc +10 s; fix dày vẫn đều 10 s trong deep idle; `alarm_trigger src=fix idle=true lateMs=3356`; FSI + âm. Đã `unforce` + `battery reset` |
| S2-6 như S2-3 + xoá app khỏi đa nhiệm ("Clear all" trong Recents) | thủ công | PASS | `…131107-S2-6`: `svc_task_removed`, process sống (cùng pid), báo đúng giờ (+5 s, fix), FSI. Chỉ là AOSP; hành vi OEM (force-stop) cần máy thật |
| S2-7 như S2-3 + thu hồi thông báo (`pm revoke … POST_NOTIFICATIONS`) | thủ công | PASS (WARN đúng kỳ vọng) | `…120420-S2-7`: dòng "Thông báo" = Chưa cấp; `alarm_notif_posted notifEnabled=false`; âm + rung chạy, màn không bật, không có thông báo nào trong `dumpsys notification`. Dừng bằng "Dừng lượt" khi đang kêu → `alarm_dismissed by=user_stop` từ chính pid đang kêu. Tóm tắt **WARN — không có màn báo thức/thông báo** (đúng U25 / ghi chú tester #7) |
| S2-8 (video YouTube) | — | Chưa chạy | Emulator không có YouTube/không loa; cần máy thật |
| (ngoài spec) DND "Hoàn toàn tắt tiếng" (`set_dnd none`) | thủ công | **FAIL — lỗi #4** | `…120806-S2-3`: `STREAM_ALARM Muted: true`, `alarm_sound_start muted=true alarmVol=0`, rung `status: ignored_app_ops`, thông báo bị chặn (`intercepted … new:none`), không FSI, màn không bật → **không có tín hiệu nào**, nhưng tóm tắt "âm thanh OK · rung OK · hiện được: có" và **PASS** |
| **M-WD (a)** X, 0,3 giờ, pha dày 9, bỏ Watchdog, quyền "Luôn cho phép", Tự huỷ phút 5 | thủ công | PASS | `…122227-S1-X`: `self_kill_now` → `exit_info REASON_SIGNALED` → `svc_start_cmd src=sticky` sau ~1,6 s, `svc_fg_ok`. Không có `src=phase_alarm`; ranh giới: service sống → `phase_alarm action=switch`, `phase_switch via=alarm`. Đúng điều kiện "(nếu có khởi động lại thì chỉ `src=sticky`)". Dừng lượt sau ranh giới (tiết kiệm thời gian) |
| **M-WD (b)** như (a) nhưng quyền "Chỉ khi dùng app"; sau sticky restart dừng service bằng `adb root` + `am stopservice` (giả lập "sticky không cứu") | thủ công | **PASS** (M-WD) / phát hiện #1 | `…123407-S1-X`: ở ranh giới `phase_alarm {lateMs=70, alive=false, action=none}`; **không** có `svc_start_cmd src=phase_alarm`. Dự phòng báo thức vẫn khởi động lại (`src=alarm_fallback`, như ghi chú vòng 3 #2) nhưng `svc_fg_fail SecurityException` → **báo thức không kêu** (xem #1). Tóm tắt FAIL đúng ("pha dày mất vị trí 9 ph", "báo thức không kích hoạt", "không chuyển sang pha dày") |
| (ngoài spec) Đối chứng dự phòng **có** quyền nền | thủ công | PASS | `…125532-S2-1`: dừng service trước mốc → `svc_start_cmd src=alarm_fallback` → `svc_fg_ok` → `alarm_trigger src=fallback lateMs=60103` → kêu. Tóm tắt WARN "kích hoạt bằng dự phòng; trễ 60 s" (đúng U16). "màn báo thức: không hiện" là sai — lỗi #3 |
| **R2-1** S2-1 đang kêu thì giết process | thủ công | **PASS** | `am kill app.napstop.probe` **không** giết được (process FGS không phải nền) → dùng `adb shell run-as app.napstop.probe kill -9 <pid>`. `…121134-S2-1`: `exit_info REASON_SIGNALED` (exitTs ≈ S + 16 s) → sticky → `alarm_error step=interrupted` → `run_stop by=auto`. Lần này `exit_info` ghi trước `run_stop` (không tái hiện được thứ tự đua, analyzer đã có U28). Tóm tắt **FAIL — báo thức bị ngắt sau 16 s** |
| **R2-2** S2-1 đang kêu thì `am force-stop`, rồi mở app bấm "Dừng lượt" | thủ công | **PASS** | `…121535-S2-1`: không sticky; mở app → `exit_info REASON_USER_REQUESTED "[FORCE STOP]…"`; "Dừng lượt" → `run_stop by=user` từ pid mới, không có `alarm_dismissed`. Tóm tắt **FAIL — báo thức bị ngắt sau 8 s** (không PASS). Phụ: dòng chết ghi "khởi động lại sau 30 s (?)" (lỗi #6) |
| Ghi chú vòng 3 #3 vế 2: "Dừng lượt" khi process đang kêu còn sống | thủ công | PASS | `…121854-S2-1`: `alarm_dismissed by=user_stop` (cùng pid) → `run_stop by=user`; tóm tắt PASS "tắt sau 47 s (user_stop)" |
| Ghi chú tester #4 (R2 Android 14: crash "did not then call startForeground"?) | thủ công | PASS (trên emulator) | Sau `svc_fg_fail` (lượt `…123407`) process vẫn sống, không có `exit_info REASON_CRASH` nào trong 8 bản ghi chết của cả buổi |
| Lệnh giao thức chạy nguyên văn | thủ công | **FAIL một phần — #7** | `adb -s <serial> install -r app/build/outputs/apk/debug/app-debug.apk` → `Success` ✔. `adb -s <serial> logcat -d -v threadtime > …` ✔. `adb -s <serial> pull /sdcard/Android/data/app.napstop.probe/files/runs …` trong Git Bash → **lỗi** `failed to stat remote object 'C:/Program Files/Git/sdcard/…'`. `exec-out run-as app.napstop.probe tar c files/runs` chạy được nhưng trên máy này chỉ ra lỗi tar "No such file" (đúng: log ở bộ nhớ ngoài, lệnh này chỉ là dự phòng) |
| Unit test probe (U01–U34, U15–U29, phụ) | unit (JVM) | PASS | 70/70 |

Phụ lục sự kiện (ngoài lỗi): pha thưa trên emulator **không có fix nào** (`loc_avail avail=false`; FLP `BALANCED` không có nguồn
mạng/Wi-Fi trên AVD) nên khoảng trống thưa của M00 = 6 ph (≤ 420 s, vẫn PASS). Đây là giới hạn emulator, không phải lỗi app.

## Tiêu chí chấp nhận

| Tiêu chí | Đạt? | Bằng chứng (test/log) |
|---|---|---|
| S1 §8.1: build + unit test U01–U14, U20–U24, U30–U34 xanh | Đạt | 70/70 (`--rerun-tasks`); B01–B05 đã được coder/reviewer kiểm, APK khớp nguồn |
| S1 §8.2: M00 chạy được trên ≥ 1 máy/emulator trước khi giao | Đạt | `20261029-112124-S1-A`, tóm tắt PASS, "via alarm", trễ 0 s (`phase_alarm.lateMs=61`, `phase_switch.lateMs=101`) |
| S1 §7.3 M-WD: `phase_alarm {alive=false, action=none}`, không có `svc_start_cmd src=phase_alarm` | Đạt | `20261029-123407-S1-X` (biến thể b). Biến thể a: chỉ `src=sticky` |
| S2 §8.1: U15–U19, U25–U29 xanh; một lượt S2-1 chạy được | Đạt | Unit test; `20261029-113612-S2-1` PASS |
| Ghi chú tester vòng 3 #1–#4 | Đạt | Xem các dòng M00, M-WD, R2-1/R2-2, user_stop ở trên; #4 (khoảng trống "service sống") không xảy ra trên emulator |
| Số liệu probe thu trên máy thật đáng tin trong mọi trình tự thao tác của giao thức | **Không đạt** | Lỗi #2, #3, #4 |
| Lệnh adb trong giao thức chạy nguyên văn | **Không đạt** | Lỗi #7 (`adb pull`) |

## Lỗi phát hiện

| # | Mức | Mô tả | Repro (lệnh/trace/bước) | Kỳ vọng vs Thực tế |
|---|---|---|---|---|
| 1 | **major — phát hiện cho designer/T15/T16** | Không có `ACCESS_BACKGROUND_LOCATION`, **lưới an toàn của báo thức không chạy**: `WatchdogReceiver` nhận `ALARM_FALLBACK`, gọi `startForegroundService(src=alarm_fallback)` (hệ thống cho phép start nhờ `ALARM_MANAGER_WHILE_IDLE`) nhưng `startForeground(TYPE_LOCATION)` ném `SecurityException` ("Foreground service started from background can not have location/camera/microphone access") → `stopSelf()`, `triggerAlarm` không bao giờ chạy. Cùng cơ chế áp cho watchdog 15 ph và `phase_alarm` khi lượt R2 | Quyền vị trí = "Chỉ khi dùng app". Lượt S1 X 0,3 giờ / dày 9 / có báo thức cuối / bỏ Watchdog. Làm service chết mà không có sticky (emulator: `adb root; adb shell am stopservice app.napstop.probe/.ProbeService`; máy thật: OEM giết/force-stop rồi hệ thống không sticky). Chờ tới mốc + 60 s. Log `…123407-S1-X` | Kỳ vọng (S2 §5.1: "luôn làm… lưới an toàn của chính báo thức"): kêu với `src=fallback`. Thực tế: `svc_start_cmd src=alarm_fallback` → `svc_fg_fail java.lang.SecurityException` → **không kêu**. Có quyền nền thì kêu bình thường (`…125532-S2-1`). Với sản phẩm: đường báo thức **không được** phụ thuộc vào việc khởi động lại FGS `location` từ nền (đề xuất cho T15/T16: phát âm từ một đường không cần quyền vị trí, ví dụ FGS kiểu khác hoặc `setAlarmClock`; hoặc bắt buộc quyền nền ở Màn 0). Trong probe: lượt R2 có báo thức sẽ luôn ra "không kích hoạt" khi service chết; designer quyết có cho fallback kêu dù `startForeground` lỗi không |
| 2 | **major — probe** | Process chết **khi đang kêu** mà không phải force-stop (LMK, OEM giết, crash, `kill -9`): process mới ghi `alarm_error interrupted` + `run_stop auto` nhưng **không huỷ thông báo báo thức id 2** (`finishRun` chỉ `silenceAlarm()` khi `player != null`). Thông báo ongoing "Báo thức thử (S2)" nằm lại, im lặng. Lần báo **kế tiếp** `notify(id 2)` thành *cập nhật* (SystemUI: `NotifCollection: UPDATED …|2|…`, không có `sending fullScreenIntent`, "No heads up") → **không FSI, không heads-up, màn không bật**, chỉ có âm + rung | Tái hiện 2 lần (`…121134` → `…121535`; `…130409` → `…130616`). Tối giản: (1) lượt S2-1 trễ 1 ph, màn khoá; khi kêu: `adb shell run-as app.napstop.probe kill -9 $(adb shell pidof app.napstop.probe)`; (2) `adb shell dumpsys notification --noredact \| grep 'pkg=app.napstop.probe user=UserHandle{0} id=2 '` → vẫn còn 1 bản ghi (`…130853-S2-1`); (3) lượt S2-1 tiếp theo, khoá màn hình | Kỳ vọng: lượt (3) giống S2-1 (màn bật, AlarmActivity). Thực tế: `mWakefulness=Asleep`, không `alarm_ui_shown`, không sự kiện `screen on`; tóm tắt ghi "màn báo thức: không hiện" → người chạy sẽ ghi "Không có gì / màn không bật" và đọc nhầm thành hành vi OEM. Sửa đề xuất: trong `onStarted` khi `alarmFired && player == null` (và khi bắt đầu lượt mới) gọi `cancel(ID_ALARM)`; hoặc dùng tag/id thông báo riêng theo lượt. Cùng bài học cho T16 |
| 3 | **minor (ảnh hưởng số liệu) — probe** | `AlarmActivity` (`singleInstance`) **không tự đóng** nếu báo thức dừng lúc activity không ở trạng thái STARTED (collector `repeatOnLifecycle(STARTED)`), ví dụ người dùng bấm Home/mở app rồi "Dừng lượt" hoặc bấm "Tắt" trên thông báo. FSI lần sau tái dùng instance cũ qua `onNewIntent` (không override): **hiện mốc/nguồn của lượt trước** và **không ghi `alarm_ui_shown`** | (1) Lượt S2-1 1 ph; khi đang kêu: `adb shell wm dismiss-keyguard; adb shell am start --activity-clear-top -n app.napstop.probe/.MainActivity`, bấm "Dừng lượt" → `dumpsys activity activities` vẫn có `Hist #0 … AlarmActivity` (`…125906-S2-1`). (2) Lượt S2-1 kế tiếp (`…130059-S2-1`, mốc 13:01:59) | Kỳ vọng: màn báo thức "Mốc 13:01:59", có `alarm_ui_shown`, tóm tắt "màn báo thức hiện trên màn khoá: có". Thực tế: màn hiện "Mốc 13:00:06" (lượt trước), không có `alarm_ui_shown`, tóm tắt "màn báo thức: không hiện" nhưng lại "tắt sau 22 s (activity)" (mâu thuẫn). Nếu thông báo cũng không hiện được (S2-7) sẽ thành WARN giả. Sửa đề xuất: override `onNewIntent` (cập nhật chữ + ghi `alarm_ui_shown`), và/hoặc kiểm `alarmActive` trong `onStart`/`onResume` để `finish()` |
| 4 | **major — spec S2 §5.5 / `RunAnalyzer`** | DND "Hoàn toàn tắt tiếng" (người dùng chặn báo thức, H2/R3): luồng báo thức bị tắt tiếng, rung bị chặn, thông báo bị chặn, không FSI → **không có tín hiệu nào**, nhưng tóm tắt ra **PASS**. `soundOk` = `isPlaying`; `alarm_sound_start` đã ghi `muted=true, alarmVol=0` nhưng analyzer không dùng; `notifVisible` không xét DND; `alarm_vibrate ok=true` dù rung `ignored_app_ops` | `adb shell cmd notification set_dnd none` (ringer im lặng), lượt S2-3 trễ 1 ph, khoá màn hình. Log `…120806-S2-3` | Kỳ vọng: tóm tắt tối thiểu WARN/FAIL ("âm báo thức đang bị tắt tiếng / âm lượng 0"). Thực tế: "âm thanh OK (âm lượng 0/7…) · rung OK · hiện được: có … DND NONE … PASS". Spec nói biên bản người nghe là chuẩn, nhưng S2-9 (qua đêm, người ngủ) và đọc nhanh tóm tắt dễ ra PASS giả. Đề xuất designer: `muted == true` hoặc `alarmVol == 0` → FAIL; `zen = NONE` (hoặc `ALARMS` không tính) → `notifVisible = false`; ghi chú "rung có thể bị DND chặn" |
| 5 | minor — probe/analyzer | Fix **cũ** (FLP trả vị trí cache khi đăng ký lại) được tính là "có vị trí lại" | `…123407-S1-X`: sau sticky restart fix `n=4` có `ageMs=84873` rồi service bị dừng, không còn fix nào; tóm tắt vẫn "có vị trí lại sau 1 s". (`…122227-S1-X`: fix cache `ageMs=130589` và fix mới cùng giây nên không sai) | Kỳ vọng: `recoveryS` và khoảng trống tính theo fix mới (`ageMs` nhỏ). Thực tế: fix 85 s tuổi được tính. Ở lượt A/B có thể làm "hồi phục" và khoảng trống nhỏ hơn thật. Đề xuất: bỏ fix có `ageMs` > ngưỡng (vd > interval pha) khi tính gap/recovery. Bài học cho Trip Engine: không dùng fix cache cũ để tính ETA |
| 6 | nit — `render` | R2-2: "khởi động lại sau 30 s (?)" — `proc_start` do người chạy mở app được tính là khởi động lại | `…121535-S2-1` | Nên ghi "không khởi động lại (process mới do mở app)" khi không có `svc_start_cmd` hệ thống kế tiếp |
| 7 | minor — tài liệu | `adb pull /sdcard/...` chạy **nguyên văn trong Git Bash bị lỗi**: MSYS đổi `/sdcard/...` thành `C:/Program Files/Git/sdcard/...` | `cd spikes/android-probe; adb -s emulator-5580 pull /sdcard/Android/data/app.napstop.probe/files/runs <đích>` | Kỳ vọng: kéo được log. Thực tế: `adb: error: failed to stat remote object 'C:/Program Files/Git/sdcard/…'`. Đã kiểm hai cách chạy được: `adb -s <serial> pull //sdcard/Android/data/app.napstop.probe/files/runs ../results/<…>/` (gạch chéo kép), hoặc `MSYS_NO_PATHCONV=1 adb … pull /sdcard/… ../results/<…>/` (khi đó đích **phải** là đường dẫn tương đối hoặc kiểu `D:/…`; đường dẫn `/c/...` sẽ ghi nhầm sang `D:\c\...`). Cần sửa ở `docs/test-protocols/S1.md` Phần 3 bước 9, `S2.md` Phần 2, `docs/spikes/S1.md` §5.9, `spikes/android-probe/README.md` |

Ghi chú, không phải lỗi:
- **H4 trên emulator:** sau khi process bị giết, **sticky restart không cần quyền nền vẫn có vị trí**. `dumpsys activity services` cho thấy ServiceRecord
  giữ `mAllowWhileInUsePermissionInFgsReason=PROC_STATE_TOP` từ lần bấm Bắt đầu. Fix dày vẫn đến mỗi 10 s sau khi khởi động lại (`…122227-S1-X`,
  quyền "Chỉ khi dùng app"). Giao thức R2 đang kỳ vọng "`svc_fg_fail` hoặc `loc_req_fail`/không fix trên Android 14+". Còn khởi động mới từ
  exact alarm (fallback, watchdog, phase_alarm) thì **thất bại** (#1). Cần xác nhận trên máy thật.
- Dừng lượt bằng `am kill` không giết được process đang chạy FGS (ghi chú tester vòng 2 #2). Phải dùng `run-as … kill -9`.
- Thông báo ở S2-4 (FSI tắt) trên màn khoá chỉ hiện dạng thu gọn, nút "Tắt" nằm trong phần mở rộng. Ghi vào thẻ UX cho T16.

## Phần chưa chạy được & lý do

Cần **máy thật** (emulator không tính kết quả, S1 §4.6):
- S1 lượt A, B (10 giờ, Doze thật, OEM), R1/R2 (hành vi OEM; xác nhận lại ghi chú H4 ở trên), bước pin của hãng / nội dung Màn 9.
- S2: **nghe thấy** thật (âm lượng, "Rõ/To"), rung cảm nhận được, video; S2-6 trên Xiaomi/Oppo/Vivo (vuốt = force-stop?), S2-8 (YouTube),
  S2-9 (sau 10 giờ), S2-10 (Android 17). Ghi chú tester #2 (FSI trên Android 15/16, luật BAL) và #3 (quyền "Hiển thị trên màn hình khoá" của
  Xiaomi): emulator chỉ có Android 14.
- AOD / màn khoá có mã PIN (emulator dùng khoá vuốt): hành vi FSI và nút "Tắt" khi khoá bảo mật.

Trạng thái emulator sau khi chạy: đã tắt (`adb emu kill`). AVD **`napstop_api34`** được giữ lại; trong AVD còn: probe đã cài và cấp quyền,
khoá màn hình vuốt bật, bàn phím ảo bị tắt (`ime disable`), chuông im lặng, định vị bật. Adb server đã chạy từ trước phiên này, không tắt.
Log `spikes/results/emulator/runs/` chưa commit (lượt `…114829-S2-1` bị đặt nhầm nhãn rồi dừng ngay, không dùng làm số liệu).

Trạng thái đề xuất: **changes-requested** về coder: sửa #2, #3 và tài liệu #7. Designer chốt #1 (fallback khi không có quyền nền) và #4
(quy tắc âm/DND trong S2 §5.5); #5, #6 tuỳ chọn. Sau khi sửa, tester chạy lại các repro #2 và #3 (mỗi cái khoảng 5 phút trên emulator).

---

# Test report S1-S2 (emulator smoke test của app thí nghiệm) — Lần 2

Kết luận: **FAIL** — toàn bộ mục chạy lại của V4-9.2 và "Ghi chú cho tester" vòng 4 **đạt**: M-FB1, M-FB2 (3 cách tắt + hết giờ),
kill -9 khi `AlarmRingService` đang kêu, repro #2 và #3 (kể cả biến thể "Tắt" trên thông báo) không còn tái hiện, M-DND ra FAIL đúng,
S2-3 mặc định / S2-1 / M00 PASS, `adb pull //sdcard/…` chạy nguyên văn, không crash, không toạ độ. Lý do FAIL: **R4-1 được xác nhận**
(lỗi L2-1). Khi một chế độ Không làm phiền tự động (lịch "Sleeping") **cho phép** báo thức còn cài đặt DND mặc định **chặn** báo thức, báo thức
vẫn kêu và nghe được. Dù vậy tóm tắt ra **FAIL "không nghe được: Không làm phiền chặn báo thức"**. Đây là số liệu sai trên máy thật,
dễ gặp ở lượt qua đêm (S2-9, S1 lượt A/B khi chế độ ngủ đang bật). Sửa thuộc quy tắc của designer (S2 V4-2) và là sửa nhỏ. Còn 4 nit, sửa
hay không tuỳ chọn.

Môi trường: như Lần 1 (Windows 11 Home 10.0.26200, Git Bash, AVD **`napstop_api34`** Android 14 SDK 34 `UE1A.230829.050`, `emulator-5580`,
headless, WHPX). Luồng vị trí giả `adb emu geo fix` mỗi 3 s quanh toạ độ tổng hợp (không phải địa điểm thật). Khoá vuốt bật.
- APK: `spikes/android-probe/app/build/outputs/apk/debug/app-debug.apk`, 3 455 775 byte, build 13:59. `./gradlew assembleDebug` báo
  UP-TO-DATE, `find app/src -newer app-debug.apk` rỗng nên APK khớp nguồn vòng 4. `adb install -r` → `Success`, giữ dữ liệu và quyền của Lần 1.
- Unit test: `./gradlew --init-script <scratchpad>/central-mirror.init.gradle :app:testDebugUnitTest --rerun-tasks` → BUILD SUCCESSFUL,
  **90/90** (RunAnalyzerTest 70, AlarmRouteTest 2, RunConfigTest 6, FlatJsonTest 8, AndroidNamesTest 3, AlarmToneTest 1).
  `apkanalyzer manifest permissions` → 15 quyền + `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`, không có `INTERNET`.
- Cách xác minh "kêu" (không có loa) giống Lần 1: `dumpsys audio` (player `USAGE_ALARM state:started`), `dumpsys vibrator_manager`,
  `dumpsys power`, `dumpsys window`, `dumpsys notification --noredact`, `dumpsys activity services|activities`, log SystemUI.
- Không làm phiền: `cmd notification set_dnd none|priority|off`. Chính sách mặc định và lịch tự động đổi qua Settings (uiautomator).

## Kết quả

20 lượt mới, log ở `spikes/results/emulator/runs/2026102914*`, `…15*`, `…16*`. `orphan.jsonl` được cập nhật; 28 dòng đầu giống hệt bản Lần 1,
chỉ có thêm dòng mới. Lần 1 dùng 1 phút trễ cho repro; Lần 2 cũng dùng **1 phút** cho mọi lượt trừ S2-1 hồi quy, M-FB2 đường 1 và S2-3
mặc định (2 phút, đúng giao thức).

| Test case | Tầng | Kết quả | Ghi chú (runId, bằng chứng) |
|---|---|---|---|
| Unit test probe (U01–U39 + phụ) | unit (JVM) | PASS | 90/90 `--rerun-tasks` |
| **S2-1 hồi quy** (chuông bình thường, không DND, 2 ph, khoá) | thủ công | **PASS** | `…141100-S2-1`: `src=fix svc=probe` lệch +6 s, `alarm_ui_shown viaFsi=true keyguardLocked=true`, `mWakefulness=Awake`, `isKeyguardShowing=true` + top `AlarmActivity`, player ALARM started, rung running. Render mới: "âm thanh: đang phát (âm lượng 6/7, focus granted) · rung: đã yêu cầu (không xác minh được) · thông báo: đã gửi, đủ điều kiện hiện: có (FSI: có)". **Không còn chữ "OK"**. PASS |
| **M-FB2 / S2-11 đường 1**: nút "Tắt báo thức" trên màn báo thức (2 ph, quyền "Chỉ khi dùng app", im lặng + DND priority) | thủ công | **PASS** | `…141619-S2-11`: `svc_cmd action=sim_kill` → `svc_destroy`; thông báo "Lượt …" (id 1) biến mất, không còn service. Lúc mốc + 60 s: `alarm_ring_fg type=systemExempted ok=true` → `alarm_trigger src=fallback svc=ring lateMs=60050` → `alarm_ui_shown viaFsi=true` → `alarm_sound_start ok=true muted=false alarmVol=6 zen=2 zenAlarms=true`. Lúc đang kêu: `AlarmRingService isForeground=true foregroundId=2 types=00000400`, player ALARM started, rung running, màn bật, AlarmActivity trên keyguard. Tắt: `svc_cmd dismiss by=activity` → `alarm_dismissed by=activity` → `run_stop by=alarm_dismissed`. Sau đó không còn service, thông báo id 2, `AlarmActivity` trong Hist, wakelock `probe:alarm` (đã REL) hay player. Tóm tắt **WARN** "kích hoạt bằng dự phòng …; báo thức trễ 60 s (> 30 s); (thông tin) service bị tắt bằng nút giả lập lúc +0:01:20", dòng báo thức có "nguồn fallback (service báo thức riêng, systemExempted)". Không có `svc_start_cmd src=alarm_fallback` |
| **M-FB2 đường 2**: nút "Tắt" trên thông báo (màn khoá, kéo shade) | thủ công | **PASS** | `…142059-S2-11`: `systemExempted ok=true`, fallback +60 s, FSI. `svc_cmd dismiss by=notif_action` cùng pid → `alarm_dismissed by=notif_action` → `run_stop by=alarm_dismissed`. Dọn sạch như trên. WARN như kỳ vọng |
| **M-FB2 đường 3**: mở app (AlarmActivity xuống nền) → "Dừng lượt" | thủ công | **PASS** | `…142415-S2-11`: lúc bấm, `Hist #0 AlarmActivity` còn ở nền. Lệnh đi tới `AlarmRingService` (`svc_cmd action=stop`) → `alarm_dismissed by=user_stop` → `run_stop by=user`. Sau đó không còn `AlarmActivity`, thông báo id 2, service. WARN "tắt sau 43 s (user_stop)". Đây cũng là repro #3 cho đường ring |
| M-FB2 đường 4 (tuỳ chọn): kêu hết 5 phút | thủ công | **PASS** | `…153952-S2-11`: `alarm_dismissed by=timeout afterMs=300150` → `run_stop by=alarm_timeout`; dọn sạch. Tóm tắt WARN "tắt sau 4 ph 59 s (timeout)". (Lượt này cũng là M-FB3, dòng dưới) |
| (ngoài spec) **M-FB3**: sau nút giả lập, **giết process đã cache** (`am kill app.napstop.probe`), khoá máy | thủ công | **PASS** | `…153952-S2-11`: ca OEM giết process sau khi service vị trí chết. Ở mốc + 60 s, **process mới** (`proc_start importance=300`, `exit_info REASON_USER_REQUESTED "[KILL BACKGROUND]"`) → `alarm_ring_fg systemExempted ok=true` → `alarm_trigger src=fallback svc=ring lateMs=60669` → FSI + âm + rung. Đường dự phòng không cần process còn sống. Nhãn dòng "Chết" sai (R4-4, lỗi L2-4) |
| **M-FB1** (M-WD (b) lặp lại: S1 X 0,3 giờ / dày 9 / có báo thức cuối / **bỏ** Watchdog, quyền "Chỉ khi dùng app", rút sạc trước khi bắt đầu, nút giả lập ở +0:00:37) | thủ công | **PASS** | `…151900-S1-X`: `svc_cmd action=sim_kill` → `svc_destroy`. Ở ranh giới: `phase_alarm {lateMs=18, alive=false, action=none}`. **Không** có `svc_start_cmd` nào ngoài `src=user` (không sticky, không `alarm_fallback`). Mốc + 60 s: `alarm_ring_fg type=systemExempted ok=true`, `alarm_trigger src=fallback svc=ring lateMs=60087`, `alarm_sound_start ok=true`, `alarm_ui_shown viaFsi=true`. `AlarmRingService types=00000400` isForeground, rung running, màn bật trên keyguard. Tắt bằng "Tắt báo thức" → `by=activity`, dọn sạch. Dòng báo thức của tóm tắt: "mốc 15:37:00, lệch +60 s · nguồn fallback (service báo thức riêng, systemExempted) …". Mức báo thức WARN ("kích hoạt bằng dự phòng", "trễ 60 s"). Verdict cả lượt FAIL là đúng, do mất vị trí 9 ph và không chuyển pha. So với Lần 1 `…123407`: trước **không kêu**, nay **kêu**. Lỗi #1 đã sửa trên emulator. Phụ: nhãn khoảng trống thưa sai (L2-2) |
| **Chết khi `AlarmRingService` đang kêu** (`run-as … kill -9`) | thủ công | **PASS** | `…142757-S2-11`: kill lúc +10 s sau khi kêu. Thông báo id 2 **mất ngay** (thông báo FGS, `REMOVED reason=APP_CANCEL` trong log SystemUI), không còn service, không có process trong 60 s → **không tự khởi động lại** (`START_NOT_STICKY`). Mở app → "Dừng lượt" (lệnh tới `ProbeService`, `run_stop by=user`). Tóm tắt **FAIL "báo thức bị ngắt sau 10 s"**, dòng chết: "REASON_SIGNALED · không tự khởi động lại (process mới do mở app sau 1 ph 17 s)" |
| Lượt S2-1 khoá máy **ngay sau** ca trên (repro #2 cho đường ring) | thủ công | **PASS** | `…143244-S2-1`: SystemUI "sending fullScreenIntent", `alarm_ui_shown viaFsi=true`, màn bật, top `AlarmActivity`. Tóm tắt PASS |
| **Repro #2** (đường `ProbeService`): S2-1 đang kêu → `kill -9` | thủ công | **PASS (không tái hiện)** | `…143529-S2-1`: sticky restart sau 1 s → `alarm_error interrupted` → `run_stop auto`. SystemUI ghi `REMOVED …|2|… reason=8:REASON_APP_CANCEL` lúc 14:36:47.734 (cùng ms với `alarm_error`), `dumpsys notification` **không còn id 2**. Lần 1 còn 1 bản ghi. Tóm tắt FAIL "bị ngắt sau 10 s" (đúng) |
| Repro #2 bước 3: lượt S2-1 kế tiếp, khoá máy | thủ công | **PASS** | `…143733-S2-1`: "sending fullScreenIntent", `alarm_ui_shown`, `mWakefulness=Awake`, màn báo thức "Mốc 14:38:33 / Nguồn kích hoạt: fix" (mốc mới). PASS. Lần 1: `Asleep`, không FSI |
| **Repro #3**: đang kêu → `wm dismiss-keyguard; am start --activity-clear-top … MainActivity` → "Dừng lượt" | thủ công | **PASS (không tái hiện)** | `…144000-S2-1`: trước khi bấm, `Hist #0 AlarmActivity` ở nền. Sau `alarm_dismissed by=user_stop`, `dumpsys activity activities` **không còn** `AlarmActivity`. Lượt kế tiếp `…144205-S2-1`: màn báo thức "Mốc 14:43:05" (mốc mới), có `alarm_ui_shown`. Lần 1: mốc cũ, không `alarm_ui_shown` |
| **Repro #3 biến thể**: AlarmActivity ở nền → nút "Tắt" trên thông báo | thủ công | **PASS** | `…144205-S2-1`: mở app (AlarmActivity xuống nền) → kéo shade, mở nhóm thông báo → "Tắt" → `svc_cmd dismiss by=notif_action` → `alarm_dismissed by=notif_action`. Không còn `AlarmActivity` trong Hist. Lượt kế tiếp `…144453-S2-1`: "Mốc 14:45:53", `alarm_ui_shown viaFsi=true`, PASS |
| **M-DND** (`set_dnd none`, im lặng, S2-3 1 ph) | thủ công | **PASS** (tóm tắt FAIL đúng) | `…144757-S2-3`: `alarm_sound_start muted=true alarmVol=0 zen=3 zenAlarms=null`. `STREAM_ALARM Muted: true`, rung `ignored_app_ops`, `mWakefulness=Asleep`, không FSI. Tóm tắt: "âm thanh: TẮT TIẾNG (luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền: hoàn toàn tắt tiếng; âm lượng 0/7) · rung: bị Không làm phiền chặn · thông báo: đã gửi, đủ điều kiện hiện: không (Không làm phiền chặn) · màn báo thức: không hiện · DND NONE" → **FAIL — không nghe được: …**. Không còn "âm thanh OK", "rung OK", "hiện được: có". Lỗi #4 đã sửa |
| **M-DND2** (R4-1): Settings → Do Not Disturb → Alarms & other interruptions → **tắt Alarms** (`mConfig=allow(alarms=false,…)`); `set_dnd priority`; im lặng; S2-3 1 ph | thủ công | **PASS** (tóm tắt FAIL đúng) | `…145128-S2-3`: **`muted=true`, `alarmVol=0` (max 7), `zen=2`, `zenAlarms=false`**. `dumpsys audio`: `STREAM_ALARM Muted: true`, `ringer mode muted streams = 0x1b6 (… STREAM_ALARM …)`; rung `ignored_app_ops`; `mWakefulness=Asleep`, không FSI. Tóm tắt "TẮT TIẾNG (luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền chặn báo thức; âm lượng 0/7) · … · DND PRIORITY (báo thức: chặn)" → **FAIL — không nghe được**. Kết luận số liệu: trên Android 14 AOSP, `isStreamMute(STREAM_ALARM)` **bắt được** ca PRIORITY chặn báo thức. Trong ca này policy đang áp dụng chính là policy mặc định, nên `zenAlarms` cũng đúng |
| (ngoài spec) **M-DND3 = R4-1 (a)**: như M-DND2 (mặc định chặn Alarms) nhưng **tắt DND thủ công** và bật lịch "Sleeping" (Schedules → Sleeping: Start 12:00 PM để bao giờ hiện tại, "Alarm can override end time" tắt, Do Not Disturb behavior → **Create custom settings → Alarms bật**, Use schedule bật) | thủ công | **FAIL — lỗi L2-1** | `…145658-S2-3`: `mZenMode=ZEN_MODE_IMPORTANT_INTERRUPTIONS`, `mConsolidatedPolicy` **có** `PRIORITY_CATEGORY_ALARMS`, `mConfig=allow(alarms=false…)`. Log: **`muted=false`, `alarmVol=6`, `zen=2`, `zenAlarms=false`**. Hệ thống: `STREAM_ALARM Muted: false`, muted streams `0x1a6` (không có ALARM), player ALARM started, **rung `status: running`**, màn bật, `AlarmActivity` trên keyguard qua FSI. Tức là **kêu và nghe được**. Tóm tắt lại ra: "âm thanh: TẮT TIẾNG (Không làm phiền chặn báo thức; âm lượng 6/7) · rung: bị Không làm phiền chặn · thông báo: … đủ điều kiện hiện: không (Không làm phiền chặn) · màn báo thức hiện trên màn khoá: **có** · DND PRIORITY (báo thức: chặn)" → **FAIL — không nghe được: Không làm phiền chặn báo thức**. Tóm tắt tự mâu thuẫn. Đã trả lịch "Sleeping" về mặc định (22:00, tắt, `zenPolicy=null`, exitAtAlarm=true) và bật lại Alarms |
| **S2-3 mặc định** (DND priority, Alarms cho phép, im lặng, 2 ph) | thủ công | **PASS** | `…150100-S2-3`: `muted=false alarmVol=6 zen=2 zenAlarms=true`, FSI trên keyguard, màn bật. Tóm tắt "… DND PRIORITY (báo thức: cho phép) …" → PASS |
| **M00 hồi quy** (S1 A, 0,2 giờ, dày 6, Watchdog bật, rút sạc **trước khi** bắt đầu, khoá màn hình) | thủ công | **PASS** | `…154832-S1-A`: `phase_alarm lateMs=15 alive=true action=switch` → `phase_switch via=alarm lateMs=28` → `loc_req HIGH 10 000 ms` cùng ms. Báo thức `src=fix` +7 s, FSI trên keyguard. Tóm tắt: "thưa 2 (khoảng trống lớn nhất 2 ph 59 s) · dày 36 (khoảng trống lớn nhất 10 s)", "Chuyển pha: … (trễ 0 s, via alarm)", **PASS**. Lượt đầu `…150503-S1-A` (cùng cấu hình) bị đánh "LƯỢT KHÔNG HỢP LỆ — có sạc" vì tester rút sạc **sau** khi bấm Bắt đầu. Đó là lỗi thao tác của tester, không phải lỗi app. Ở lượt đó "bỏ qua 1 vị trí cũ" vẫn cho khoảng trống dày 10 s (fix cache đầu lượt không làm khoảng trống > 60 s) |
| Tóm tắt log cũ `…121535-S2-1` (V4-4) | thủ công | **PASS** | Dòng chết: "REASON_USER_REQUESTED 10 "[FORCE STOP] …" · **không tự khởi động lại (process mới do mở app sau 30 s)** · không hồi phục". Không còn "(?)" |
| **Nút "Tắt service (giữ lượt)"** | thủ công | **PASS** | Không có lượt: `enabled=false`. Có lượt, service sống: `enabled=true`. Sau khi bấm: `enabled=false`, thông báo id 1 mất, không còn ServiceRecord, không có `svc_start_cmd src=sticky` (cả 6 lượt dùng nút). `…160207-S2-11`: bấm nút rồi "Dừng lượt" **trước** mốc → `svc_cmd action=stop` tới `ProbeService` mới → `run_stop by=user` → `svc_destroy` (không lên foreground). Không còn alarm nào của probe trong hàng đợi `dumpsys alarm`. Qua mốc + 60 s không có `alarm_trigger`/`alarm_ring_fg`. Tóm tắt WARN "lượt dừng trước giờ báo …" (đúng). Không bấm nút khi đang kêu (R4-3) |
| **`adb pull //sdcard/…` nguyên văn** (giao thức S1 Phần 3 bước 9 / S2 Phần 2, Git Bash, trong `spikes/android-probe`) | thủ công | **PASS** | `mkdir -p ../results/tmp-l2pull && adb -s emulator-5580 pull //sdcard/Android/data/app.napstop.probe/files/runs ../results/tmp-l2pull/` → "42 files pulled, 0 skipped", tạo `../results/tmp-l2pull/runs/…`. So khớp bản kéo về scratchpad, rồi đã xoá thư mục tạm. Lỗi #7 đã sửa |
| **Crash / lỗi startForeground** | thủ công | **PASS** | `dumpsys activity exit-info app.napstop.probe` (toàn bộ lịch sử, cả Lần 1): chỉ có SIGNALED ×5 (kill -9 của tester), PERMISSION CHANGE ×5 (`pm revoke`), FORCE STOP ×1, KILL BACKGROUND ×1. **Không có CRASH/ANR**. Log lượt mới: không có `REASON_CRASH`, `svc_fg_fail`, `wd_restart_fail` hay `alarm_error` nào ngoài `interrupted` của repro #2. `logcat -b all \| grep -iE "did not then call\|ForegroundServiceDidNotStart\|ForegroundServiceStartNotAllowed\|FATAL EXCEPTION"` rỗng, nhưng buffer chỉ phủ từ 16:02 vì script `logcat -c` mỗi lượt; `exit-info` là bằng chứng chính. Ca "mọi kiểu FGS lỗi": **không tái hiện được** trên emulator |
| **Riêng tư** | grep | **PASS** | `grep -rlE '"(lat\|lng\|lon\|latitude\|longitude\|alt)"' spikes/results/emulator/runs` rỗng. `grep` giá trị toạ độ đã bơm (`10.0000…`) rỗng. Toàn bộ khoá JSON trong log: không có khoá vị trí (`dM` là khoảng cách mét giữa hai fix, `acc`, `spd`, `ageMs`) |

## Tiêu chí chấp nhận

| Tiêu chí | Đạt? | Bằng chứng (test/log) |
|---|---|---|
| V4-9.1 unit test xanh U01–U39; B01–B05 (B02 = 15 quyền) | Đạt | 90/90 `--rerun-tasks`; apkanalyzer 15 quyền, không `INTERNET`; APK khớp nguồn |
| V4-9.2 M-FB1, M-FB2 kêu với `src=fallback svc=ring`, mức báo thức WARN | Đạt | `…151900-S1-X`, `…141619/142059/142415/153952-S2-11`; `systemExempted ok=true` ở mọi lượt, `types=00000400` |
| V4-9.2 M-DND ra FAIL "không nghe được" | Đạt | `…144757-S2-3` |
| V4-9.2 repro #2, #3 không còn tái hiện | Đạt | #2: `…143529` → `…143733`; ring: `…142757` → `…143244`. #3: `…144000` → `…144205`; biến thể: `…144205` → `…144453`; ring: `…142415` |
| V4-9.2 S2-1 và M00 vẫn PASS | Đạt | `…141100-S2-1`, `…154832-S1-A` |
| V4-9.3 `adb pull //sdcard/…` nguyên văn trong Git Bash | Đạt | Dòng `adb pull` ở trên |
| Ghi chú tester vòng 4 #5 S2-3 mặc định PASS, có "DND PRIORITY (báo thức: cho phép)" | Đạt | `…150100-S2-3` |
| Ghi chú tester vòng 4 #9, #10 (crash, riêng tư) | Đạt | Xem bảng |
| Số liệu probe trên máy thật không cho FAIL/PASS giả trong các cấu hình DND thường gặp | **Không đạt** | L2-1 (`…145658-S2-3`) |

## Lỗi phát hiện

| # | Mức | Mô tả | Repro (lệnh/trace/bước) | Kỳ vọng vs Thực tế |
|---|---|---|---|---|
| L2-1 (= R4-1, xác nhận) | **major — quy tắc spec S2 V4-2 / `AlarmPlayer.zenAllowsAlarms` / `RunAnalyzer`** | `zenAlarms` lấy từ `NotificationManager.getNotificationPolicy()`, tức policy **mặc định** của DND, không phải policy hợp nhất đang áp dụng. Khi một quy tắc/chế độ tự động có policy riêng cho phép báo thức đang bật, báo thức kêu nghe rõ nhưng analyzer coi `zen=2 && zenAlarms=false` là "chặn". Kết quả: FAIL "không nghe được", rung "bị chặn", thông báo "đủ điều kiện hiện: không" | Emulator `napstop_api34`: (1) Settings → Notifications → Do Not Disturb → Alarms & other interruptions → tắt **Alarms**. (2) `adb shell cmd notification set_dnd off`. (3) Schedules → Sleeping: Start time 12:00 PM (để giờ hiện tại nằm trong lịch), tắt "Alarm can override end time", Do Not Disturb behavior → Create custom settings → bật **Alarms**, bật "Use schedule". Kiểm `dumpsys notification`: `mConsolidatedPolicy` có `PRIORITY_CATEGORY_ALARMS`, `mConfig=allow(alarms=false…)`. (4) Chế độ im lặng, lượt S2-3 trễ 1 ph, khoá máy. Log `…145658-S2-3` | Kỳ vọng: PASS (hoặc tối đa WARN "có thể bị DND chặn (policy mặc định)"). Thực tế: `muted=false, alarmVol=6, zen=2, zenAlarms=false`, âm phát, rung `running`, FSI hiện trên keyguard. Tóm tắt lại **FAIL — không nghe được: Không làm phiền chặn báo thức** và tự mâu thuẫn ("đủ điều kiện hiện: không" cạnh "màn báo thức hiện trên màn khoá: có"). Trên máy thật, ca này rơi vào lượt qua đêm (S2-9, S1 A/B) khi lịch/chế độ ngủ đang bật. Giao thức S2 bước 7 sẽ dẫn người chạy ghi "mặc định chặn báo thức", và designer có thể kết luận sai "GO có điều kiện". Số liệu emulator cho designer: ca **thật sự chặn** (M-DND2 `…145128`) thì `muted=true, alarmVol=0`; ca **cho phép** (`…145658`) thì `muted=false, alarmVol=6`. Trên Android 14 AOSP, `muted`/`alarmVol` phản ánh đúng policy hợp nhất trong cả hai ca, còn `zenAlarms` sai ở ca thứ hai. Đề xuất (designer chốt): chỉ coi `zenAlarms=false` là lý do FAIL khi `muted=true` hoặc `alarmVol=0`; ngược lại hạ thành WARN/ghi chú "policy mặc định chặn báo thức, chế độ đang bật có thể khác". Áp dụng cùng logic cho `VibrationEvidence.BLOCKED` và `notifHiddenBy`. Nếu muốn đọc policy hợp nhất bằng API, phải kiểm tài liệu chính thức trước (không suy diễn). Cần xác nhận `isStreamMute` trên OEM ở máy thật. Ghi cho T22: thẻ "Sẵn sàng" không được chỉ dựa vào `getNotificationPolicy()` |
| L2-2 | minor — `RunAnalyzer.gapAt` (nhãn khoảng trống) | `serviceAlive` của một khoảng trống chỉ xét "có sự kiện sống bên trong và process không chết", **không** xét `svc_destroy`. Ở `…151900-S1-X`, sự kiện `battery` lúc +0:00:01 (trước khi bấm nút giả lập) làm khoảng trống thưa 9 phút (+0:00 → +9:00) được ghi "WARN (service sống, không nhận vị trí)". Thực tế service đã bị tắt từ +0:00:37 và suốt 8 ph 23 s sau đó không có service vị trí | Log `…151900-S1-X` (M-FB1), hoặc bất kỳ lượt S1 nào bấm "Tắt service (giữ lượt)" trước khi có fix tươi | Kỳ vọng: "(không thấy service sống)" hoặc tách khoảng trống tại `svc_destroy`. Thực tế: "service sống, không nhận vị trí". Mức không đổi (mức chỉ tính theo độ dài), nhưng ghi sai nguyên nhân: đọc R1/R2/M-WD trên máy thật sẽ quy cho FLP thay vì service chết. Đề xuất: `liveInside` bỏ qua sự kiện sau `svc_destroy` cùng pid nếu không có `svc_start_cmd` sau đó |
| L2-3 | nit — render lý do | Lượt S2-11 (service bị tắt bằng nút giả lập) ghi lý do "kích hoạt bằng dự phòng (**FLP không giao vị trí đúng hạn**)". Nguyên nhân thật là service vị trí đã chết | `…141619/142059/142415/153952-S2-11`, `…151900-S1-X` | Có dòng "(thông tin) service bị tắt bằng nút giả lập" đi kèm nên đọc được. Đề xuất: khi `ringSvc == "ring"` ghi "(service vị trí không chạy)" |
| L2-4 (= R4-4, xác nhận) | nit — `restartOf` | Process mới do `AlarmRingService` (dự phòng) khởi động bị gắn nhãn "process chạy lại sau 1 ph 29 s **nhưng service không khởi động**", trong khi service báo thức có chạy và kêu đủ 5 phút | `…153952-S2-11` (M-FB3: nút giả lập → `adb shell am kill app.napstop.probe` → chờ dự phòng) | Như reviewer mô tả. Đề xuất: "process chạy lại sau X (service báo thức dự phòng), service vị trí không khởi động" khi có `alarm_trigger svc=ring` sau `proc_start` |
| L2-5 | nit — tài liệu giao thức S2-11 | Sau "Bắt đầu S2" của S2-11, app hiện hộp thoại **"Thiếu quyền"** (thiếu Vị trí nền, đúng thiết kế). Hộp thoại che nút "Tắt service (giữ lượt)", nhưng giao thức không nói phải bấm OK. Lần chạy đầu, tester (script) khoá máy khi hộp thoại còn mở, nên lượt `…141619` bấm nút muộn (+1:20 thay vì "ngay sau khi bắt đầu") | `docs/test-protocols/S2.md` Phần 3, dòng S2-11 | Thêm "bấm **OK** ở hộp thoại Thiếu quyền (Vị trí nền), cuộn xuống mục Lượt đang chạy" trước bước bấm nút |

Ghi chú, không phải lỗi:
- **Đường dự phòng trên Android 14 emulator:** `systemExempted` thành công ở cả 6 lượt ring (không lượt nào phải lùi về `mediaPlayback`).
  Cả hai ca đều kêu: process còn sống (cached) và process đã bị giết (M-FB3, process mới khởi động từ exact alarm). Thông báo FGS có FSI
  bật màn hình trên keyguard như đường chính. Trễ dự phòng ổn định 60,05–60,67 s.
- `kill -9` khi `AlarmRingService` đang kêu: thông báo id 2 bị hệ thống gỡ cùng process (là thông báo FGS), không để lại thông báo "mồ côi".
  Đây là điểm khác đường `ProbeService` (lượt sau tự dọn).
- Lượt `…150503-S1-A` không hợp lệ do tester rút sạc sau khi bắt đầu. Lượt này chỉ dùng như bằng chứng phụ cho "bỏ qua 1 vị trí cũ"; chấm M00
  bằng `…154832-S1-A`.

## Phần chưa chạy được & lý do

Như Lần 1 (cần **máy thật**: S1 lượt A/B 10 giờ, R1/R2 trên OEM, nghe/rung thật, S2-6 OEM, S2-8, S2-9, S2-10, FSI Android 15/16, màn khoá
PIN/AOD). Thêm phần của vòng 4:
- **S2-11 trên mọi máy thật** (điều kiện để giữ ADR-001): emulator chỉ chứng minh `systemExempted` chạy được trên AOSP 14. Chưa biết OEM
  (Xiaomi/Oppo/Vivo/Samsung) có chặn khởi động FGS từ exact alarm khi app đã bị "dọn" hoặc khi có force-stop không. Force-stop huỷ luôn exact
  alarm, nên ca đó không có lưới an toàn (giới hạn đã biết của Android, không phải lỗi probe).
- **L2-1 trên Android 15/16 có "Chế độ" (Modes):** cần đo `muted`/`alarmVol`/`zenAlarms` khi chế độ "Ngủ"/"Bedtime" bật với policy khác
  DND mặc định, để designer chốt quy tắc.
- Ca "mọi kiểu FGS lỗi" của `AlarmRingService`: không tái hiện được trên emulator.

Trạng thái emulator sau khi chạy: đã tắt (`adb emu kill`, không còn tiến trình `emulator`/`qemu`). Vòng lặp `geo fix` đã dừng. AVD
**`napstop_api34`** được giữ lại, trạng thái trong AVD: probe đã cài (APK vòng 4) và đủ quyền (Vị trí "Luôn cho phép" đã cấp lại), DND tắt và
chính sách mặc định cho phép Báo thức, lịch "Sleeping" về mặc định, `dumpsys battery reset`, chuông im lặng (như cuối Lần 1), khoá vuốt
bật. Không đụng `amomi_api34`. Log chưa commit.

Trạng thái đề xuất: **changes-requested**. Designer chốt lại quy tắc `zenAlarms` (L2-1) trong S2 V4-2, coder sửa `RunAnalyzer` (và
`AlarmPlayer` nếu đổi nguồn dữ liệu). L2-2 … L2-5 tuỳ chọn. Sau khi sửa, tester chạy lại M-DND2 và M-DND3 (`…145658`, khoảng 10 phút gồm
cài lịch) cùng S2-3 mặc định trên emulator. Các phần khác của vòng 4 không cần chạy lại.

---

# Test report S1-S2 (emulator smoke test của app thí nghiệm) — Lần 3

Kết luận: **PASS (còn phần chờ máy thật)**. Đã chạy toàn bộ mục thủ công của V5-8.2 (M-DND2, M-DND3, M-DND4, M-DND5, M-OLD, M-S2-11)
và mọi "Ghi chú cho tester" của review vòng 5 (#1–#7, #9), tất cả **đạt**. L2-1 không còn: M-DND3 chạy lại ra **PASS** với
`zenAlarmsActive=true`, khớp `mConsolidatedPolicy` của `dumpsys notification`. M-DND4 (mặc định cho phép, lịch chặn) ra **FAIL đúng**. Ở
ca này luồng báo thức **bị tắt tiếng thật** trên AOSP 14. 6 lượt có `zen=2` đều có `zenAlarmsActive` khác `null` và không lượt nào có
`zenActiveErr`. Không có lỗi mới của probe.

Môi trường: như Lần 2. Windows 11 Home 10.0.26200, Git Bash, AVD **`napstop_api34`** (Android 14, SDK 34, `UE1A.230829.050`),
`emulator-5580`, headless, WHPX, `-no-snapshot`. Không đụng `amomi_api34`.
- APK: `spikes/android-probe/app/build/outputs/apk/debug/app-debug.apk` (vòng 5), build 16:39, 3 459 023 byte,
  md5 `0436fe49885c6d6a8cfbb45a4e66f226`. **Không build lại.** Lúc bắt đầu (16:46), `find app/src -newer app-debug.apk` rỗng.
  `classes3.dex`/`classes4.dex` có chuỗi `zenAlarmsActive`/`zenActiveErr`. `adb install -r` → `Success`.
  Lượt đầu tiên đã có cả hai khoá (ghi chú tester #1).
- **Lưu ý:** trong buổi chạy, `RunAnalyzer.kt` và `RunAnalyzerTest.kt` được sửa **sau** thời điểm build APK (coder làm song song;
  `find -newer` lúc 17:30 liệt kê hai file này). Mọi tóm tắt dưới đây là của analyzer **trong APK 16:39**, tức bản vòng 5 đã APPROVE.
  Nếu bản sửa mới chạm `analyzeAlarm`/`render`, cần render lại các log Lần 3 bằng analyzer mới (log đã lưu đủ, xem "Phần chưa chạy").
- Unit test: **không chạy lại** (không build để tránh đụng thay đổi song song). Số liệu unit 104/104 của vòng 5 lấy từ review.
- Vị trí: luồng giả `adb emu geo fix` mỗi 3 s quanh toạ độ tổng hợp (10.00xx°, 10.00xx°), không phải địa điểm thật. Khoá vuốt bật.
- Cách xác minh "kêu" giống Lần 1–2: `dumpsys audio`, `vibrator_manager`, `power`, `window`, `notification`, `activity services`.
- DND: `cmd notification set_dnd off|priority|none|alarms`. Policy mặc định ("Alarms & other interruptions → Alarms") và lịch "Sleeping"
  (Start time, "Alarm can override end time", Do Not Disturb behavior → custom/default, "Use schedule") đổi qua Settings bằng uiautomator.
  Chuông: bảng âm lượng SystemUI.
- Thao tác UI dùng script uiautomator. Mỗi lần dump mất khoảng 3–5 s, xem ghi chú ở dòng M-S2-11.

## Kết quả

9 lượt mới, log ở `spikes/results/emulator/runs/20261029-165026-S2-1` … `…172645-S2-3`. `orphan.jsonl` được cập nhật: 50 dòng đầu giống
hệt bản Lần 2, thêm 10 dòng mới. Lượt nào cũng dùng trễ 1 phút, trừ S2-11 (2 phút, đúng giao thức).

| Test case | Tầng | Kết quả | Ghi chú (runId, bằng chứng) |
|---|---|---|---|
| Ghi chú tester #1: APK vòng 5, có khoá mới | thủ công | **PASS** | `…165026-S2-1` `alarm_sound_start` có `"zenAlarmsActive":null,"zenActiveErr":null` (`zen=1`) |
| **S2-1 hồi quy** (chuông NORMAL, không DND, khoá) | thủ công | **PASS** | `…165026-S2-1`: `src=fix` +5 s, `alarm_ui_shown viaFsi=true`, `mWakefulness=Awake`, focus `AlarmActivity` + `isKeyguardShowing=true`, player `USAGE_ALARM state:started`, rung `Usage=ALARM running`. Tóm tắt "… · DND ALL · chuông NORMAL · tắt sau 17 s (activity)", **PASS**. Dòng DND không có ngoặc báo thức (ghi chú #7) |
| **M-DND hồi quy** (`set_dnd none`, im lặng) | thủ công | **PASS** (tóm tắt FAIL đúng) | `…165444-S2-3`: `muted=true alarmVol=0 zen=3 zenAlarms=null zenAlarmsActive=null`. `STREAM_ALARM Muted: true`, muted streams `0x9be` (có ALARM), player `mutedState:appOps`, rung `ignored_app_ops`, `Asleep`, không FSI. Tóm tắt "… DND NONE …" (không ngoặc) → **FAIL — không nghe được: luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền: hoàn toàn tắt tiếng; không có màn báo thức/thông báo** |
| **M-DND5** (mặc định cho phép, `set_dnd priority`, im lặng) | thủ công | **PASS** | `…170046-S2-3`: `muted=false alarmVol=6 zen=2 zenAlarms=true zenAlarmsActive=true`, `zenActiveErr=null`. `mConsolidatedPolicy` có `PRIORITY_CATEGORY_ALARMS`. Kêu, rung `running`, `Awake`, `AlarmActivity` trên keyguard. Tóm tắt "DND PRIORITY (báo thức: cho phép)" → **PASS** |
| **M-DND2** (mặc định **chặn** Alarms, `set_dnd priority`, im lặng) | thủ công | **PASS** (tóm tắt FAIL đúng) | `…170328-S2-3`: `muted=true alarmVol=0 zen=2 zenAlarms=false zenAlarmsActive=false`, `zenActiveErr=null`. `mConfig=allow(alarms=false…)`, `mConsolidatedPolicy` **không** có ALARMS. `STREAM_ALARM Muted: true`, muted streams `0x1b6` (có ALARM), player `mutedState:appOps`, rung `ignored_app_ops`, `Asleep`, focus `NotificationShade` (không FSI). Tóm tắt "TẮT TIẾNG (…) · rung: bị Không làm phiền chặn · … đủ điều kiện hiện: không (Không làm phiền chặn) · màn báo thức: không hiện · DND PRIORITY (báo thức: chặn)" → **FAIL — không nghe được: luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền chặn báo thức; không có màn báo thức/thông báo** |
| **M-DND3** chạy lại (L2-1): mặc định **chặn**, DND tắt tay, lịch "Sleeping" đang bật (12:00 PM → 7:00 AM, không "Alarm can override", custom **Alarms: allow**) | thủ công | **PASS** | `…170753-S2-3`: `muted=false alarmVol=6 zen=2 zenAlarms=false` **`zenAlarmsActive=true`**, `zenActiveErr=null`. Đối chiếu `dumpsys notification` (ghi chú #3): `mZenMode=ZEN_MODE_IMPORTANT_INTERRUPTIONS`, `mConsolidatedPolicy` **có** `PRIORITY_CATEGORY_ALARMS`, `mConfig=allow(alarms=false…)`, `EVERY_NIGHT_DEFAULT_RULE state=STATE_TRUE` với `zenPolicy … alarms=allow`. **Log khớp hệ thống.** Kêu: `STREAM_ALARM Muted: false`, muted streams `0x1a6` (không có ALARM), player `started mutedState:none`, rung `running`, `Awake`, `AlarmActivity` trên keyguard. Tóm tắt "âm thanh: đang phát (âm lượng 6/7, focus granted) · rung: đã yêu cầu (không xác minh được) · thông báo: đã gửi, đủ điều kiện hiện: có (FSI: có) · màn báo thức hiện trên màn khoá: có · **DND PRIORITY (báo thức: cho phép; mặc định: chặn)**" → **PASS — (thông tin) cài đặt Không làm phiền mặc định chặn báo thức, chế độ đang bật cho phép**. Lần 2 (`…145658`): FAIL giả |
| **M-DND4** (mới): mặc định **cho phép**, DND tắt tay, lịch "Sleeping" đang bật, custom **Alarms: disallow** | thủ công | **PASS** (tóm tắt FAIL đúng) | `…171148-S2-3`: `muted=true alarmVol=0 zen=2 zenAlarms=true` **`zenAlarmsActive=false`**, `zenActiveErr=null`. Hệ thống: `mConfig=allow(alarms=true…)`, `mConsolidatedPolicy` **không** có ALARMS, rule `zenPolicy … alarms=disallow`. Ghi chú #4, `dumpsys audio`: `STREAM_ALARM Muted: true`, `ringer mode muted streams = 0x1b6 (… STREAM_ALARM …)`, player `USAGE_ALARM state:started mutedState:appOps` (player chạy nhưng bị tắt tiếng). Rung `ignored_app_ops`, `Asleep`, focus `NotificationShade`, không FSI. Tóm tắt "TẮT TIẾNG (luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền chặn báo thức; âm lượng 0/7) · rung: bị Không làm phiền chặn · … đủ điều kiện hiện: không (Không làm phiền chặn) · màn báo thức: không hiện · **DND PRIORITY (báo thức: chặn; mặc định: cho phép)**" → **FAIL — không nghe được: …** Không có info "đối chiếu biên bản nghe" (đúng: luồng tắt tiếng). Ca "`muted=false` mà player bị chặn" **không xảy ra** trên AOSP 14 |
| (ngoài spec) DND "Chỉ báo thức" (`set_dnd alarms`, `zen=4`) | thủ công | **PASS** | `…172645-S2-3`: `muted=false alarmVol=6 zen=4`, `zenAlarms`/`zenAlarmsActive`/`zenActiveErr` = `null`. Kêu, `Awake`, `AlarmActivity`. Tóm tắt "DND ALARMS" (không ngoặc) → **PASS**. Vùng rủi ro: bộ lọc "chỉ báo thức" không bị coi là chặn |
| **M-S2-11** (giao thức đã sửa: OK ở "Thiếu quyền" → "Tắt service (giữ lượt)" ngay; quyền vị trí "Chỉ khi dùng app" bằng `pm revoke … ACCESS_BACKGROUND_LOCATION`, app hiện "Vị trí nền: Chưa cấp"; `set_dnd priority`, im lặng, 2 ph) | thủ công | **PASS** | Hộp thoại "Thiếu quyền" có nút OK. Sau OK, nút "Tắt service (giữ lượt)" bấm được ngay. Lượt chính `…172013-S2-11`: `svc_cmd action=sim_kill` ở **+0:00:11** (≤ 15 s) → `svc_destroy`. Mốc + 60 s: `alarm_ring_fg type=systemExempted ok=true` → `alarm_trigger src=fallback svc=ring lateMs=60222` → `alarm_ui_shown viaFsi=true` → `alarm_sound_start muted=false zen=2 zenAlarmsActive=true`. `AlarmRingService isForeground=true foregroundId=2 types=00000400`. Tóm tắt **WARN — kích hoạt bằng dự phòng (service vị trí không chạy); báo thức trễ 60 s (> 30 s)**, không có "FLP không giao vị trí đúng hạn". Khoảng trống: "(service vị trí đã dừng lúc +0:00:11)" (V5-2, trên log mới). Sau "Tắt báo thức": 0 ServiceRecord, không còn thông báo id 2. Lượt đầu `…171610-S2-11` giống hệt, nhưng `sim_kill` ở +0:00:22 vì script uiautomator chậm (mỗi lần dump 3–5 s), không phải do app. Lượt `…172013` bấm bằng toạ độ cố định nên kịp ≤ 15 s. Đã `pm grant` lại vị trí nền |
| **M-OLD** (6 log cũ, mở tóm tắt trên AVD bằng APK vòng 5) | thủ công | **PASS** | Khớp bảng "Kết quả kỳ vọng" V5-1 và Round 5 của coder, từng chuỗi: `…145658` **WARN** "có thể không nghe được: cài đặt Không làm phiền mặc định chặn báo thức, luồng báo thức không bị tắt tiếng (chưa rõ chế độ đang bật)", "đủ điều kiện hiện: có (FSI: có)", "màn báo thức hiện trên màn khoá: có", "DND PRIORITY (báo thức mặc định: chặn)", không có "đủ điều kiện hiện: không". `…145128` **FAIL** "không nghe được: luồng báo thức bị tắt tiếng, âm lượng báo thức 0, Không làm phiền chặn báo thức", "(báo thức mặc định: chặn)". `…150100` **PASS**, "(báo thức mặc định: cho phép)". `…151900` cả hai khoảng trống "(service vị trí đã dừng lúc +0:00:37)", không còn chuỗi "service sống" ở đâu cả, "kích hoạt bằng dự phòng (service vị trí không chạy)", verdict FAIL (mất vị trí pha dày, như trước). `…153952` dòng Chết "… · process chạy lại sau 1 ph 29 s (service báo thức dự phòng), service vị trí không khởi động · không hồi phục", "Khởi động lại: không". `…141619` **WARN** "kích hoạt bằng dự phòng (service vị trí không chạy)", "báo thức trễ 60 s" |
| V5-8.2: không tóm tắt nào có cùng lúc "đủ điều kiện hiện: không" và "màn báo thức hiện trên màn khoá: có" | thủ công | **PASS** | Đã kiểm 9 tóm tắt mới + 6 tóm tắt cũ. "đủ điều kiện hiện: không" chỉ xuất hiện cùng "màn báo thức: không hiện" (`…165444`, `…170328`, `…171148`, `…145128`) |
| Ghi chú #2 / V5-8.2: mọi lượt `zen=2` có `zenAlarmsActive ≠ null`, không có `zenActiveErr` | grep log | **PASS** | 6/6 lượt `zen=2` (`…170046` true, `…170328` false, `…170753` true, `…171148` false, `…171610` true, `…172013` true), `zenActiveErr=null` ở cả 9 lượt. Trên AOSP 14, đọc `getConsolidatedNotificationPolicy()` không ném lỗi dù app không có quyền truy cập policy |
| Riêng tư (ghi chú #9) | grep | **PASS** | `grep -rlE '"(lat\|lng\|lon\|latitude\|longitude\|alt)"' spikes/results/emulator/runs` rỗng (exit 1). `grep -rlE '10\.00[0-9]{2}'` (giá trị toạ độ đã bơm) rỗng (exit 1). Danh sách khoá JSON của 9 lượt mới + `orphan.jsonl`: không có khoá vị trí (khoá duy nhất chứa "lat" là `lateMs`) |

Số liệu cho designer (V5-1 / R5-1), Android 14 AOSP. Cả 4 tổ hợp "policy mặc định × policy đang áp dụng" đã đo:

| Mặc định (`zenAlarms`) | Đang áp dụng (`zenAlarmsActive`) | `muted` / `alarmVol` | `STREAM_ALARM Muted` | Player | Kêu? | Tóm tắt | runId |
|---|---|---|---|---|---|---|---|
| cho phép | cho phép (DND tay) | false / 6 | false | started, `mutedState:none` | Có | PASS | `…170046` |
| chặn | chặn (DND tay) | true / 0 | true | started, `mutedState:appOps` | Không | FAIL | `…170328` |
| chặn | cho phép (lịch) | false / 6 | false | started, `mutedState:none` | Có | PASS + info | `…170753` |
| cho phép | chặn (lịch) | true / 0 | true | started, `mutedState:appOps` | Không | FAIL | `…171148` |

`muted`/`alarmVol` và `zenAlarmsActive` cho cùng một kết luận ở cả 4 ca. `zenAlarms` (mặc định) sai ở 2 ca có lịch, đúng như phân tích V5-1.
Ca R5-1 cần **cả ba** điều kiện: đọc lỗi, chế độ chặn, luồng không tắt tiếng. Trên AOSP 14 thì không thể xảy ra, vì đọc không lỗi và luồng
có bị tắt tiếng. Chỉ máy OEM mới trả lời được.

Ghi chú, không phải lỗi:
- Policy custom của lịch "Sleeping" có `visualEffects fullScreenIntent=disallow`, nhưng ở M-DND3 (lịch cho phép Báo thức) FSI vẫn hiện
  `AlarmActivity` trên keyguard. Hiệu ứng ẩn chỉ áp lên thông báo **bị chặn**, mà thông báo báo thức được phép đi qua. Đây là số liệu cho
  T16/T22: một chế độ "ẩn toàn màn hình" không chặn màn báo thức nếu chế độ đó cho phép Báo thức (AOSP 14; OEM chưa rõ).
- Ở ca bị chặn (M-DND2/M-DND4), `MediaPlayer` vẫn `state:started` nhưng `mutedState:appOps`. Nếu T16 chỉ dựa vào `isPlaying` thì sẽ
  tưởng là kêu. Bài học cùng loại với lỗi #4 Lần 1 (đã sửa trong probe).
- Mỗi tóm tắt S2 có dòng "(thông tin) lượt S2-x: có sạc" vì emulator luôn báo đang cắm sạc (trừ khi `battery unplug`). Dòng này đúng
  thiết kế, không ảnh hưởng mức.

## Tiêu chí chấp nhận

| Tiêu chí | Đạt? | Bằng chứng (test/log) |
|---|---|---|
| V5-8.1 unit test xanh (U35b/c sửa + U40–U49), B01–B05 | Đạt (theo review, không chạy lại) | Review vòng 5: 104/104 `--rerun-tasks`, 15 quyền, không `INTERNET`/`ACCESS_NOTIFICATION_POLICY`. Tester không build để tránh đụng thay đổi song song |
| V5-8.2 M-DND2 FAIL | Đạt | `…170328-S2-3`, "(báo thức: chặn)" |
| V5-8.2 M-DND3 **PASS** | Đạt | `…170753-S2-3`, `zenAlarmsActive=true` khớp `mConsolidatedPolicy`, "(báo thức: cho phép; mặc định: chặn)" + info |
| V5-8.2 M-DND4 FAIL | Đạt | `…171148-S2-3`, "(báo thức: chặn; mặc định: cho phép)", `muted=true alarmVol=0`, `STREAM_ALARM Muted: true` |
| V5-8.2 M-DND5 PASS | Đạt | `…170046-S2-3`, "(báo thức: cho phép)" |
| V5-8.2 mọi lượt `zen=2` có `zenAlarmsActive ≠ null`, không `zenActiveErr` | Đạt | 6/6 lượt |
| V5-8.2 M-OLD khớp bảng | Đạt | 6/6 log |
| V5-8.2 M-S2-11: `sim_kill` ≤ +0:00:15, WARN "(service vị trí không chạy)" | Đạt | `…172013-S2-11` (+0:00:11) |
| V5-8.2 không có "đủ điều kiện hiện: không" cạnh "màn báo thức hiện trên màn khoá: có" | Đạt | 15 tóm tắt |
| V5-8.3 giao thức S2-11 (bấm OK) + S2-12 | Đạt | Bước OK làm theo được. Giao thức S2-12 (a)/(b) hiện ghi "(báo thức: chặn; mặc định: cho phép)" / "(báo thức: cho phép; mặc định: chặn)", **khớp từng chữ** với tóm tắt thật M-DND4/M-DND3 (R5-2 đã sửa) |
| Hồi quy S2-1, M-DND (ghi chú #7) | Đạt | `…165026-S2-1` PASS "DND ALL"; `…165444-S2-3` FAIL "DND NONE" |
| Riêng tư | Đạt | grep rỗng |

## Lỗi phát hiện

Không có lỗi mới của probe hoặc analyzer trong phạm vi vòng 5. L2-1 đã sửa trên emulator, L2-2 … L2-5 cũng đã sửa (M-OLD, M-S2-11).

| # | Mức | Mô tả | Repro (lệnh/trace/bước) | Kỳ vọng vs Thực tế |
|---|---|---|---|---|
| L3-1 | nit — quy trình (không phải lỗi app) | `RunAnalyzer.kt`/`RunAnalyzerTest.kt` bị sửa **sau** khi build APK 16:39, ngay trong buổi chạy. Kết quả Lần 3 chỉ chứng nhận analyzer của APK 16:39 (vòng 5 đã APPROVE) | `cd spikes/android-probe && find app/src -newer app/build/outputs/apk/debug/app-debug.apk` → 2 file (lúc 16:46 còn rỗng) | Nếu thay đổi đó (có lẽ là R5-1, giao thức S2-12 đã nhắc WARN "không đọc được chính sách …") chạm `analyzeAlarm`/`render`: reviewer xem diff, rồi render lại 9 log Lần 3 + 6 log M-OLD bằng test tạm (như coder đã làm ở Round 5) hoặc trên AVD. Kỳ vọng: không lượt nào đổi mức, vì `zenActiveErr=null` ở mọi lượt |

## Phần chưa chạy được & lý do

Cần **máy thật** (emulator không tính kết quả, S1 §4.6). Danh sách như Lần 2 (S1 lượt A/B 10 giờ, R1/R2 trên OEM, nghe/rung thật, S2-6 OEM,
S2-8, S2-9, S2-10, FSI Android 15/16, màn khoá PIN/AOD, S2-11 trên mọi máy), thêm phần vòng 5:
- **S2-12 (a)/(b) trên Android 15/16 có Chế độ (V5-6).** AVD Android 14 chỉ có lịch DND (Schedules). Cần đo: `zenAlarmsActive` khác
  `null` trên OEM (V5-6.1), có `zenActiveErr` không, và luồng có bị tắt tiếng không khi một Chế độ chặn Báo thức. Đặc biệt là ca **R5-1**:
  đọc lỗi + chế độ chặn + luồng không tắt tiếng. Trên AOSP 14 ca này không xảy ra (bảng 4 tổ hợp ở trên), nên chỉ máy OEM mới trả lời được.
- Chế độ chỉ đổi hiển thị (V5-6.4) và "Chế độ ngủ" riêng của hãng (V5-6.5).
- Máy Android 10 (API 29), nếu có: lịch có policy riêng chặn Báo thức, mặc định cho phép (R5-1 trên API < 30).
- Nghe thật ở M-DND3/M-DND4: emulator không có loa. "Kêu/không kêu" chỉ xác minh bằng `dumpsys audio` (`Muted`, `mutedState`).
- Render lại log Lần 3 bằng analyzer mới nếu L3-1 áp dụng (khoảng 5 phút; log ở `spikes/results/emulator/runs/20261029-16[5-9]*`,
  `…-17*`).

Trạng thái emulator sau khi chạy: đã tắt (`adb emu kill`, không còn tiến trình `emulator`/`qemu`, `adb devices` rỗng). Vòng lặp `geo fix`
đã dừng. AVD **`napstop_api34`** được giữ lại, trạng thái trong AVD: DND tắt (`ZEN_MODE_OFF`), policy mặc định `allow(alarms=true…)`,
lịch "Sleeping" về mặc định (`enabled=FALSE`, 22:00–7:00, `exitAtAlarm=true`, `zenPolicy=null`, `modified=false`), không còn alarm nào
của probe trong hàng đợi, không còn service. Probe cài APK vòng 5, đủ quyền (Vị trí nền đã `pm grant` lại; FSI, thông báo đã cấp). Chuông
im lặng (như lúc bắt đầu; S2-1 tạm đổi NORMAL rồi trả lại), khoá vuốt bật. Không đụng `amomi_api34`. Log chưa commit.

Trạng thái đề xuất: **done** cho phần emulator của vòng 5. S1/S2 vẫn chờ biên bản máy thật để viết "Kết luận"/Go-No-go. L3-1 chuyển
reviewer: chỉ cần xem lại nếu thay đổi song song chạm analyzer.
