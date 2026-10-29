# S5 — Bản nháp nộp store (NapStop MVP 1)

Đi kèm `docs/spikes/S5.md`. **Bản tiếng Việt là bản gốc**; bản tiếng Anh dịch theo. Mọi nội dung là nháp — PO duyệt
trước T40. Chuỗi hiển thị trong app (mục 4.1) sẽ được T21 đưa vào ARB; tên khoá ở đây là đề xuất.
Giới hạn ký tự ghi theo hiểu biết hiện tại — **kiểm lại trong Play Console/App Store Connect khi nhập**.

Nguyên tắc copy (từ S5): nói rõ dùng **vị trí** ở mô tả (Play yêu cầu tính năng dùng vị trí phải được nêu nổi bật);
gọi tính năng là **"theo dõi chuyến đi"**, không dùng chữ "geofence/vùng địa lý"; nhấn **"báo thức"** (để khớp
nhóm FSI "setting an alarm"); không hứa "100%"; nói thật về Firebase/Google Maps.

---

## 1. Google Play — Store listing

### 1.1 Tiếng Việt (mặc định)

**Tên app (≤ 30):** `NapStop – Báo thức theo trạm`

**Mô tả ngắn (≤ 80):**
`Báo thức theo vị trí: ngủ yên trên xe, tàu – tỉnh dậy trước khi tới trạm.`

**Mô tả đầy đủ (≤ 4000):**

```
Đi xe khách, tàu đêm hay xe buýt đường dài mà sợ ngủ quên lỡ trạm? NapStop là báo thức theo vị trí: chọn điểm đến, cứ ngủ, NapStop đánh thức bạn khi sắp tới nơi.

CÁCH DÙNG
1. Chọn điểm đến: tìm nhanh ga tàu, bến xe trên toàn quốc (gõ không dấu cũng được) hoặc ghim trên bản đồ.
2. Chọn cách báo:
   • Theo khoảng cách – ví dụ còn 1 km.
   • Theo thời gian – ví dụ còn 15 phút, tính theo tốc độ thực tế của xe.
   • Thông minh – để bạn có khoảng 10 phút tỉnh ngủ, không bao giờ muộn hơn mốc 1 km.
3. Bấm "Bắt đầu theo dõi" và ngủ. NapStop theo dõi chuyến đi bằng vị trí của điện thoại và báo thức khi bạn sắp tới.

BÁO THỨC ĐÁNH THỨC ĐƯỢC THẬT
• Kêu cả khi máy khoá, đang im lặng hoặc Không làm phiền.
• Màn hình báo thức toàn màn hình, vuốt để tắt; báo lại 1 lần sau 1 phút.
• Âm lượng tăng dần, rung, đèn flash, ưu tiên tai nghe.
• Rung nhẹ nhắc trước khi còn khoảng 30 phút.

LO TRƯỚC NHỮNG TÌNH HUỐNG KHÓ
• Mất GPS khi qua hầm: tự ước tính vị trí, báo sớm nếu cần.
• Pin yếu: dự báo pin có đủ tới nơi không, báo sớm khi pin còn 5%.
• Lỡ đi quá trạm: báo ngay và mở chỉ đường quay lại.
• Hướng dẫn tắt tối ưu pin theo từng hãng máy (Xiaomi, Samsung, Oppo, Vivo).

TIẾT KIỆM PIN
NapStop lấy vị trí thưa khi còn xa và dày dần khi sắp tới.

QUYỀN RIÊNG TƯ
• NapStop dùng vị trí của bạn để theo dõi chuyến đi và báo thức, kể cả khi màn hình tắt, chỉ trong chuyến đi bạn đã bắt đầu. Khi chuyến đi kết thúc, NapStop ngừng dùng vị trí.
• Vị trí chỉ được xử lý trên điện thoại của bạn, không gửi lên máy chủ nào. Không cần tài khoản.
• Trong lúc theo dõi, thông báo cố định luôn hiện, có nút Dừng.

Lịch sử chuyến đi, điểm đã lưu (Nhà, Quê, Công ty) giúp đặt lại chuyến quen chỉ với 1 chạm.

Góp ý: <support email – Q3>
Chính sách quyền riêng tư: <privacy URL – Q2>
```

### 1.2 English

**App name (≤ 30):** `NapStop: Location Alarm`

**Short description (≤ 80):**
`Location alarm for bus & train rides. Sleep, and wake up before your stop.`

