# ADR-002 — Thay Google Maps Platform: Apple MapKit trên iOS (PlatformView tự viết), bỏ Places; Android quyết sau

Trạng thái: **Đã chấp nhận (phương án A)**. PO quyết ngày 06/11/2026: Q1 = A (Apple MapKit trên iOS). Q2, Q3, Q5, Q6 theo đề xuất của
designer. Q4 có kết luận ở §13. Bản nháp đầu (cùng ngày) đề xuất phương án B (`flutter_map` + OSM); PO không chọn. B được giữ làm ứng viên cho
Android (§6.3).

Spec thực hiện: `docs/specs/T23.2.md` (gỡ Google), `docs/specs/T23.3.md` (MapKit iOS). Khi ADR được chấp nhận, orchestrator sửa `CLAUDE.md`,
ARCHITECTURE, PRD, PLAN-ios, TASKS theo §8 (task T19.1).

## 1. Bối cảnh

- PO xác nhận ngày 06/11/2026: Google Cloud từ chối tạo thanh toán Maps Platform với thông báo *"Maps Platform unavailable in this region —
  Google Maps Platform services cannot be billed to accounts located in prohibited territories per the Terms of Service."* Tài khoản của PO ở
  Việt Nam.
- Việt Nam nằm trong danh sách "Prohibited Territories" của Maps Platform [GMP-PT]. Điều khoản Maps Platform có mục *"No Use in Prohibited
  Territories. Customer will not distribute or market in a Prohibited Territory any Customer Application(s) that use the Google Maps Core
  Services"* [GMP-TOS]. Trang chính thức không tải được bằng công cụ, nên nguyên văn lấy từ bản chép của bên thứ ba [GMP-TOS-COPY]. Vì vậy
  **mượn tài khoản thanh toán ở nước khác cũng không hợp lệ**. Phải loại mọi dịch vụ cần khoá Maps Platform: Maps SDK, Places API, Geocoding.
- `CLAUDE.md` đang chốt "Bản đồ: Google Maps SDK; … fallback Places Autocomplete". Muốn đổi phải có ADR.
- Ràng buộc: PO ưu tiên **iOS trước** (05/11) và không có Mac. Mã iOS được kiểm bằng typecheck WSL (xtool SDK), CI macOS (Simulator) và iPhone
  của PO khi PO cắm máy (`docs/PLAN-ios.md` §1, §6). Dự án iOS **chỉ dùng Swift Package Manager**: không có `Podfile`, các plugin vào qua
  `FlutterGeneratedPluginSwiftPackage`.

## 2. Hiện trạng phụ thuộc Google (grep `app/`, `.github/`, `docs/` ngày 06/11)

| Nơi | Thành phần | Dùng gì | Mức phụ thuộc |
|---|---|---|---|
| Dart — màn 2 (T23) | `lib/features/destination/presentation/widgets/destination_map.dart` | `google_maps_flutter` (`GoogleMap`, `Marker` kéo được, `Circle`, `onLongPress`, `animateCamera`) | **Cao, nhưng chỉ ở một file.** Có seam `destinationMapBuilderProvider` + `DestinationMapProps`; widget test dùng bản giả |
| Dart — màn 2 | `data/places/{places_client,places_models,session_token}.dart`, `widgets/places_section.dart`, `widgets/google_maps_attribution.dart`, `PlacesEntryRow` (`result_row.dart`), nhánh Places trong `destination_controller.dart` (~60 chỗ), chip "Địa chỉ" (`DestinationFilter.places`), `mapsConfigProvider`, `placesClientProvider`, `placesHttpClientProvider`, `placesRandomProvider` | Places API (New) REST, cần khoá | **Cao.** Gỡ được trọn khối vì Places chỉ chạy khi người dùng chủ động chọn (T23 D5) |
| Dart — ARB | `destinationFilterPlaces`, `destinationPlaces*`, `destinationPlaceResolveFailed`; `destinationCatalogError` và `destinationSearchHint` có nhắc Google/địa chỉ | chuỗi | Trung bình |
| Dart — test | `places_client_test`, `session_token_test`, `destination_places_billing_tester_test`, `config_files_test` (TS42), `source_scan_t23_test`, phần Places trong `destination_controller_test`, `destination_screen_test`, `destination_harness`, `crash_privacy_tester_test` | | Trung bình (chủ yếu xoá) |
| Pigeon | `MapsConfigMsg` + `PermissionHostApi.mapsConfig()` (`pigeons/core_api.dart`, 3 file sinh), `CoreBridge.mapsConfig`, `FakeCoreBridge`, `bridge_samples`, `core_bridge_test` TB01, `core_bridge_tester_test`, `bridge_generated_scan_test` | khoá + định danh app cho header Places | Trung bình. **Gỡ là thay đổi phá vỡ Pigeon** (§9) |
| Pigeon (giữ) | `distancesFromLastKnownM` | vị trí cache của máy, không liên quan Google | Không |
| Android | `MapsConfigReader.kt` (+ `CertFingerprint`), `readMapsConfig` ở `PermissionHostApiImpl`/`PermissionHostApiStub`/`BridgeRegistrar`, test `PermissionFakes`, `T21PermissionTesterTest`; `build.gradle.kts` (`napSecret`, `manifestPlaceholders["mapsApiKey"]`); meta-data `com.google.android.geo.API_KEY`; `secrets.properties.example` | khoá Maps | Thấp – trung bình |
| iOS | `AppDelegate.swift` (`import GoogleMaps`, `GMSServices.provideAPIKey`); `Info.plist` `GMSApiKey`; `Flutter/{Debug,Release}.xcconfig` `#include? "Secrets.xcconfig"`; `Secrets.xcconfig.example`; `DeviceBridge.swift` (`enum MapsConfig`, `mapsConfig()`); `IOSPermissionHostApi.mapsConfig`; gói SPM GoogleMaps qua `google_maps_flutter_ios_sdk10` | khoá + SDK GoogleMaps | Trung bình |
| iOS — script | `ios/scripts/typecheck-wsl.sh` (bước stub GoogleMaps), `typecheck-stubs/GoogleMaps.swift` | typecheck WSL | Thấp |
| CI | `ios-compile.yml:695` `SECRET_VALUES: ${{ secrets.IOS_MAPS_API_KEY }}`; `publish-ci-results.sh` (lọc `GMSApiKey`/`AIza…`) + test | | Thấp. Giữ bộ lọc `AIza…`, vì khoá Firebase cũng có dạng này |
| pubspec | `google_maps_flutter ^2.19.0`, `google_maps_flutter_ios_sdk10 ^2.19.0`, `http ^1.6.0` (chỉ Places dùng) | | Gỡ |
| Màn 8 (T27, T28.3) | `route_back.dart` `routeBackUri` → `https://www.google.com/maps/dir/?api=1&destination=…`, `maps_launcher.dart` | **Google Maps URLs, không cần khoá** [G-URLS] | **Không ảnh hưởng** (§5) |
| Tài liệu | `CLAUDE.md` (Tech stack); ARCHITECTURE §7.1; PRD §3 màn 2, §5; PLAN-ios §3.1, §3.2, §5 T23.1, §5.1, §8 Q5; TASKS T23.1; spec T23; `app/README.md` "Bản đồ & Places"; S5 F8, S5-store-drafts; `docs/test-protocols/T23.md` | | Sửa chữ |

