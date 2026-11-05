# Âm báo thức (T16, PO Q3 = A)

| Id (`AlarmSounds`) | Tên hiển thị (T28) | File | Nguồn | Giấy phép |
|---|---|---|---|---|
| `horn` (mặc định, cả `default`) | Còi tàu | `app/android/app/src/main/res/raw/alarm_horn.wav` | Tự sinh bằng `tools/alarm_sounds/generate.py` (hợp âm 3 nốt trầm + hài bậc lẻ, 2 hồi/vòng lặp, ≈ 2,6 s) | CC0 1.0 |
| `bell` | Chuông | `…/raw/alarm_bell.wav` | Tự sinh (các họa âm không điều hoà của chuông gõ, tắt dần, 2 tiếng/vòng lặp, 2 s) | CC0 1.0 |
| `beep` | Bíp | `…/raw/alarm_beep.wav` | Tự sinh (4 tiếng bíp 1 kHz + nghỉ, ≈ 1,4 s) | CC0 1.0 |
| `system` | Âm báo thức của máy | — | `RingtoneManager.getActualDefaultRingtoneUri(TYPE_ALARM)` của máy người dùng | không đóng gói |

- Không dùng bản ghi hay thư viện mẫu nào: cả ba file chỉ cộng các sóng sin trong script (Python chuẩn, không phụ thuộc
  ngoài). Người viết script (dự án NapStop) dành các file này cho phạm vi công cộng theo
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- Định dạng: WAV PCM 16 bit, mono, 22 050 Hz, mỗi file ≤ 120 KB (spec ≤ 200 KB), đầu/cuối có fade ngắn để lặp liền mạch.
  Spec ghi `.ogg`; máy dev không có bộ mã hoá Vorbis nên dùng WAV (MediaPlayer và âm kênh thông báo đều phát được). Đổi sang
  OGG chỉ là đổi đuôi file, tên tài nguyên `alarm_*` giữ nguyên.
- Sinh lại (kết quả giống từng byte): `python3 tools/alarm_sounds/generate.py`.
- PO nghe và duyệt ở bước review (Q3). Muốn thay bằng bản ghi CC0 khác: giữ tên `alarm_horn|bell|beep`, ghi nguồn + link
  giấy phép vào bảng trên.

## Bản iOS (T17.2)

| File | Nguồn | Độ dài | Giấy phép |
|---|---|---|---|
| `app/ios/Runner/Sounds/alarm_horn.wav` | `…/raw/alarm_horn.wav`, nâng lên 44 100 Hz, lặp nguyên vòng 11 lần | 29,149 s | CC0 1.0 (như bản Android) |
| `app/ios/Runner/Sounds/alarm_bell.wav` | `…/raw/alarm_bell.wav`, nâng lên 44 100 Hz, lặp 14 lần | 28,000 s | CC0 1.0 |
| `app/ios/Runner/Sounds/alarm_beep.wav` | `…/raw/alarm_beep.wav`, nâng lên 44 100 Hz, lặp 21 lần | 29,400 s | CC0 1.0 |

- **Định dạng:** WAV PCM 16 bit mono 44 100 Hz, giống âm thử `probe_alarm.wav` đã kêu được qua AlarmKit ở S3 (`WavTone.make`; review T17.2
  #1). AlarmKit `AlertSound.named(_:)` không nêu định dạng/độ dài.
- **Nâng tần số:** nguồn Android 22 050 Hz được nâng ×2 bằng nội suy tuyến tính. Mẫu chẵn giữ nguyên; mẫu lẻ = trung bình (cắt về 0) của
  mẫu đó và mẫu kế, mẫu cuối nối với mẫu đầu để vòng lặp liền.
- **Độ dài:** 28–29,5 s (< 30 s để dùng lại được cho kênh thông báo T17.3). Số vòng = số lớn nhất mà tổng ≤ 29,5 s
  (`docs/specs/T17.2.md` D10). Mỗi file ~2,5 MB.
- **Vị trí:** gốc main bundle (Resources của target Runner).
  - WWDC25 "Wake up to the AlarmKit API" (https://developer.apple.com/videos/play/wwdc2025/230/) và S3 §4.1 ghi: file `.named` nằm ở main
    bundle hoặc `Library/Sounds` của container app.
  - S3 đã thử `Library/Sounds`. Bundle chưa được thử trên máy (AM04).
  - Nếu AM04 không kêu: chép file vào `Library/Sounds` lúc mở app như S3 (`ToneFile.swift`).
- **Sinh lại:** giống từng byte, chỉ cần bash, od, awk, coreutils (không cần ffmpeg/sox): `bash app/ios/scripts/make-alarm-sounds.sh`.
  Kiểm lệch: `bash app/ios/scripts/make-alarm-sounds.sh --check`. Test AU13 của `TripRuntimeTests` chạy lệnh này và tính lại cùng các
  byte bằng Swift.
- **`system`:** trên iOS là âm mặc định của AlarmKit (`AlertSound.default`), không đóng gói.
