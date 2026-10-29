# NapStop Probe (spike S1 + S2, throwaway)

App Android thuần Kotlin để đo trên máy thật:

- **S1**: foreground service `location` có sống 10 giờ trên Xiaomi/Oppo/Vivo/Samsung không, process bị giết có tự hồi phục
  không (`START_STICKY`, watchdog exact alarm, `BOOT_COMPLETED`).
- **S2**: báo thức `USAGE_ALARM` + full-screen intent có kêu khi khoá máy, im lặng, Không làm phiền không.

Đây là **code bỏ đi** sau Gate 1: T15/T16 viết lại theo spec riêng, không chép nguyên. CI không build thư mục này.

| Tài liệu | Nội dung |
|---|---|
| `docs/spikes/S1.md` §5 | Đặc tả app (manifest, service, log, `RunAnalyzer`) + Implementation notes |
| `docs/spikes/S2.md` §5 | Đường báo thức |
| `docs/test-protocols/S1.md`, `docs/test-protocols/S2.md` | Giao thức cho người chạy trên máy thật |

## Yêu cầu

- JDK 17 (`JAVA_HOME`), Android SDK với platform 36 (`ANDROID_HOME`, máy dev: `D:\work\android-sdk`). Không cần Flutter.
- Toolchain giống `app/`: AGP 9.1.0 (Kotlin tích hợp), Gradle 9.3.1 (wrapper có sẵn), minSdk 26, compile/target 36.

## Lệnh (Git Bash trên Windows)

```bash
export PATH="/d/work/android-sdk/platform-tools:$PATH"     # adb
cd /d/work/gps-alarm/spikes/android-probe
./gradlew :app:testDebugUnitTest                           # unit test JVM (RunAnalyzer, FlatJson, ...)
./gradlew :app:assembleDebug                               # → app/build/outputs/apk/debug/app-debug.apk
adb devices -l                                             # lấy <serial>
adb -s <serial> install -r app/build/outputs/apk/debug/app-debug.apk   # KHÔNG dùng -g
mkdir -p ../results/<yyyyMMdd>-<hang>-<model>
adb -s <serial> pull //sdcard/Android/data/app.napstop.probe/files/runs ../results/<yyyyMMdd>-<hang>-<model>/
adb -s <serial> logcat -d -v threadtime > ../results/<...>/logcat.txt   # tuỳ chọn, ngay sau lượt
```

`//sdcard` (gạch chéo kép) là cố ý: Git Bash (MSYS) đổi `/sdcard/...` thành `C:/Program Files/Git/sdcard/...`. Cách khác:
`MSYS_NO_PATHCONV=1 adb -s <serial> pull /sdcard/... ../results/<...>/` (đích phải là đường dẫn tương đối hoặc `D:/...`, không dùng
`/d/...`). PowerShell/cmd dùng dạng thường `/sdcard/...`.

Nếu máy không có thư mục trên (bộ nhớ ngoài không dùng được), log nằm ở bộ nhớ trong:
`adb -s <serial> exec-out run-as app.napstop.probe tar c files/runs > ../results/<...>/runs.tar`.

Chỉ có bản `debug` (biến thể `release` bị tắt trong `app/build.gradle.kts`).

Nút **"Tắt service (giữ lượt)"** (mục "Lượt đang chạy"): dừng service vị trí nhưng giữ lượt và mọi exact alarm (giả lập service bị
giết mà không tự khởi động lại, không cần root). Dùng cho M-WD và kịch bản S2-11: báo thức dự phòng kêu từ `AlarmRingService`.

## Log

- `runs/<runId>/events.jsonl`: JSON Lines, mỗi dòng một object phẳng; `runId` = `yyyyMMdd-HHmmss-<S1|S2>-<nhãn>`.
- `runs/orphan.jsonl`: sự kiện ngoài lượt (vd `proc_start`, `exit_info` khi không có lượt).
- **Không có toạ độ** (chỉ độ chính xác, tốc độ, provider, tuổi fix, khoảng cách tới fix trước); app không có quyền `INTERNET`.
  Logcat (tag `NapStopProbe`) in đúng các dòng đó.
- Tóm tắt + kết luận tự động (PASS/WARN/FAIL): màn **Xem kết quả** trong app.