Màn 4 (T26 D5, Q1 = A của T26) **hiện không có bản đồ**. Thực tế chưa có khoá nào, nên mọi bản build hiện đang chạy không bản đồ, không Places
(placeholder `destinationMapUnavailable`).

## 3. Các phương án đã xem

### 3.1 Tiêu chí

Chi phí · điều khoản và attribution · khả dụng ở Việt Nam · chất lượng bản đồ Việt Nam · công sức (nhất là iOS khi không có Mac) · rủi ro
store · quyền riêng tư (tile request không lộ vị trí người dùng quá mức cần) · offline.

### 3.2 Bảng so sánh

| | **(A) Apple MapKit trên iOS — đã chọn** | (B) `flutter_map` (thuần Dart) + tile raster XYZ | (B′) MapLibre Native + OpenFreeMap | (C) Không bản đồ |
|---|---|---|---|---|
| Chi phí | Không tốn thêm ngoài phí Developer Program; Apple DTS nói "no specified limits", nhưng có điều khoản cho Apple toàn quyền [AP-MK-COST] | Thư viện miễn phí (BSD-3) [FM-PUB]. Tile: OSM công cộng 0 đồng nhưng có chính sách giới hạn [OSM-TUP]; gói thương mại xem §3.3 | 0 đồng: OpenFreeMap không đăng ký, không khoá, cho thương mại [OFM] | 0 |
| Khoá / tài khoản | Không | OSM: không. Gói trả phí: có | Không | — |
| Attribution | Logo Apple Maps + "Legal" do MapKit tự vẽ; không được che liên tục [HIG-MAPS] | Dòng OSM bắt buộc | MapLibre tự hiện | — |
| Chất lượng ở VN | **Chưa kiểm** (đo ở protocol máy T23.3) | OSM: đường chính, ga, bến, tên tiếng Việt tốt | Như OSM | — |
| Công sức iOS | PlatformView Swift tự viết (§3.4) + lớp Dart mỏng; chạy thật chỉ được trên CI Simulator/máy | Nhỏ nhất: thuần Dart, kiểm hết trên Windows | Trung bình: plugin native, chưa rõ hỗ trợ SPM | Rất nhỏ |
| Android | **Không có.** Phải làm riêng (§6.3) | Cùng mã với iOS | Cùng mã với iOS | — |
| Riêng tư | Apple nhận tile request của vùng đang xem + IP (§6.2) | Nhà cung cấp tile nhận vùng xem + IP + UA | OpenFreeMap nhận vùng xem + IP | Tốt nhất |
| Offline | Không có API offline cho app bên thứ ba | Có (asset/file tile) | Có giới hạn | — |
| Đáp ứng PRD màn 2 | Có (iOS) | Có | Có | Không |

### 3.3 Nguồn tile cho (B) — dùng lại khi làm Android (kiểm 06/11/2026)

| Nhà cung cấp | Miễn phí | Thương mại | Ghi chú |
|---|---|---|---|
| `tile.openstreetmap.org` | Có | Không cấm, nhưng *"Commercial services … should be especially aware that access may be withdrawn at any point"* [OSM-TUP] | Bắt buộc: UA riêng, attribution, tôn trọng cache, không prefetch/offline. Hợp với beta ít người |
| Mapbox Raster Tiles | 750 000 tile/tháng [MB-PRICE] | Có | Cần tài khoản + token |
| Stadia Maps | 200 000 credit/tháng | **Free: không** [STADIA] | Starter 20 USD/tháng |
| MapTiler | 100 000 request/tháng | **Free: "non-commercial use"** [MAPTILER] | Flex 30 USD/tháng |
| Esri Location Platform | 2 000 000 tile/tháng [ESRI] | Chưa kiểm | Cần khoá |
| VietMap / Goong (VN) | Dùng thử / 100 USD credit [VM-OV][VM-LIM][GOONG] | Có, thanh toán VND | Chưa kiểm raster XYZ |

