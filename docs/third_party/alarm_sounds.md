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
