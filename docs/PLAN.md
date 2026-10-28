# Kế hoạch tới bản demo — NapStop MVP 1

## Định nghĩa "bản demo xong" (Definition of Done)
1. **Cài được:** APK (Play Internal Testing) + bản iOS (TestFlight).
2. **Luồng chính chạy trọn vẹn** màn 0 → 1 → 2 → 3 → 4 → 5 với GPS thật **và** với chế độ giả lập.
3. **Báo thức kêu khi máy khoá + im lặng + Không làm phiền** trên 4 máy Android (Xiaomi, Oppo, Vivo,
   Samsung) và iPhone iOS 26 (AlarmKit).
4. 3 chế độ báo đúng theo bộ trace (sai lệch ≤ 1 phút / ≤ 300 m); cảnh báo khoảng cách quá ngắn hoạt động.
5. Mất GPS, pin yếu, quá trạm: phát hiện đúng trên trace tương ứng.
6. Lịch sử lưu đúng kết quả; cài đặt chung được ghi nhớ; giao diện tiếng Việt + tiếng Anh.
7. Chạy nền 10 giờ không crash; pin ≤ 15% (đo thật ít nhất trên 2 máy).
8. Có **kịch bản demo** + video: chuyến tàu Hà Nội → Đồng Hới giả lập 60×, và 1 clip đi xe thật.

## Lộ trình (≈ 10 tuần, team 1–2 dev + 4 agent)

| Phase | Tuần | Mục tiêu | Gate (người dùng duyệt) |
|---|---|---|---|
| **0. Khởi động** | 1 (đầu) | Repo, toolchain, CI, khung Flutter, fixture trace đầu tiên | Build được APK rỗng, CI xanh |
| **1. Spikes rủi ro** | 1–2 | Trả lời 4 câu hỏi sống còn (báo thức nền iOS, OEM Android, pin, chính sách store) | **Go / No-go** cho kiến trúc. No-go → ADR đổi hướng |
| **2. Core engine** | 2–4 | Trip Engine (spec + Kotlin + Swift), Location, Alarm native, Pigeon, chế độ giả lập | Trace test xanh trên cả 2 nền tảng; demo giả lập chạy trên Android |
| **3. Giao diện** | 4–7 | 12 màn theo wireframe, dataset ga/bến, i18n, Firebase phụ trợ | Đi trọn luồng 0→5 trên máy thật |
| **4. Tích hợp & kiểm thử** | 7–9 | Integration test, field test trên tàu/xe, test pin 10 giờ, sửa lỗi | Đạt mục 3, 4, 5, 7 của DoD |
| **5. Phát hành demo** | 9–10 | TestFlight, Play Internal, kịch bản + video demo | **Bản demo** |

## Vai trò

| Vai trò | Ai | Trách nhiệm |
|---|---|---|
| Product owner | Người dùng | Duyệt Gate, trả lời câu hỏi mở trong spec, quyết định No-go |
| Orchestrator | Session Claude chính | Chọn task, gọi agent đúng thứ tự, cập nhật `TASKS.md`, commit cục bộ, báo cáo |
| `solution-designer` | Agent | Spec kỹ thuật, ADR, kế hoạch spike, test case |
| `coder` | Agent | Hiện thực theo spec + unit test cơ bản |
| `reviewer` | Agent | Review theo spec và checklist (nền, pin, quyền, riêng tư, a11y) |
| `tester` | Agent | Fixture trace, test tự động, giao thức test thủ công, báo cáo |
| Field tester | Người (dev/QA) | Task `[device]`: đi tàu/xe thật, test pin, test máy OEM |
| Mac builder | Người có Mac (hoặc Claude Code trên Mac) | Task `[mac]`: Swift, Xcode, TestFlight |

## Môi trường thực thi
| Nhãn | Ở đâu | Ví dụ |
|---|---|---|
| `[linux]` | Container cloud này / máy Linux | Dart, Flutter Android build, Kotlin JVM test, tracegen, dataset |
| `[mac]` | macOS + Xcode | Swift Trip Engine, iOS location/alarm, TestFlight |
| `[device]` | Điện thoại thật + người | Spike OEM, test pin, field test trên tàu/xe |

Container cloud **chưa có Flutter/Android SDK** (T00 cài đặt; nếu bị chặn mạng thì cấu hình lại network
của environment) và **là tạm thời** → cần một remote Git (GitHub) trước khi bắt đầu Phase 0.

## Rủi ro & phương án dự phòng
| Rủi ro | Dấu hiệu | Phương án |
|---|---|---|
| iOS không phát được báo thức to từ nền | Spike S3 thất bại | Time Sensitive + âm thanh 30 giây lặp lại + xin Critical Alerts; demo iOS ghi rõ giới hạn |
| OEM diệt service | Spike S1: service chết < 10 giờ | Màn hướng dẫn pin bắt buộc trước chuyến đầu + watchdog tự khởi động lại + nhắc trong thẻ "Sẵn sàng" |
| Pin > 15% | Spike S4 | Nới chiến lược lấy mẫu, dùng geofence nhiều hơn khi còn xa |
| Store từ chối quyền nền | Spike S5 | Chuẩn bị video + mô tả sớm; nộp bản internal sớm để biết phản hồi |
| Thiếu người field test | Phase 4 trễ | Lên lịch sẵn 3 chuyến thật từ tuần 6 |

## Nhịp làm việc
- Mỗi ngày: orchestrator chạy vòng agent cho các task sẵn sàng, cuối ngày tóm tắt (task xong, blocker, câu hỏi).
- Mỗi Gate: báo cáo ngắn gồm demo/ảnh chụp, kết quả test, rủi ro còn lại, đề xuất cho phase sau.