### 3.4 Hiện thực MapKit: plugin có sẵn hay PlatformView tự viết

| Bằng chứng | `apple_maps_flutter` (fluttercommunity.dev) | PlatformView tự viết (`UiKitView` + `MKMapView`) |
|---|---|---|
| Bảo trì | 1.4.0, đăng **21 tháng trước**; changelog mới nhất chỉ là "Flutter 3.27.1 compatibility"; README ghi "should also be considered a developers preview" [AMF-PUB][AMF-CL]. `pubspec.yaml` trên nhánh master còn ràng buộc Dart `>=2.14.0 <3.0.0` [AMF-REPO] | Tự kiểm soát |
| SPM | **Không**: repo chỉ có `ios/apple_maps_flutter.podspec` (deployment target 9.0), không có `Package.swift` (404) [AMF-REPO]. Flutter phải quay về CocoaPods cho plugin không hỗ trợ SPM [FL-SPM], tức là thêm `Podfile` + `pod install` vào một dự án hiện chỉ dùng SPM. CocoaPods registry **chuyển sang chỉ đọc từ 02/12/2026** [FL-SPM] | Mã nằm trong Runner/gói local; không thêm phụ thuộc |
| Flutter 3.47 / iOS 16 | Chưa kiểm được trên máy; khai báo đã cũ | `UiKitView` + `FlutterPlatformViewFactory` đăng ký trong `didInitializeImplicitFlutterEngine` (mẫu UIScene của Flutter ≥ 3.41) [FL-PV], giống cách `AppDelegate` đang đăng ký `FlutterAssetTraceStore` |
| Tính năng cần | API Dart có `onLongPress`, `circles`, `Annotation(draggable, onDragEnd)`, `myLocationEnabled`, `padding` [AMF-API] | `MKMapView`, `MKCircle`/`MKCircleRenderer`, `MKAnnotationView.isDraggable` (annotation phải có `setCoordinate:` → dùng `MKPointAnnotation`) [MK-DRAG], `UILongPressGestureRecognizer`, `showsUserLocation` [MK-USERLOC], `cameraBoundary`/`cameraZoomRange` [MK-VIEW] |
| Kiểm khi không có Mac | Mã plugin không đi qua typecheck WSL của dự án; lỗi CocoaPods chỉ lộ ra trên CI | Typecheck WSL (SDK xtool có MapKit); phần phân tích message là Swift thuần, `swift test` trên WSL |

**Kết luận: tự viết PlatformView mỏng.** Plugin chỉ có CocoaPods, trong khi dự án chỉ dùng SPM và registry CocoaPods sắp đóng băng. Đây là yếu tố
quyết định, chưa kể plugin đã không được cập nhật gần hai năm. Phần native giữ ở mức tối thiểu: mọi quyết định (khung camera, đổi đích sau khi kéo,
kiểm toạ độ, giới hạn vùng) nằm ở Dart thuần đã có test (T23 §5).

## 4. Tìm kiếm điểm đến (Q3 = A)

- **Bỏ Places.** Chỉ tìm trong dataset ga/bến offline (T24/T23, thuật toán không đổi). Trên iOS, điểm đến ngoài dataset thì **nhấn giữ trên bản
  đồ để ghim** (luồng `mapPin` của T23 D8/§10).
- **Không có geocoding địa chỉ tự do trong MVP 1.** Nominatim công cộng cấm autocomplete phía client và giới hạn 1 request/giây [NOM-UP]. Ứng viên
  sau MVP: VietMap Autocomplete (thanh toán VND [VM-OV]) hoặc `MKLocalSearchCompleter` trên iOS (không khoá, chưa kiểm chất lượng ở VN). Cả hai
  đều gửi nội dung gõ ra ngoài nên phải có dòng công bố như T23 D5.
- `DestinationSource.places` và `DestinationKind.address` **giữ trong enum** để đọc được dòng drift cũ (`converters.dart`) và các nhánh `switch`
  hiện có. Chỉ bỏ nơi sinh ra giá trị mới.

## 5. "Xem đường quay lại" (Q6 = A)

Giữ Google Maps URLs (T27 D8, T28.3 D7): *"You don't need a Google API key to use Maps URLs"*; không có app thì mở trình duyệt [G-URLS]. Không
qua tài khoản Maps Platform. Apple Maps URL dạng hợp nhất `maps.apple.com/directions?destination=` chỉ có từ iOS 18.4 [AP-URL]; dạng cũ `daddr` đã
có báo cáo hỏng [AP-URL-FORUM]. Đưa vào "Đề xuất sau MVP".

## 6. Quyết định

### 6.1 iOS — MapKit qua PlatformView tự viết

1. Bỏ toàn bộ Google Maps Platform (Maps SDK, Places, `mapsConfig`, khoá, secret CI): **T23.2**.
2. **T23.3:** bản đồ iOS = `UiKitView` (viewType `app.napstop/nap_map`) bọc `MKMapView`.
   - Mỗi view có một `MethodChannel` riêng `app.napstop/nap_map/<viewId>` dùng `StandardMessageCodec`, **không dùng Pigeon**. Lý do: message mang
     toạ độ điểm đến, mà T14 D5 cấm lớp Pigeon có trường toạ độ (Pigeon sinh `toString` in mọi trường).
   - Mã native chia hai phần:
     - `NapStopIOS` (gói local, file tự gom): `NapMapController`, bọc MapKit.
     - Gói local, phần chỉ dùng Foundation: `MapWire`, phân tích và dựng message, test bằng `swift test` trên WSL.
   - Runner chỉ thêm **một** file glue `NapMapPlatformView.swift` (factory + `FlutterPlatformView`), đăng ký trong
     `AppDelegate.didInitializeImplicitFlutterEngine`.
