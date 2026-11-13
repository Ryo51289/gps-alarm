# fixtures/commute — ca dùng chung cho tuyến đi làm (T23.8)

Hai file kiểm cùng một luật ở mọi bản hiện thực của tuyến đi làm (`docs/specs/T23.8.md` §5.2–§5.4, §5.6, §5.6a, D6–D8, D12, D18):

| File | Kiểm | Swift (C1) | Dart (C4) | Kotlin (T23.8.A) |
|---|---|---|---|---|
| `validation_cases.json` | Kiểm tuyến trước khi lưu (`setRoute`) | `CommuteRouteValidator` — CU15, CU16 | `commute_validation.dart` — CD03 | bản Kotlin của validator |
| `trigger_cases.json` | Quyết định tự bật khi có sự kiện vùng | `CommuteTriggerEvaluator` — CU27 (gồm CU01–CU14) | không dùng (Dart không quyết định, D3) | bản Kotlin của evaluator |

Test Swift: `app/ios/Core/Tests/TripRuntimeTests/Commute/CommuteFixtureTests.swift`.

Toạ độ và tên điểm trong file là **giả** (quanh 21,0° B / 105,8° Đ), không phải nơi ở của ai. File sửa tay (không có generator);
sau khi sửa chạy `app/ios/Core/scripts/test-wsl.sh --filter Commute` (và test Dart khi có C4). UTF-8 không BOM, LF.

## Quy tắc chung

- Không dùng số ở chỗ cần `Bool` và ngược lại (Foundation trên Apple bắc cầu 0/1 sang `Bool`).
- `null` = vắng / `nil`. Số nguyên và số thực đều là số JSON.
- Ca mới không được đặt khoảng cách A–B sát ngưỡng (cách ≥ 50 m): `sin`/`cos` của mỗi nền tảng có thể lệch vài ULP.

## `validation_cases.json`

```
{ "version": 1, "base": Route, "cases": [ { "name", "override": Object, "expected": String | null, "requiredSeparationM": Number } ] }
```

- Tuyến của một ca = `base` **gộp sâu** với `override`: khoá là object ở cả hai bên thì gộp đệ quy, còn lại giá trị của `override`
  thay thế (kể cả `null`).
- `Route` = `{ revision, enabled, nameA, nameB, aLat, aLng, bLat, bLng, towardB: Window, towardA: Window, templateTowardB: Template,
  templateTowardA: Template }`.
- `Window` = `{ enabled: Bool, startMinute, endMinute, weekdayMask }` (phút trong ngày giờ địa phương, `[start, end)`; bit0 = Thứ Hai …
  bit6 = Chủ Nhật).
- `Template` = phần của `TripConfigMsg` không có toạ độ: `{ tripId, destinationName, mode: "distance"|"time"|"smart",
  distanceThresholdM, timeThresholdMin, preAlertEnabled, vehicleHint: "train"|"coach"|"bus"|"unknown", soundId, volume,
  engineParamsJson }`. Các trường báo khác (`rampUp`, rung, …) không ảnh hưởng luật, bên đọc tự điền mặc định. Đích của
  `templateTowardB` là B, của `templateTowardA` là A.
- `expected`: lỗi đầu tiên dạng `"<field>: <rule>"` (mã `invalid-config`), `null` = hợp lệ. Thứ tự kiểm: `revision` → `nameA`, `nameB`
  → `aLat`, `aLng`, `bLat`, `bLng` → `towardB`, `towardA` (`startMinute` 0…1439, `endMinute` 1…1440, `order` end > start, `tooShort`
  < 15 phút, `tooLong` > 720 phút, `weekdayMask` 1…127; kiểm cả chiều/tuyến đang tắt) → `templateTowardB`, `templateTowardA`
  (V1–V11 của `TripConfigValidator`, thông điệp gốc có tiền tố `templateTowardX.`; có `simulation` → `simulation: notAllowed`)
  → `route: tooClose`.