**Full description:**

```
Taking a long-distance bus, a night train or a coach and afraid of sleeping past your stop? NapStop is a location-based alarm: pick your destination, fall asleep, and NapStop wakes you up as you get close.

HOW IT WORKS
1. Pick a destination: search train stations and bus terminals across Vietnam (no accents needed) or drop a pin on the map.
2. Choose how to be woken:
   • By distance – e.g. 1 km before arrival.
   • By time – e.g. 15 minutes before arrival, based on your vehicle's actual speed.
   • Smart – gives you about 10 minutes to wake up, never later than 1 km out.
3. Tap "Start tracking" and sleep. NapStop tracks your trip using your phone's location and sounds the alarm as you approach.

AN ALARM THAT ACTUALLY WAKES YOU
• Rings even when the phone is locked, silenced or in Do Not Disturb.
• Full-screen alarm, swipe to dismiss; snooze once for 1 minute.
• Gradually increasing volume, vibration, flashlight, headphones first.
• A gentle vibration about 30 minutes ahead.

READY FOR THE HARD CASES
• Lost GPS in a tunnel: estimates your position and alerts early if needed.
• Low battery: predicts whether your battery will last, alerts early at 5%.
• Missed your stop: alerts you right away and opens directions back.
• Step-by-step battery optimization guides for Xiaomi, Samsung, Oppo and Vivo.

BATTERY FRIENDLY
NapStop checks your location sparingly while you are far away and more often as you get close.

PRIVACY
• NapStop uses your location to track your trip and sound the alarm, even when the screen is off, only during a trip you started. When the trip ends, NapStop stops using your location.
• Your location is processed only on your phone and is never sent to any server. No account needed.
• While tracking, a persistent notification is always shown, with a Stop button.

Trip history and saved places (Home, Hometown, Work) let you repeat a familiar trip in one tap.

Feedback: <support email – Q3>
Privacy policy: <privacy URL – Q2>
```

### 1.3 Đồ hoạ (Q4)
- Icon 512×512 PNG; feature graphic 1024×500; ≥ 2 ảnh chụp điện thoại. Đề xuất 5 ảnh: (1) Trang chủ thẻ "Sẵn
  sàng"; (2) Chọn điểm đến "dong hoi"; (3) Cài đặt báo 3 chế độ; (4) Đang theo dõi (khoảng cách/ETA chữ lớn);
  (5) Màn báo thức. Chú thích trên ảnh bằng tiếng Việt (bản en: tiếng Anh).

## 2. App Store

| Trường | Tiếng Việt | English |
|---|---|---|
| Name (≤ 30) | `NapStop – Báo thức theo trạm` | `NapStop: Location Alarm` |
| Subtitle (≤ 30) | `Ngủ không lỡ trạm` | `Wake up before your stop` |
| Promotional text (≤ 170) | `Đi xe, đi tàu cứ ngủ yên. NapStop theo dõi chuyến đi và báo thức khi bạn sắp tới nơi – kể cả khi máy im lặng.` | `Sleep on the bus or train. NapStop tracks your trip and wakes you as you approach your stop – even in silent mode.` |
| Keywords (≤ 100 byte, phân cách dấu phẩy) | `báo thức,vị trí,xe khách,tàu,bến xe,ga,ngủ,lỡ trạm,GPS` (kiểm số byte UTF-8 khi nhập) | `alarm,location,bus,train,stop,station,sleep,commute,GPS,wake` |
| Description | Dùng mô tả đầy đủ §1.1, bỏ dòng "Hướng dẫn tắt tối ưu pin…" (chỉ Android); đổi "Không làm phiền" → "chế độ Tập trung" | Dùng §1.2, bỏ dòng battery guides; "Do Not Disturb" → "Focus" |
| Support URL / Privacy URL | Q3 / Q2 | Q3 / Q2 |

Lưu ý iOS: dòng "Kêu cả khi máy khoá, im lặng, chế độ Tập trung" chỉ đúng hoàn toàn với **iOS 26+ (AlarmKit)**. Với
iOS 16–25, S3 sẽ chốt mức đảm bảo; nếu không kêu được khi im lặng thì sửa thành "Trên iOS 26 trở lên, …".

## 3. Chính sách quyền riêng tư (nháp, đăng tại URL Q2)

### 3.1 Tiếng Việt

