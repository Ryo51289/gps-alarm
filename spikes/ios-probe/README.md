# NapStop Probe iOS (spike S3, code bỏ đi)

App iOS thuần Swift (SwiftUI, không Flutter) để đo trên iPhone thật: báo thức **AlarmKit** (iOS 26+) và thông báo
**Time Sensitive** có kêu khi máy khoá / Im lặng / Tập trung không, đặt từ nền nhờ vị trí When In Use; báo dự phòng đặt trước;
vị trí nền 10 giờ. Đây là **code bỏ đi** sau Gate 1: T17 viết lại theo spec riêng. CI (`ci.yml`) không build thư mục này.

| Tài liệu | Nội dung |
|---|---|
| `docs/spikes/S3.md` | Kế hoạch, đặc tả app (§6), đường build không cần Mac (§7), Implementation notes |
| `docs/test-protocols/S3.md` | Giao thức cho người chạy (Windows + iPhone) |

## Cấu trúc

```
spikes/ios-probe/
├── project.yml                  XcodeGen (project/target/scheme NapStopProbe); .xcodeproj sinh trên runner, không commit
├── NapStopProbe/
│   ├── Info.plist               viết tay: UIBackgroundModes=[location], 3 chuỗi quyền, UIFileSharingEnabled
│   ├── App/                     ProbeApp (@main), AppDelegate (proc_start, vòng đời, delegate thông báo)
│   ├── Core/Location/           LocationRecorder (CLLocationManager + CLBackgroundActivitySession), WalkMonitor (CLMonitor, S3-13)
│   ├── Core/Trip/               RunController (lượt, kích hoạt, dự phòng), RunStore (UserDefaults, kịch bản)
│   ├── Core/Alarm/              AlarmKitChannel, ProbeAlarmMetadata, ProbeStopIntent, NotificationChannel,
│   │                            BackgroundAudioProbe (S3-14), ToneFile (Library/Sounds/probe_alarm.wav)
│   ├── Core/Log/                EventLog (JSON Lines), DeviceSnapshot
│   └── UI/                      MainView, RunListView, SummaryView, ShareSheet
└── ProbeCore/                   Swift package thuần (Foundation): FlatJson, IsoTime, TriggerLogic, WavTone, RunAnalyzer + test
```

Target app biên dịch thẳng `ProbeCore/Sources/ProbeCore` (không `import ProbeCore`, không SwiftPM trong Xcode).
Deployment target iOS 26.0, Swift 5 mode, strict concurrency `minimal`. Không có package ngoài, không dùng mạng.

## Build IPA (Windows, không cần Mac)

Dùng MobAI ios-builder (`D:/src/bin/builder.exe`, v0.11.0) + GitHub Actions macOS. `builder.json` ở gốc repo chỉ tới thư mục này;
workflow `.github/workflows/ios-build.yml` phải nằm trên `main` trước lần build đầu.

```bash
cd /d/work/gps-alarm
git status                      # builder đẩy CẢ file chưa commit/chưa track (trừ .gitignore) lên ref ẩn
/d/src/bin/builder.exe ios build    # → dist/<build-id>.ipa; ref refs/ios-builder/jobs/<id> bị xoá khi xong
git ls-remote origin 'refs/ios-builder/*'   # phải rỗng sau build
```

Trên runner: bước "Generate Xcode project (XcodeGen)" chạy `brew install xcodegen && xcodegen generate` trong
`spikes/ios-probe` (vì có `project.yml` và không có `.xcodeproj`), rồi `xcodebuild … -scheme NapStopProbe -configuration Debug
-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` và đóng gói `.app` thành IPA **không ký**.
Cài lên iPhone: ký lại bằng Apple ID miễn phí (MobAI hoặc Sideloadly) — xem `docs/test-protocols/S3.md` Phần 0.

Mỗi build tốn ~4–7 phút macOS (tính tiền theo phút, dùng chung phần miễn phí với `ci.yml`): gom thay đổi rồi mới build.
Workflow có `timeout-minutes: 90` và không có `concurrency` (giữ nguyên template): theo dõi tab Actions, **huỷ tay nếu một build
chạy quá 20 phút**, và không chạy hai build song song.

## Test phần thuần (ProbeCore)

Cần Swift toolchain (Swift cho Windows, WSL2 Ubuntu, hoặc Docker `swift:6.0`):

```bash
cd /d/work/gps-alarm/spikes/ios-probe/ProbeCore
swift build && swift test       # U1–U16 (docs/spikes/S3.md §9.1)
# Docker (khi Docker Desktop đang chạy):
docker run --rm -v "D:/work/gps-alarm/spikes/ios-probe/ProbeCore:/pkg" -w /pkg swift:6.0 swift test
```

## Log

- `Documents/runs/<runId>/events.jsonl`: JSON Lines phẳng, `runId` = `yyyyMMdd-HHmmss-<kịch bản>-<kênh>`;
  `Documents/runs/orphan.jsonl`: sự kiện ngoài lượt (`proc_start`, thử nhanh S3-0).
- **Không có toạ độ**: `FlatJson.encode` từ chối khoá `lat/lng/lon/latitude/longitude/alt/altitude/coordinate`. Toạ độ chỉ nằm trong
  bộ nhớ (khoảng cách giữa hai fix, tâm vùng đi bộ S3-13). App không dùng mạng.
- Lấy ra: trong app **Xem kết quả → lượt → Chia sẻ log / Chia sẻ tóm tắt**; hoặc app **Apple Devices** trên Windows → Tệp →
  NapStop Probe → kéo thư mục `runs` (nhờ `UIFileSharingEnabled`). Lưu vào `spikes/results/ios-<yyyyMMdd>-<model>/runs/`.
- `os.Logger` subsystem `app.napstop.probe` in đúng các dòng đó (xem trực tiếp qua MobAI khi cắm cáp).