3. Tính năng:
   - **Màn 2:** ghim kéo được (`MKPointAnnotation` + `MKMarkerAnnotationView.isDraggable`); vòng tròn vùng báo theo mét (`MKCircle`); nhấn giữ để
     thả ghim (điểm ngoài dataset); không đổi đích khi chạm hay kéo bản đồ (T23 D8). **Không** hiện vị trí người dùng (giữ T23).
   - **Màn 4:** chỉ làm nếu PO chọn ở T23.3 Q1. Đề xuất: bản đồ chỉ mở khi người dùng bấm "Xem bản đồ"; ghim đích không kéo được; vòng tròn khi
     chế độ khoảng cách; chấm vị trí của MapKit (`showsUserLocation`) chỉ với chuyến thật, đã có quyền và app đang `resumed`; camera mặc định chỉ
     khung điểm đến; nút "Vị trí của tôi" mới khung cả vị trí. Màn 4 có bản đồ là **mở rộng phạm vi** so với PRD §3 và T26 D5.
   - **Attribution:** logo Apple Maps + "Legal" do MapKit vẽ. Bản đồ màn 2 được đặt sao cho mép dưới trùng vị trí nghỉ thấp nhất của panel (mốc
     0,30), để logo và Legal luôn hiện trên panel khi panel ở mốc thấp nhất, đúng HIG ("place the Apple logo and legal link … above the lowest
     resting position of the card") [HIG-MAPS]. Ở mốc cao hơn panel che tạm thời; HIG cho phép.
   - **Chủ quyền (Q5 = A):** `cameraBoundary` + `cameraZoomRange` giữ khung xem trong đất liền và đảo ven bờ (khoảng lat 8,3–23,6, lng 102,0–109,7;
     không gồm hai quần đảo). Hằng số chỉnh ở CI Simulator và trên máy (T23.3).
4. Dart: `destinationMapBuilderProvider` trả `null` (= placeholder) trên mọi nền tảng ở T23.2. T23.3 trả bản MapKit khi
   `defaultTargetPlatform == iOS`, còn Android vẫn `null`.

### 6.2 Quyền riêng tư (đánh giá theo quy tắc "vị trí không rời khỏi máy")

- MapKit tải tile và dữ liệu bản đồ **từ máy chủ Apple** cho vùng đang hiển thị. Apple nhận: vùng/zoom đang xem, IP, thông tin thiết bị. Trang
  quyền riêng tư Apple Maps nói số liệu sử dụng gắn với *"an identifier that rotates multiple times per hour, and is not tied to your Apple Account"*,
  và *"we convert precise locations to less-exact locations within 24 hours"* [AP-MAPS-PRIV]. Trang này **chỉ nói về app Apple Maps**, không nói
  về MapKit trong app bên thứ ba. NapStop không giả định các cam kết đó áp dụng.
- **Màn 2:** không bật vị trí người dùng, camera mở ở khung Việt Nam rồi tới điểm đến người dùng chọn. Apple chỉ thấy vùng điểm đến, như trước đây
  với Google. **Đạt** quy tắc: vị trí hiện tại không rời máy.
- **Màn 4 (nếu làm):** chấm vị trí do MapKit vẽ tại chỗ bằng Core Location trong process [MK-USERLOC]; toạ độ không qua Dart, không qua kênh của
  app. Nhưng khi khung nhìn **bao gồm vị trí hiện tại**, các tile request cho Apple biết người dùng đang ở vùng nào (độ chi tiết theo mức zoom). Đây
  là **lộ vị trí ở mức vùng tile tới Apple**. Để giữ tinh thần quy tắc: bản đồ màn 4 chỉ mở khi người dùng bấm; camera mặc định chỉ khung điểm đến;
  khung vị trí hiện tại chỉ khi người dùng bấm "Vị trí của tôi"; công bố trong chính sách riêng tư (T40). PO quyết ở T23.3 Q1.
- App không log toạ độ hay message của kênh bản đồ ở bất kỳ mức nào; `toString` của mọi lớp mang toạ độ không in toạ độ (như T23 `MapPoint`).
- Khai App Privacy (T40): dữ liệu do framework hệ thống của Apple xử lý không phải dữ liệu app thu thập. T40 đối chiếu lại định nghĩa.

### 6.3 Android — quyết khi quay lại Android

- Sau T23.2, Android **không có bản đồ**: màn 2 chỉ tìm ga/bến, không ghim được điểm ngoài dataset.
- Đề xuất cho **T23.4** (làm khi quay lại Android): **(B) `flutter_map` + tile OSM, chỉ cho Android**, sau cùng seam `destinationMapBuilderProvider`.
  Thuần Dart, kiểm hết trên Windows, ~1 ngày. Nguồn tile cho phát hành công khai chọn từ §3.3 (Q2 = đề xuất: quyết ở T40.1). Phương án khác: giữ
  Android không bản đồ tới sau MVP.

### 6.4 Kiểm chứng khi không có Mac

| Lớp | Công cụ | Kiểm gì |
|---|---|---|
| Dart (Windows) | `flutter test` | Logic thuần: mã hoá/giải mã message, khung camera, giới hạn vùng, đổi đích sau khi kéo. Bộ điều khiển kênh với `MethodChannel` giả. Widget màn 2/4 dùng seam `destinationMapBuilderProvider` với bản giả |
| Swift thuần (WSL) | `test-wsl.sh` (`swift test`) | `MapWire` phân tích/dựng message; fixture JSON dùng chung với Dart (parity) |
| Kiểu (WSL) | `typecheck-wsl.sh` | `NapMapController` (MapKit) + glue Runner biên dịch với SDK iOS thật, cho thiết bị và Simulator |
| CI Simulator | `ios-sim-test` (`flutter test integration_test` trên Simulator) | `UiKitView` tạo được, native gửi `ready`; lệnh chẩn đoán (chỉ bản `NAPSTOP_DIAG`) mô phỏng nhấn giữ/kéo ghim qua đúng đường chuyển đổi toạ độ và đọc trạng thái native (số annotation, overlay, bán kính, khung nhìn); kiểm giới hạn vùng. Không xác nhận được chất lượng tile (Simulator có thể không có mạng hay ảnh bản đồ) |
| Máy thật | Protocol T23.3 | Cử chỉ thật, Legal/logo, VoiceOver, giao diện tối, ngoại tuyến, đảo/biển ở rìa đông, chấm vị trí màn 4 |

## 7. Hệ quả

- (+) Không khoá, không tài khoản bản đồ, không thanh toán. Hết chặn T23.1/Q5.
- (+) Bản đồ Apple native, mượt, tự theo giao diện tối, có POI của Apple (giúp tìm bến không có trong dataset, như Bến xe liên tỉnh Đà Lạt).
- (+) Bỏ SDK GoogleMaps và bước stub typecheck.
- (−) Mã native mới chỉ chạy thật trên CI/máy. Giảm rủi ro bằng cách giữ native mỏng, `MapWire` test trên WSL, lệnh chẩn đoán trên Simulator.
- (−) Android không có bản đồ tới T23.4.
- (−) Mất tìm địa chỉ tự do.
- (−) Chất lượng Apple Maps ở VN và cách Apple vẽ biển đảo chưa kiểm (R1, R2).
- Pin: màn 2 không chạy nền. Màn 4 (nếu có) chỉ mở theo yêu cầu, tắt `showsUserLocation` khi app rời `resumed`.

## 8. Danh sách thay đổi và dòng TASKS đề xuất

| ID | Task | Env | Phụ thuộc | Trạng thái đề xuất | Tiêu chí hoàn thành |
|---|---|---|---|---|---|
| **T23.1** | (cũ) Bản đồ/Places iOS bằng khoá Google | — | — | **huỷ** | Ghi: "Huỷ theo ADR-002 (Maps Platform không dùng được ở VN); thay bằng T23.2/T23.3" |
| **T23.2** | Gỡ Google Maps Platform khỏi app, Pigeon, CI, secrets; giữ seam bản đồ; tìm kiếm chỉ dataset offline (`docs/specs/T23.2.md`) | linux + wsl + ci-mac | T23 | todo | Theo spec: grep `app/` không còn Google Maps/Places/`MapsConfig`; Flutter + Kotlin test xanh; typecheck WSL 0 lỗi; build Simulator xanh |
| **T23.3** | Bản đồ MapKit iOS (PlatformView tự viết) cho màn 2; màn 4 theo Q1 của spec (`docs/specs/T23.3.md`) | wsl + ci-mac + device (+ linux cho Dart) | T23.2, T01.2, T17.1 (quyền vị trí cho màn 4), T26 (màn 4) | todo | Theo spec: MW/MC/SW xanh; typecheck; MI01–MI06 trên Simulator; protocol MM01–MM09 trên iPhone |
| **T23.4** | Bản đồ Android (đề xuất `flutter_map` + OSM sau seam) — **quyết khi quay lại Android** | linux | T23.2 | todo (để sau) | Spec viết khi bắt đầu; nguồn tile theo Q2 |
| **T24.2** | Bổ sung bến must-have đã waive (Đà Lạt trước) lên OSM rồi fetch lại | linux (+ PO) | — | todo (ưu tiên thấp, trước T23.4/T40) | `check` exit 0, gỡ waiver Đà Lạt |
| **T19.1** | Đồng bộ tài liệu theo ADR-002 | linux | ADR-002 chấp nhận | todo | Các sửa đổi ở bảng dưới |
| T28.3 | Không đổi (PM03 vẫn kiểm Google Maps URL) | | | | |
| T29.1 | `placesRequestFailed` bị gỡ ở T23.2; `mapsLoadFailed` dùng cho lỗi tải bản đồ MapKit | | | | |
| T40 / T40.1 | Data safety / App Privacy / chính sách riêng tư: bản đồ của Apple (iOS), nhà cung cấp tile (Android, khi có); không còn Google Places; Q2 | | | | |

**Tài liệu cần sửa (T19.1)**

| Tài liệu | Sửa |
|---|---|
| `CLAUDE.md` Tech stack | "**Bản đồ:** iOS = Apple MapKit qua PlatformView tự viết (ADR-002); Android = chưa có (T23.4, quyết sau). Tìm kiếm chỉ dataset ga/bến offline + ghim tay trên bản đồ. Chỉ đường quay lại = Google Maps URLs (không khoá)". Bỏ "Google Maps SDK", "Places Autocomplete" |
| ARCHITECTURE | §1: thêm khối bản đồ iOS (`NapMapController` trong `NapStopIOS`, kênh `app.napstop/nap_map/<id>`, không Pigeon); §3: bỏ `mapsConfig`; §7.1 `INTERNET`: "Firebase; bản đồ Android khi có" (bỏ "Places"); §7.2: MapKit không cần khoá Info.plist |
| PRD | §3 màn 2: "Dataset ga/bến offline (tìm không dấu); không có thì ghim trên bản đồ (iOS: Apple Maps); vòng tròn vùng báo". §3 màn 4: thêm theo quyết định T23.3 Q1. §5: "trừ bản đồ nền" (bỏ "và tìm địa chỉ") |
| PLAN-ios | §3.1 bỏ hàng `mapsConfig()`; §3.2 hàng "Google Maps iOS (T23)" → "Bản đồ MapKit (T23.3)"; §5/§5.1: T23.1 → T23.2 → T23.3; §8 Q5 + §8.1: "đóng theo ADR-002" |
| Spec T23 | Thêm mục "Thay đổi sau ADR-002" trỏ tới T23.2/T23.3 (không sửa thân spec đã done) |
| `app/README.md` | Bỏ mục "Bản đồ & Places" (khoá); thêm một đoạn ngắn: bản đồ iOS dùng MapKit, không cần cấu hình |
| S5 F8, `S5-store-drafts.md` | Đoạn Google Maps/Places → "Bản đồ trên iPhone dùng Apple Maps: khi bạn xem bản đồ, máy tải dữ liệu bản đồ của vùng đang xem từ Apple. NapStop không gửi vị trí hiện tại của bạn" (+ câu về màn 4 nếu PO chọn có) |
| `docs/test-protocols/T23.md` | Đánh dấu các bước Places "bỏ theo ADR-002" |

## 9. Thay đổi phá vỡ

- **Pigeon:** gỡ `MapsConfigMsg` và `PermissionHostApi.mapsConfig()`. Chỉ Dart của app gọi hàm này. Sinh lại 3 file trong cùng commit (T14 D8).
  Ảnh hưởng: T14 (danh sách phương thức trong `bridge_generated_scan_test`), T21 (`PermissionHostApiImpl`), T17.1 (`IOSPermissionHostApi`).
- **Spec T23 (done):** D1–D7, §6 (`mapsConfig`), §7, §8, chip "Địa chỉ", khoá ARB `destinationPlaces*`, test TP*, TS42 hết hiệu lực. Tìm offline
  (§4), máy trạng thái lựa chọn (§10, trừ nhánh Places), ghim (D8), khoảng cách (D9) giữ nguyên.
- **T26 D5** (màn 4 không bản đồ): bị thay nếu PO chọn T23.3 Q1 = A hoặc B.
- **Dữ liệu người dùng:** không phá. Dòng drift cũ có `source = places` vẫn đọc được.

## 10. Phương án đã loại

| Phương án | Lý do |
|---|---|
| Giữ Google với tài khoản thanh toán nước ngoài | Vi phạm "No Use in Prohibited Territories" [GMP-TOS] |
| (B) `flutter_map` cho iOS | PO chọn A ngày 06/11. Giữ (B) làm đề xuất cho Android (T23.4) |
| `apple_maps_flutter` | Chỉ có CocoaPods, không có `Package.swift`; dự án chỉ dùng SPM; CocoaPods registry chỉ đọc từ 02/12/2026; không cập nhật 21 tháng; "developers preview" (§3.4) |
| (B′) MapLibre | Plugin native, chưa rõ SPM; không cần khi iOS dùng MapKit |
| (C) Không bản đồ trên iOS | Không đáp ứng PRD màn 2; chỉ là trạng thái tạm giữa T23.2 và T23.3 |
| Nominatim/Photon | Cấm autocomplete phía client, 1 request/giây [NOM-UP] |

## 11. Rủi ro

| # | Rủi ro | Phương án |
|---|---|---|
| R1 | Chất lượng Apple Maps ở VN kém (thiếu đường, tên) | Bản đồ chỉ để xem và ghim; đích chính vẫn chọn từ dataset. Đo ở MM (T23.3). Kém nghiêm trọng → ADR mới (dùng (B) cho cả iOS) |
| R2 | Apple vẽ Hoàng Sa/Trường Sa không đúng quy định VN. **Chưa kiểm văn bản pháp luật gốc** | Giới hạn camera (Q5 = A); MI05 trên Simulator + MM07 trên máy; PO xác nhận với tư vấn pháp lý trước T40 |
| R3 | Sửa tay `project.pbxproj` sai | Chỉ thêm một file vào Runner, chép đúng mẫu `FlutterAssetTraceStore.swift`; phần MapKit nằm trong gói (file tự gom); CI build bắt lỗi |
| R4 | PlatformView (hybrid composition) giật khi kéo panel hoặc bàn phím lên | App không dùng `BackdropFilter`/`ShaderMask`/`ColorFiltered` (đã grep) — các hiệu ứng Flutter hạn chế với platform view iOS [FL-PV]. Đo ở MM09 |
| R5 | Xung đột cử chỉ: nhấn giữ của bản đồ và kéo ghim (cũng là nhấn giữ) | Native bỏ qua nhấn giữ khi điểm chạm nằm trên annotation view; test chẩn đoán MI03 + MM02 |
| R6 | Android không có bản đồ tới T23.4: không chọn được điểm ngoài dataset | Chấp nhận (PO ưu tiên iOS); T24.2 bổ sung bến quan trọng |
| R7 | Tile request màn 4 lộ vùng vị trí tới Apple | §6.2: mở theo yêu cầu, camera mặc định khung điểm đến, công bố |

## 12. Câu hỏi PO đã quyết (06/11/2026)

| # | Câu hỏi | Quyết định |
|---|---|---|
| Q1 | Thay Google bằng gì | **A — Apple MapKit trên iOS**; Android quyết sau (§6.3) |
| Q2 | Nguồn tile khi phát hành công khai | Theo đề xuất: quyết ở T40.1. Với A, chỉ còn áp dụng cho Android (T23.4) |
| Q3 | Tìm địa chỉ tự do | Theo đề xuất: **không** trong MVP 1 |
| Q5 | Giới hạn vùng xem (biển đảo) | Theo đề xuất: **giới hạn camera** trong đất liền + đảo ven bờ; xác nhận pháp lý trước T40 |
| Q6 | Chỉ đường quay lại trên iPhone không có Google Maps | Theo đề xuất: **giữ Google Maps URL** |

## 13. Q4 (bến must-have không có trên OSM) — kết luận với phương án A

- **iOS:** không còn chặn. Người dùng ghim tay trên bản đồ Apple, và bản đồ Apple có POI riêng của Apple (có thể có Bến xe liên tỉnh Đà Lạt; chưa
  kiểm), giúp tìm chỗ để nhấn giữ.
- **Android:** sau T23.2 không có bản đồ, nên Đà Lạt (điểm đến xe khách hàng đầu, `docs/reviews/T24.md`) **không chọn được** trên Android tới khi có
  T23.4.
- **Kết luận:** vẫn cần, nhưng **không chặn** T23.2/T23.3. Giữ **T24.2** ở ưu tiên thấp, làm trước khi phát hành Android hoặc T40. Cách làm: PO thêm
  bến lên OSM bằng tài khoản của mình rồi fetch lại, không chép toạ độ từ nguồn ngoài (T24 Q3). Lạc Long: kiểm còn hoạt động không trước khi thêm.

## 14. Điều kiện xem lại

- MapKit ở VN kém (R1) hoặc vướng pháp lý (R2) → ADR mới: (B) cho cả hai nền tảng, hoặc nhà cung cấp VN.
- Có plugin MapKit hỗ trợ SPM, được bảo trì → có thể thay mã tự viết nếu giảm được bảo trì.
- Cần tìm địa chỉ tự do → ADR/spec riêng (VietMap hoặc `MKLocalSearchCompleter`).

## 16. Amendment 2026-11-07 — mở lại phạm vi tìm địa chỉ và thêm trạm buýt

PO quyết ngày 07/11/2026. Phần này **thay** các câu nói "không tìm địa chỉ tự do trong MVP 1": §4 (đoạn "Không có geocoding địa chỉ tự do"), §12 Q3,
§7 hệ quả "Mất tìm địa chỉ tự do", §14 dòng thứ ba. Các phần khác (MapKit qua PlatformView, bỏ Google, Android chưa có bản đồ) giữ nguyên.

**Quyết định**
1. **iOS: tìm địa chỉ bằng `MKLocalSearchCompleter` + `MKLocalSearch`** (spec `docs/specs/T23.5.md`). Không khoá, không tài khoản. `DestinationSource.places` và
   `DestinationKind.address` (đã giữ trong enum ở §4) được **dùng lại** làm nguồn/loại của đích địa chỉ nên không đổi drift/Analytics.
2. Nội dung gửi ra ngoài: chuỗi gõ và vùng khung Việt Nam; **không** vị trí người dùng; không log; không Analytics; có dòng công bố trên màn 2.
   Quy tắc "vị trí không rời máy" giữ nguyên, nhưng "nội dung tìm kiếm không rời máy" **không còn đúng** cho mục địa chỉ trên iOS (cập nhật PRD §5, T40).
3. Kênh: `MethodChannel` ứng dụng `app.napstop/address_search` (không Pigeon, T14 D5), cùng nguyên tắc T23.3 D3.
4. **Android: không có tìm địa chỉ** (không có MapKit, chưa có bản đồ). Ứng viên khi làm T23.4: VietMap (§4) hoặc nhà cung cấp khác, cần ADR/spec riêng.
5. **Trạm buýt Hà Nội + TP. HCM** nằm trong dataset offline từ OSM (spec `docs/specs/T24.3.md`), file riêng `bus_stops.json`; cả Android và iOS. Đây là dữ liệu
   ODbL cùng nghĩa vụ ghi công/công bố như T24.

**Phương án đã loại:** VietMap/Nominatim cho iOS (thêm nhà cung cấp, thanh toán hoặc cấm autocomplete phía client, §10); tìm địa chỉ cả Android bằng Nominatim (cấm).

**Hệ quả và rủi ro mới**
- Điều khoản Apple Developer Program License Agreement, Attachment 6: §2.4 phải hiện bản đồ Apple cùng kết quả địa chỉ; §2.5 Map Data (gồm toạ độ,
  §1.2) không được cache/lưu quá mức tạm thời; §2.2 không dùng trong "secondary or derived database"; §2.7 Apple có thể giới hạn số giao dịch
  [DPLA-A6]. Lưu đích địa chỉ vào lịch sử/điểm đã lưu có thể vi phạm §2.5 → **T23.5 Q1** (PO quyết; cần tư vấn pháp lý trước T40). Chưa tra
  điều khoản "MapKit" riêng trong Apple Developer Terms ngoài DPLA.
- Giới hạn tần suất của MapKit Search không có số công bố; `MKError.loadingThrottled` nói lỗi có thể xảy ra khi "an app makes frequent requests for
  data over a short period of time" [MK-THR]. Giảm bằng debounce 400 ms, tối thiểu 3 ký tự, nghỉ 30 s khi bị giới hạn.
- Chủ quyền biển đảo (R2): kết quả tìm kiếm có thể trỏ tới hoặc gắn nhãn hai quần đảo. T23.5 lọc nhãn Trung Quốc ở gợi ý và từ chối điểm ngoài khung
  `kVietnamBounds` (đảo xa bờ nằm ngoài khung camera T23.3 D11). Vẫn cần xác nhận pháp lý trước T40.
- Quyền riêng tư: Apple nhận chuỗi gõ; tài liệu không nói MapKit có tự kèm vị trí thiết bị vào yêu cầu tìm hay không (T23.5 R3).
- T40: chính sách riêng tư và App Privacy thêm "nội dung tìm địa chỉ được gửi tới Apple" (iOS).

**Tham khảo bổ sung (kiểm 2026-11-07)**
- [MK-THR] https://developer.apple.com/documentation/mapkit/mkerror/code/loadingthrottled
- [DPLA-A6] https://developer.apple.com/support/terms/apple-developer-program-license-agreement/ (Attachment 6)
- `MKLocalSearchCompleter`: https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter ; `MKLocalSearch`: https://developer.apple.com/documentation/mapkit/mklocalsearch
- Spec: `docs/specs/T23.5.md`, `docs/specs/T24.3.md`.

## 15. Tham khảo (kiểm 2026-11-06)

Google
- [GMP-PT] Prohibited Territories: https://cloud.google.com/maps-platform/terms/maps-prohibited-territories (trang trực tiếp không tải được bằng công
  cụ; căn cứ chính là thông báo lỗi PO nhận ngày 06/11/2026)