```
Chính sách quyền riêng tư – NapStop
Cập nhật: <ngày>

1. Vị trí
NapStop dùng vị trí chính xác của điện thoại để theo dõi chuyến đi bạn đã bắt đầu và báo thức khi bạn sắp tới điểm đến, kể cả khi màn hình tắt. Vị trí chỉ được xử lý và lưu trên điện thoại của bạn. NapStop không gửi vị trí của bạn lên máy chủ nào, không chia sẻ với bên thứ ba, không dùng cho quảng cáo. NapStop ngừng dùng vị trí khi chuyến đi kết thúc hoặc khi bạn bấm Dừng.

2. Dữ liệu lưu trên máy
Điểm đến, điểm đã lưu, lịch sử chuyến đi và cài đặt được lưu trên điện thoại. Xoá ứng dụng sẽ xoá toàn bộ dữ liệu này. Bạn có thể xoá từng chuyến trong mục Lịch sử.

3. Dịch vụ bên thứ ba
• Google Maps / Google Places: hiển thị bản đồ và tìm địa chỉ. Khi bạn tìm địa chỉ, nội dung bạn gõ được gửi tới Google. NapStop không gửi vị trí hiện tại của bạn kèm theo yêu cầu tìm kiếm. Google có thể thu thập địa chỉ IP và thông tin thiết bị theo chính sách của Google.
• Firebase Analytics: ghi nhận các sự kiện sử dụng ẩn danh (ví dụ: bắt đầu chuyến, báo thức đã kêu) để cải thiện ứng dụng. Không bao gồm vị trí.
• Firebase Crashlytics: báo cáo lỗi ứng dụng (thông tin thiết bị, nhật ký lỗi). Không bao gồm vị trí.
• Firebase Remote Config: tải tham số cấu hình ứng dụng.

4. Quyền của bạn
Bạn có thể thu hồi quyền vị trí, thông báo bất cứ lúc nào trong Cài đặt của điện thoại. NapStop không có tài khoản nên không lưu dữ liệu cá nhân nào trên máy chủ của chúng tôi.

5. Trẻ em
NapStop không dành cho trẻ em dưới 13 tuổi.

6. Liên hệ
<support email – Q3>
```

### 3.2 English
Bản dịch trung thành của 3.1 (T40 dịch khi PO duyệt bản vi; giữ nguyên 6 mục). Điểm bắt buộc: câu "Your location is
processed and stored only on your phone and is never sent to any server", danh sách bên thứ ba, cách thu hồi quyền.

**Phải kiểm lại trước khi đăng:** nội dung mục 3 khớp với Data safety / App Privacy thực tế sau T23, T29.

## 4. Chuỗi xin quyền

### 4.1 Android — màn giải thích trước prompt hệ thống (màn 0, T21 → ARB)

Hiển thị **trước** khi gọi prompt hệ thống, trong luồng sử dụng bình thường (không chỉ trong Cài đặt).

| Khoá ARB (đề xuất) | Tiếng Việt | English |
|---|---|---|
| `permLocationTitle` | Cho phép dùng vị trí | Allow location access |
| `permLocationBody` | NapStop dùng dữ liệu vị trí để theo dõi chuyến đi và báo thức khi bạn sắp tới nơi, kể cả khi màn hình tắt hoặc bạn mở ứng dụng khác, cho tới khi chuyến đi kết thúc. Vị trí chỉ xử lý trên máy này, không gửi đi đâu. | NapStop uses location data to track your trip and sound the alarm as you approach your stop, even when the screen is off or you are using other apps, until the trip ends. Location is processed only on this phone and never sent anywhere. |
| `permLocationHint` | Hãy chọn "Khi dùng ứng dụng" và bật "Vị trí chính xác". | Choose "While using the app" and turn on "Precise location". |
| `permLocationApproxWarning` | Bạn đang cho phép vị trí gần đúng. Báo thức có thể lệch vài km. Bật "Vị trí chính xác" để báo đúng lúc. | You allowed approximate location only. The alarm may be off by several km. Turn on "Precise location" to be woken on time. |
| `permNotificationsTitle` | Cho phép thông báo | Allow notifications |
| `permNotificationsBody` | Cần để hiện báo thức và trạng thái chuyến đi. Không có quyền này, báo thức có thể không hiện trên màn hình khoá. | Needed to show the alarm and trip status. Without it, the alarm may not appear on the lock screen. |
| `permFullScreenTitle` | Báo thức toàn màn hình | Full-screen alarm |
| `permFullScreenBody` | Cho phép NapStop hiện báo thức toàn màn hình khi máy đang khoá, giống đồng hồ báo thức. | Let NapStop show the alarm full screen when your phone is locked, like an alarm clock. |
| `permBatteryTitle` | Tắt tối ưu pin cho NapStop | Turn off battery optimization for NapStop |
| `permBatteryBody` | Một số máy tự tắt ứng dụng chạy lâu. Tắt tối ưu pin để NapStop theo dõi suốt chuyến đi. | Some phones stop long-running apps. Turn off battery optimization so NapStop can track your whole trip. |
| `permOpenSettings` | Mở Cài đặt | Open Settings |
| `tripInterruptedTitle` | Chuyến đi bị gián đoạn | Trip tracking was interrupted |
| `tripInterruptedBody` | Chạm để tiếp tục theo dõi tới {destination}. | Tap to resume tracking to {destination}. |

