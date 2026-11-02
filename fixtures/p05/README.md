# Transcript P05 (T12 §9 — chép nguyên văn)

Thư mục này chứa khoá hồi quy P05 dùng chung Kotlin (T12) / Swift (T13):

- `manifest.json`: số dòng + SHA-256 của transcript của mọi lượt chính (291), **do test Kotlin sinh**, không sửa tay.
- `samples/*.jsonl`: transcript đầy đủ của 3 lượt mẫu.

Ghi lại (chỉ khi cố ý đổi hành vi, có designer duyệt; ghi lý do vào commit):

```bash
cd app/android && ./gradlew :core-trip:test --tests '*P05ManifestTest*' -Pnapstop.updateP05=true --rerun
./gradlew :core-trip:test --tests '*TraceSuiteTest*' -Pnapstop.dumpTranscripts=true --rerun   # mọi transcript → app/build/core-trip/napstop/transcripts/
```

Phần dưới là bản chép nguyên văn `docs/specs/T12.md` §9.1–§9.5. Spec là chuẩn; khi lệch thì sửa file này cho khớp.

Một lượt = `(trace, case, mode, phase)`. Hai harness phải tạo ra **cùng chuỗi byte**. Transcript kiểm cả engine **và** harness
(osSim, thứ tự tick). Lệch ở `in` nghĩa là lỗi harness; lệch ở `ev`/`v` nghĩa là lỗi engine.

### 9.1 Khoá lượt
- `run = "<traceId>/<caseId>/<mode>"`.
- `mode` = `all` hoặc `policy`. Case có `policyPhaseSweep` dùng `policy-j00` … `policy-j35` (hai chữ số, `j` từ 0) thay cho `policy`.
- Case có `samplingModes` chỉ có các chế độ được khai.
- Bộ fixture hiện tại có **291** lượt (53 × 2 + 5 × 37).

### 9.2 Định dạng file
- JSONL, UTF-8 (chỉ ASCII), mỗi dòng kết thúc bằng `\n`, file kết thúc bằng `\n`.
- Không có khoảng trắng nào ngoài giá trị chuỗi. Khoá đúng thứ tự quy định dưới đây.
- Dòng 1 (header): `{"p05":1,"run":"train_hn_dh/distance_1000/all"}`.
- Mỗi Step **được ghi** (§8.3: không ghi input tới khi đã ENDED) là một dòng:
  `{"t":<tick s>,"in":[…],"ev":[…],"v":{…}}`.
  - `ev`: **bỏ hẳn khoá** khi không có sự kiện.
  - `v`: **chỉ ghi** khi chuỗi `v` khác chuỗi `v` đã ghi gần nhất. Step đầu tiên luôn ghi.
- Dòng mốc kill: `{"t":<kill.t>,"in":["KILL"]}`.

**Mã hoá giá trị:**
- **Mọi thời điểm** (ms epoch) ghi dạng **tương đối** `x − startMs` (số nguyên). Nhờ vậy P06 = trùng từng byte.
- Int/Long: thập phân, có `-` nếu âm, không số 0 đứng đầu, không `+`.
- Bool: `true`/`false`. Null: `null`. Enum: chuỗi `UPPER_SNAKE`.
- Double (chỉ trong file chẩn đoán §9.5): chuỗi 16 chữ số hex **thường** của bit thô.
  - Kotlin: `java.lang.Long.toHexString(java.lang.Double.doubleToRawLongBits(x)).padStart(16, '0')`.
  - Swift: `String(x.bitPattern, radix: 16)`, đệm `0` bên trái cho đủ 16.

**`in`** (mảng, phần tử đầu là mã input):

| Input | Mã hoá |
|---|---|
| `start` | `["START"]` |
| `restore` | `["RESTORE",now,"<STATUS>",firedAtMs\|null,dismissedAtMs\|null]` |
| `LocationFix` | `["FIX",atMs,i]`, `i` = chỉ số 0-based của `trkpt` trong GPX (không ghi toạ độ) |
| `Tick` | `["TICK",atMs]` |
| `BatterySample` | `["BATTERY",atMs,levelPct,charging]` |
| `LocationAvailability` | `["AVAIL",atMs,"<CAUSE>"]` |
| `FallbackScheduled` | `["FB_SCHEDULED",atMs,fallbackAtMs,ok]` |
| `FallbackFired` | `["FB_FIRED",atMs,firedAtMs]` |
| `AlarmSilenced` | `["SILENCED",atMs,silencedAtMs]` |
| `UserAction` | `["USER",atMs,"<ACTION>"]` |

**`ev`** (mảng object theo thứ tự trong Step; khoá `e` đứng đầu, các trường tiếp theo đúng thứ tự T10 §2.3):
```
{"e":"preAlert","atMs":_,"distanceM":_,"etaS":_}
{"e":"alarm","atMs":_,"reason":_,"ringNow":_,"snoozeAllowed":_,"distanceM":_,"etaS":_,"batteryPct":_}
{"e":"snoozed","atMs":_,"untilMs":_}
{"e":"gpsLost","atMs":_,"cause":_,"lastFixAgeS":_}
{"e":"gpsRecovered","atMs":_,"lostForS":_}
{"e":"lowBatteryRisk","atMs":_,"levelPct":_,"availableMin":_,"neededMin":_}
{"e":"overshoot","atMs":_,"pastM":_}
{"e":"arrived","atMs":_,"distanceM":_}
{"e":"fallbackAlarmChanged","atMs":_,"fallbackAtMs":_,"cause":_}
{"e":"samplingPolicyChanged","atMs":_,"policy":{"tier":_,"intervalS":_,"minIntervalS":_,"accuracy":_}}
{"e":"tripEnded","atMs":_,"outcome":_,"endReason":_,"summary":{"startedAtMs":_,"alarmAtMs":_,"alarmReason":_,"dismissedAtMs":_,"snoozeCount":_,"travelledM":_,"vehicleGuess":_}}
```