- [GMP-TOS] Maps Platform Terms: https://cloud.google.com/maps-platform/terms
- [GMP-TOS-COPY] Bản chép "No Use in Prohibited Territories" (bên thứ ba): https://conductatlas.com/platform/google-maps/google-maps-platform-terms-of-service/prohibition-on-prohibited-territory-distribution/
- [G-URLS] Google Maps URLs: https://developers.google.com/maps/documentation/urls/get-started

Apple
- [MK-VIEW] `MKMapView` (overlays, annotations, `showsUserLocation`, `cameraBoundary`, `cameraZoomRange`, `setVisibleMapRect(_:edgePadding:animated:)`,
  `convert(_:toCoordinateFrom:)`): https://developer.apple.com/documentation/mapkit/mkmapview
- [MK-DRAG] `MKAnnotationView.isDraggable` (annotation phải có `setCoordinate:`; không được chặn thao tác kéo đã bắt đầu):
  https://developer.apple.com/documentation/mapkit/mkannotationview/isdraggable
- [MK-USERLOC] `MKMapView.showsUserLocation` (dùng Core Location, theo dõi định kỳ khi bật): https://developer.apple.com/documentation/mapkit/mkmapview/showsuserlocation
- [HIG-MAPS] Human Interface Guidelines — Maps (logo Apple + Legal; đặt trên vị trí nghỉ thấp nhất của card; không hiện khi bản đồ < 200×100):
  https://developer.apple.com/design/human-interface-guidelines/maps
