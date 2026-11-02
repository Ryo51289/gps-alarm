# tracegen

CLI Dart thuần sinh **trace GPS tổng hợp, tất định** cho Trip Engine của NapStop (Kotlin T12, Swift T13).
Mỗi trace gồm `fixtures/traces/<id>.gpx` (chuỗi mẫu vị trí) và `fixtures/traces/<id>.expect.json` (sự thật của
chuyến, mốc khoảng cách/thời gian, case kỳ vọng). Định dạng hai file (hợp đồng cho consumer):
[`fixtures/traces/README.md`](../../fixtures/traces/README.md). Thiết kế đầy đủ: [`docs/specs/T02.md`](../../docs/specs/T02.md).

Dữ liệu **hoàn toàn tổng hợp**: toạ độ chỉ là ga, bến, nút giao công cộng (OpenStreetMap, ODbL) hoặc điểm ước lượng;
không có hành trình thật nào.

## Lệnh

Chạy **trong thư mục `tools/tracegen`** (Git Bash trên Windows; Dart của Flutter 3.47.8, Dart 3.13.7):

```bash
cd tools/tracegen
dart pub get
dart run bin/tracegen.dart list                                  # <id> <vehicle> <route>
dart run bin/tracegen.dart generate --profile train_hn_dh        # mặc định --out ../../fixtures/traces
dart run bin/tracegen.dart generate --all
dart run bin/tracegen.dart check                                 # so byte fixture đã commit với generator
dart run bin/tracegen.dart validate --dir ../../fixtures/traces  # kiểm cấu trúc GPX + expect
dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test
```

| Lệnh | Tuỳ chọn | Exit |
|---|---|---|
| `list` | `--data <dir>` (mặc định `data`) | 0; dữ liệu lỗi 65 |
| `generate` | `--profile <id>` (lặp được) hoặc `--all`; `--out <dir>`; `--data <dir>` | 0; profile không có 64; dữ liệu lỗi 65 |
| `check` | `--out <dir>`, `--data <dir>` | 0 khớp hết; 1 có file khác/thiếu/thừa |
| `validate` | `--dir <dir>` hoặc danh sách file | 0 hợp lệ; 1 có lỗi |
| sai cú pháp / không lệnh | | 64 (`--help`: 0) |

## Thêm hoặc sửa trace

1. Thêm/sửa lộ trình `data/routes/<route>.json` và hồ sơ `data/profiles/<id>.json` (viết UTF-8 trong editor; không
   truyền tiếng Việt qua tham số dòng lệnh).
2. `dart run bin/tracegen.dart generate --profile <id>` (hoặc `--all`).
3. `dart run bin/tracegen.dart check && dart run bin/tracegen.dart validate --dir ../../fixtures/traces && dart test`.
4. Commit **cả** profile/route **lẫn** fixture sinh ra. Không bao giờ sửa tay file trong `fixtures/traces/`.

Đổi code generator làm đổi output → tăng `version` trong `pubspec.yaml` **và** `kGeneratorVersion`
(`lib/src/expect_writer.dart`), rồi `generate --all`.

## Lộ trình `data/routes/<id>.json`

```json
{
  "id": "road_dn_langco",
  "title": "Bến xe Trung tâm Đà Nẵng → Lăng Cô qua hầm Hải Vân",
  "attribution": "Toạ độ có nguồn osm:*: © OpenStreetMap contributors, ODbL 1.0",
  "waypoints": [
    {"id": "bx_trung_tam_da_nang", "name": "Bến xe Trung tâm Đà Nẵng", "lat": 16.0550100, "lng": 108.1733575, "source": "osm:way/256668716"},
    {"id": "hoa_khanh", "lat": 16.0760, "lng": 108.1500, "source": "approx"}
  ]
}
```

- `id` = tên file, mẫu `^[a-z0-9]+(_[a-z0-9]+)*$`; waypoint `id` duy nhất; `name` tuỳ chọn.
- `source`: `osm:(node|way|relation)/<số>` (toạ độ tra từ OSM) hoặc `approx` (điểm uốn ước lượng).
- `lat ∈ [−90, 90]`, `lng ∈ [−180, 180)`, hai waypoint liền nhau cách ≥ 1 m. Lộ trình là polyline thô (nối thẳng).

## Hồ sơ `data/profiles/<id>.json`

