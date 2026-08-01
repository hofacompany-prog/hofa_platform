# hofa_driver_app

App tài xế HOFA — Android & iOS (Flutter). Đăng nhập bằng SĐT, bật/tắt online, bật/tắt
tự động nhận đơn, nhận push khi có đơn mới, xác nhận từng bước giao hàng bằng OTP.

## Chạy thử

```bash
cd hofa_driver_app
cp env.example.json env.json   # điền SUPABASE_URL, SUPABASE_ANON_KEY, API_BASE_URL thật
flutter pub get
flutter run   # cần máy ảo/điện thoại Android hoặc iOS đã kết nối
```

Không cấu hình Firebase (bước dưới) app vẫn chạy và dùng được bình thường — chỉ riêng
push notification khi có đơn mới sẽ không hoạt động (app vẫn tự cập nhật khi mở lại
màn hình, chỉ là không có thông báo đẩy).

## Thiết lập Firebase (bắt buộc để có push notification)

1. Vào [Firebase Console](https://console.firebase.google.com) → tạo project mới (hoặc dùng
   chung project với các app khác nếu có).
2. **Thêm app Android**: package name `com.hofa.hofa_driver` (khớp `applicationId` trong
   `android/app/build.gradle.kts`) → tải file `google-services.json` → bỏ vào
   `hofa_driver_app/android/app/google-services.json`.
3. **Thêm app iOS**: Bundle ID lấy trong Xcode (`ios/Runner.xcodeproj`, thường là
   `com.hofa.hofaDriver`) → tải file `GoogleService-Info.plist` → mở `ios/Runner.xcworkspace`
   bằng Xcode, kéo file vào thư mục `Runner` (tick "Copy items if needed").
4. **iOS cần thêm APNs key**: Apple Developer → Certificates, Identifiers & Profiles → Keys →
   tạo 1 APNs key → upload key đó vào Firebase Console (Project settings → Cloud Messaging →
   Apple app configuration).
5. Lấy **service account key** cho server: Firebase Console → Project settings → Service
   accounts → Generate new private key → dán TOÀN BỘ nội dung file JSON đó vào biến môi
   trường `FIREBASE_SERVICE_ACCOUNT_JSON` trên Render (server/, xem `.env.example`).
6. Build lại app (`flutter build apk` / build iOS qua Xcode) sau khi có 2 file cấu hình trên —
   `android/app/build.gradle.kts` chỉ áp dụng Google Services plugin khi thấy file
   `google-services.json`, nên trước đó build vẫn chạy bình thường (chỉ thiếu push).

`google-services.json`, `GoogleService-Info.plist` đã được thêm vào `.gitignore` — không
commit lên git vì gắn với project Firebase thật.

## Chạy cron quét đơn quá hạn (khuyến nghị, không bắt buộc)

Khi tài xế không xác nhận kịp trong khung giờ cho phép (mặc định 25s,
`server/src/dispatch.js`), hệ thống chỉ tự chuyển sang tài xế khác khi:
- app tài xế đó tự gọi từ chối lúc đếm ngược về 0 (đã code sẵn), hoặc
- có ai đó gọi `POST /internal/sweep-expired-offers` (header `x-internal-secret` khớp
  `INTERNAL_SWEEP_SECRET`).

Nên trỏ 1 Render Cron Job (hoặc cron-job.org, dịch vụ ping ngoài bất kỳ) gọi endpoint này
mỗi 15–20 giây để chắc chắn không có đơn bị kẹt khi app tài xế bị tắt hẳn giữa chừng.

## Giới hạn đã biết (v1)

- **Vị trí chỉ theo dõi khi app đang mở** (foreground). Muốn tiếp tục gửi vị trí khi tài
  xế tắt màn hình/thu nhỏ app lâu, cần thêm 1 background service riêng (vd gói
  `flutter_background_service`) — chưa làm ở bản này.
- **Không có bản đồ/chỉ đường trong app** — nút "chỉ đường" mở thẳng Google Maps/Apple Maps
  ngoài app (không cần Google Maps API key, không tốn phí Directions API).
- **Gán tài xế tuần tự, không phải broadcast song song**: hệ thống mời từng tài xế gần nhất
  một, từ chối/hết hạn thì mời người kế tiếp — không mời cùng lúc nhiều tài xế rồi ai bấm
  trước thắng như Grab. Đơn giản hơn, không có race-condition, nhưng chậm hơn 1 chút nếu
  tài xế đầu tiên không phản hồi.