- [AP-MAPS-PRIV] Apple Maps & Privacy: https://www.apple.com/legal/privacy/data/en/apple-maps/
- [AP-MK-COST] Diễn đàn Apple, MapKit pricing: https://developer.apple.com/forums/thread/127493
- [AP-URL] Unified Maps URLs (iOS 18.4+): https://developer.apple.com/documentation/mapkit/unified-map-urls
- [AP-URL-FORUM] `daddr` và trả lời của DTS: https://developer.apple.com/forums/thread/784030

Flutter / pub.dev
- [FL-PV] Hosting native iOS views (UiKitView, factory trong `didInitializeImplicitFlutterEngine`, giới hạn composition):
  https://docs.flutter.dev/platform-integration/ios/platform-views
- [FL-SPM] Swift Package Manager for app developers (CocoaPods fallback; registry chỉ đọc từ 02/12/2026):
  https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers
- [AMF-PUB] `apple_maps_flutter`: https://pub.dev/packages/apple_maps_flutter ; [AMF-CL] changelog: https://pub.dev/packages/apple_maps_flutter/changelog ;
  [AMF-API] `AppleMap`, `Annotation`: https://pub.dev/documentation/apple_maps_flutter/latest/ ; [AMF-REPO] `pubspec.yaml`, `ios/apple_maps_flutter.podspec`
  (có), `ios/apple_maps_flutter/Package.swift` (404): https://github.com/LuisThein/apple_maps_flutter
- [FM-PUB] `flutter_map`: https://pub.dev/packages/flutter_map

OpenStreetMap và nhà cung cấp (cho Android / tham khảo)
- [OSM-TUP] Tile Usage Policy: https://operations.osmfoundation.org/policies/tiles/
- [NOM-UP] Nominatim Usage Policy: https://operations.osmfoundation.org/policies/nominatim/
- [OFM] https://openfreemap.org/ · [MB-PRICE] https://www.mapbox.com/pricing · [STADIA] https://stadiamaps.com/pricing/ ·
  [MAPTILER] https://www.maptiler.com/cloud/pricing/ · [ESRI] https://location.arcgis.com/pricing/ ·
  [VM-OV] https://maps.vietmap.vn/docs/map-api/overview/ · [VM-LIM] https://maps.vietmap.vn/docs/map-api/console/usage-limitation/ ·
  [GOONG] https://goong.io/pricing-plans/

Nội bộ: `docs/specs/T23.md`, `T24.md` + `docs/reviews/T24.md`, `T26.md` D5/Q1, `T27.md` D8, `T28.3.md` D7/Q1, `T14.md` D5, `docs/PLAN-ios.md` §1, §3,
§6, §8 Q5, `docs/spikes/S5.md` F8, ADR-001.