### 4.2 iOS — Info.plist (bản địa hoá qua `InfoPlist.strings`)

| Khoá | Tiếng Việt | English |
|---|---|---|
| `NSLocationWhenInUseUsageDescription` | NapStop dùng vị trí để tính khoảng cách tới điểm đến và báo thức khi bạn sắp tới, kể cả khi màn hình tắt. Vị trí chỉ xử lý trên máy, không gửi đi đâu. | NapStop uses your location to measure the distance to your destination and wake you as you approach, even with the screen off. Location stays on your iPhone. |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | Chọn "Luôn luôn" để NapStop vẫn báo thức được nếu iOS tạm dừng ứng dụng trong chuyến đi dài. Vị trí chỉ xử lý trên máy, không gửi đi đâu. | Choose "Always" so NapStop can still wake you if iOS pauses the app during a long trip. Location stays on your iPhone. |
| `NSAlarmKitUsageDescription` | NapStop đặt báo thức để đánh thức bạn khi sắp tới điểm đến, kể cả khi máy đang im lặng. | NapStop schedules alarms to wake you as you approach your destination, even in silent mode. |

### 4.3 Play Console — nội dung khai báo

**Foreground service — type `location`**
- Use case: **Navigation** (ride tracking).
- Mô tả chức năng (en, nhập vào Console):
  > NapStop is a location-based alarm for bus and train passengers. After the user picks a destination and taps
  > "Start tracking", a location foreground service tracks the ride to compute the remaining distance and ETA and
  > sounds an alarm when the user is about to arrive. The service is started only from this in-app action, shows a
  > persistent notification with a Stop button, and stops as soon as the alarm is dismissed, the user arrives, or the
  > user stops the trip. Location is processed on the device only.
- User impact if deferred/interrupted (en):
  > If the service is deferred or stopped, the app cannot know when the user is approaching the destination and the
  > alarm will not ring, so a sleeping passenger misses their stop. The trigger depends on continuous distance, speed
  > and ETA (time-based and smart modes, GPS loss in tunnels, overshoot detection), which a one-off geofence cannot
  > provide.

**Full-screen intent**
- Chọn: app có chức năng cốt lõi là **báo thức (alarm)**.
- Nếu có ô giải thích (en):
  > NapStop's core feature is an alarm that wakes a sleeping passenger before their stop. When the alarm fires while
  > the phone is locked, a full-screen alarm activity with swipe-to-dismiss and snooze is shown, like a clock app's
  > alarm.

### 4.4 Lý do cần vị trí chính xác liên tục (chỉ dùng nếu Play Console có form "precise location" — S5 F7)

> NapStop's core feature is waking a sleeping passenger at a chosen distance (200 m – 10 km) or time before their
> stop. Approximate location (accuracy of several km) or a one-time location button cannot detect a 1 km threshold
> or compute speed/ETA during a ride that lasts up to 10 hours, so precise location is needed continuously, only
> while a user-started trip is active.

## 5. Kịch bản video

Chung: quay màn hình máy Android thật (Android 14+), bản `prod` ký số, ngôn ngữ app **tiếng Anh** (reviewer), phụ đề
tiếng Anh, không nhạc. Đăng YouTube chế độ **Unlisted**. Không lộ thông tin cá nhân (tắt thông báo khác, dùng điểm
đến công cộng). Mục tiêu ≤ 30 giây theo khuyến nghị Play cho video vị trí [S5 P1]; FGS chưa có giới hạn công bố —
giữ ≤ 45 giây.

