# data/stations

Dữ liệu đầu vào của dataset ga/bến offline (`app/assets/stations.json`), dựng bằng
[`tools/stationgen`](../../tools/stationgen/README.md). Thiết kế: [`docs/specs/T24.md`](../../docs/specs/T24.md).
Giấy phép: [`LICENSE.md`](LICENSE.md) (ODbL 1.0, © OpenStreetMap contributors).

| File | Nội dung | Ai sửa |
|---|---|---|
| `query.overpassql` | Truy vấn Overpass (ga tàu, bến xe, ranh giới tỉnh admin_level 4) | Người, rồi `fetch` lại |
| `raw/overpass.json` | Bản chụp thô Overpass, nguyên byte | **Chỉ `fetch`** |
| `raw/fetch-meta.json` | Thời điểm, endpoint, `osmBase`, số byte, toàn văn truy vấn | **Chỉ `fetch`** |
| `provinces.json` | 34 tỉnh/thành sau sáp nhập (NQ 202/2025/QH15) ← 63 tỉnh cũ + biến thể tên | Người |
| `overrides.json` | Sửa tay `drop`/`patch`/`add`, mỗi mục có `reason` + `source` | Người |
| `must_have.json` | Ga/bến bắt buộc phải có (35 ga + 21 bến); mục `waived` = không có trên OSM | Người |
| `fold_vectors.json` | Test vector gập dấu, dùng chung tool + app | Người |
| `BUILD_REPORT.md` | Báo cáo build (tất định) | **Chỉ `build`** |
| `bus_query.overpassql` | Truy vấn trạm dừng xe buýt (T24.3): `highway=bus_stop` ∪ `public_transport=platform`+`bus=yes`, vùng `VN-HN`, `VN-SG` | Người, rồi `fetch --dataset bus` |
| `raw/bus_overpass.json`, `raw/bus_fetch-meta.json` | Bản chụp thô trạm buýt và meta | **Chỉ `fetch --dataset bus`** |
| `bus_overrides.json` | Sửa tay trạm buýt (`drop`/`patch`/`add`, cùng quy tắc `source`; không có `kind`/alias, `add` ghi `"kind": "bus"`) | Người |
| `bus_must_have.json` | Tối đa 10 trạm buýt bắt buộc `{match, province}` (B4) | Người (PO xác nhận) |
| `BUS_BUILD_REPORT.md` | Báo cáo build trạm buýt (tất định) | **Chỉ `build`** |

Trạm buýt (T24.3, `docs/specs/T24.3.md`): `fetch --dataset bus` → `build` (dựng cả hai dataset, ghi thêm
`app/assets/bus_stops.json` + `BUS_BUILD_REPORT.md`) → đọc `BUS_BUILD_REPORT.md` (B1–B4, trạm bị loại, cụm gộp hai chiều đường,
trạm trùng bến, cặp cùng tên 150–300 m) → sửa trên OSM hoặc `bus_overrides.json` → `check`.

Quy trình: `fetch` → đọc `BUILD_REPORT.md` → sửa trên OSM (ưu tiên) hoặc `overrides.json` → `build` → `check` → commit
cùng lúc `raw/`, `overrides.json`, `BUILD_REPORT.md`, `app/assets/stations.json`. CI chỉ chạy `check` (không mạng).

Repo này private nên việc commit ở đây **chưa** đủ nghĩa vụ ODbL §4.6: trước lần phân phối ra ngoài nhóm (T40) phải
công bố `stations.json`, `bus_stops.json` cùng thư mục này ở một repo public riêng (quyết định Q1 của T24), rồi điền
`kStationDataPublicUrl` trong `app/lib/features/destination/data/station_license.dart`.