| Key | Ý nghĩa |
|---|---|
| `id`, `title`, `vehicle` | `id` = tên file; `vehicle` ∈ `train`, `coach`, `bus` |
| `route`, `destination` | id lộ trình; waypoint đích (không phải waypoint đầu) |
| `destinationOffsetM` (tuỳ chọn) | int, `|o| ≤ 5000`, mặc định 0: dời đích vuông góc với hướng waypoint liền trước → waypoint đích (dương = bên trái). Đích dời dùng cho `destination.lat/lng`, khoảng cách chim bay, `straight<=`, quá trạm, điểm nhảy giả; đại lượng dọc tuyến vẫn theo waypoint. Sinh thêm `truth.closest` (T11 §4.2) |
| `seed`, `noiseSeed` | int `[0, 2^53)`; `noiseSeed` tuỳ chọn, mặc định = `seed` (chuyển động dùng `seed`, cảm biến dùng `noiseSeed`) |
| `startTime` | `YYYY-MM-DDTHH:MM:SSZ` |
| `sampleIntervalS`, `startDwellS`, `endDwellS` | chu kỳ lấy mẫu (≥ 1), thời gian đứng ở đầu / cuối tuyến (≥ 0) |
| `motion` | `{accelMps2 > 0, decelMps2 > 0, cruiseJitter ∈ [0, 0.5), jitterChunkM ≥ 100}` |
| `speedLimits[]` | `{from: waypoint, kmh ∈ (0, 200], jitter?: bool = true}`; entry đầu là waypoint đầu, `from` theo thứ tự tuyến |
| `stops[]` (tuỳ chọn) | `{at: waypoint (không phải đầu/cuối), dwellS ≥ 2·sampleIntervalS}` |
| `regularStops` (tuỳ chọn) | `{everyM ≥ 200, dwellS, marginM ≥ 0}`: trạm đều đặn (buýt), bỏ trạm gần đầu/cuối/đích/stop < `marginM` |
| `gpsGaps[]` (tuỳ chọn) | `{at: waypoint, durationS}`: mất GPS từ tick đầu tiên tới `at`; hoặc `{atStop: stop, offsetS, durationS | until}`: bắt đầu `offsetS` giây sau khi tới một stop khai báo trong `stops[]` (phải còn đang dừng), kết thúc sau `durationS` hoặc ở `until = {anchor, offsetS?}` (anchor tĩnh, không dùng `gpsGap[…]`, `kill`, `closest*`; không kẹp). `durationS`, `offsetS` chia hết cho chu kỳ; các gap theo thứ tự thời gian, không chồng/chạm |
| `noise` | `{sigmaM, rho ∈ [0, 1), accMinM > 0, speedSigmaMps, speedMissingRate, outlierRate, outlierMinM, outlierMaxM}` |
| `scriptedOutliers[]` (tuỳ chọn) | `{atRemainingM, count ≥ 1, distanceToDestinationM ≥ 0, accM > 0, side?: behind}`: điểm nhảy giả cách đích đúng `d` m; `behind` = phía xe (T02), `beyond` = bên kia đích (T11 §4.4) |
| `dropSpeedAtStops` (tuỳ chọn) | bool, mặc định `false`: bỏ `napstop:spd` ở mọi mẫu lúc xe đang dừng (đầu tuyến, ga giữa, đích); vị trí, `acc` và nhiễu các tick khác giữ nguyên |
| `cases[]` | xem dưới |

**Case** (định dạng ghi ra và ngữ nghĩa: [`fixtures/traces/README.md`](../../fixtures/traces/README.md) §3.1):

```
{id, status?: draft, testIds?: ["TRxx"], config, samplingModes?, policyPhaseSweep?: false, expect: [...], expectAfter?,
 expectFallback?, killSweep?, expectOutcome?, expectSummary?: {vehicleGuess}, forbid: [event], forbidMatch?, forbidAfter?}
config: {mode: distance|time|smart, thresholdM (200..10000) | thresholdMin (5..60) | (smart: không có), preAlert?: true,
         vehicleHint?, params?: {tên: số}, battery?: [{t, levelPct, charging}], actions?: [{at, action}], kill?: At,
         relaunch?: {at, fallbackStatus}, osDismiss?: {offsetS}, osSim?, osRingMaxS?}
expect[]:       {event, reason?, ringNow?, cause?, notBefore: {anchor, offsetS?}, notAfter: {…}, ref}
expectAfter[]:  {event, reason?, ringNow?, cause?, after: At, withinS: [lo, hi], ref}
expectFallback: {modeAt: {anchor, offsetS?}, toleranceS: [lo, hi], ref}       -- cửa sổ tính theo T11.1 §4 (T10.2)
killSweep:      {from: At, everyS, notAfter: At, earlyFrom: At, statsOnly?: false}   -- T11.1, T10 §8.1-6
forbidMatch[]:  {event, reason?, ringNow?, cause?};  forbidAfter[]: {event, reason?, ringNow?, cause?, after: At}
At:             {t} hoặc {anchor, offsetS?}
```

