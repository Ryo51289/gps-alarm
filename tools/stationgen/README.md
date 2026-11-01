# stationgen

CLI Dart thuần dựng **dataset ga/bến offline** của NapStop (`app/assets/stations.json`) từ bản chụp OpenStreetMap
(Overpass) đã commit trong [`data/stations/`](../../data/stations/README.md). Thiết kế đầy đủ:
[`docs/specs/T24.md`](../../docs/specs/T24.md).

Dữ liệu © OpenStreetMap contributors, giấy phép **ODbL 1.0** ([`data/stations/LICENSE.md`](../../data/stations/LICENSE.md)).

## Lệnh

Chạy **trong thư mục `tools/stationgen`** (Git Bash trên Windows; Dart của Flutter 3.47.8, Dart 3.13.7):

```bash
cd tools/stationgen
dart pub get
dart run bin/stationgen.dart fetch     # CÓ MẠNG, chạy tay. Mặc định --endpoint https://overpass-api.de/api/interpreter
dart run bin/stationgen.dart build     # offline: ghi ../../app/assets/stations.json + ../../data/stations/BUILD_REPORT.md
dart run bin/stationgen.dart check     # offline (CI): build trong bộ nhớ, so byte 2 file đã commit, kiểm A1–A5
dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test
```

| Lệnh | Tuỳ chọn | Exit |
|---|---|---|
| `fetch` | `--endpoint <https url>`, `--data <dir>` (mặc định `../../data/stations`) | 0; lỗi HTTP/response 1; thiếu `query.overpassql` 65 |
| `build` | `--data <dir>`, `--out <file>` (mặc định `../../app/assets/stations.json`) | 0; không đạt A1–A5 1 (vẫn ghi `BUILD_REPORT.md`, không ghi `stations.json`); dữ liệu vào lỗi 65 |
| `check` | `--data <dir>`, `--out <file>` | 0 khớp và đạt; 1 khác hoặc không đạt; 65 dữ liệu vào lỗi |
| sai cú pháp / không lệnh | | 64 (`--help`: 0) |

`fetch` là lệnh **duy nhất** gọi mạng; `build`/`check`/test/CI không bao giờ gọi mạng (test TC14 chặn `HttpClient`).

## Quy trình làm mới dữ liệu (vài lần mỗi năm)

1. `dart run bin/stationgen.dart fetch` — gửi **đúng 1 request**, không tự thử lại. Gặp 429/504 hoặc `remark`
   (Overpass quá tải/timeout) thì exit 1 và giữ nguyên bản chụp cũ: đợi rồi chạy lại, hoặc dùng một instance khác trong
   [danh sách instance công khai](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances)
   bằng `--endpoint`. Chính sách sử dụng: <https://dev.overpass-api.de/overpass-doc/en/preface/commons.html>.
2. `dart run bin/stationgen.dart build`. Lỗi `E_STALE_OVERRIDE` → dọn `overrides.json` (id không còn trong bản chụp).
   Lỗi `E_PROVINCE_UNRESOLVED` → thêm patch `province`.
3. Đọc `data/stations/BUILD_REPORT.md`: ngưỡng A1–A5, must-have, mục 4 (bị loại), 6 (gần trùng), 7 (đoán loại),
   12 (ga tàu ở Hà Nội/TP. Hồ Chí Minh — rà ga metro lọt lưới).
4. Sửa sai **ưu tiên trên OSM** rồi fetch lại; chỉ khi chưa sửa được mới dùng `overrides.json`.
5. `dart run bin/stationgen.dart check && dart test`, rồi commit **cùng lúc** `raw/`, `overrides.json`, `BUILD_REPORT.md`,
   `app/assets/stations.json`.

Sửa `query.overpassql` thì phải `fetch` lại (`build` báo `E_QUERY_CHANGED`). Không bao giờ sửa tay `raw/*` hay
`app/assets/stations.json`.

## Chính sách nguồn dữ liệu

- Nguồn duy nhất của dataset là OpenStreetMap. `overrides.json` bắt buộc có `reason` và `source` thuộc một trong các dạng
  `survey` (biết trực tiếp tại chỗ), `osm:<type>/<id>@<ngày>` (đã sửa trên OSM, chờ fetch lại), `odbl:<url>`,
  `public-domain:<url>`.
- **Cấm** lấy tên/toạ độ từ Google Maps/Places hay bản đồ độc quyền (điều khoản Google Maps Platform cấm trích xuất, và
  làm hỏng nghĩa vụ ODbL). Tool từ chối `source` chứa `google`, `goo.gl`, `maps.app`.
- Danh sách ga của Đường sắt Việt Nam / bến của các Sở GTVT chỉ dùng để **rà xem còn thiếu gì**, không chép
  (quyết định Q3 của T24).
- Mục must-have thật sự không có trên OSM được đánh dấu `"waived": "<lý do>"` trong `must_have.json` (báo cáo hiện ⚠);
  không được waive `dong hoi` (train) và `my dinh` (coach).

## Đổi code

Đổi code làm đổi output → tăng `version` trong `pubspec.yaml` **và** `kGeneratorVersion` (`lib/src/writer.dart`), rồi
`build`. `lib/src/fold.dart` phải giống hệt `app/lib/core/text/vn_fold.dart`; bảng tiền tố `lib/src/prefixes.dart` phải
giống `app/lib/features/destination/domain/station_query.dart`. Hai bản `foldVi` chạy chung `data/stations/fold_vectors.json`;
bảng tiền tố được so bằng `app/test/features/destination/domain/kind_prefixes_parity_test.dart` (đọc source của tool).
