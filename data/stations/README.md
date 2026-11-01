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

Quy trình: `fetch` → đọc `BUILD_REPORT.md` → sửa trên OSM (ưu tiên) hoặc `overrides.json` → `build` → `check` → commit
cùng lúc `raw/`, `overrides.json`, `BUILD_REPORT.md`, `app/assets/stations.json`. CI chỉ chạy `check` (không mạng).

Repo này private nên việc commit ở đây **chưa** đủ nghĩa vụ ODbL §4.6: trước lần phân phối ra ngoài nhóm (T40) phải
công bố `stations.json` cùng thư mục này ở một repo public riêng (quyết định Q1 của T24), rồi điền
`kStationDataPublicUrl` trong `app/lib/features/destination/data/station_license.dart`.