### 5.1 Video khai báo FGS `location` (BẮT BUỘC)

| Thời điểm | Hình | Phụ đề |
|---|---|---|
| 0–4 s | Mở NapStop, Trang chủ | "NapStop – location alarm for bus and train passengers" |
| 4–10 s | Màn 0: màn giải thích vị trí (§4.1) → prompt hệ thống → chọn "While using the app" + "Precise" | "The user grants location access while using the app" |
| 10–16 s | Màn 2: gõ "dong hoi", chọn Ga Đồng Hới; Màn 3: chọn "1 km" | "The user picks a destination and an alarm distance" |
| 16–20 s | Bấm **Start tracking** → màn 4; kéo thanh thông báo xuống thấy notification cố định có nút Stop | "Tracking starts only from this user action and shows a persistent notification" |
| 20–24 s | Bấm nút nguồn tắt màn hình; bật lại thấy notification cập nhật khoảng cách | "Location keeps updating while the screen is off – this is why the foreground service is needed" |
| 24–36 s | (chế độ giả lập 60× đã bật trước, phụ đề nói rõ) màn hình khoá → báo thức toàn màn hình hiện, chuông kêu | "Simulated ride at 60× speed for this demo: the alarm fires as the user approaches the stop" |
| 36–42 s | Vuốt tắt → app hiện kết quả chuyến; notification biến mất | "When the alarm is dismissed, the trip ends and the foreground service stops immediately" |

Ghi chú: nếu muốn ≤ 30 s, bỏ cảnh 20–24 s và rút cảnh giả lập còn 8 s.

### 5.2 Video full-screen intent (chỉ khi Play Console yêu cầu)
Cắt từ 5.1 cảnh 24–42 s: máy khoá + chế độ im lặng (hiện biểu tượng im lặng trên thanh trạng thái) → báo thức toàn màn
hình kêu → vuốt tắt / báo lại. Phụ đề: "Alarm-clock style full-screen alarm on the lock screen".

### 5.3 Video khai báo vị trí nền (DỰ PHÒNG — chỉ dùng nếu ADR-001 bị đảo ngược sau S1)
Yêu cầu của Play [S5 P1]: thể hiện (1) tính năng được kích hoạt từ nền, (2) màn prominent disclosure, (3) prompt hệ
thống; ≤ 30 s.

| Thời điểm | Hình | Phụ đề |
|---|---|---|
| 0–8 s | Màn disclosure theo mẫu Play: "NapStop collects location data to track your ride and wake you before your stop, and to resume tracking after your phone restarts or the system stops the app, even when the app is closed or not in use." → "Continue" | "Prominent disclosure before the permission request" |
| 8–14 s | Prompt hệ thống → Settings → "Allow all the time" | "The user grants background location" |
| 14–20 s | Đang theo dõi → khởi động lại máy (tua nhanh) | "The phone restarts during a ride" |
| 20–30 s | Sau khởi động, không mở app: notification theo dõi tự xuất hiện lại, sau đó báo thức kêu (giả lập) | "Tracking resumes in the background and the alarm still wakes the user" |

## 6. Ghi chú cho reviewer / Test information

**Play Console → App access** và **App Store Connect → App Review notes** (en):

```
No account or login is required.
To see the alarm without travelling: open Settings (gear icon) > press and hold the NapStop logo for 3 seconds >
Simulation mode > choose "Train Hanoi – Dong Hoi" > speed 60× > Start. The full pipeline (location -> trip engine ->
alarm) runs on recorded GPS data and the alarm rings in about 1–2 minutes. Lock the phone to see the lock-screen
alarm. Location data never leaves the device.
```

**TestFlight → Test Information** (vi cho tester trong nước, en cho external review):
- Mô tả beta: "Bản thử NapStop – báo thức theo vị trí cho chuyến xe/tàu."
- Cần thử: đặt điểm đến, bắt đầu theo dõi, khoá máy + bật im lặng; chế độ giả lập 60×; báo lại; mất GPS (giả lập
  "hầm Hải Vân"); lịch sử.
- Email feedback: Q3.

(Số phút báo thức trong chế độ giả lập phụ thuộc T18 — cập nhật khi T18 xong.)
