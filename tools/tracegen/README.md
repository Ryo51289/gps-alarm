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
| `seed`, `noiseSeed` | int `[0, 2^53)`; `noiseSeed` tuỳ chọn, mặc định = `seed` (chuyển động dùng `seed`, cảm biến dùng `noiseSeed`) |
| `startTime` | `YYYY-MM-DDTHH:MM:SSZ` |
| `sampleIntervalS`, `startDwellS`, `endDwellS` | chu kỳ lấy mẫu (≥ 1), thời gian đứng ở đầu / cuối tuyến (≥ 0) |
| `motion` | `{accelMps2 > 0, decelMps2 > 0, cruiseJitter ∈ [0, 0.5), jitterChunkM ≥ 100}` |
| `speedLimits[]` | `{from: waypoint, kmh ∈ (0, 200], jitter?: bool = true}`; entry đầu là waypoint đầu, `from` theo thứ tự tuyến |
| `stops[]` (tuỳ chọn) | `{at: waypoint (không phải đầu/cuối), dwellS ≥ 2·sampleIntervalS}` |
| `regularStops` (tuỳ chọn) | `{everyM ≥ 200, dwellS, marginM ≥ 0}`: trạm đều đặn (buýt), bỏ trạm gần đầu/cuối/đích/stop < `marginM` |
| `gpsGaps[]` (tuỳ chọn) | `{at: waypoint, durationS}`: mất GPS từ tick đầu tiên tới `at`; `durationS` chia hết cho chu kỳ |
| `noise` | `{sigmaM, rho ∈ [0, 1), accMinM > 0, speedSigmaMps, speedMissingRate, outlierRate, outlierMinM, outlierMaxM}` |
| `scriptedOutliers[]` (tuỳ chọn) | `{atRemainingM, count ≥ 1, distanceToDestinationM ≥ 0, accM > 0}`: điểm nhảy giả cách đích đúng `d` m |
| `cases[]` | `{id, status?: draft, config: {mode: distance|time, thresholdM|thresholdMin, preAlert?: true}, expect: [{event, notBefore: {anchor, offsetS?}, notAfter: {…}, ref}], forbid: [event]}` |

Anchor: `start`, `end`, `arrival`, `overshoot`, `gpsGap[i].start|end`, `route<=M`, `straight<=M`. Cửa sổ =
`clamp(anchor + offsetS, 0, durationS)`. Key lạ là lỗi (bắt lỗi chính tả); lỗi báo kèm đường dẫn trường, ví dụ
`profiles/x.json: speedLimits[2].from`.

## Thuật toán (tóm tắt spec T02 §5–§6)

1. **PRNG SplitMix64** tự viết (3 stream: chuyển động, nhiễu, outlier). Gauss = Irwin–Hall 12.
2. **Chỉ dùng `+ − × ÷ sqrt`** (IEEE làm tròn đúng) để output giống hệt trên Windows/Linux. `cos` là đa thức Taylor tự
   viết; khoảng cách là xấp xỉ equirectangular. Test `determinism_test.dart` chặn `sin/cos/exp/log/pow/Random` trong `lib/`.
3. **Chuyển động:** lưới 10 m; giới hạn tốc độ × hệ số jitter theo đoạn; dừng (tốc độ 0 + dwell) ở stop; hồ sơ tốc độ
   2 lượt (phanh lùi, tăng tốc tiến); dòng thời gian → trạng thái thật mỗi tick.
4. **Cảm biến:** nhiễu AR(1) mỗi trục, `acc = max(accMinM, 1.5σ·(0.8…1.2))`, tốc độ có thể vắng, outlier ngẫu nhiên và
   có kịch bản, mất GPS = không phát mẫu. Mỗi tick luôn rút đủ số RNG nên thêm gap/outlier không đổi nhiễu tick khác.
5. **Sự thật + mốc:** giờ tới, các lần dừng, gap, outlier, quá trạm, mốc khoảng cách (dọc tuyến, chim bay), mốc thời gian;
   giải anchor của case thành giây.
6. **Ghi file:** GPX + JSON chuẩn tắc, UTF-8 không BOM, LF, số in bằng `toStringAsFixed` với số chữ số cố định.