**`v`** = các trường view **không có dấu (∗)** ở T10 §4.16, trừ `tripId` và `atMs`. Thứ tự:
```
{"phase":_,"gps":_,"locationCause":_,"distanceM":_,"isEstimated":_,"etaS":_,"predictedAlarmAtMs":_,
 "samplingPolicy":{"tier":_,"intervalS":_,"minIntervalS":_,"accuracy":_}|null,"fallbackAtMs":_,"fallbackStatus":_,
 "batteryPct":_,"batteryRisk":_,"preAlertFired":_,"alarmAtMs":_,"alarmReason":_,"alarmRinging":_,"snoozeCount":_,
 "snoozeUntilMs":_,"overshootPastM":_,"outcome":_,"vehicleGuess":_,"travelledM":_,"droppedFixes":_,"wakeAtMs":_}
```
(Viết trên nhiều dòng chỉ để dễ đọc; trong file là một dòng, không có khoảng trắng.)

Ví dụ hai dòng:
```
{"t":0,"in":["START"],"ev":[{"e":"samplingPolicyChanged","atMs":0,"policy":{"tier":"DENSE","intervalS":5,"minIntervalS":2,"accuracy":"HIGH"}},{"e":"fallbackAlarmChanged","atMs":0,"fallbackAtMs":10980000,"cause":"ETA"}],"v":{"phase":"ACQUIRING",…}}
{"t":0,"in":["FB_SCHEDULED",0,10980000,true],"v":{"phase":"ACQUIRING",…,"fallbackStatus":"CONFIRMED",…}}
```

### 9.3 Lượt nào có transcript
- Mọi lượt chính (291), mỗi lượt một transcript.
- **Không** có transcript: lượt khôi phục I8, lượt chạy lại I9, lượt dịch thời gian P06, lượt âm TR36/TR37.

### 9.4 Manifest và mẫu (`fixtures/p05/`)
- `manifest.json` (do Kotlin sinh, không sửa tay):
  ```
  {
    "p05": 1,
    "runs": [
      {"run": "bus_hn_brt01/distance_1000/all", "lines": 812, "sha256": "<64 hex thường>"},
      …
    ]
  }
  ```
  - Thụt lề 2 dấu cách, mỗi lượt một dòng, sắp theo `run` (thứ tự byte), LF, có `\n` cuối file.
  - `lines` tính cả header; `sha256` tính trên toàn bộ byte của transcript.
- `samples/<run với "/" đổi thành "__">.jsonl`: transcript đầy đủ của 3 lượt.
  - `coach_dn_langco_tunnel/distance_1000_gps_lost/all` và `…/policy`: mất GPS, dead reckoning.
  - `coach_gb_phuly_overshoot/distance_1000_fallback_silenced/all`: kill, osSim, RANG, AlarmSilenced, quá trạm kêu lại.
- `README.md`: bản chép nguyên văn §9.1–§9.5. Spec này là chuẩn; khi lệch thì sửa README cho khớp.
- `P05ManifestTest`:
  - tính `lines` và `sha256` của 291 lượt; so với `manifest.json`; so 3 mẫu từng byte;
  - lệch → fail, ghi transcript của lượt lệch vào `build/core-trip/napstop/p05-mismatch/`;
  - với `-Pnapstop.updateP05=true`: ghi lại manifest + mẫu, test đạt; chỉ dùng khi **cố ý** đổi hành vi (designer duyệt), ghi lý do vào
    commit;
  - với `-Pnapstop.dumpTranscripts=true`: xuất cả 291 transcript ra `build/core-trip/napstop/transcripts/`.
- **Quy trình của T13:**
  1. Swift tạo transcript cho mọi lượt, tính `lines` + `sha256`, so với `manifest.json`.
  2. Lượt lệch: diff với mẫu (nếu có) hoặc với transcript Kotlin dump trên máy Windows.
  3. Dòng lệch đầu tiên chỉ ra Step và trường lệch.

### 9.5 File chẩn đoán (khuyến nghị, không chặn)
- Với `-Pnapstop.dumpTranscripts=true`, mỗi lượt có thêm `<run>.diag.jsonl`: mỗi dòng ứng với một dòng Step của transcript, dạng
  `{"t":_,"s":{…}}`.
  - Double ghi hex: `dSmooth`, `dStartM`, `minD`, `ground`, `closing`, `movingTimeS`, `movingDistM`, `cvGuard` (mảng),
    `speedKmh`, `progress`, `alarmMarkerProgress`.
  - Int: `routeDistanceEstM`, `distanceErrorM`, `etaMinS`, `etaMaxS`.
- Dùng để tìm chỗ lệch bit **trước khi** một ngưỡng lật. Không thuộc P05.