- `requiredSeparationM` (**bắt buộc ở mọi ca**, số nguyên, kể cả ca lỗi trước bước D12 — giá trị của tuyến đó): khoảng cách A–B
  tối thiểu D12 (spec §5.6a). Swift/Kotlin tự tính rồi so bằng nhau; Dart không tính (không có bộ đọc `engineParamsJson` của engine)
  mà dùng số này làm đầu vào của `commute_validation`.
  ```
  p        = EngineParamsFactory.fromOverrides(mẫu.engineParamsJson)     // JSON sai / khoá sai miền → mặc định, như engine
  v        = hint(mẫu.vehicleHint, p) / 3.6                             // expectedSpeedKmh{Bus,Train,Coach,Unknown}
  reach(T) = v < p.minSpeedForEtaMps ? 0 : max(0, T − p.etaStopPenaltyS) · v / p.routeFactorPrior
  R(mẫu)   = distance: distanceThresholdM · p.distanceModeFactor
             time:     max(p.arrivedRadiusM, reach(timeThresholdMin · 60))
             smart:    max(slowDistM, p.smartFloorM, reach(p.smartTargetS)),  slowDistM = max(smartTargetS · smartSlowSpeedKmh / 3.6, smartFloorM)
  requiredSeparationM = max(2000, ceil(max(R(templateTowardB), R(templateTowardA)) + 1000))
  ```
  Trường thiếu (ca lỗi V5/V6) tính như 0. Khoảng cách A–B = haversine, bán kính 6 371 008,8 m; `tooClose` ⇔ khoảng cách <
  `requiredSeparationM`. Giá trị mẫu (params mặc định): distance 1000 → 2000; time 10 phút bus → 3686; smart bus → 3686; smart train
  → 8385; smart coach/unknown → 9056.

## `trigger_cases.json`

```
{ "version": 1, "defaults": { "route": RouteT, "state": State, "ctx": Ctx }, "cases": [ Case ] }
Case = { "name", "ids": [String], "route"?: Object, "state"?: Object, "steps": [ Step ] }
Step = { "event": Event, "ctx"?: Object, "expect": Decision, "rejected"?: Bool,
         "expectLastState"?: { "A"|"B": RegionState }, "expectFiredKeys"?: [String] }
```

- `RouteT` = `{ revision, enabled, towardB: Window, towardA: Window }` (bộ quyết định không dùng toạ độ, tên, mẫu). `route` của ca
  **gộp sâu** vào `defaults.route`.
- `State` = `{ revision, lastState: { "A"|"B": RegionState }, lastEventAtMs: { "A"|"B": Number }, firedKeys: [String] }`;
  thiếu điểm trong `lastState` = `unknown`. `state` của ca **gộp nông**: mỗi khoá có mặt thay thế nguyên khoá đó của `defaults.state`
  (vd `"lastState": {}` = mọi điểm `unknown`).
- `Ctx` = `{ utcOffsetS, always, fullAccuracy, servicesEnabled, tripActive, osSupported, processedAt? }`; `ctx` của bước **gộp nông**
  vào `defaults.ctx` (chỉ cho bước đó). `processedAt` (ISO 8601) = giờ xử lý; vắng = đúng giờ sự kiện.
- `Event` = `{ id, state: "inside"|"outside"|"unknown", at: ISO 8601 có múi giờ, giây chẵn, authorizationDenied?: Bool (mặc định false) }`.
  Thời điểm sự kiện = mili giây Unix của `at`; giờ địa phương để đánh giá lấy theo `ctx.utcOffsetS`, **không** theo múi giờ ghi trong `at`.
- `Decision` = `{ "start": "towardB"|"towardA", "dateKey": "yyyy-MM-dd" }` hoặc `{ "skip": SkipReason }` (tên case của
  `SkipReason`, §5.2).
- Các bước của một ca chạy nối tiếp trên cùng `State`: state ra của bước trước là state vào của bước sau. Khi quyết định là `start` và
  bước không có `"rejected": true`, bên chạy ghi nhận chuyến đã bắt đầu thành công (thêm khoá `"<direction>@<dateKey>"` vào `firedKeys`,
  việc của controller — D7); `rejected` = `runtime.start` bị từ chối, không thêm khoá.
- `expectLastState` / `expectFiredKeys`: so sau bước (sau khi ghi nhận `start`). `expectFiredKeys` so cả thứ tự.
- Sự kiện `unknown` (D6, sau review C1 #2) không lệch thứ tự là `skip(notEntry)` và **không** đổi `lastState` lẫn `lastEventAtMs`: `outside →
  unknown → inside` vẫn là vào vùng; trạng thái chưa từng biết + `unknown` → vẫn chưa biết.
- Lệch thứ tự (D18, sau review C1 #3): sự kiện có thời điểm **nhỏ hơn** `lastEventAtMs` của cùng điểm → `skip(outOfOrder)`, state không
  đổi; trừ khi `lastEventAtMs` > giờ xử lý (đồng hồ máy bị chỉnh lùi) thì nhận như thường. Thứ tự: `duplicate` → `outOfOrder` →
  `unknown` → cập nhật state → các bước còn lại. Ca lệch thứ tự phải đặt `ctx.processedAt` ≥ `lastEventAtMs` (mặc định giờ xử lý =
  giờ sự kiện, tức nhỏ hơn bản ghi → rơi vào ngoại lệ).