Anchor tĩnh: `start`, `end`, `arrival`, `overshoot`, `gpsGap[i].start|end`, `route<=M`, `straight<=M`, `closest`,
`closest.departT`, `kill`; anchor chạy (chỉ biết khi chạy engine): `event:<tên>`, `relaunch`, `osFallbackFired`. Cửa sổ `expect` =
`clamp(anchor + offsetS, 0, durationS)` (v1); `At` tĩnh được giải thành `t = anchor + offsetS` (không kẹp, phải trong
`[0, durationS]`), anchor chạy ghi nguyên. Trong `actions[].at` và `relaunch.at`, anchor chạy cần `offsetS ≥ sampleIntervalS`
(lỗi khi nạp profile; `expectAfter`/`forbidAfter` thì được dùng `offsetS ≤ 0`). `status: final` cần `testIds`. Trong khoá mới, `t`/`offsetS` chia hết cho chu kỳ. Kiểm
nhất quán (trùng `expect`, `forbid`/`forbidMatch`/`forbidAfter` mâu thuẫn, bộ lọc sai sự kiện, anchor sai chỗ…) theo T11 §5.2.
Key lạ là lỗi (bắt lỗi chính tả); lỗi báo kèm đường dẫn trường, ví dụ `profiles/x.json: speedLimits[2].from`.

Khoá T11.1 (spec [`docs/specs/T11.1.md`](../../docs/specs/T11.1.md) §2–§3; cùng quy tắc ở `validate`):

| Khoá | Cú pháp, ràng buộc |
|---|---|
| `policyPhaseSweep` | bool (V1), chỉ ghi ra fixture khi `true`. `true` không đi cùng `samplingModes: ["all"]` (V2) hoặc action `batteryMaxSaving` (V3); `samplingSparseIntervalS` hiệu lực (`config.params` hoặc 180) phải chia hết cho `sampleIntervalS` (V4) |
| `killSweep` | đủ `from`, `everyS`, `notAfter`, `earlyFrom`; `statsOnly` tuỳ chọn; khoá lạ là lỗi (V5). `from.t ≥ sampleIntervalS`, kiểm sau khi giải anchor (V6). `everyS` int > 0, bội số của chu kỳ (V7). `statsOnly` bool, chỉ ghi khi `true` (V8). Ba `At` là anchor tĩnh trừ `kill` (V9), `t` đã giải trong `[0, durationS]`. Không đi cùng `config.kill`, `config.relaunch`, `config.osDismiss`, `config.osSim: false` (V10) |
| `expectFallback` | thêm V11: không đi với `params` override 12 tên của công thức (`fallbackLagS`, `fallbackEarlyFrac`, `fallbackEarlyMaxS`, `fallbackNearS`, `fallbackHintSpeedFactor`, `routeFactorPrior`, `expectedSpeedKmh{Train,Coach,Bus,Unknown}`, `etaStopPenaltyS`, `smartTargetS`). Fixture ghi thêm `window.asOfStraightM` (chim bay từ vị trí thật ở `killT − I` tới đích, `floor`) và `window.hintEstimateT` |

Anchor `overshoot` cần `truth.overshoot`: `generate` báo khi giải anchor, `validate` báo trên fixture (V13).

## Thuật toán (tóm tắt spec T02 §5–§6)

1. **PRNG SplitMix64** tự viết (3 stream: chuyển động, nhiễu, outlier). Gauss = Irwin–Hall 12.
2. **Chỉ dùng `+ − × ÷ sqrt`** (IEEE làm tròn đúng) để output giống hệt trên Windows/Linux. `cos` là đa thức Taylor tự
   viết; khoảng cách là xấp xỉ equirectangular. Test `determinism_test.dart` chặn `sin/cos/exp/log/pow/Random` trong `lib/`.
3. **Chuyển động:** lưới 10 m; giới hạn tốc độ × hệ số jitter theo đoạn; dừng (tốc độ 0 + dwell) ở stop; hồ sơ tốc độ
   2 lượt (phanh lùi, tăng tốc tiến); dòng thời gian → trạng thái thật mỗi tick.
4. **Cảm biến:** nhiễu AR(1) mỗi trục, `acc = max(accMinM, 1.5σ·(0.8…1.2))`, tốc độ có thể vắng, outlier ngẫu nhiên và
   có kịch bản, mất GPS = không phát mẫu. Mỗi tick luôn rút đủ số RNG nên thêm gap/outlier không đổi nhiễu tick khác.
5. **Sự thật + mốc:** giờ tới, các lần dừng, gap, outlier, quá trạm, điểm gần nhất (đích ngoài tuyến), mốc khoảng cách
   (dọc tuyến, chim bay), mốc thời gian; giải anchor tĩnh của case thành giây (cả `killSweep`), tính cửa sổ `expectFallback`
   (T11.1 §4: ước lượng theo ETA đúng và theo sàn tốc độ của loại xe).
6. **Ghi file:** GPX + JSON chuẩn tắc, UTF-8 không BOM, LF, số in bằng `toStringAsFixed` với số chữ số cố định.
