# fixtures/map_wire — ca dùng chung cho kênh bản đồ MapKit (T23.3)

`cases.json` kiểm hai đầu của kênh `app.napstop/nap_map/<viewId>` (giao thức v1, `docs/specs/T23.3.md` §2) dùng cùng một quy tắc:

- **Dart** (`app/test/core/map/map_wire_test.dart`, MW09):
  - `point`: `decodePoint(input)` hợp lệ đúng như `valid`, giá trị bằng `input`.
  - `state`, `frame`, `creation` có `valid: true`: dựng đối tượng Dart từ `input`, `toWire()` (hoặc `creationParams`) phải bằng `input`.
    Dart chỉ **gửi** ba loại này nên ca `valid: false` chỉ phía Swift kiểm.
- **Swift** (`app/ios/Core/Tests/NapStopIOSTests/MapWireTests.swift`, SW04): `MapWire.coordinate/state/frame/creation(input)` khác `nil`
  đúng khi `valid`, và giá trị khớp `input`.

Schema: `{ "version": 1, "point": [Case], "state": [Case], "frame": [Case], "creation": [Case], "centerEastLimit": {...}, "maxDistance": [...] }`,
`Case = { "name": String, "input": <bất kỳ JSON>, "valid": Bool }`.

MW06b (D11): `centerEastLimit = { "capEast", "eastLimit", "cases": [{ "span", "expect" }] }` kiểm `centerEastLimit` (Dart) và
`MapCameraGuard.centerEastLimit` (Swift); `maxDistance = [{ "distance", "span", "maxSpan", "expect" | null }]` chỉ phía Swift kiểm
(`MapCameraGuard.maxDistance`, chỉ native dùng). Bảng `targetLngSpan = [{ "name", "rect", "height", "width", "viewHeight", "top", "left", "bottom", "right", "expect" | null }]`
(R2-1, R3-1: span lớn hơn của trục ngang và trục dọc) cũng chỉ phía
Swift kiểm (`MapCameraGuard.targetLngSpan`). Chuỗi `"NaN"` thay cho số NaN (JSON không có NaN). So sánh với sai số 1e-9.

Quy tắc ca (để kết quả giống nhau trên Linux và Apple):

- Không dùng số ở chỗ cần `Bool` và ngược lại: Foundation trên Apple bắc cầu `NSNumber` 0/1 sang `Bool`, nên kết quả khác Linux. Ca "sai kiểu"
  của cờ dùng chuỗi hoặc `null`.
- JSON không có `NaN`/`Infinity`: các ca đó nằm trong unit test riêng mỗi bên (MW03, SW01).
- Số nguyên và số thực đều là số (`16` = `16.0`); `v` và `accent` phải là số nguyên.

Ca mới: sửa tay file này (không có generator), chạy cả `flutter test test/core/map` và `test-wsl.sh --filter MapWire`.
